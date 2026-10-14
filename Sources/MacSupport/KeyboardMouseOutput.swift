import AppKit
import CoreGraphics
#if SWIFT_PACKAGE
import GamepadCore
#endif

public enum InputDiagnostics {
    public static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PocketPad/input-trace.log")
    }
}

/// Records only Pocket Pad input edges/output decisions, never system keyboard activity.
private final class InputTrace {
    private let writer = DispatchQueue(label: "gamepad.input-trace", qos: .utility)
    private var file: FileHandle?
    private var bytes = 0
    init() {
        let url = InputDiagnostics.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 512_000 {
            let previous = url.deletingLastPathComponent().appendingPathComponent("input-trace.previous.log")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: url, to: previous)
        }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        file = try? FileHandle(forWritingTo: url)
        bytes = Int((try? file?.seekToEnd()) ?? 0)
        record("SESSION \(Date())")
    }
    func record(_ text: String) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let date = Date()
        writer.async { [self] in write(text, uptime: uptime, date: date) }
    }
    private func write(_ text: String, uptime: TimeInterval, date: Date) {
        if bytes >= 512_000 {
            try? file?.close()
            let url = InputDiagnostics.url
            let previous = url.deletingLastPathComponent().appendingPathComponent("input-trace.previous.log")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: url, to: previous)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            file = try? FileHandle(forWritingTo: url); bytes = 0
        }
        let line = String(format: "%.3f ", uptime) + date.ISO8601Format() + " " + text + "\n"
        let data = Data(line.utf8); try? file?.write(contentsOf: data); bytes += data.count
    }
    deinit { try? file?.close() }
}

/// Passive observation of this process's tagged mouse clicks only. No physical
/// clicks or keyboard events are recorded, and the event stream is never changed.
private final class MouseDeliveryObserver {
    static let marker: Int64 = 0x504F434B00000000 | Int64(ProcessInfo.processInfo.processIdentifier)
    private let trace: InputTrace
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    init(trace: InputTrace) {
        self.trace = trace
        DispatchQueue.main.async { self.start() }
    }
    private func start() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        port = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                                options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let observer = Unmanaged<MouseDeliveryObserver>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                observer.trace.record("OBSERVER temporarily disabled type=\(type.rawValue)")
                if let port = observer.port { CGEvent.tapEnable(tap: port, enable: true) }
            } else if event.getIntegerValueField(.eventSourceUserData) == MouseDeliveryObserver.marker {
                observer.trace.record("OS_CLICK type=\(type.rawValue) number=\(event.getIntegerValueField(.mouseEventNumber)) targetPID=\(event.getIntegerValueField(.eventTargetUnixProcessID)) frontPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) flags=\(event.flags.rawValue) position=\(event.location)")
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            if let port { CFMachPortInvalidate(port) }; self.port = nil
            trace.record("OBSERVER unavailable; OS delivery cannot be verified with current permissions")
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        trace.record("OBSERVER active: own mouse clicks at annotated session stage")
    }
    func stop() {
        // Main-run-loop ownership keeps callback context alive until invalidation.
        DispatchQueue.main.async {
            if let port = self.port { CFMachPortInvalidate(port) }
            if let source = self.runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            self.port = nil; self.runLoopSource = nil
        }
    }
}

public enum KeyboardMousePermissions {
    public static var allowed: Bool { CGPreflightPostEventAccess() }
    @discardableResult public static func request() -> Bool { CGRequestPostEventAccess() }
}

