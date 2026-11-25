import Foundation
import Network
import CoreBluetooth
#if SWIFT_PACKAGE
import GamepadCore
#endif

protocol InputLink: AnyObject {
    func readExactly(_ count: Int, timeout: TimeInterval) throws -> Data
    func write(_ data: Data) throws
    func interrupt()
}
extension StreamSocket: InputLink {}

/// Bounded stream assembly, shared by TCP and BLE notifications. No partial
/// packet can extend the caller's deadline or be interpreted as a fresh state.
final class LinkInbox {
    private let condition = NSCondition()
    private var bytes = Data()
    private var failure: String?
    private var ready = false
    func markReady() { condition.lock(); ready = true; condition.broadcast(); condition.unlock() }
    func fail(_ message: String) { condition.lock(); failure = message; condition.broadcast(); condition.unlock() }
    func append(_ data: Data) {
        condition.lock(); defer { condition.unlock() }
        guard failure == nil else { return }
        if bytes.count + data.count > 8192 { failure = "Wireless input backlog; reconnect" }
        else { bytes.append(data) }
        condition.broadcast()
    }
    private func wait(until predicate: () -> Bool, timeout: TimeInterval) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !predicate() {
            if let failure { throw LinkError.message(failure) }
            let left = deadline - ProcessInfo.processInfo.systemUptime
            guard left > 0 else { throw LinkError.message("Wireless input timed out; controls released") }
            condition.wait(until: Date(timeIntervalSinceNow: min(left, 0.1)))
        }
        if let failure { throw LinkError.message(failure) }
    }
    func awaitReady(timeout: TimeInterval) throws {
        condition.lock(); defer { condition.unlock() }
        try wait(until: { ready }, timeout: timeout)
    }
    func read(_ count: Int, timeout: TimeInterval) throws -> Data {
        condition.lock(); defer { condition.unlock() }
        try wait(until: { bytes.count >= count }, timeout: timeout)
        let result = Data(bytes.prefix(count)); bytes.removeFirst(count); return result
    }
}

final class WiFiLink: InputLink {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "gamepad.wifi", qos: .userInteractive)
    private let inbox = LinkInbox()
    init(host: String, code: String, port: UInt16 = WirelessSettings.port) {
        let endpoint: NWEndpoint = host.hasPrefix("bonjour:")
            ? .service(name: String(host.dropFirst(8)), type: WirelessSettings.bonjourService, domain: "local.", interface: nil)
            : .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        connection = NWConnection(to: endpoint, using: WirelessSettings.parameters(code: code))
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.inbox.markReady(); self.receive()
            case .waiting(let error), .failed(let error): self.inbox.fail(Self.failureMessage(error, localNetworkDenied: self.connection.currentPath?.unsatisfiedReason == .localNetworkDenied))
            case .cancelled: self.inbox.fail("Wi-Fi disconnected")
            default: break
            }
        }
        connection.start(queue: queue)
    }
    static func failureMessage(_ error: NWError, localNetworkDenied: Bool) -> String {
        if localNetworkDenied { return "Local Network access is blocked. Enable Gamepad Air in System Settings → Privacy & Security → Local Network; allow it on the iPhone too." }
        switch error {
        case .posix(.EHOSTDOWN), .posix(.EHOSTUNREACH), .posix(.ENETDOWN), .posix(.ENETUNREACH), .posix(.ETIMEDOUT):
            return "iPhone is unreachable (\(error)). Find it again, check the same Wi-Fi network and Local Network permissions on both devices. Guest networks or VPNs may block access."
        case .posix(.ECONNREFUSED): return "iPhone refused the connection. Select Wi-Fi in Gamepad Air on the phone and keep it open."
        case .tls: return "Pairing failed. Enter the current six-digit code and update both apps."
        default: return "Wi-Fi: \(error.localizedDescription)"
        }
    }
    func prepare(timeout: TimeInterval = 15) throws {
        do { try inbox.awaitReady(timeout: timeout) }
        catch {
            if error.localizedDescription.contains("timed out") {
                throw LinkError.message("iPhone did not respond. Find it again; check Wi-Fi mode, Local Network permissions, and that both devices are on the same network.")
            }
            throw error
        }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.inbox.append(data) }
            if complete || error != nil { self.inbox.fail("Wi-Fi connection closed") }
            else { self.receive() }
        }
    }
    func readExactly(_ count: Int, timeout: TimeInterval) throws -> Data { try inbox.read(count, timeout: timeout) }
    func write(_ data: Data) throws {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.inbox.fail(error.localizedDescription) }
        })
    }
    func interrupt() { inbox.fail("Wi-Fi disconnected"); connection.cancel() }
    deinit { connection.cancel() }
}

