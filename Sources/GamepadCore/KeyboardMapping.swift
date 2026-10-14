import Foundation

public enum MappedControl: String, Codable, CaseIterable, Sendable {
    case south, east, west, north, leftShoulder, rightShoulder, back, start, leftClick, rightClick
    case leftTrigger, rightTrigger, dpadUp, dpadRight, dpadDown, dpadLeft
    case leftUp, leftRight, leftDown, leftLeft, rightUp, rightRight, rightDown, rightLeft
    case autoRun
    case custom1, custom2, custom3, custom4, custom5, custom6, custom7, custom8
    case custom9, custom10, custom11, custom12, custom13, custom14, custom15, custom16
    public static let customControls: [Self] = [.custom1, .custom2, .custom3, .custom4, .custom5, .custom6, .custom7, .custom8, .custom9, .custom10, .custom11, .custom12, .custom13, .custom14, .custom15, .custom16]
    public var label: String {
        if let index = Self.customControls.firstIndex(of: self) { return "Custom \(index + 1)" }
        return ["autoRun": "Left stick auto-run", "south": "A / ×", "east": "B / ○", "west": "X / □", "north": "Y / △",
         "leftShoulder": "LB / L1", "rightShoulder": "RB / R1", "back": "View / Share", "start": "Menu / Options",
         "leftClick": "L3", "rightClick": "R3", "leftTrigger": "LT / L2", "rightTrigger": "RT / R2",
         "dpadUp": "D-pad ↑", "dpadRight": "D-pad →", "dpadDown": "D-pad ↓", "dpadLeft": "D-pad ←",
         "leftUp": "Left stick ↑", "leftRight": "Left stick →", "leftDown": "Left stick ↓", "leftLeft": "Left stick ←",
         "rightUp": "Right stick ↑", "rightRight": "Right stick →", "rightDown": "Right stick ↓", "rightLeft": "Right stick ←"][rawValue]!
    }
}

