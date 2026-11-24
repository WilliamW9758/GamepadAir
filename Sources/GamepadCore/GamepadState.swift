import Foundation

public enum PadButton: Int, CaseIterable, Codable, Sendable {
    case south, east, west, north, leftShoulder, rightShoulder, back, start, leftClick, rightClick, guide
    public var mask: UInt16 { 1 << rawValue }
}

public enum PointerMode: UInt8, Sendable {
    case profile = 0, cursor = 1, aim = 2
    public func usesRelativeAim(profile: Bool) -> Bool {
        switch self { case .profile: return profile; case .cursor: return false; case .aim: return true }
    }
}

public struct GamepadState: Equatable, Sendable {
    public var isPaused = false
    public var pointerMode = PointerMode.profile
    /// Preview only: 0 idle, 1 touching center, 2...9 selected radial direction.
    public var radialPreview: UInt8 = 0
    public var hasActiveControls: Bool {
        buttons != 0 || customButtons != 0 || hat != 8 || leftX != 0 || leftY != 0 || rightX != 0 || rightY != 0 || leftTrigger != 0 || rightTrigger != 0
    }
    public var buttons: UInt16 = 0
    public var customButtons: UInt16 = 0
    /// Clockwise from north (0); 8 means released.
    public var hat: UInt8 = 8
    public var leftX: Int16 = 0
    public var leftY: Int16 = 0
    public var rightX: Int16 = 0
    public var rightY: Int16 = 0
    public var leftTrigger: UInt8 = 0
    public var rightTrigger: UInt8 = 0
    public init() {}
    public static let neutral = GamepadState()
    public static var paused: GamepadState { var s = GamepadState(); s.isPaused = true; return s }

    public mutating func set(_ button: PadButton, pressed: Bool) {
        if pressed { buttons |= button.mask } else { buttons &= ~button.mask }
    }

    public mutating func setCustom(_ slot: Int, pressed: Bool) {
        guard (0..<16).contains(slot) else { return }
        let mask = UInt16(1) << slot
        if pressed { customButtons |= mask } else { customButtons &= ~mask }
    }

    public static func axis(_ value: Double) -> Int16 {
        guard value.isFinite else { return 0 }
        return Int16((max(-1, min(1, value)) * 32767).rounded())
    }

    /// Radial dead zone; retains the entire remaining analog range.
    public static func stick(x: Double, y: Double, deadZone: Double = 0.12) -> (Int16, Int16) {
        guard x.isFinite, y.isFinite, deadZone >= 0, deadZone < 1 else { return (0, 0) }
        let magnitude = hypot(x, y)
        guard magnitude > deadZone else { return (0, 0) }
        let scaled = (min(1, magnitude) - deadZone) / (1 - deadZone)
        return (axis(x / magnitude * scaled), axis(y / magnitude * scaled))
    }
}

/// Direction sectors use screen coordinates: positive Y points down.
public enum DPadStyle: String, Codable, CaseIterable, Sendable {
    case fourWay, eightWay
    public var title: String { self == .fourWay ? "4 directions" : "8 directions" }
    public var directions: [Int] { self == .fourWay ? [0, 2, 4, 6] : Array(0..<8) }
    public var sectorHalfAngle: Double { self == .fourWay ? .pi / 4 : .pi / 8 }
    public func hat(x: Double, y: Double) -> UInt8 {
        guard x.isFinite, y.isFinite, hypot(x, y) > 0.18 / 0.7 else { return 8 }
        let step = self == .fourWay ? 2 : 1
        let sector = Int((atan2(x, -y) / (.pi / 4 * Double(step))).rounded())
        return UInt8(((sector * step) + 8) % 8)
    }
}

public enum PadStyle: String, CaseIterable, Codable, Sendable {
    case xbox = "Xbox", playStation = "PlayStation"
    public func label(_ button: PadButton) -> String {
        let xbox = ["A", "B", "X", "Y", "LB", "RB", "View", "Menu", "L3", "R3", "Xbox"]
        let ps = ["×", "○", "□", "△", "L1", "R1", "Share", "Options", "L3", "R3", "PS"]
        return (self == .xbox ? xbox : ps)[button.rawValue]
    }
}

