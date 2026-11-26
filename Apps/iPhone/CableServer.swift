import Foundation
import Network
import Combine
import Darwin

/// One selected foreground transport. USB stays loopback-only; wireless is opt-in.
final class CableServer: ObservableObject {
    @Published private(set) var status = "Connect your iPhone to your Mac"
    @Published private(set) var connected = false
    @Published private(set) var connectionIssue: String?
    @Published private(set) var setupStage: SetupStage?
    @Published private(set) var transport = LinkTransport.usb
    @Published private(set) var pairingCode: String = {
        if let code = UserDefaults.standard.string(forKey: "wireless-pairing-code"), WirelessSettings.validCode(code) { return code }
        let code = WirelessSettings.newCode(); UserDefaults.standard.set(code, forKey: "wireless-pairing-code"); return code
    }()
    private var pairingAttempts = PairingAttemptLimiter()
    private var bluetooth: BluetoothServer?
    var wifiAddress: String {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return "Unavailable" }
        defer { freeifaddrs(list) }
        var current = list
        var addresses: [String] = []
        while let item = current {
            defer { current = item.pointee.ifa_next }
            let name = String(cString: item.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("ap"), let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: buffer)
                if !value.hasPrefix("169.254."), !addresses.contains(value) { addresses.append(value) }
            }
        }
        return addresses.isEmpty ? "Join Wi-Fi or enable Personal Hotspot" : addresses.joined(separator: " · ")
    }
    func selectTransport(_ value: LinkTransport) { stop(); transport = value; start() }
    func renameDevice(_ name: String) {
        stop(); WirelessSettings.setDeviceName(name); objectWillChange.send(); start()
    }
    func newPairingCode() {
        stop(); pairingCode = WirelessSettings.newCode(); UserDefaults.standard.set(pairingCode, forKey: "wireless-pairing-code"); start()
    }
    private var listener: NWListener?
    private var client: NWConnection?
    private var timer: Timer?
    private var handshakeTimeout: DispatchWorkItem?
    private let gameRumble = GameRumble()
    private var state = GamepadState.neutral
    private var pointerMode = PointerMode.aim
    private var sequence: UInt32 = 0
    private var pending: [Data] = []
    var onLayoutCommand: ((LayoutCommand) -> Void)?
    private var commandBuffer = Data()
    private var commandReceiver = LayoutCommandReceiver()
    private var snapshot: ControllerSnapshot?
    private var layoutChunks: [Data] = []
    func updateLayout(_ value: ControllerSnapshot) {
        guard snapshot != value else { return }
        snapshot = value
        layoutChunks = (try? LayoutTelemetry.chunks(value)) ?? []
    }
    private func restartLayoutTelemetry() {
        commandBuffer.removeAll(); commandReceiver = LayoutCommandReceiver()
        layoutChunks = snapshot.flatMap { try? LayoutTelemetry.chunks($0) } ?? []
    }
    private var sending = false
    private var sendStarted: TimeInterval = 0

    func start() {
        guard listener == nil, bluetooth == nil else { return }
        connectionIssue = nil
        if transport == .bluetooth {
            let bluetooth = BluetoothServer(code: pairingCode); self.bluetooth = bluetooth
            bluetooth.onConnected = { [weak self] in
                guard let self else { return }; self.sequence = 0; self.restartLayoutTelemetry(); self.connected = true; self.status = "Bluetooth connected"; self.enqueue()
            }
            bluetooth.onDisconnected = { [weak self] in self?.gameRumble.stop(); self?.connected = false; self?.setupStage = nil; self?.status = "Bluetooth ready · reconnect on Mac" }
            bluetooth.onCommandData = { [weak self] in self?.receiveCommands($0) }
            bluetooth.onStatus = { [weak self] in self?.status = $0 }
            startHeartbeat(); return
        }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let parameters = transport == .wifi ? WirelessSettings.parameters(code: pairingCode) : NWParameters(tls: nil, tcp: tcp)
            if transport == .usb {
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: StateFrame.port)!)
            }
            // Let Network.framework accept IPv4/IPv6 and the Personal Hotspot interface.
            // A required .wifi interface excludes the phone's hotspot-serving path.
            let listener = try NWListener(using: parameters, on: transport == .wifi ? NWEndpoint.Port(rawValue: WirelessSettings.port)! : .any)
            if transport == .wifi {
                listener.service = NWListener.Service(name: WirelessSettings.deviceName(), type: WirelessSettings.bonjourService)
            }
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] value in
                guard let self, self.listener === listener else { return }
                switch value {
                case .ready: self.connectionIssue = nil; self.status = self.transport == .wifi ? "Wi-Fi ready · \(self.wifiAddress)" : "Ready for USB · open the Mac companion"
                case .waiting(let error): self.connectionIssue = "Wi-Fi is not ready: \(error.localizedDescription). Check Local Network access in Settings."; self.status = self.connectionIssue!
                case .failed(let error): self.stop(); self.connectionIssue = "Could not listen: \(error.localizedDescription)"; self.status = self.connectionIssue!
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: .main)
            startHeartbeat()
        } catch { connectionIssue = "Could not start connection: \(error.localizedDescription)"; status = connectionIssue! }
    }

    private func startHeartbeat() {
        timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.enqueue() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() {
        bluetooth?.stop(); bluetooth = nil
        timer?.invalidate(); timer = nil
        // Teardown of the stream also triggers the Mac's neutral-state handling.
        dropClient()
        listener?.cancel(); listener = nil
        state = .neutral
        status = "Paused"
    }

    func setPointerMode(_ mode: PointerMode) {
        pointerMode = mode
        update(.neutral) // Changing modes releases all inputs immediately.
    }
    func update(_ next: GamepadState) {
        if next.isPaused { gameRumble.stop() }
        var next = next; next.pointerMode = pointerMode
        guard state != next else { return }
        state = next
        enqueue() // Button edges are sent immediately; timer provides full-state heartbeats.
    }

    func pointer(_ action: PointerAction, dx: Double, dy: Double) {
        guard connected, !state.isPaused else { return }
        func fixed(_ value: Double) -> Int16 { Int16(max(-4096, min(4096, (value * 16).rounded()))) }
        enqueue(PointerFrame(sequence: sequence, action: action, dx: fixed(dx), dy: fixed(dy)).encode())
    }

    private func accept(_ connection: NWConnection) {
        guard client == nil else { connection.cancel(); return }
        if transport == .wifi && !pairingAttempts.accept(now: ProcessInfo.processInfo.systemUptime) {
            connection.cancel(); status = "Too many pairing attempts · wait one minute"; return
        }
        client = connection
        connection.stateUpdateHandler = { [weak self, weak connection] value in
            guard let self, let connection, self.client === connection else { return }
            switch value {
            case .ready: self.readHello(connection)
            case .failed, .cancelled: self.dropClient()
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self, weak connection] in
            guard let self, self.client === connection, !self.connected else { return }
            self.dropClient()
        }
        handshakeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + (transport == .wifi ? 15 : 2), execute: timeout)
        connection.start(queue: .main)
    }

    private func readHello(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: StateFrame.hello.count, maximumLength: StateFrame.hello.count) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.client === connection else { return }
            guard data == StateFrame.hello, !complete, error == nil else { self.dropClient(); return }
            self.handshakeTimeout?.cancel(); self.handshakeTimeout = nil
            self.sequence = 0; self.restartLayoutTelemetry()
            self.pairingAttempts.succeeded()
            self.connected = true
            self.status = "\(self.transport.rawValue) connected"
            self.enqueue()
            self.readSetup(connection)
        }
    }

    private func readSetup(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: SetupStage.byteCount, maximumLength: SetupStage.byteCount) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.client === connection else { return }
            guard error == nil, let data else { self.dropClient(); return }
            self.receiveCommands(data)
            if complete { self.dropClient() } else { self.readSetup(connection) }
        }
    }

    private func receiveCommands(_ data: Data) {
        commandBuffer.append(data)
        while commandBuffer.count >= 4 {
            let frame = Data(commandBuffer.prefix(4)); commandBuffer.removeFirst(4)
            do {
                if let rumble = RumbleFrame(data: frame) { gameRumble.apply(state.isPaused ? RumbleFrame() : rumble) }
                else if let stage = try? SetupStage(data: frame) { setupStage = stage }
                else if let command = try commandReceiver.accept(frame) { onLayoutCommand?(command) }
            } catch {
                commandBuffer.removeAll(); commandReceiver = LayoutCommandReceiver()
                status = "Layout update rejected: " + error.localizedDescription
            }
        }
    }

    private func enqueue(_ pointerData: Data? = nil) {
        guard connected else { return }
        var safeState = state
        if !layoutChunks.isEmpty { safeState.isPaused = true }
        var data = layoutChunks.isEmpty ? (pointerData ?? StateFrame(sequence: sequence, state: safeState).encode()) : StateFrame(sequence: sequence, state: safeState).encode()
        sequence &+= 1
        // Keep input gated until the complete layout is applied, but do not
        // throttle USB/TCP metadata to 16 payload bytes per heartbeat. BLE keeps
        // its conservative pacing to respect notification backpressure.
        for _ in 0..<min(layoutChunks.count, bluetooth == nil ? 16 : 1) {
            var chunk = layoutChunks.removeFirst()
            for i in 0..<4 { chunk[8 + i] = UInt8(truncatingIfNeeded: sequence >> (8 * i)) }
            sequence &+= 1
            data.append(chunk)
        }
        if let bluetooth { bluetooth.send(data); return }
        guard pending.count < 64, !sending || ProcessInfo.processInfo.systemUptime - sendStarted < 0.2 else {
            dropClient(); status = "Connection stalled · reconnecting"; return
        }
        pending.append(data)
        flush()
    }

    private func flush() {
        guard !sending, !pending.isEmpty, let client, connected else { return }
        let data = pending.removeFirst()
        sending = true
        sendStarted = ProcessInfo.processInfo.systemUptime
        client.send(content: data, completion: .contentProcessed { [weak self, weak client] error in
            guard let self, self.client === client else { return }
            self.sending = false
            if error != nil { self.dropClient() } else { self.flush() }
        })
    }

    private func dropClient() {
        gameRumble.stop()
        handshakeTimeout?.cancel(); handshakeTimeout = nil
        let old = client; client = nil; old?.cancel()
        connected = false; setupStage = nil; sending = false; pending.removeAll()
        status = "Ready for \(transport.rawValue) · open the Mac companion"
    }
}
