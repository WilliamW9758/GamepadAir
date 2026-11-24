import CoreHaptics
import Foundation

/// Main-thread haptic playback with a short lease: lost links cannot leave the
/// phone vibrating. Game motor channels become intensity and sharpness.
final class GameRumble {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var expires: DispatchWorkItem?
    private var current = RumbleFrame()
    func apply(_ value: RumbleFrame) {
        expires?.cancel()
        guard value != RumbleFrame(), CHHapticEngine.capabilitiesForHardware().supportsHaptics else { stop(); return }
        let expiry = DispatchWorkItem { [weak self] in self?.stop() }
        expires = expiry; DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: expiry)
        if value == current, player != nil { return }
        do {
            if engine == nil {
                let created = try CHHapticEngine()
                created.resetHandler = { [weak self] in
                    DispatchQueue.main.async { self?.stop(); self?.engine = nil }
                }
                created.stoppedHandler = { [weak self] _ in
                    DispatchQueue.main.async { self?.stop() }
                }
                engine = created
            }
            try engine?.start()
            if player == nil {
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: 0, duration: 1)
                player = try engine?.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                player?.loopEnabled = true
                try player?.start(atTime: CHHapticTimeImmediate)
            }
            let low = Float(value.low) / 255, high = Float(value.high) / 255
            try player?.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: max(low, high), relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: high / max(0.001, low + high), relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
            current = value
        } catch { stop(); engine = nil }
    }
    func stop() {
        expires?.cancel(); expires = nil
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil; current = RumbleFrame()
    }
}
