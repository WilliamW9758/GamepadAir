import Foundation

extension LayoutDocument {
    public static func starter(name: String, style: PadStyle, input: LayoutInputType = .keyboardMouse) -> Self {
        var actions: [String: DocumentAction] = [:]
        var controls: [DocumentControl] = []
        let roles = PadButton.allCases.map { String(describing: $0) } + ["leftTrigger", "rightTrigger", "leftStick", "rightStick", "dpad"]
        let keyboard = KeyboardProfile.starter
        for role in roles where role != "guide" || input == .gamepad {
            let id = role.lowercased()
            var control = DocumentControl(id: id, role: role)
            let directions = ["leftStick", "rightStick", "dpad"].contains(role) ? ["up", "right", "down", "left"] : ["press"]
            for direction in directions {
                guard let mapped = control.mappedControl(direction: direction),
                      !(input == .gamepad && ["leftStick", "rightStick"].contains(role)),
                      !(input == .keyboardMouse && role == "rightStick") else { continue }
                let actionID = id + "-" + direction
                if input == .gamepad { actions[actionID] = DocumentAction(label: mapped.label, outputs: ["gamepad." + mapped.rawValue]) }
                else {
                    let binding = keyboard[mapped]
                    actions[actionID] = DocumentAction(label: mapped.label, outputs: binding.outputs.map(\.documentOutput), behavior: binding.behavior.rawValue)
                }
                if control.bindings == nil { control.bindings = [:] }
                control.bindings?[direction] = actionID
            }
            controls.append(control)
        }
        return Self(name: name, inputType: input.rawValue, templateStyle: style == .xbox ? "xbox" : "playstation",
                    controllerStyle: input == .gamepad ? (style == .xbox ? "xbox" : "playstation") : nil,
                    actions: actions, controls: controls,
                    modes: [DocumentMode(id: "play", name: "Play", floatingLeft: true, floatingRight: true)], initialMode: "play")
    }
}

extension LocalLayout {
    public init(name: String, style: PadStyle, input: LayoutInputType = .keyboardMouse) {
        self.init(document: .starter(name: name, style: style, input: input))
    }
    public var name: String { get { document.name } set { document.name = newValue } }
    public var style: PadStyle { document.padStyle }
    public var effectiveInputType: LayoutInputType { LayoutInputType(rawValue: document.inputType)! }
    public var effectiveControllerStyle: PadStyle { document.inputType == "gamepad" ? document.outputStyle : document.padStyle }
    public var effectiveTouchHaptic: ButtonHaptic { ButtonHaptic.allCases.first { $0.rawValue.lowercased() == (document.haptics ?? "medium") } ?? .medium }
    public var hasCursorSwitching: Bool { document.modes.count > 1 }
    public var keyboardProfile: KeyboardProfile { document.compileInput().keyboard }
    public var gamepadProfile: GamepadProfile { document.compileInput().gamepad }
    public func controlID(runtimeID: String) -> String? { document.controls.first { $0.runtimeID == runtimeID }?.id }
}