/// Positions are fractions of the playable surface; size is relative to the preset.
public struct ControlPlacement: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var scale: Double
    public init(x: Double, y: Double, scale: Double = 1) {
        self.x = x; self.y = y; self.scale = scale
    }
    public var sanitized: Self {
        Self(x: x.isFinite ? max(0, min(1, x)) : 0.5,
             y: y.isFinite ? max(0, min(1, y)) : 0.5,
             scale: scale.isFinite ? max(0.65, min(1.8, scale)) : 1)
    }
    public func fitting(width: Double, height: Double, baseRadius: Double) -> Self {
        var p = sanitized
        guard width > 0, height > 0 else { p.x = 0.5; p.y = 0.5; return p }
        let radius = max(0, baseRadius) * p.scale + 4
        let mx = min(0.5, radius / width), my = min(0.5, radius / height)
        p.x = max(mx, min(1 - mx, p.x)); p.y = max(my, min(1 - my, p.y))
        return p
    }
}

/// Disposable presentation data compiled from a document. Not a storage format.
public struct ResolvedControlPresentation: Equatable {
    public var presets: [String: [String: ControlPlacement]] = [:]
    public var customSlots: [String: [Int]]?
    public var names: [String: [String: String]]?
    public init() {}
    public func customButtons(for style: PadStyle) -> [Int] { customSlots?[style.rawValue] ?? [] }
    public func controls(for style: PadStyle) -> [String: ControlPlacement] { presets[style.rawValue] ?? [:] }
    public mutating func set(_ placement: ControlPlacement, control: String, style: PadStyle) { presets[style.rawValue, default: [:]][control] = placement }
    public mutating func rename(_ control: String, to name: String, style: PadStyle) {
        if names == nil { names = [:] }; names?[style.rawValue, default: [:]][control] = name
    }
}

/// A held attack becomes a floating aiming stick without a mouse jump at activation.
public struct HoldAimGesture {
    public private(set) var isAiming = false
    public private(set) var originX = 0.0
    public private(set) var originY = 0.0
    private var startedAt: TimeInterval?
    public init() {}
    public mutating func begin(now: TimeInterval) { reset(); startedAt = now }
    public mutating func reset() { startedAt = nil; isAiming = false; originX = 0; originY = 0 }
    public mutating func update(x: Double, y: Double, now: TimeInterval, delay: Double, radius: Double) -> (Int16, Int16) {
        guard let startedAt, x.isFinite, y.isFinite, radius.isFinite, radius > 0 else { return (0, 0) }
        if !isAiming {
            guard now - startedAt >= delay else { return (0, 0) }
            // Recenter on the finger at activation, including any pre-threshold drift.
            originX = x; originY = y; isAiming = true
        }
        return GamepadState.stick(x: (x - originX) / radius, y: (y - originY) / radius)
    }
}

public struct TrackpadGesture {
    private var start: TimeInterval?
    private var originX = 0.0, originY = 0.0, lastX = 0.0, lastY = 0.0
    public private(set) var moved = false
    public private(set) var rightClicked = false
    public init() {}
    public mutating func begin(x: Double, y: Double, now: TimeInterval) {
        self = Self(); start = now; originX = x; originY = y; lastX = x; lastY = y
    }
    public mutating func move(x: Double, y: Double) -> (Double, Double) {
        guard start != nil else { return (0, 0) }
        if !moved && hypot(x - originX, y - originY) > 6 { moved = true }
        guard moved else { return (0, 0) }
        let delta = (x - lastX, y - lastY); lastX = x; lastY = y
        return delta
    }
    public mutating func hold(now: TimeInterval, delay: Double) -> PointerAction? {
        guard let start, !moved, !rightClicked, now - start >= delay else { return nil }
        rightClicked = true
        return .rightClick
    }
    public mutating func end(now: TimeInterval, delay: Double) -> PointerAction? {
        defer { self = Self() }
        guard start != nil, !moved, !rightClicked else { return nil }
        return hold(now: now, delay: delay) ?? .leftClick
    }
    public mutating func cancel() { self = Self() }
}