/// Explicit mouse chronology: down/drag/up share an event number per button.
/// Constructors on the target Mac produce timestamp=0 and eventNumber=0.
struct MouseEventSequence {
    private var nextNumber: Int64 = 0
    private var numbers: [UInt32: Int64] = [:]
    mutating func prepare(_ event: CGEvent, button: CGMouseButton, down: Bool?, timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        if down == true {
            nextNumber = nextNumber == Int64.max ? 1 : nextNumber + 1
            numbers[button.rawValue] = nextNumber
        }
        event.timestamp = timestamp
        event.setIntegerValueField(.mouseEventNumber, value: numbers[button.rawValue] ?? 0)
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        if down != nil || numbers[button.rawValue] != nil {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        if down == false { numbers[button.rawValue] = nil }
    }
}

/// Relative game motion carries deltas without accumulating an absolute cursor
/// position. Desktop mode moves the cursor but never emits off-display clicks.
struct MousePositioning {
    static func position(current: CGPoint, dx: Double = 0, dy: Double = 0,
                         relative: Bool, displays: [CGRect]) -> CGPoint {
        let screens = displays.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        guard !screens.isEmpty else { return .zero }
        func distance(_ rect: CGRect) -> Double {
            let x = min(rect.maxX, max(rect.minX, current.x))
            let y = min(rect.maxY, max(rect.minY, current.y))
            return hypot(current.x - x, current.y - y)
        }
        let screen = screens.first(where: { $0.contains(current) }) ?? screens.min(by: { distance($0) < distance($1) })!
        let safe = screen.contains(current) ? current : CGPoint(x: screen.midX, y: screen.midY)
        if relative { return safe }
        let proposed = CGPoint(x: safe.x + dx, y: safe.y + dy)
        if screens.contains(where: { $0.contains(proposed) }) { return proposed }
        return CGPoint(x: min(screen.maxX - 1, max(screen.minX, proposed.x)),
                       y: min(screen.maxY - 1, max(screen.minY, proposed.y)))
    }
}

final class KeyboardMouseOutput: GamepadOutput {
    private let queue = DispatchQueue(label: "gamepad.keyboard-mouse", qos: .userInteractive)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var timer: DispatchSourceTimer?
    private var mapper: KeyboardMapper
    private let targetPID: Int32?
    private let relativeGameAim: Bool
    private var displayBounds: [CGRect] = []
    private var pointerActiveUntil = 0.0
    private var lastInput: TimeInterval?
    private let trace = InputTrace()
    private var deliveryObserver: MouseDeliveryObserver?
    private var latest = GamepadState.neutral
    private var gate = KeyboardInputGate()
    private var closed = false
    private var permissionCheckedAt = -Double.infinity
    private var focusCheckedAt = -Double.infinity
    private var permissionAllowed = false
    private var targetFocused = false
    private var previousTick: TimeInterval?
    private var timingWindow = ProcessInfo.processInfo.systemUptime
    private var maximumTickGap = 0.0, maximumInputGap = 0.0
    private var timingTicks = 0, timingInputs = 0, lateTicks = 0
    private var message = "Release controls, then focus your target app"
    private var posted = Set<OutputToken>()
    private var scrollRepeat: [OutputToken: TimeInterval] = [:]
    private var mouseSequence = MouseEventSequence()
    private var remainderX = 0.0, remainderY = 0.0
    private let source = CGEventSource(stateID: .privateState)
    var statusDescription: String { queue.sync { targetPID == nil && message == KeyboardInputGate.Status.active.rawValue ? "Keyboard/mouse active · global" : message } }
    var interpretedInput: String { queue.sync {
        guard message == KeyboardInputGate.Status.active.rawValue else { return "Paused · no output" }
        var labels = mapper.activeOutputs.map(\.label)
        if mapper.profile.rightStickMouse && (latest.rightX != 0 || latest.rightY != 0) { labels.append("Mouse look") }
        if ProcessInfo.processInfo.systemUptime < pointerActiveUntil { labels.append("Pointer move") }
        return labels.isEmpty ? "No input" : labels.joined(separator: " + ")
    } }

