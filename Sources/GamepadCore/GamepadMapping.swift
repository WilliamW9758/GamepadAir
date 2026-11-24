import Foundation

/// Gamepad bindings are deliberately separate from keyboard/mouse bindings.
public struct GamepadProfile: Codable, Equatable {
    public var version = 1
    public var bindings: [String: String] = [:]
    public var swapSticks = false
    public var disableLeftStick: Bool?
    public var disableRightStick: Bool?
    public var invertLeftY = false
    public var invertRightY = false
    public init() {}
    public static let controls: [MappedControl] = destinations + MappedControl.customControls
    public static let destinations: [MappedControl] = [
        .south, .east, .west, .north, .leftShoulder, .rightShoulder,
        .back, .start, .leftClick, .rightClick, .guide, .leftTrigger, .rightTrigger,
        .dpadUp, .dpadRight, .dpadDown, .dpadLeft
    ]

    public subscript(_ control: MappedControl) -> MappedControl? {
        get {
            if let value = bindings[control.rawValue] {
                return Self.destinations.first { $0.rawValue == value }
            }
            return Self.destinations.contains(control) ? control : nil
        }
        set { bindings[control.rawValue] = newValue?.rawValue ?? "none" }
    }
    public static func restore(_ data: Data?) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 else { return Self() }
        return value
    }
    public func apply(_ input: GamepadState) -> GamepadState {
        guard !input.isPaused else { return .neutral }
        var result = GamepadState()
        result.leftX = swapSticks ? input.rightX : input.leftX
        result.leftY = swapSticks ? input.rightY : input.leftY
        result.rightX = swapSticks ? input.leftX : input.rightX
        result.rightY = swapSticks ? input.leftY : input.rightY
        // The wire rejects -32768; also tolerate it in locally constructed states.
        func axis(_ value: Int16, invert: Bool = false) -> Int16 {
            Int16(max(-32767, min(32767, Int(value) * (invert ? -1 : 1))))
        }
        result.leftX = axis(result.leftX); result.rightX = axis(result.rightX)
        result.leftY = axis(result.leftY, invert: invertLeftY)
        result.rightY = axis(result.rightY, invert: invertRightY)
        if disableLeftStick == true { result.leftX = 0; result.leftY = 0 }
        if disableRightStick == true { result.rightX = 0; result.rightY = 0 }
        let active = KeyboardProfile.starter.activeControls(input, previous: [])
        var directions = Set<MappedControl>()
        for source in Self.controls where active.contains(source) {
            guard let destination = self[source] else { continue }
            if let index = Self.destinations.prefix(PadButton.allCases.count).firstIndex(of: destination) { result.buttons |= 1 << index }
            else if destination == .leftTrigger { result.leftTrigger = max(result.leftTrigger, source == .leftTrigger ? input.leftTrigger : source == .rightTrigger ? input.rightTrigger : 255) }
            else if destination == .rightTrigger { result.rightTrigger = max(result.rightTrigger, source == .leftTrigger ? input.leftTrigger : source == .rightTrigger ? input.rightTrigger : 255) }
            else { directions.insert(destination) }
        }
        let x = (directions.contains(.dpadRight) ? 1 : 0) - (directions.contains(.dpadLeft) ? 1 : 0)
        let y = (directions.contains(.dpadDown) ? 1 : 0) - (directions.contains(.dpadUp) ? 1 : 0)
        switch (x, y) {
        case (0, -1): result.hat = 0
        case (1, -1): result.hat = 1
        case (1, 0): result.hat = 2
        case (1, 1): result.hat = 3
        case (0, 1): result.hat = 4
        case (-1, 1): result.hat = 5
        case (-1, 0): result.hat = 6
        case (-1, -1): result.hat = 7
        default: result.hat = 8
        }
        return result
    }
    public func summary(_ input: GamepadState) -> String {
        let state = apply(input)
        let active = KeyboardProfile.starter.activeControls(state, previous: [])
        var labels = Self.destinations.filter { active.contains($0) }.map(\.label)
        if state.leftX != 0 || state.leftY != 0 { labels.append("Left stick") }
        if state.rightX != 0 || state.rightY != 0 { labels.append("Right stick") }
        return labels.isEmpty ? "No gamepad input" : labels.joined(separator: " + ")
    }
}
