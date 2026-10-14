import Foundation
import Network
import Combine
import Darwin

/// One selected foreground transport. USB stays loopback-only; wireless is opt-in.
final class CableServer: ObservableObject {
    @Published private(set) var status = "Connect your iPhone to your Mac"
    @Published private(set) var connected = false
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
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard String(cString: item.pointee.ifa_name) == "en0", let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: buffer) }
        }
        return "Join a Wi-Fi network"
    }
    func selectTransport(_ value: LinkTransport) { stop(); transport = value; start() }
    func newPairingCode() {
        stop(); pairingCode = WirelessSettings.newCode(); UserDefaults.standard.set(pairingCode, forKey: "wireless-pairing-code"); start()
    }
    private var listener: NWListener?
    private var client: NWConnection?
    private var timer: Timer?
    private var handshakeTimeout: DispatchWorkItem?
    private var state = GamepadState.neutral
    private var pointerMode = PointerMode.aim
    private var sequence: UInt32 = 0
    private var pending: [Data] = []
    private var sending = false
    private var sendStarted: TimeInterval = 0

    func start() {
        guard listener == nil, bluetooth == nil else { return }
        if transport == .bluetooth {
            let bluetooth = BluetoothServer(code: pairingCode); self.bluetooth = bluetooth
            bluetooth.onConnected = { [weak self] in
                guard let self else { return }; self.sequence = 0; self.connected = true; self.status = "Bluetooth connected"; self.enqueue()
            }
            bluetooth.onDisconnected = { [weak self] in self?.connected = false; self?.status = "Bluetooth ready · reconnect on Mac" }
            bluetooth.onStatus = { [weak self] in self?.status = $0 }
            startHeartbeat(); return
        }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let parameters = transport == .wifi ? WirelessSettings.parameters(code: pairingCode) : NWParameters(tls: nil, tcp: tcp)
            if transport == .usb {
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: StateFrame.port)!)
            } else {
                parameters.requiredLocalEndpoint = .hostPort(host: "0.0.0.0", port: NWEndpoint.Port(rawValue: WirelessSettings.port)!)
                parameters.requiredInterfaceType = .wifi
            }
            let listener = try NWListener(using: parameters)
            if transport == .wifi {
                listener.service = NWListener.Service(name: WirelessSettings.deviceName(), type: WirelessSettings.bonjourService)
            }
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] value in
                guard let self, self.listener === listener else { return }
                switch value {
                case .ready: self.status = self.transport == .wifi ? "Wi-Fi ready · \(self.wifiAddress)" : "Ready for USB · open the Mac companion"
                case .waiting(let error): self.status = "Wi-Fi waiting: \(error.localizedDescription). Allow Local Network in Settings."
                case .failed(let error): self.stop(); self.status = "Listener: \(error.localizedDescription)"
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: .main)
            startHeartbeat()
        } catch { status = "Could not start connection: \(error.localizedDescription)" }
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
        var next = next; next.pointerMode = pointerMode
        guard state != next else { return }
        state = next
        enqueue() // Button edges are sent immediately; timer provides full-state heartbeats.
    }

    func pointer(_ action: PointerAction, dx: Double, dy: Double) {
        guard connected, pointerMode == .cursor, !state.isPaused else { return }
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
            self.sequence = 0
            self.pairingAttempts.succeeded()
            self.connected = true
            self.status = "\(self.transport.rawValue) connected"
            self.enqueue()
            // Any data after the hello violates v1; EOF releases the session too.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self, weak connection] _, _, _, _ in
                guard let self, self.client === connection else { return }
                self.dropClient()
            }
        }
    }

    private func enqueue(_ pointerData: Data? = nil) {
        guard connected else { return }
        if let bluetooth {
            let data = pointerData ?? StateFrame(sequence: sequence, state: state).encode()
            sequence &+= 1; bluetooth.send(data); return
        }
        guard pending.count < 64, !sending || ProcessInfo.processInfo.systemUptime - sendStarted < 0.2 else {
            dropClient(); status = "Connection stalled · reconnecting"; return
        }
        pending.append(pointerData ?? StateFrame(sequence: sequence, state: state).encode())
        sequence &+= 1
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
        handshakeTimeout?.cancel(); handshakeTimeout = nil
        let old = client; client = nil; old?.cancel()
        connected = false; sending = false; pending.removeAll()
        status = "Ready for \(transport.rawValue) · open the Mac companion"
    }
}
