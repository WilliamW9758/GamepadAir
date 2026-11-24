import Foundation

public enum LayoutInputType: String, Codable, CaseIterable, Identifiable {
    case keyboardMouse, gamepad
    public var id: String { rawValue }
    public var title: String { self == .keyboardMouse ? "Keyboard & mouse" : "Controller" }
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
