import Foundation

/// Closed vocabulary: no input content, names, identifiers or error descriptions.
public enum UsageMetric: String, Codable, CaseIterable {
    case setupStarted, setupCompleted, connectionAttempt, connectionConnected
    case connectionFailed, connectionDisconnected, connectionStopped, phoneConnectionEnded
    case connectTime, reconnectTime, inputProcessingTime
    case updateOffered, updateDownloaded, updateInstallRequested, updateCompleted, updateFailed
}
public struct UsageMetricCount: Codable, Hashable {
    public let name: UsageMetric
    public let transport: String
    public let bucket: Int
    public var count: Int
}
public struct UsageMetricBuffer {
    public private(set) var enabled = false
    private var counts: [String: UsageMetricCount] = [:]
    public init() {}
    public mutating func setEnabled(_ value: Bool) { enabled = value; counts.removeAll() }
    public static func timingBucket(_ milliseconds: Double) -> Int {
        [5.0, 16, 50, 100, 250, 1000, 3000, 10000].firstIndex { milliseconds <= $0 } ?? 8
    }
    public mutating func record(_ name: UsageMetric, transport: String = "none", milliseconds: Double? = nil) {
        guard enabled, ["none", "usb", "wifi", "bluetooth"].contains(transport) else { return }
        if let milliseconds, !milliseconds.isFinite || milliseconds < 0 { return }
        let bucket = milliseconds.map(Self.timingBucket) ?? -1
        let key = "\(name.rawValue):\(transport):\(bucket)"
        if counts[key] != nil { counts[key]!.count = min(10000, counts[key]!.count + 1) }
        else if counts.count < 128 { counts[key] = UsageMetricCount(name: name, transport: transport, bucket: bucket, count: 1) }
    }
    public mutating func drain() -> [UsageMetricCount] {
        defer { counts.removeAll() }
        return counts.keys.sorted().compactMap { counts[$0] }
    }
}
