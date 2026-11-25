import Foundation

extension LayoutDocument {
    private mutating func editOverride(_ id: String, modeID: String, _ edit: (inout DocumentOverride) -> Void) throws {
        var next = self
        guard controls.contains(where: { $0.id == id }), let index = modes.firstIndex(where: { $0.id == modeID }) else { throw LayoutDocumentError("Unknown control or mode") }
        var overrides = next.modes[index].overrides ?? [:]
        var value = overrides[id] ?? DocumentOverride(); edit(&value)
        overrides[id] = value; next.modes[index].overrides = overrides
        try next.validate(); self = next
    }
    public mutating func resetArrangement(modeID: String) throws {
        var next = self
        guard let index = modes.firstIndex(where: { $0.id == modeID }) else { throw LayoutDocumentError("Unknown mode") }
        next.linkedControls = nil; next.modes[index].sizeFactor = 1
        for control in controls {
            var value = next.modes[index].overrides?[control.id] ?? DocumentOverride()
            value.placement = .null
            if next.modes[index].overrides == nil { next.modes[index].overrides = [:] }
            next.modes[index].overrides?[control.id] = value
        }
        try next.validate(); self = next
    }
    public mutating func resetPlacement(_ id: String, modeID: String) throws {
        var next = self; next.linkedControls?.removeAll { $0 == id }
        try next.editOverride(id, modeID: modeID) { $0.placement = .null }
        self = next
    }
    public mutating func linkControl(_ id: String, linked: Bool, modeID: String, placement: DocumentPlacement) throws {
        var next = self
        var linkedIDs = next.linkedControls ?? []; linkedIDs.removeAll { $0 == id }
        if linked { linkedIDs.append(id) }
        next.linkedControls = linkedIDs
        try next.placeControl(id, at: placement, modeID: modeID)
        self = next
    }
    public mutating func setFeedback(_ id: String, modeID: String, tint: String) throws {
        var feedback = resolvedControl(id, modeID: modeID)?.feedback ?? DocumentFeedback(haptic: haptics ?? "medium", tint: "automatic")
        feedback.tint = tint == "default" ? "automatic" : tint
        try editOverride(id, modeID: modeID) { $0.feedback = .value(feedback) }
    }
    public mutating func setControlVisible(role: String, visible: Bool, modeID: String) throws {
        var next = self
        let id: String
        if let existing = controls.first(where: { $0.role == role }) { id = existing.id }
        else if visible { id = try next.addControl(role: role) }
        else { return }
        try next.editOverride(id, modeID: modeID) { $0.hidden = !visible }
        self = next
    }
    public mutating func hideRadialSources(modeID: String) throws {
        var next = self
        for id in Set(controls.first { $0.role == "radial" }?.radialSlots?.values.map { $0 } ?? []) {
            try next.editOverride(id, modeID: modeID) { $0.hidden = true }
        }
        self = next
    }
    public static let radialDirections = ["up", "upRight", "right", "downRight", "down", "downLeft", "left", "upLeft"]
    public mutating func assignRadial(direction: Int, customSlot: Int) throws {
        var next = self
        guard Self.radialDirections.indices.contains(direction), let index = controls.firstIndex(where: { $0.role == "radial" }) else { throw LayoutDocumentError("Unknown radial direction") }
        let target = controls.first { $0.role == "customButton" && $0.customSlot == customSlot }
        guard customSlot == -1 || target != nil else { throw LayoutDocumentError("Add a custom button before assigning its radial direction") }
        if next.controls[index].radialSlots == nil { next.controls[index].radialSlots = [:] }
        next.controls[index].radialSlots?[Self.radialDirections[direction]] = target?.id
        try next.validate(); self = next
    }

    /// Explicit backend conversion for making a new layout. Never used when loading a document.
    public func converted(to type: LayoutInputType, name: String) throws -> Self {
        var next = self; next.name = name
        guard type.rawValue != inputType else { try next.validate(); return next }
        let compiled = compileInput()
        next.inputType = type.rawValue
        if type == .gamepad {
            next.keyboard = nil; next.gamepad = DocumentGamepadSettings()
            next.controllerStyle = templateStyle
            for id in next.controls.filter({ $0.role == "trackpad" }).map(\.id) { try next.removeControl(id) }
            let equivalents = ["key.space": "gamepad.south", "key.escape": "gamepad.start", "mouse.left": "gamepad.rightTrigger", "mouse.right": "gamepad.leftTrigger", "key.up": "gamepad.dpadUp", "key.right": "gamepad.dpadRight", "key.down": "gamepad.dpadDown", "key.left": "gamepad.dpadLeft"]
            for id in next.actions.keys {
                let action = next.actions[id]!
                next.actions[id]?.outputs = action.outputs.count == 1 && (action.behavior ?? "hold") == "hold" ? action.outputs.first.flatMap { equivalents[$0] }.map { [$0] } ?? [] : []
                next.actions[id]?.behavior = "hold"
            }
            let wasd: [(MappedControl, OutputToken)] = [(.leftUp,.w),(.leftRight,.d),(.leftDown,.s),(.leftLeft,.a)]
            next.gamepad?.disableLeftStick = !wasd.allSatisfy { compiled.keyboard[$0.0].outputs == [$0.1] && compiled.keyboard[$0.0].behavior == .hold }
            next.gamepad?.disableRightStick = !compiled.keyboard.rightStickMouse
            for index in next.controls.indices where ["leftStick", "rightStick"].contains(next.controls[index].role) { next.controls[index].bindings = nil }
        } else {
            next.gamepad = nil; next.controllerStyle = nil
            if next.motion?.mode == "steering" { next.motion?.mode = "off" }
            next.keyboard = DocumentKeyboardSettings(rightStickMouse: compiled.gamepad.disableRightStick != true && !compiled.gamepad.swapSticks)
            // An action is converted once, retaining its identity and every intentional shared reference.
            for id in next.actions.keys {
                let outputs = next.actions[id]!.outputs
                let destination = outputs.first.flatMap { MappedControl(rawValue: String($0.dropFirst("gamepad.".count))) }
                let binding = destination.map { KeyboardProfile.starter[$0] } ?? KeyBinding()
                next.actions[id]?.outputs = binding.outputs.map(\.documentOutput)
                next.actions[id]?.behavior = binding.behavior.rawValue
            }
            let guideIDs = controls.filter { $0.role == "guide" }.map(\.id)
            for id in guideIDs { try next.removeControl(id) }
            if let left = next.controls.first(where: { $0.role == "leftStick" }), compiled.gamepad.disableLeftStick != true && !compiled.gamepad.swapSticks {
                for (direction, key) in [("up", "key.w"), ("right", "key.d"), ("down", "key.s"), ("left", "key.a")] {
                    try next.rebind(.control(id: left.id, direction: direction), outputs: [key])
                }
            }
        }
        try next.validate(); return next
    }
}
