import Foundation

extension OutputToken {
    public var documentOutput: String {
        switch self {
        case .mouseLeft: return "mouse.left"
        case .mouseRight: return "mouse.right"
        case .mouseMiddle: return "mouse.middle"
        case .scrollUp: return "mouse.scrollUp"
        case .scrollDown: return "mouse.scrollDown"
        default: return "key." + rawValue
        }
    }
    public init?(documentOutput: String) {
        let mouse: [String: OutputToken] = ["mouse.left": .mouseLeft, "mouse.right": .mouseRight, "mouse.middle": .mouseMiddle, "mouse.scrollUp": .scrollUp, "mouse.scrollDown": .scrollDown]
        if let value = mouse[documentOutput] { self = value }
        else if documentOutput.hasPrefix("key."), let value = Self(rawValue: String(documentOutput.dropFirst(4))) { self = value }
        else { return nil }
    }
}

extension DocumentControl {
    public func mappedControl(direction: String) -> MappedControl? {
        if role == "customButton", direction == "press", let slot = customSlot, (0..<16).contains(slot) { return MappedControl.customControls[slot] }
        let prefixes = ["leftStick": "left", "rightStick": "right", "dpad": "dpad"]
        if let prefix = prefixes[role], ["up", "right", "down", "left"].contains(direction) {
            return MappedControl(rawValue: prefix + direction.prefix(1).uppercased() + direction.dropFirst())
        }
        return direction == "press" ? MappedControl(rawValue: role) : nil
    }
    /// Fixed input slots are derived from roles, never used as persistent document IDs.
    public var runtimeID: String {
        if let button = PadButton.allCases.first(where: { String(describing: $0) == role }) { return "button-\(button.rawValue)" }
        switch role {
        case "customButton": return "custom-\(customSlot ?? -1)"
        case "leftStick": return "left-stick"
        case "rightStick": return "right-stick"
        case "leftTrigger": return "left-trigger"
        case "rightTrigger": return "right-trigger"
        case "modeSwitch": return "mode-toggle"
        default: return role
        }
    }
}

public struct CompiledLayoutInput {
    public let keyboard: KeyboardProfile
    public let gamepad: GamepadProfile
}

extension LayoutDocument {
    /// Disposable execution profiles. Never encode or use these as an editing source.
    public func compileInput() -> CompiledLayoutInput {
        var k = KeyboardProfile()
        for control in MappedControl.allCases { k[control] = KeyBinding() }
        let settings = keyboard ?? DocumentKeyboardSettings()
        let roles = Set(controls.map(\.role))
        k.rightStickMouse = motion?.mode == "aim" || (roles.contains("rightStick") && (settings.rightStickMouse ?? true))
        k.mouseSpeed = settings.mouseSpeed ?? 900
        k.mouseSmoothing = settings.mouseSmoothing ?? 0.025
        k.relativeGameAim = settings.relativeGameAim ?? true
        k.mouseUpdateRate = settings.mouseUpdateRate ?? 1000
        k.autoRunEnabled = roles.contains("leftStick") && (settings.autoRunEnabled ?? false)
        k.autoRunThreshold = settings.autoRunThreshold ?? 0.8
        k.invertMouseY = settings.invertMouseY ?? false
        k.stickThreshold = settings.stickThreshold ?? 0.35
        k.comboGap = settings.comboGap ?? 0.03; k.tapDuration = settings.tapDuration ?? 0.12
        func binding(_ id: String) -> KeyBinding {
            guard let action = actions[id] else { return KeyBinding() }
            return KeyBinding(action.outputs.compactMap(OutputToken.init(documentOutput:)), behavior: action.behavior == "tap" ? .tap : .hold)
        }
        if let id = settings.autoRunAction { k[.autoRun] = binding(id) }
        var g = GamepadProfile()
        for control in GamepadProfile.controls { g[control] = nil }
        g.swapSticks = gamepad?.swapSticks ?? false
        g.invertLeftY = gamepad?.invertLeftY ?? false; g.invertRightY = gamepad?.invertRightY ?? false
        // Disable missing destination axes, accounting for the runtime's swap-before-disable order.
        let hasLeft = roles.contains("leftStick") || motion?.mode == "steering"
        let hasRight = roles.contains("rightStick") || motion?.mode == "aim"
        g.disableLeftStick = (gamepad?.disableLeftStick ?? false) || !(g.swapSticks ? hasRight : hasLeft)
        g.disableRightStick = (gamepad?.disableRightStick ?? false) || !(g.swapSticks ? hasLeft : hasRight)
        for control in controls {
            for (direction, id) in control.bindings ?? [:] {
                guard let source = control.mappedControl(direction: direction) else { continue }
                if inputType == "keyboardMouse" { k[source] = binding(id) }
                else if let output = actions[id]?.outputs.first, output.hasPrefix("gamepad.") {
                    g[source] = MappedControl(rawValue: String(output.dropFirst(8)))
                }
            }
        }
        return CompiledLayoutInput(keyboard: k, gamepad: g)
    }
    public func radialSlots() -> [Int] {
        let directions = ["up", "upRight", "right", "downRight", "down", "downLeft", "left", "upLeft"]
        let slots = controls.first { $0.role == "radial" }?.radialSlots ?? [:]
        return directions.map { direction in
            guard let id = slots[direction] else { return -1 }
            return controls.first { $0.id == id }?.customSlot ?? -1
        }
    }
    public var padStyle: PadStyle { templateStyle == "playstation" ? .playStation : .xbox }
    public var outputStyle: PadStyle { controllerStyle == "playstation" ? .playStation : .xbox }
}

