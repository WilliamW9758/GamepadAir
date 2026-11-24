import Foundation

public struct RumbleFrame: Equatable {
    public var low: UInt8
    public var high: UInt8
    public init(low: UInt8 = 0, high: UInt8 = 0) { self.low = low; self.high = high }
    public var data: Data { Data([0x49, 0x52, low, high]) }
    public init?(data: Data) {
        let b = Array(data)
        guard b.count == 4, b[0] == 0x49, b[1] == 0x52 else { return nil }
        low = b[2]; high = b[3]
    }
    /// Decode only known motor output reports, not lighting/configuration writes.
    public static func decodeHID(_ data: Data, reportID: Int, style: PadStyle) -> Self? {
        let b = Array(data)
        if style == .playStation {
            guard reportID == 5, b.count >= 7, b[0] == 5, b[1] & 1 != 0 else { return nil }
            return Self(low: b[5], high: b[4])
        }
        guard reportID == 3, b.count >= 9, b[0] == 3 else { return nil }
        func scale(_ value: UInt8) -> UInt8 { UInt8(min(100, Int(value)) * 255 / 100) }
        return Self(low: b[1] & 2 != 0 ? scale(b[4]) : 0,
                    high: b[1] & 1 != 0 ? scale(b[5]) : 0)
    }
}