public enum StickTapAction: String, Codable, CaseIterable {
    case off, leftClick, rightTrigger, rightClick, leftTrigger
    public var label: String {
        switch self {
        case .off: return "Off"
        case .leftClick: return "L3 · Sneak mapping"
        case .rightTrigger: return "RT · Attack mapping"
        case .rightClick: return "R3 mapping"
        case .leftTrigger: return "LT · Block mapping"
        }
    }
    public func apply(to state: inout GamepadState) {
        switch self {
        case .off: break
        case .leftClick: state.set(.leftClick, pressed: true)
        case .rightClick: state.set(.rightClick, pressed: true)
        case .rightTrigger: state.rightTrigger = 255
        case .leftTrigger: state.leftTrigger = 255
        }
    }
}

public struct StickGesture {
    public private(set) var originX = 0.0, originY = 0.0
    private var startX = 0.0, startY = 0.0, began = 0.0
    private var moved = false
    public init(x: Double, y: Double, centerX: Double, centerY: Double, floating: Bool, now: Double) {
        startX = x; startY = y; began = now
        originX = floating ? x : centerX; originY = floating ? y : centerY
    }
    public mutating func move(x: Double, y: Double) {
        if hypot(x - startX, y - startY) > 8 { moved = true }
    }
    public func isTap(now: Double) -> Bool { !moved && now - began <= 0.25 }
}

public struct ResolvedLayoutMode: Equatable, Identifiable {
    public var id = UUID().uuidString
    public var name: String
    public var cursor: Bool
    public var controls: ResolvedControlPresentation
    public var showDPad = true
    public var dpadStyle: DPadStyle?
    public var effectiveDPadStyle: DPadStyle { dpadStyle ?? .eightWay }
    public var holdAimEnabled = true
    public var holdAimDelay = 0.3
    public var trackpadHoldDelay = 0.5
    public var floatingLeft = false, floatingRight = false
    public var leftTap = StickTapAction.off, rightTap = StickTapAction.off
    public var sizeFactor = 1.0
    public var radialSlots: [Int]?
    public var radialEnabled: Bool?
    public var radialTitle: String?
    public var hiddenControls: Set<String>?
    public var buttonFeedback: [String: ButtonFeedback]?
    public init(name: String, cursor: Bool, controls: ResolvedControlPresentation = ResolvedControlPresentation()) {
        self.name = name; self.cursor = cursor; self.controls = controls
    }
}

public enum RadialInput {
    /// Empty sectors are shared at the angular midpoint between mapped neighbors.
    public static func direction(x: Double, y: Double, deadZone: Double, slots: [Int]) -> Int? {
        guard x.isFinite, y.isFinite, hypot(x, y) >= max(1, deadZone) else { return nil }
        let angle = atan2(x, -y)
        let mapped = (0..<min(8, slots.count)).filter { (0..<16).contains(slots[$0]) }
        func distance(_ index: Int) -> Double {
            let delta = angle - Double(index) * .pi / 4
            return abs(atan2(sin(delta), cos(delta)))
        }
        return mapped.min { distance($0) < distance($1) }
    }

    public static func direction(x: Double, y: Double, deadZone: Double) -> Int? {
        guard x.isFinite, y.isFinite, hypot(x, y) >= max(1, deadZone) else { return nil }
        return (Int((atan2(x, -y) / (.pi / 4)).rounded()) + 8) % 8
    }
}

/// Optional per-mode preferences keep existing saved layouts unchanged on decode.
public enum ButtonHaptic: String, Codable, CaseIterable { case off = "Off", light = "Light", medium = "Medium", strong = "Strong" }
public enum ButtonTint: String, Codable, CaseIterable { case automatic = "Default", mint = "Mint", blue = "Blue", violet = "Violet", pink = "Pink", red = "Red", orange = "Orange", yellow = "Yellow", white = "White" }
public struct ButtonFeedback: Codable, Equatable {
    public var haptic: ButtonHaptic = .off
    public var tint: ButtonTint = .automatic
    public init(haptic: ButtonHaptic = .off, tint: ButtonTint = .automatic) { self.haptic = haptic; self.tint = tint }
}
