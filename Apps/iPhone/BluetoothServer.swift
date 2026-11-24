import Foundation
import CoreBluetooth

/// Foreground-only BLE peripheral. Notifications carry the same framed stream
/// as USB; split at the negotiated MTU without dropping button edges.
final class BluetoothServer: NSObject, CBPeripheralManagerDelegate {
    var onCommandData: ((Data) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private let code: String
    private var manager: CBPeripheralManager!
    private var dataCharacteristic: CBMutableCharacteristic!
    private var central: CBCentral?
    private var hello = Data()
    private var authenticated = false
    private var stopped = false
    private var pairingAttempts = PairingAttemptLimiter()
    private var pending: [(Data, TimeInterval)] = []
    init(code: String) {
        self.code = WirelessSettings.normalizedCode(code)
        super.init(); manager = CBPeripheralManager(delegate: self, queue: .main)
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard !stopped else { return }
        switch peripheral.state {
        case .poweredOn:
            dataCharacteristic = CBMutableCharacteristic(type: CBUUID(string: WirelessSettings.dataCharacteristic),
                properties: [.notify, .notifyEncryptionRequired], value: nil, permissions: [])
            let control = CBMutableCharacteristic(type: CBUUID(string: WirelessSettings.controlCharacteristic), properties: [.write], value: nil, permissions: [.writeable, .writeEncryptionRequired])
            let service = CBMutableService(type: CBUUID(string: WirelessSettings.service), primary: true)
            service.characteristics = [dataCharacteristic!, control]; peripheral.add(service)
        case .poweredOff: drop(); onStatus?("Turn Bluetooth on")
        case .unauthorized: drop(); onStatus?("Allow Bluetooth access in iPhone Settings")
        case .unsupported: drop(); onStatus?("Bluetooth Low Energy unavailable")
        default: drop()
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard !stopped else { return }
        if let error { onStatus?(error.localizedDescription); return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: WirelessSettings.service)],
                                     CBAdvertisementDataLocalNameKey: WirelessSettings.deviceName()])
        onStatus?("Bluetooth ready · enter this phone's pairing code on the Mac")
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard !stopped, self.central == nil || self.central?.identifier == central.identifier else { return }
        guard pairingAttempts.accept(now: ProcessInfo.processInfo.systemUptime) else { onStatus?("Too many pairing attempts · wait one minute"); return }
        self.central = central; hello = Data(); authenticated = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.authenticated, self.central?.identifier == central.identifier else { return }
            self.drop()
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if self.central?.identifier == central.identifier { drop() }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if authenticated, !stopped, central?.identifier == request.central.identifier,
               request.characteristic.uuid == CBUUID(string: WirelessSettings.controlCharacteristic),
               request.offset == 0, let data = request.value {
                peripheral.respond(to: request, withResult: .success)
                onCommandData?(data)
                continue
            }
            guard !stopped, !authenticated, central?.identifier == request.central.identifier,
                  request.characteristic.uuid == CBUUID(string: WirelessSettings.controlCharacteristic),
                  request.offset == 0, let value = request.value, hello.count + value.count <= StateFrame.hello.count + code.utf8.count + 1 else {
                peripheral.respond(to: request, withResult: .writeNotPermitted); continue
            }
            hello.append(value)
            let expected = StateFrame.hello + Data((code + "\n").utf8)
            guard expected.starts(with: hello) else {
                peripheral.respond(to: request, withResult: .insufficientAuthentication); drop(); continue
            }
            peripheral.respond(to: request, withResult: .success)
            if hello == expected { pairingAttempts.succeeded(); authenticated = true; onConnected?() }
        }
    }
    func send(_ data: Data) {
        guard authenticated, !stopped else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard pending.count < 64, pending.first.map({ now - $0.1 < 0.2 }) ?? true else {
            drop(); onStatus?("Bluetooth stalled · reconnect on Mac"); return
        }
        pending.append((data, now)); flush()
    }
    private func flush() {
        guard let central, authenticated, !stopped else { return }
        while let first = pending.first {
            guard ProcessInfo.processInfo.systemUptime - first.1 < 0.2 else { drop(); return }
            let chunk = Data(first.0.prefix(max(1, central.maximumUpdateValueLength)))
            guard manager.updateValue(chunk, for: dataCharacteristic, onSubscribedCentrals: [central]) else { return }
            if chunk.count == first.0.count { pending.removeFirst() }
            else { pending[0].0.removeFirst(chunk.count) }
        }
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { flush() }
    private func drop() {
        let wasConnected = authenticated
        central = nil; authenticated = false; hello = Data(); pending.removeAll()
        if wasConnected { onDisconnected?() }
    }
    func stop() { stopped = true; drop(); manager.stopAdvertising(); manager.removeAllServices(); manager.delegate = nil }
}
