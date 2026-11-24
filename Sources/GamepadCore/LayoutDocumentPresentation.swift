import Foundation

extension LocalLayout {
    /// Read-only view for existing gesture/rendering code. This is never saved or edited.
    public func resolvedMode(_ modeID: String) -> ResolvedLayoutMode {
        let source = document.modes.first { $0.id == modeID } ?? document.modes[0]
        var mode = ResolvedLayoutMode(name: source.name, cursor: source.pointerMode == "cursor")
        mode.id = source.id
        mode.sizeFactor = source.sizeFactor ?? 1; mode.dpadStyle = DPadStyle(rawValue: source.dpadStyle ?? "eightWay")
        mode.holdAimEnabled = source.holdAimEnabled ?? true; mode.holdAimDelay = source.holdAimDelay ?? 0.3
        mode.trackpadHoldDelay = source.trackpadHoldDelay ?? 0.5
        mode.floatingLeft = source.floatingLeft ?? false; mode.floatingRight = source.floatingRight ?? false
        mode.leftTap = StickTapAction(rawValue: source.leftTap ?? "off") ?? .off
        mode.rightTap = StickTapAction(rawValue: source.rightTap ?? "off") ?? .off
        let allIDs = Set(PadButton.allCases.map { "button-\($0.rawValue)" } + ["left-stick", "right-stick", "left-trigger", "right-trigger", "dpad", "radial", "mode-toggle"] + (0..<16).map { "custom-\($0)" })
        var visible = Set<String>()
        mode.showDPad = false; mode.radialEnabled = false; mode.radialSlots = document.radialSlots()
        for base in document.controls {
            guard let control = document.resolvedControl(base.id, modeID: source.id) else { continue }
            let id = control.runtimeID
            if control.hidden != true { visible.insert(id) }
            if let p = control.placement { mode.controls.set(ControlPlacement(x: p.x, y: p.y, scale: p.scale ?? 1), control: id, style: style) }
            if let label = control.label { mode.controls.rename(id, to: label, style: style) }
            if control.role == "dpad" { mode.showDPad = control.hidden != true }
            if control.role == "radial" { mode.radialEnabled = control.hidden != true; mode.radialTitle = control.label }
            if control.role == "customButton", let slot = control.customSlot {
                if mode.controls.customSlots == nil { mode.controls.customSlots = [:] }
                mode.controls.customSlots?[style.rawValue, default: []].append(slot)
            }
            if let feedback = control.feedback {
                if mode.buttonFeedback == nil { mode.buttonFeedback = [:] }
                mode.buttonFeedback?[id] = ButtonFeedback(
                    haptic: ButtonHaptic.allCases.first { $0.rawValue.lowercased() == feedback.haptic } ?? .off,
                    tint: ButtonTint.allCases.first { $0.rawValue.lowercased() == feedback.tint } ?? .automatic)
            }
        }
        mode.hiddenControls = allIDs.subtracting(visible)
        return mode
    }
    public func displayLabels(modeID: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: LayoutGeometry.resolve(document, modeID: modeID, width: 800, height: 360).map { ($0.runtimeID, $0.label) })
    }
    public func reference(for mapped: MappedControl) -> LayoutBindingReference? {
        if mapped == .autoRun { return .autoRun }
        for control in document.controls {
            for direction in ["press", "up", "right", "down", "left"] where control.mappedControl(direction: direction) == mapped {
                return .control(id: control.id, direction: direction)
            }
        }
        return nil
    }
    public var unmappedControls: [MappedControl] {
        document.controls.flatMap { control in
            ["press", "up", "right", "down", "left"].compactMap { direction -> MappedControl? in
                guard let mapped = control.mappedControl(direction: direction) else { return nil }
                if effectiveInputType == .gamepad && ["leftStick", "rightStick"].contains(control.role) {
                    let disabled = control.role == "leftStick" ? document.gamepad?.disableLeftStick : document.gamepad?.disableRightStick
                    return disabled == true ? mapped : nil
                }
                if effectiveInputType == .keyboardMouse && control.role == "rightStick" && (document.keyboard?.rightStickMouse ?? true) { return nil }
                let action = control.bindings?[direction].flatMap { document.actions[$0] }
                return action?.outputs.isEmpty != false ? mapped : nil
            }
        }
    }
}

extension LayoutDocument {
    public mutating func setModeSwitching(_ enabled: Bool) {
        if enabled && modes.count == 1 {
            var second = modes[0]; second.id = modes[0].id == "cursor" ? "alternate" : "cursor"
            second.name = "Cursor"; second.pointerMode = "cursor"; modes.append(second)
            var id = "mode-switch"; while controls.contains(where: { $0.id == id }) { id += "-new" }
            controls.append(DocumentControl(id: id, role: "modeSwitch", command: "cycleModes"))
        } else if !enabled && modes.count > 1 {
            modes = [modes[0]]
            let removed = Set(controls.filter { $0.role == "modeSwitch" }.map(\.id))
            controls.removeAll { removed.contains($0.id) }
            linkedControls?.removeAll { removed.contains($0) }
            modes[0].overrides = modes[0].overrides?.filter { !removed.contains($0.key) }
        }
    }
    @discardableResult public mutating func addControl(role: String) throws -> String {
        var next = self
        guard role == "customButton" || !controls.contains(where: { $0.role == role }) else { throw LayoutDocumentError("This control already exists") }
        let used = Set(controls.compactMap(\.customSlot))
        let slot = (0..<16).first { !used.contains($0) }
        if role == "customButton" && slot == nil { throw LayoutDocumentError("All 16 custom slots are in use") }
        let stem = role.lowercased(); var id = stem; var suffix = 2
        while controls.contains(where: { $0.id == id }) { id = "\(stem)-\(suffix)"; suffix += 1 }
        next.controls.append(DocumentControl(id: id, role: role, customSlot: role == "customButton" ? slot : nil,
                                             placement: DocumentPlacement(x: 0.5, y: 0.5)))
        try next.validate(); self = next; return id
    }
}