public struct ResolvedLayoutControl: Equatable, Identifiable {
    public let id: String
    public let runtimeID: String
    public let role: String
    public let label: String
    public let placement: ControlPlacement
    public let radius: Double
    public let width: Double
    public let height: Double
    public let rectangular: Bool
    public let hidden: Bool
    public let feedback: DocumentFeedback?
}

/// Phone and Mac use exactly the same full-canvas fitting and template positions.
public enum LayoutGeometry {
    public static func resolve(_ document: LayoutDocument, modeID: String, width: Double, height: Double) -> [ResolvedLayoutControl] {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              let mode = document.modes.first(where: { $0.id == modeID }) else { return [] }
        let unit = min(height / 320, width / 800) * (mode.sizeFactor ?? 1)
        let ps = document.templateStyle == "playstation"
        let identity = document.inputType == "gamepad" ? document.outputStyle : document.padStyle
        return document.controls.compactMap { base in
            guard let control = document.resolvedControl(base.id, modeID: modeID) else { return nil }
            var x = 0.5, y = 0.5, radius = 23.0, label = control.role
            if let button = PadButton.allCases.first(where: { String(describing: $0) == control.role }) { label = identity.label(button) }
            switch control.role {
            case "south", "east", "west", "north":
                let offsets: [String: (Double, Double)] = ["south": (0,1), "east": (1,0), "west": (-1,0), "north": (0,-1)]
                let offset = offsets[control.role]!
                x = 0.85 + offset.0 * 48 * unit / width; y = 0.44 + offset.1 * 48 * unit / height
            case "leftShoulder": x = 0.26; y = 0.12; radius = 27
            case "rightShoulder": x = 0.74; y = 0.12; radius = 27
            case "leftTrigger": x = 0.12; y = 0.12; radius = 27; label = identity == .playStation ? "L2" : "LT"
            case "rightTrigger": x = 0.88; y = 0.12; radius = 27; label = identity == .playStation ? "R2" : "RT"
            case "back": x = 0.445; y = 0.24; radius = 22
            case "start": x = 0.545; y = 0.24; radius = 22
            case "leftClick": x = 0.435; y = 0.78; radius = 22
            case "rightClick": x = 0.525; y = 0.78; radius = 22
            case "guide": x = 0.5; y = 0.35; radius = 20
            case "leftStick": x = ps ? 0.30 : 0.18; y = ps ? 0.69 : 0.43; radius = 62; label = "L"
            case "rightStick": x = 0.65; y = 0.70; radius = 62; label = "R"
            case "trackpad": x = 0.65; y = 0.55; radius = 62; label = "Trackpad"
            case "dpad": x = ps ? 0.14 : 0.355; y = ps ? 0.43 : 0.66; radius = 50; label = "✣"
            case "modeSwitch": x = 0.5; y = 0.15; radius = 25; label = mode.name
            case "radial": radius = 30; label = "Quick bar"
            case "customButton":
                let slot = control.customSlot ?? 0
                x = 0.10 + Double(slot % 8) * 0.11; y = slot < 8 ? 0.91 : 0.51; radius = 19; label = "C\(slot + 1)"
            default: break
            }
            let p = control.placement.map { ControlPlacement(x: $0.x, y: $0.y, scale: $0.scale ?? 1) } ?? ControlPlacement(x: x, y: y)
            var fitted = p.fitting(width: width, height: height, baseRadius: radius * unit)
            let rectangular = control.role == "trackpad" || control.placement?.width != nil
            let w = rectangular ? min(max(0, width - 8), (control.placement?.width ?? 0.28) * width) : radius * unit * fitted.scale * 2
            let h = rectangular ? min(max(0, height - 8), (control.placement?.height ?? 0.4) * height) : radius * unit * fitted.scale * 2
            if rectangular {
                fitted.x = min(1 - (w / 2 + 4) / width, max((w / 2 + 4) / width, p.x))
                fitted.y = min(1 - (h / 2 + 4) / height, max((h / 2 + 4) / height, p.y))
            }
            return ResolvedLayoutControl(id: control.id, runtimeID: control.runtimeID, role: control.role,
                                         label: control.label ?? label, placement: fitted, radius: radius * unit * fitted.scale,
                                         width: w, height: h, rectangular: rectangular, hidden: control.hidden ?? false, feedback: control.feedback)
        }
    }
}