    init(profile: KeyboardProfile, targetPID: Int32?, global: Bool = false) throws {
        guard KeyboardMousePermissions.allowed else {
            throw LinkError.message("Keyboard/mouse output needs Accessibility permission. Use Enable Accessibility in the Mac app, then reconnect.")
        }
        if !global {
            guard let targetPID, NSRunningApplication(processIdentifier: targetPID) != nil else {
                throw LinkError.message("Choose Global or a running target app before connecting.")
            }
        }
        self.targetPID = global ? nil : targetPID
        relativeGameAim = profile.usesRelativeGameAim
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(32, &displays, &displayCount)
        displayBounds = displays.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
        trace.record("MOUSE relativeGameAim=\(relativeGameAim) displays=\(displayBounds)")
        trace.record(global ? "TARGET global" : "TARGET pid=\(targetPID ?? 0)")
        mapper = KeyboardMapper(profile: profile)
        deliveryObserver = MouseDeliveryObserver(trace: trace)
        queue.setSpecific(key: queueKey, value: true)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .microseconds(1_000_000 / profile.updateRate), leeway: .microseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
    }
    func submit(_ state: GamepadState) throws {
        queue.sync {
            guard !closed else { return }
            if state.pointerMode != latest.pointerMode { trace.record("POINTER mode=\(state.pointerMode)") }
            if state.rightTrigger != latest.rightTrigger || state.leftTrigger != latest.leftTrigger {
                trace.record("INPUT RT=\(state.rightTrigger) LT=\(state.leftTrigger) left=(\(state.leftX),\(state.leftY)) right=(\(state.rightX),\(state.rightY))")
            }
            let now = ProcessInfo.processInfo.systemUptime
            if let lastInput { maximumInputGap = max(maximumInputGap, now - lastInput) }
            timingInputs += 1
            latest = state; lastInput = now
            if ready() { emit(mapper.receive(gate.filteredState, now: lastInput!)) }
        }
    }
    func pointer(_ frame: PointerFrame) throws {
        queue.sync {
            guard !closed, latest.pointerMode == .cursor, ready() else { return }
            if frame.action == .move { pointerActiveUntil = ProcessInfo.processInfo.systemUptime + 0.1; move(dx: Double(frame.dx) / 16 * 2, dy: Double(frame.dy) / 16 * 2) }
            else { emit(mapper.pointerClick(right: frame.action == .rightClick, now: ProcessInfo.processInfo.systemUptime)) }
        }
    }
    func reset() throws {
        queue.sync { disarm(); latest = .neutral; lastInput = nil }
    }
    func close() {
        // The timer's last temporary strong reference can be released on this queue.
        if DispatchQueue.getSpecific(key: queueKey) == true { closeOnQueue() }
        else { queue.sync { closeOnQueue() } }
    }
    private func closeOnQueue() {
        guard !closed else { return }
        timer?.cancel(); timer = nil
        disarm(); deliveryObserver?.stop(); deliveryObserver = nil; closed = true
    }
    deinit { close() }

    private func tick() {
        guard !closed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let previousTick {
            let gap = now - previousTick
            maximumTickGap = max(maximumTickGap, gap)
            if gap > 0.008 { lateTicks += 1 }
        }
        previousTick = now; timingTicks += 1
        if now - timingWindow >= 5 {
            trace.record(String(format: "TIMING seconds=%.2f ticks=%d inputFrames=%d maxTickMs=%.2f ticksOver8ms=%d maxInputMs=%.2f", now - timingWindow, timingTicks, timingInputs, maximumTickGap * 1000, lateTicks, maximumInputGap * 1000))
            timingWindow = now; timingTicks = 0; timingInputs = 0; lateTicks = 0
            maximumTickGap = 0; maximumInputGap = 0
        }
        guard ready() else { return }
        emit(mapper.tick(now: now))
        for token in [OutputToken.scrollUp, .scrollDown] {
            if let due = scrollRepeat[token], now >= due { scroll(token); scrollRepeat[token] = now + 0.1 }
        }
    }
    private func ready() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        // System queries are not mouse samples. Bound their cost separately while
        // evaluating pause and USB freshness on every output tick.
        if now - permissionCheckedAt >= 0.25 {
            permissionAllowed = KeyboardMousePermissions.allowed; permissionCheckedAt = now
        }
        if now - focusCheckedAt >= 0.008 {
            targetFocused = InputTargetPolicy.accepts(global: targetPID == nil, selectedPID: targetPID, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
            focusCheckedAt = now
        }
        let status = gate.evaluate(state: latest, lastInput: lastInput, now: now,
                                   authorized: permissionAllowed, focused: targetFocused)
        if message != status.rawValue { trace.record("GATE \(status.rawValue)") }
        message = status.rawValue
        if status != .active { emit(mapper.reset()); remainderX = 0; remainderY = 0; return false }
        return true
    }
    private func disarm() {
        trace.record("RESET output")
        pointerActiveUntil = 0
        emit(mapper.reset()); gate.reset(); remainderX = 0; remainderY = 0
    }

