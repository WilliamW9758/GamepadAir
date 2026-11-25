import Foundation
import Combine
import Network
import CoreBluetooth

struct NearbyPhone: Identifiable, Hashable {
    let id: String
    let name: String
}

final class PhoneDiscovery: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var phones: [NearbyPhone] = []
    @Published var status = ""
    private var browser: NWBrowser?
    private var bluetooth: CBCentralManager?
    private var transport = LinkTransport.usb
    func search(_ transport: LinkTransport) {
        stop(); self.transport = transport; phones = []
        status = "Searching for iPhones…"
        if transport == .wifi {
            let browser = NWBrowser(for: .bonjour(type: WirelessSettings.bonjourService, domain: "local."), using: .tcp)
            self.browser = browser
            browser.stateUpdateHandler = { [weak self, weak browser] state in
                guard let self, self.browser === browser else { return }
                switch state {
                case .waiting(let error), .failed(let error): self.status = "Discovery: \(error.localizedDescription). Allow Local Network access on both devices."
                default: break
                }
            }
            browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
                guard let self, self.browser === browser else { return }
                self.phones = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint { return NearbyPhone(id: "bonjour:" + name, name: name) }
                    return nil
                }.sorted { $0.name < $1.name }
                self.status = self.phones.isEmpty ? "No phones found. Select Wi-Fi on the iPhone and allow Local Network access." : "Select your phone, then enter its six-digit code."
            }
            browser.start(queue: .main)
        } else if transport == .bluetooth {
            bluetooth = CBCentralManager(delegate: self, queue: .main)
        } else { status = "" }
    }
    func stop() {
        browser?.cancel(); browser = nil
        bluetooth?.stopScan(); bluetooth?.delegate = nil; bluetooth = nil
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === bluetooth, transport == .bluetooth else { return }
        if central.state == .poweredOn { central.scanForPeripherals(withServices: [CBUUID(string: WirelessSettings.service)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) }
        else if central.state == .unauthorized { status = "Allow Gamepad Air Bluetooth access in System Settings." }
        else if central.state == .poweredOff { status = "Turn Bluetooth on." }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === bluetooth else { return }
        let id = "ble:" + peripheral.identifier.uuidString
        // CBPeripheral.name can remain cached after a phone changes its advertising name.
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let existing = phones.first { $0.id == id }?.name
        let name = advertisedName ?? existing ?? "iPhone"
        let phone = NearbyPhone(id: id, name: name.range(of: "^PocketPad-[0-9A-Fa-f]{4}$", options: .regularExpression) != nil ? "iPhone" : name)
        if let index = phones.firstIndex(where: { $0.id == id }) {
            if phones[index] != phone { phones[index] = phone }
        } else { phones.append(phone) }
        phones.sort { $0.name < $1.name }
        status = "Select the phone name shown on your iPhone."
    }
    deinit { browser?.cancel(); bluetooth?.stopScan() }
}
