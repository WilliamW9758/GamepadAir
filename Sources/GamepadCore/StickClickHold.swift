import Foundation

/// Latches a stick click after dwelling near center. Moving before activation
/// cancels this touch's hold; moving after activation keeps the click held.
public struct StickClickHold {
    public private(set) var pressed = false
    private var eligible = true
    private let began: TimeInterval
    public init(now: TimeInterval) { began = now }
    public mutating func update(x: Double, y: Double, now: TimeInterval) {
        guard !pressed, eligible else { return }
        guard hypot(x, y) <= 0.20 else { eligible = false; return }
        if now - began >= 0.45 { pressed = true }
    }
}
