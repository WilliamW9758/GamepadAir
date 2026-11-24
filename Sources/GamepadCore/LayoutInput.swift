import Foundation

public enum LayoutInputType: String, Codable, CaseIterable, Identifiable {
    case keyboardMouse, gamepad
    public var id: String { rawValue }
    public var title: String { self == .keyboardMouse ? "Keyboard & mouse" : "Controller" }
}
extension SavedLayout {
    public var effectiveInputType: LayoutInputType { inputType ?? .keyboardMouse }
    public var presentControls: [MappedControl] {
        var controls = Array(GamepadProfile.destinations.prefix(PadButton.allCases.count + 2))
        if effectiveInputType != .gamepad { controls.removeAll { $0 == .guide } }
        if modes.contains(where: { $0.showDPad }) { controls += [.dpadUp, .dpadRight, .dpadDown, .dpadLeft] }
        let slots = Set(modes.flatMap { mode in
            mode.controls.customButtons(for: style) + (mode.radialEnabled == true ? (mode.radialSlots ?? Array(0..<8)).filter { $0 >= 0 } : [])
        })
        controls += slots.filter { (0..<MappedControl.customControls.count).contains($0) }.sorted().map { MappedControl.customControls[$0] }
        return controls.filter { control in modes.contains { !($0.hiddenControls ?? []).contains(control.canvasID) } }
    }
    public var unmappedControls: [MappedControl] {
        if effectiveInputType == .gamepad {
            let profile = gamepadProfile ?? GamepadProfile()
            var result = presentControls.filter { profile[$0] == nil }
            if profile.disableLeftStick == true { result += [.leftUp, .leftRight, .leftDown, .leftLeft] }
            if profile.disableRightStick == true { result += [.rightUp, .rightRight, .rightDown, .rightLeft] }
            return result.filter { control in modes.contains { !($0.hiddenControls ?? []).contains(control.canvasID) } }
        }
        let profile = keyboardProfile ?? .starter
        var result = presentControls.filter { profile[$0].outputs.isEmpty }
        result += [MappedControl.leftUp, .leftRight, .leftDown, .leftLeft].filter { profile[$0].outputs.isEmpty }
        if !profile.rightStickMouse {
            result += [MappedControl.rightUp, .rightRight, .rightDown, .rightLeft].filter { profile[$0].outputs.isEmpty }
        }
        return result.filter { control in modes.contains { !($0.hiddenControls ?? []).contains(control.canvasID) } }
    }
    public func converted(to type: LayoutInputType) -> SavedLayout {
        var copy = self; copy.inputType = type
        guard type != effectiveInputType else {
            if type == .keyboardMouse { copy.keyboardProfile = keyboardProfile ?? .starter }
            else { copy.gamepadProfile = gamepadProfile ?? GamepadProfile() }
            return copy
        }
        if type == .gamepad {
            let keyboard = keyboardProfile ?? .starter
            var gamepad = GamepadProfile()
            // Only explicit, single-input equivalents. Combos are never guessed.
            let equivalents: [OutputToken: MappedControl] = [
                .space: .south, .escape: .start, .mouseLeft: .rightTrigger, .mouseRight: .leftTrigger,
                .up: .dpadUp, .right: .dpadRight, .down: .dpadDown, .left: .dpadLeft
            ]
            for control in GamepadProfile.controls {
                if control == .guide { continue } // Newly available system button keeps its native binding.
                let binding = keyboard[control]
                gamepad[control] = binding.outputs.count == 1 ? equivalents[binding.outputs[0]] : nil
            }
            let wasd: [(MappedControl, OutputToken)] = [(.leftUp,.w),(.leftRight,.d),(.leftDown,.s),(.leftLeft,.a)]
            gamepad.disableLeftStick = !wasd.allSatisfy { keyboard[$0.0].outputs == [$0.1] && keyboard[$0.0].behavior == .hold }
            gamepad.disableRightStick = !keyboard.rightStickMouse
            copy.gamepadProfile = gamepad
        } else {
            let gamepad = gamepadProfile ?? GamepadProfile()
            var keyboard = KeyboardProfile.starter
            for control in GamepadProfile.controls {
                if let destination = gamepad[control] { keyboard[control] = KeyboardProfile.starter[destination] }
                else { keyboard[control] = KeyBinding() }
            }
            if gamepad.disableLeftStick == true || gamepad.swapSticks {
                for control in [MappedControl.leftUp, .leftRight, .leftDown, .leftLeft] { keyboard[control] = KeyBinding() }
            }
            keyboard.rightStickMouse = gamepad.disableRightStick != true && !gamepad.swapSticks
            if !keyboard.rightStickMouse {
                for control in [MappedControl.rightUp, .rightRight, .rightDown, .rightLeft] { keyboard[control] = KeyBinding() }
            }
            copy.keyboardProfile = keyboard
        }
        return copy
    }
}
extension MappedControl {
    public var canvasID: String {
        if let slot = Self.customControls.firstIndex(of: self) { return "custom-\(slot)" }
        if let index = GamepadProfile.destinations.prefix(PadButton.allCases.count).firstIndex(of: self) { return "button-\(index)" }
        switch self {
        case .leftTrigger: return "left-trigger"
        case .rightTrigger: return "right-trigger"
        case .leftUp, .leftRight, .leftDown, .leftLeft, .autoRun: return "left-stick"
        case .rightUp, .rightRight, .rightDown, .rightLeft: return "right-stick"
        default: return "dpad"
        }
    }
}

extension SavedLayout {
    /// Geometry and saved overrides belong to the template; default captions follow output identity.
    public func displayLabels(modeIndex: Int) -> [String: String] {
        guard modes.indices.contains(modeIndex) else { return [:] }
        let identity = effectiveInputType == .gamepad ? effectiveControllerStyle : style
        var labels = Dictionary(uniqueKeysWithValues: PadButton.allCases.map {
            ("button-\($0.rawValue)", identity.label($0))
        })
        labels["left-trigger"] = identity == .playStation ? "L2" : "LT"
        labels["right-trigger"] = identity == .playStation ? "R2" : "RT"
        labels.merge(modes[modeIndex].controls.labels(for: style)) { _, custom in custom }
        return labels
    }

    public func controlLabel(_ control: MappedControl, modeIndex: Int) -> String {
        guard modes.indices.contains(modeIndex),
              let name = modes[modeIndex].controls.labels(for: style)[control.canvasID], !name.isEmpty else {
            return effectiveInputType == .gamepad ? (displayLabels(modeIndex: modeIndex)[control.canvasID] ?? control.label) : control.label
        }
        let direction: String?
        switch control {
        case .leftUp, .rightUp, .dpadUp: direction = "Up"
        case .leftRight, .rightRight, .dpadRight: direction = "Right"
        case .leftDown, .rightDown, .dpadDown: direction = "Down"
        case .leftLeft, .rightLeft, .dpadLeft: direction = "Left"
        case .autoRun: direction = "Run"
        default: direction = nil
        }
        return direction.map { name + " · " + $0 } ?? name
    }
}