final class BluetoothLink: NSObject, InputLink, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let queue = DispatchQueue(label: "gamepad.bluetooth", qos: .userInteractive)
    private let inbox = LinkInbox()
    private let code: String
    private let deviceID: UUID
    private var manager: CBCentralManager!
    private var peer: CBPeripheral?
    private var control: CBCharacteristic?
    private var notifications: CBCharacteristic?
    private var writes: [Data] = []
    private var writing = false
    private var stopped = false
    init(code: String, deviceID: UUID) {
        self.deviceID = deviceID
        self.code = WirelessSettings.normalizedCode(code)
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue)
    }
    func prepare() throws { try inbox.awaitReady(timeout: 30) }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !stopped else { return }
        switch central.state {
        case .poweredOn: central.scanForPeripherals(withServices: [CBUUID(string: WirelessSettings.service)])
        case .poweredOff: inbox.fail("Turn Bluetooth on on this Mac")
        case .unauthorized: inbox.fail("Allow Gamepad Air Bluetooth access in System Settings")
        case .unsupported: inbox.fail("Bluetooth Low Energy is unavailable")
        default: break
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !stopped, peer == nil,
              peripheral.identifier == deviceID else { return }
        peer = peripheral; peripheral.delegate = self
        central.stopScan(); central.connect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !stopped else { central.cancelPeripheralConnection(peripheral); return }
        peripheral.discoverServices([CBUUID(string: WirelessSettings.service)])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { inbox.fail("Bluetooth connection failed") }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { inbox.fail("Bluetooth disconnected") }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first else { inbox.fail("Bluetooth service unavailable"); return }
        peripheral.discoverCharacteristics([CBUUID(string: WirelessSettings.dataCharacteristic), CBUUID(string: WirelessSettings.controlCharacteristic)], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { inbox.fail("Bluetooth characteristics unavailable"); return }
        control = service.characteristics?.first { $0.uuid == CBUUID(string: WirelessSettings.controlCharacteristic) }
        notifications = service.characteristics?.first { $0.uuid == CBUUID(string: WirelessSettings.dataCharacteristic) }
        guard control != nil, let notifications else { inbox.fail("Bluetooth protocol mismatch"); return }
        peripheral.setNotifyValue(true, for: notifications)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil || !characteristic.isNotifying { inbox.fail("Bluetooth pairing/subscription failed") }
        else { inbox.markReady() }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == CBUUID(string: WirelessSettings.dataCharacteristic), error == nil, let data = characteristic.value else {
            inbox.fail("Invalid Bluetooth notification"); return
        }
        inbox.append(data)
    }
    func readExactly(_ count: Int, timeout: TimeInterval) throws -> Data { try inbox.read(count, timeout: timeout) }
    func write(_ data: Data) throws {
        queue.async { [weak self] in
            guard let self, !self.stopped, let peer = self.peer else { return }
            let payload = data == StateFrame.hello ? data + Data((self.code + "\n").utf8) : data
            let limit = max(1, peer.maximumWriteValueLength(for: .withResponse))
            for start in stride(from: 0, to: payload.count, by: limit) { self.writes.append(Data(payload[start..<min(start + limit, payload.count)])) }
            self.flush()
        }
    }
    private func flush() {
        guard !stopped, !writing, !writes.isEmpty, let peer, let control else { return }
        writing = true; peer.writeValue(writes.removeFirst(), for: control, type: .withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writing = false
        if error != nil { inbox.fail("Bluetooth authentication failed") } else { flush() }
    }
    func interrupt() {
        inbox.fail("Bluetooth disconnected")
        queue.async { [self] in stopped = true; manager.stopScan(); if let peer { manager.cancelPeripheralConnection(peer) }; manager.delegate = nil; peer?.delegate = nil }
    }
}
