import Foundation

/// A calibrated angular displacement becomes a bounded analog axis.
public enum MotionInput {
    public static func axis(angle: Double, sensitivity: Double, deadZone: Double) -> Double {
        guard angle.isFinite, sensitivity.isFinite, deadZone.isFinite else { return 0 }
        let value = max(-1, min(1, angle * max(0.1, min(4, sensitivity)) / 0.6))
        let dead = max(0, min(0.3, deadZone))
        guard abs(value) > dead else { return 0 }
        return (value < 0 ? -1 : 1) * (abs(value) - dead) / (1 - dead)
    }
}