/// Physical macOS key positions; names correspond to a US keyboard layout.
public enum OutputToken: String, CaseIterable, Codable, Sendable {
    case mouseLeft, mouseRight, mouseMiddle, scrollUp, scrollDown
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case one, two, three, four, five, six, seven, eight, nine, zero
    case space, shift, control, option, command, tab, escape, enter, backspace
    case up, down, left, right, minus, equal, leftBracket, rightBracket, semicolon, quote, comma, period, slash, backslash, grave
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    public var label: String {
        switch self {
        case .scrollUp: return "Scroll up"
        case .scrollDown: return "Scroll down"
        case .mouseLeft: return "LMB"
        case .mouseRight: return "RMB"
        case .mouseMiddle: return "Middle mouse"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .zero: return "0"
        default: return rawValue.count == 1 ? rawValue.uppercased() : rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
    public var keyCode: UInt16? {
        let codes: [OutputToken: UInt16] = [
            .a:0, .s:1, .d:2, .f:3, .h:4, .g:5, .z:6, .x:7, .c:8, .v:9, .b:11,
            .q:12, .w:13, .e:14, .r:15, .y:16, .t:17, .one:18, .two:19, .three:20,
            .four:21, .six:22, .five:23, .equal:24, .nine:25, .seven:26, .minus:27,
            .eight:28, .zero:29, .rightBracket:30, .o:31, .u:32, .leftBracket:33,
            .i:34, .p:35, .enter:36, .l:37, .j:38, .quote:39, .k:40, .semicolon:41,
            .backslash:42, .comma:43, .slash:44, .n:45, .m:46, .period:47, .tab:48,
            .space:49, .grave:50, .backspace:51, .escape:53, .command:55, .shift:56,
            .option:58, .control:59, .f1:122, .f2:120, .f3:99, .f4:118, .f5:96,
            .f6:97, .f7:98, .f8:100, .f9:101, .f10:109, .f11:103, .f12:111,
            .left:123, .right:124, .down:125, .up:126]
        return codes[self]
    }
}

public struct KeyBinding: Codable, Equatable, Sendable {
    public enum Behavior: String, CaseIterable, Codable, Sendable { case hold, tap }
    public var outputs: [OutputToken]
    public var behavior: Behavior
    public init(_ outputs: [OutputToken] = [], behavior: Behavior = .hold) {
        self.outputs = outputs; self.behavior = behavior
    }
    public var summary: String { outputs.isEmpty ? "Unmapped" : outputs.map(\.label).joined(separator: " + ") }
}

public struct KeyboardProfile: Codable, Equatable, Sendable {
    public var version = 1
    public var bindings: [String: KeyBinding] = [:]
    public var rightStickMouse = true
    public var mouseSpeed = 900.0
    // Optional so profiles saved before smoothing retain all their mappings.
    public var mouseSmoothing: Double?
    public var smoothingTime: Double { mouseSmoothing ?? 0.025 }
    public var relativeGameAim: Bool?
    public var usesRelativeGameAim: Bool { relativeGameAim ?? true }
    public var mouseUpdateRate: Int?
    public var updateRate: Int { [250, 500, 1000].contains(mouseUpdateRate ?? 1000) ? (mouseUpdateRate ?? 1000) : 1000 }
    public var autoRunEnabled: Bool?
    public var autoRunThreshold: Double?
    public var runThreshold: Double { autoRunThreshold ?? 0.8 }
    public var invertMouseY = false
    public var stickThreshold = 0.35
    public var comboGap = 0.03
    public var tapDuration = 0.12
    public init() {}
    public subscript(_ control: MappedControl) -> KeyBinding {
        get {
            if let binding = bindings[control.rawValue] { return binding }
            if control == .autoRun { return KeyBinding([.shift]) }
            if let index = MappedControl.customControls.firstIndex(of: control), index < 8 {
                return KeyBinding([[OutputToken.one, .two, .three, .four, .five, .six, .seven, .eight][index]], behavior: .tap)
            }
            return KeyBinding()
        }
        set { bindings[control.rawValue] = newValue }
    }
    public var sanitized: Self {
        var p = self
        func clamp(_ n: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            n.isFinite ? min(range.upperBound, max(range.lowerBound, n)) : fallback
        }
        p.mouseUpdateRate = mouseUpdateRate == nil ? nil : updateRate
        if let autoRunThreshold { p.autoRunThreshold = clamp(autoRunThreshold, 0.2...0.95, 0.8) }
        p.mouseSpeed = clamp(mouseSpeed, 100...2400, 900)
        if let mouseSmoothing { p.mouseSmoothing = clamp(mouseSmoothing, 0...0.08, 0.025) }
        p.stickThreshold = clamp(stickThreshold, 0.15...0.8, 0.35)
        p.comboGap = clamp(comboGap, 0.01...0.1, 0.03)
        p.tapDuration = clamp(tapDuration, 0.05...0.5, 0.12)
        p.bindings = bindings.mapValues { binding in
            var seen = Set<OutputToken>()
            return KeyBinding(Array(binding.outputs.filter { seen.insert($0).inserted }.prefix(4)), behavior: binding.behavior)
        }
        return p
    }
    public static func restore(_ data: Data?) -> Self {
        guard let data, let p = try? JSONDecoder().decode(Self.self, from: data), p.version == 1 else { return .starter }
        return p.sanitized
    }
    /// Suggested starting bindings, editable to match the game's own settings.
    public static var starter: Self {
        var p = Self()
        p[.leftUp] = KeyBinding([.w]); p[.leftLeft] = KeyBinding([.a])
        p[.leftDown] = KeyBinding([.s]); p[.leftRight] = KeyBinding([.d])
        p[.south] = KeyBinding([.space]); p[.east] = KeyBinding([.mouseRight, .space], behavior: .tap)
        p[.west] = KeyBinding([.e]); p[.north] = KeyBinding([.r])
        p[.leftTrigger] = KeyBinding([.mouseRight]); p[.rightTrigger] = KeyBinding([.mouseLeft])
        p[.leftShoulder] = KeyBinding([.shift]); p[.rightShoulder] = KeyBinding([.mouseMiddle])
        p[.back] = KeyBinding([.tab], behavior: .tap); p[.start] = KeyBinding([.escape], behavior: .tap)
        p[.leftClick] = KeyBinding([.control]); p[.rightClick] = KeyBinding([.q], behavior: .tap)
        p[.dpadUp] = KeyBinding([.one], behavior: .tap); p[.dpadRight] = KeyBinding([.two], behavior: .tap)
        p[.dpadDown] = KeyBinding([.three], behavior: .tap); p[.dpadLeft] = KeyBinding([.four], behavior: .tap)
        return p
    }

    public func activeControls(_ state: GamepadState, previous: Set<MappedControl>) -> Set<MappedControl> {
        guard !state.isPaused else { return [] }
        var active = Set<MappedControl>()
        for (index, control) in MappedControl.allCases.prefix(10).enumerated() where state.buttons & (1 << index) != 0 { active.insert(control) }
        for (slot, control) in MappedControl.customControls.enumerated() where state.customButtons & (UInt16(1) << slot) != 0 { active.insert(control) }
        if state.leftTrigger > 0 { active.insert(.leftTrigger) }
        if state.rightTrigger > 0 { active.insert(.rightTrigger) }
        if [7, 0, 1].contains(state.hat) { active.insert(.dpadUp) }
        if [1, 2, 3].contains(state.hat) { active.insert(.dpadRight) }
        if [3, 4, 5].contains(state.hat) { active.insert(.dpadDown) }
        if [5, 6, 7].contains(state.hat) { active.insert(.dpadLeft) }
        let axes: [(MappedControl, Double)] = [(.leftUp, -Double(state.leftY)), (.leftRight, Double(state.leftX)),
            (.leftDown, Double(state.leftY)), (.leftLeft, -Double(state.leftX))] + (rightStickMouse ? [] :
            [(.rightUp, -Double(state.rightY)), (.rightRight, Double(state.rightX)), (.rightDown, Double(state.rightY)), (.rightLeft, -Double(state.rightX))])
        for (control, value) in axes {
            let threshold = previous.contains(control) ? stickThreshold * 0.75 : stickThreshold
            if value / 32767 > threshold { active.insert(control) }
        }
        if autoRunEnabled == true {
            let radius = hypot(Double(state.leftX), Double(state.leftY)) / 32767
            // Five percentage points of hysteresis prevent chatter near the circle.
            let threshold = previous.contains(.autoRun) ? runThreshold - 0.05 : runThreshold
            if radius >= threshold { active.insert(.autoRun) }
        }
        return active
    }
}

public enum MappedEvent: Equatable, Sendable {
    case down(OutputToken), up(OutputToken)
    case mouse(dx: Double, dy: Double)
}

public struct KeyboardInputGate {
    public enum Status: String {
        case permission = "Accessibility permission missing"
        case stale = "Waiting for fresh controller input"
        case editing = "Layout editing · keyboard/mouse paused"
        case focus = "Paused · focus the selected target app"
        case release = "Release held controls individually to resume them"
        case active = "Keyboard/mouse active · target app focused"
    }
    private var armed = false
    private var suppressed = GamepadState.neutral
    public private(set) var filteredState = GamepadState.neutral
    public init() {}
    public mutating func reset() { armed = false; suppressed = .neutral; filteredState = .neutral }
    public mutating func evaluate(state: GamepadState, lastInput: TimeInterval?, now: TimeInterval, authorized: Bool, focused: Bool) -> Status {
        let reason: Status?
        if !authorized { reason = .permission }
        else if lastInput == nil || now - lastInput! >= 0.25 { reason = .stale }
        else if state.isPaused { reason = .editing }
        else if !focused { reason = .focus }
        else { reason = nil }
        if let reason { reset(); return reason }
        if !armed {
            suppressed = state
            armed = true
        }
        // Require release only for controls held when output resumes. A held
        // movement stick must not prevent a newly pressed attack from working.
        suppressed.buttons &= state.buttons
        suppressed.customButtons &= state.customButtons
        if state.leftTrigger == 0 { suppressed.leftTrigger = 0 }
        if state.rightTrigger == 0 { suppressed.rightTrigger = 0 }
        if state.hat == 8 { suppressed.hat = 8 }
        func centered(_ x: Int16, _ y: Int16) -> Bool { abs(Int(x)) < 2500 && abs(Int(y)) < 2500 }
        if centered(state.leftX, state.leftY) { suppressed.leftX = 0; suppressed.leftY = 0 }
        if centered(state.rightX, state.rightY) { suppressed.rightX = 0; suppressed.rightY = 0 }
        filteredState = state
        filteredState.buttons &= ~suppressed.buttons
        filteredState.customButtons &= ~suppressed.customButtons
        if suppressed.leftTrigger != 0 { filteredState.leftTrigger = 0 }
        if suppressed.rightTrigger != 0 { filteredState.rightTrigger = 0 }
        if suppressed.hat != 8 { filteredState.hat = 8 }
        if !centered(suppressed.leftX, suppressed.leftY) { filteredState.leftX = 0; filteredState.leftY = 0 }
        if !centered(suppressed.rightX, suppressed.rightY) { filteredState.rightX = 0; filteredState.rightY = 0 }
        if suppressed.hasActiveControls && !filteredState.hasActiveControls { return .release }
        return .active
    }
}

/// Pure state machine. Shared outputs are reference-counted across virtual buttons.
/// Timer ticks drive combo timing and mouse motion independently of USB packet rate.
public struct KeyboardMapper {
    private struct Gesture {
        let id: UInt64
        let control: MappedControl?
        let binding: KeyBinding
        let started: TimeInterval
    }
    public let profile: KeyboardProfile
    private var previous = Set<MappedControl>()
    private var gestures: [Gesture] = []
    private var held: [OutputToken] = []
    private var serial: UInt64 = 0
    private var state = GamepadState.neutral
    private var lastMotion: TimeInterval?
    private var velocityX = 0.0, velocityY = 0.0
    public init(profile: KeyboardProfile) { self.profile = profile.sanitized }

    public mutating func receive(_ next: GamepadState, now: TimeInterval) -> [MappedEvent] {
        if next.isPaused { return reset() }
        state = next
        if hypot(Double(next.rightX), Double(next.rightY)) / 32767 <= 0.08 {
            velocityX = 0; velocityY = 0
        }
        let active = profile.activeControls(next, previous: previous)
        gestures.removeAll { $0.binding.behavior == .hold && ($0.control.map { !active.contains($0) } ?? false) }
        for control in MappedControl.allCases where active.contains(control) && !previous.contains(control) {
            var binding = profile[control]
            if control == .autoRun { binding.behavior = .hold }
            // One pulse per control at a time; rapid retriggers cannot accumulate a backlog.
            if !binding.outputs.isEmpty && !gestures.contains(where: { $0.control == control }) {
                serial &+= 1
                gestures.append(Gesture(id: serial, control: control, binding: binding, started: now))
            }
        }
        previous = active
        return advance(now: now, motion: false)
    }

    public var activeOutputs: [OutputToken] { held }
    public mutating func pointerClick(right: Bool, now: TimeInterval) -> [MappedEvent] {
        serial &+= 1
        gestures.append(Gesture(id: serial, control: nil, binding: KeyBinding([right ? .mouseRight : .mouseLeft], behavior: .tap), started: now))
        return advance(now: now, motion: false)
    }
    public mutating func tick(now: TimeInterval) -> [MappedEvent] { advance(now: now, motion: true) }
    public mutating func reset() -> [MappedEvent] {
        let release = held.reversed().map { MappedEvent.up($0) }
        held.removeAll(); gestures.removeAll(); previous.removeAll(); state = .neutral; lastMotion = nil
        velocityX = 0; velocityY = 0
        return release
    }
    private mutating func advance(now: TimeInterval, motion: Bool) -> [MappedEvent] {
        gestures.removeAll { gesture in
            gesture.binding.behavior == .tap && now >= gesture.started + Double(gesture.binding.outputs.count - 1) * profile.comboGap + profile.tapDuration
        }
        var desired: [OutputToken] = []
        for gesture in gestures {
            for (index, token) in gesture.binding.outputs.enumerated() where now >= gesture.started + Double(index) * profile.comboGap {
                // Wheel taps stay single-step even with a long configured tap or combo.
                if gesture.binding.behavior == .tap && (token == .scrollUp || token == .scrollDown),
                   now >= gesture.started + Double(index) * profile.comboGap + 0.12 { continue }
                if !desired.contains(token) { desired.append(token) }
            }
        }
        var events = held.reversed().filter { !desired.contains($0) }.map { MappedEvent.up($0) }
        let retained = held.filter { desired.contains($0) }
        let pressed = desired.filter { !held.contains($0) }
        events += pressed.map { .down($0) }
        held = retained + pressed
        if motion {
            // Discard long scheduling gaps instead of catching up with a large camera jump.
            let dt = min(0.02, max(0, now - (lastMotion ?? now)))
            lastMotion = now
            if profile.rightStickMouse {
                let x = Double(state.rightX) / 32767, y = Double(state.rightY) / 32767
                let magnitude = hypot(x, y)
                if magnitude > 0.08 {
                    let speed = pow(min(1, (magnitude - 0.08) / 0.92), 1.6) * profile.mouseSpeed
                    let targetX = x / magnitude * speed
                    let targetY = y / magnitude * speed * (profile.invertMouseY ? -1 : 1)
                    let tau = profile.smoothingTime
                    let dx: Double, dy: Double
                    if tau > 0 {
                        // Exact integration of exponential velocity smoothing avoids dependence
                        // on timer frequency. 25 ms reaches ~95% of target in 75 ms.
                        let blend = -expm1(-dt / tau)
                        dx = targetX * dt + (velocityX - targetX) * tau * blend
                        dy = targetY * dt + (velocityY - targetY) * tau * blend
                        velocityX += (targetX - velocityX) * blend
                        velocityY += (targetY - velocityY) * blend
                    } else {
                        velocityX = targetX; velocityY = targetY
                        dx = targetX * dt; dy = targetY * dt
                    }
                    if dt > 0 { events.append(.mouse(dx: dx, dy: dy)) }
                } else {
                    velocityX = 0; velocityY = 0
                }
            }
        }
        return events
    }
}


public enum InputTargetPolicy {
    public static func accepts(global: Bool, selectedPID: Int32?, frontmostPID: Int32?) -> Bool {
        global || (selectedPID != nil && selectedPID == frontmostPID)
    }
}