    private var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if posted.contains(.shift) { flags.insert(.maskShift) }
        if posted.contains(.control) { flags.insert(.maskControl) }
        if posted.contains(.option) { flags.insert(.maskAlternate) }
        if posted.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
    private func emit(_ events: [MappedEvent]) {
        for event in events {
            switch event {
            case .down(let token): post(token, down: true)
            case .up(let token): post(token, down: false)
            case .mouse(let dx, let dy): move(dx: dx, dy: dy)
            }
        }
    }
    private func scroll(_ token: OutputToken) {
        let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1,
                            wheel1: token == .scrollUp ? 1 : -1, wheel2: 0, wheel3: 0)
        event?.timestamp = DispatchTime.now().uptimeNanoseconds
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
    private func post(_ token: OutputToken, down: Bool) {
        if token == .scrollUp || token == .scrollDown {
            if down { scroll(token); scrollRepeat[token] = ProcessInfo.processInfo.systemUptime + 0.35 }
            else { scrollRepeat[token] = nil }
            return
        }
        trace.record("OUTPUT \(token.rawValue) \(down ? "down" : "up")")
        if down { posted.insert(token) } else { posted.remove(token) }
        let event: CGEvent?
        if let code = token.keyCode {
            event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        } else {
            let button: CGMouseButton = token == .mouseLeft ? .left : token == .mouseRight ? .right : .center
            let type: CGEventType = token == .mouseLeft ? (down ? .leftMouseDown : .leftMouseUp) :
                token == .mouseRight ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
            event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: MousePositioning.position(current: CGEvent(source: nil)?.location ?? .zero, relative: true, displays: displayBounds), mouseButton: button)
            if let event { mouseSequence.prepare(event, button: button, down: down) }
        }
        if event == nil { trace.record("ERROR could not construct \(token.rawValue) event") }
        event?.timestamp = DispatchTime.now().uptimeNanoseconds
        event?.flags = flags
        event?.setIntegerValueField(.eventSourceUserData, value: MouseDeliveryObserver.marker)
        if let event, token.keyCode == nil { trace.record("POST_CLICK type=\(event.type.rawValue) number=\(event.getIntegerValueField(.mouseEventNumber)) flags=\(event.flags.rawValue) position=\(event.location)") }
        event?.post(tap: .cghidEventTap)
    }
    private func move(dx: Double, dy: Double) {
        remainderX += dx; remainderY += dy
        let x = Int64(remainderX.rounded(.towardZero)), y = Int64(remainderY.rounded(.towardZero))
        remainderX -= Double(x); remainderY -= Double(y)
        guard x != 0 || y != 0 else { return }
        let point = CGEvent(source: nil)?.location ?? .zero
        let button: CGMouseButton = posted.contains(.mouseLeft) ? .left : posted.contains(.mouseRight) ? .right : .center
        let type: CGEventType = posted.contains(.mouseLeft) ? .leftMouseDragged : posted.contains(.mouseRight) ? .rightMouseDragged :
            posted.contains(.mouseMiddle) ? .otherMouseDragged : .mouseMoved
        let event = CGEvent(mouseEventSource: source, mouseType: type,
                            mouseCursorPosition: MousePositioning.position(current: point, dx: Double(x), dy: Double(y), relative: latest.pointerMode.usesRelativeAim(profile: relativeGameAim), displays: displayBounds), mouseButton: button)
        if let event { mouseSequence.prepare(event, button: button, down: nil) }
        event?.setIntegerValueField(.mouseEventDeltaX, value: x)
        event?.setIntegerValueField(.mouseEventDeltaY, value: y)
        event?.flags = flags.union(.maskNonCoalesced)
        event?.post(tap: .cghidEventTap)
    }
}