extension LayoutGeometry {
    /// Conservative bounds feedback includes round controls' bounding boxes.
    public static func overlappingIDs(_ controls: [ResolvedLayoutControl], width: Double, height: Double) -> Set<String> {
        let visible = controls.filter { !$0.hidden }
        var result = Set<String>()
        for i in visible.indices {
            for j in visible.indices where j > i {
                let a = visible[i], b = visible[j]
                if abs(a.placement.x - b.placement.x) * width < (a.width + b.width) / 2,
                   abs(a.placement.y - b.placement.y) * height < (a.height + b.height) / 2 {
                    result.insert(a.id); result.insert(b.id)
                }
            }
        }
        return result
    }
    public static func fitted(_ p: ControlPlacement, canvasWidth: Double, canvasHeight: Double, controlWidth: Double, controlHeight: Double) -> ControlPlacement {
        var result = p
        let insetX = min(0.5, (controlWidth / 2 + 4) / max(1, canvasWidth))
        let insetY = min(0.5, (controlHeight / 2 + 4) / max(1, canvasHeight))
        result.x = min(1 - insetX, max(insetX, p.x)); result.y = min(1 - insetY, max(insetY, p.y))
        return result
    }
    public static func snapped(_ p: ControlPlacement, others: [ControlPlacement]) -> ControlPlacement {
        var result = p
        result.x = (p.x * 40).rounded() / 40; result.y = (p.y * 20).rounded() / 20
        if let x = ([0.5] + others.map(\.x)).min(by: { abs($0 - p.x) < abs($1 - p.x) }), abs(x - p.x) < 0.012 { result.x = x }
        if let y = ([0.5] + others.map(\.y)).min(by: { abs($0 - p.y) < abs($1 - p.y) }), abs(y - p.y) < 0.02 { result.y = y }
        return result
    }
}
