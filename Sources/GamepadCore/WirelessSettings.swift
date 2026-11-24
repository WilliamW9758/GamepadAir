import Foundation
import Network
import Security
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

public enum LinkTransport: String, CaseIterable, Codable {
    case usb = "USB cable", wifi = "Wi-Fi", bluetooth = "Bluetooth"
}

public enum WirelessSettings {
    public static let port: UInt16 = 27184
    public static let service = "7DF753E4-0122-47CF-A167-B91C725DDD01"
    public static let dataCharacteristic = "7DF753E4-0122-47CF-A167-B91C725DDD02"
    public static let controlCharacteristic = "7DF753E4-0122-47CF-A167-B91C725DDD03"
    public static let bonjourService = "_pocketpad._tcp"
    public static func normalizedCode(_ code: String) -> String { code.filter { "0123456789".contains($0) } }
    public static func validCode(_ code: String) -> Bool {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count == 6 && value.allSatisfy { "0123456789".contains($0) }
    }
    public static func newCode() -> String { String(format: "%06d", Int.random(in: 0...999999)) }
    public static func formattedCode(_ code: String) -> String { normalizedCode(code) }
    public static func deviceName() -> String {
        if let name = UserDefaults.standard.string(forKey: "custom-device-name"), !name.isEmpty { return name }
#if canImport(UIKit)
        return UIDevice.current.name
#else
        return "iPhone"
#endif
    }
    public static func setDeviceName(_ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        UserDefaults.standard.set(clean, forKey: "custom-device-name")
    }
    public static func parameters(code: String) -> NWParameters {
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let tls = NWProtocolTLS.Options()
        let secret = Data(SHA256.hash(data: Data(normalizedCode(code).utf8)))
        let identity = Data("PocketPad-1".utf8)
        secret.withUnsafeBytes { key in identity.withUnsafeBytes { name in
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, DispatchData(bytes: key) as AnyObject as! dispatch_data_t, DispatchData(bytes: name) as AnyObject as! dispatch_data_t)
        } }
        // Ephemeral key exchange prevents passive offline PIN guessing from TLS captures.
        // Failed live attempts are separately rate-limited by the phone.
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: UInt16(TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256))!)
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }
}


public struct PairingAttemptLimiter {
    private var attempts: [TimeInterval] = []
    public init() {}
    public mutating func accept(now: TimeInterval) -> Bool {
        attempts.removeAll { now - $0 >= 60 }
        guard attempts.count < 5 else { return false }
        attempts.append(now); return true
    }
    public mutating func succeeded() { attempts.removeAll() }
}
