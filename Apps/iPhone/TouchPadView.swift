import UIKit

/// UIKit owns individual touches, allowing two sticks plus simultaneous buttons.
final class TouchPadView: UIView {
    enum Control: Hashable {
        case custom(Int), button(PadButton), leftStick, rightStick, dpad, leftTrigger, rightTrigger, modeToggle, radial
        var id: String {
            switch self {
            case .custom(let slot): return "custom-\(slot)"
            case .button(let button): return "button-\(button.rawValue)"
            case .leftStick: return "left-stick"
            case .rightStick: return "right-stick"
            case .dpad: return "dpad"
            case .radial: return "radial"
            case .modeToggle: return "mode-toggle"
            case .leftTrigger: return "left-trigger"
            case .rightTrigger: return "right-trigger"
            }
        }
    }
    struct Item { let control: Control; let center: CGPoint; let radius: CGFloat; let label: String }
    var hiddenControls = Set<String>()
    var unmapped = Set<String>()
    var referencePlacements: [String: ControlPlacement] = [:]
    var referenceSizeFactor = 1.0
    var referenceAvailable = true
    var showGhost = true
    var onReference: ((ControlPlacement?) -> Void)?
    var onCanvasSize: ((CGSize) -> Void)?
    private func reference(for item: Item) -> ControlPlacement? {
        guard showsModeSwitch, referenceAvailable, let base = presetItems.first(where: { $0.control == item.control }) else { return nil }
        var p = referencePlacements[item.control.id] ?? ControlPlacement(x: base.center.x / max(1, bounds.width), y: base.center.y / max(1, bounds.height))
        p.scale *= referenceSizeFactor / max(0.01, sizeFactor)
        return p
    }
    var buttonFeedback: [String: ButtonFeedback] = [:]
    var touchHaptic: ButtonHaptic = .medium
    private static let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private static let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private static let strongHaptic = UIImpactFeedbackGenerator(style: .heavy)
    static func playHaptic(_ kind: ButtonHaptic, intensity: Double = 1) {
        switch kind {
        case .off: return
        case .light: lightHaptic.impactOccurred(intensity: CGFloat(max(0, min(1, intensity))))
        case .medium: mediumHaptic.impactOccurred(intensity: CGFloat(max(0, min(1, intensity))))
        case .strong: strongHaptic.impactOccurred(intensity: CGFloat(max(0, min(1, intensity))))
        }
    }
    private func pressHaptic(_ control: Control) {
        Self.playHaptic(touchHaptic)
    }
    var style = PadStyle.xbox
    var radialEnabled = false
    var radialSlots = Array(0..<8)
    var radialTitle = "Quick bar"
    var onRename: ((String, String) -> Void)?
    private var radialChoice: Int?
    private var radialOrigin = CGPoint.zero
    private var radialPulses = Set<Int>()
    private var radialEnds: [Int: DispatchWorkItem] = [:]
    var modeName = "Aim"
    var onToggle: (() -> Void)?
    var floatingLeft = true, floatingRight = true
    var leftTap = StickTapAction.off, rightTap = StickTapAction.off
    var legacyCanvas = false
    var sizeFactor = 1.0
    var onMigration: (([String: ControlPlacement], Double) -> Void)?
    private var migrationSent = false
    private var stickGestures: [Control: StickGesture] = [:]
    private var stickClickHolds: [Control: StickClickHold] = [:]
    private var stickHoldWork: [Control: DispatchWorkItem] = [:]
    private var pulses: [UUID: StickTapAction] = [:]
    private var pulseEnds: [UUID: DispatchWorkItem] = [:]
    var showDPad = true
    var showsModeSwitch = true
    var cursorMode = false
    var trackpadHoldDelay = 0.5
    var onPointer: ((PointerAction, Double, Double) -> Void)?
    private var trackpad = TrackpadGesture()
    private var trackpadActivation: DispatchWorkItem?
    var holdAimEnabled = true
    var holdAimDelay = 0.3
    private var holdAim = HoldAimGesture()
    private var aimActivation: DispatchWorkItem?
    var customSlots: [Int] = []
    var labels: [String: String] = [:]
    var onState: ((GamepadState) -> Void)?
    var placements: [String: ControlPlacement] = [:]
    var selectedID: String?
    var onSelect: ((String, String, ControlPlacement) -> Void)?
    var onPlacement: ((String, ControlPlacement) -> Void)?
    var onEditEnded: (() -> Void)?
    var editing = false {
        didSet { if editing != oldValue { touches.removeAll(); cancelSticks(); cancelAim(); cancelTrackpad(); editTouch = nil; refresh() } }
    }
    private var editTouch: ObjectIdentifier?
    private var editControl: Control?
    private var dragOffset = CGPoint.zero
    private var previousSize = CGSize.zero
    private var touches: [ObjectIdentifier: (control: Control, point: CGPoint)] = [:]
    private var state = GamepadState.neutral

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        accessibilityLabel = "Gamepad touch controls"
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: TouchPadView, _: UITraitCollection) in view.setNeedsDisplay()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var showsGuideButton = false
    var guideLabel = "Xbox"

    private var presetItems: [Item] {
        let w = bounds.width, h = bounds.height
        let unit = min(h / 320, w / 800) * sizeFactor
        func item(_ c: Control, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ label: String) -> Item {
            Item(control: c, center: CGPoint(x: w * x, y: h * y), radius: r * unit, label: label)
        }
        let ps = style == .playStation
        var result = [
            item(.modeToggle, 0.5, 0.15, 25, modeName),
            item(.leftTrigger, 0.12, 0.12, 27, ps ? "L2" : "LT"),
            item(.button(.leftShoulder), 0.26, 0.12, 27, style.label(.leftShoulder)),
            item(.button(.rightShoulder), 0.74, 0.12, 27, style.label(.rightShoulder)),
            item(.rightTrigger, 0.88, 0.12, 27, ps ? "R2" : "RT"),
            item(.leftStick, ps ? 0.30 : 0.18, ps ? 0.69 : 0.43, 62, "L"),
            item(.rightStick, 0.65, 0.70, 62, "R"),
            item(.button(.back), 0.445, 0.24, 22, style.label(.back)),
            item(.button(.start), 0.545, 0.24, 22, style.label(.start)),
            item(.button(.leftClick), 0.435, 0.78, 22, "L3"),
            item(.button(.rightClick), 0.525, 0.78, 22, "R3")
        ]
        let center = CGPoint(x: w * 0.85, y: h * 0.44)
        for (button, dx, dy) in [(PadButton.south, 0.0, 1.0), (.east, 1, 0), (.west, -1, 0), (.north, 0, -1)] {
            result.append(Item(control: .button(button), center: CGPoint(x: center.x + dx * 48 * unit, y: center.y + dy * 48 * unit), radius: 23 * unit, label: style.label(button)))
        }
        if showsGuideButton { result.append(item(.button(.guide), 0.5, 0.35, 20, guideLabel)) }
        if showDPad { result.append(item(.dpad, ps ? 0.14 : 0.355, ps ? 0.43 : 0.66, 50, "D-PAD")) }
        for slot in customSlots {
            result.append(item(.custom(slot), 0.10 + CGFloat(slot % 8) * 0.11, slot < 8 ? 0.91 : 0.51, 19, "C\(slot + 1)"))
        }
        if radialEnabled { result.append(item(.radial, 0.5, 0.5, 30, radialTitle)) }
        if !showsModeSwitch { result.removeAll { $0.control == .modeToggle } }
        return result
    }

    private var items: [Item] {
        presetItems.filter { !hiddenControls.contains($0.control.id) }.map { item in
            let fallback = ControlPlacement(x: item.center.x / max(1, bounds.width), y: item.center.y / max(1, bounds.height))
            let p = (placements[item.control.id] ?? fallback).fitting(width: bounds.width, height: bounds.height, baseRadius: item.radius)
            return Item(control: item.control, center: CGPoint(x: p.x * bounds.width, y: p.y * bounds.height), radius: item.radius * p.scale, label: item.control == .modeToggle ? modeName : (labels[item.control.id] ?? item.label))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if legacyCanvas && !migrationSent && bounds.width > 0 && window != nil {
            // The previous app used the safe-area width and a 78-point header.
            // Convert to full-screen coordinates without moving or resizing controls.
            let insets = window?.safeAreaInsets ?? .zero
            let old = CGRect(x: insets.left, y: insets.top + 78,
                             width: bounds.width - insets.left - insets.right,
                             height: bounds.height - insets.top - insets.bottom - 78)
            if old.width > 0 && old.height > 0 {
                let factor = min(old.height / 320, old.width / 800) / min(bounds.height / 320, bounds.width / 800)
                var converted: [String: ControlPlacement] = [:]
                for item in presetItems where item.control != .modeToggle {
                    let fallback = ControlPlacement(x: item.center.x / bounds.width, y: item.center.y / bounds.height)
                    let p = (placements[item.control.id] ?? fallback).fitting(width: old.width, height: old.height, baseRadius: item.radius * factor)
                    converted[item.control.id] = ControlPlacement(x: (old.minX + p.x * old.width) / bounds.width,
                        y: (old.minY + p.y * old.height) / bounds.height, scale: p.scale)
                }
                migrationSent = true
                let callback = onMigration
                DispatchQueue.main.async { callback?(converted, factor) }
            }
        }
        if previousSize != bounds.size {
            previousSize = bounds.size
            touches.removeAll(); cancelSticks(); cancelAim(); cancelTrackpad(); editTouch = nil; refresh()
            let size = bounds.size
            if size.width > 0 && size.height > 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.bounds.size == size else { return }
                    self.onCanvasSize?(size)
                }
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing {
            guard editTouch == nil, let touch = touches.first else { return }
            let point = touch.location(in: self)
            guard let item = items.min(by: { distance($0.center, point) / $0.radius < distance($1.center, point) / $1.radius }),
                  hit(item, point) else { return }
            if touch.tapCount == 2 {
                onReference?(reference(for: item))
                onRename?(item.control.id, item.label); return
            }
            editTouch = ObjectIdentifier(touch); editControl = item.control
            selectedID = item.control.id
            dragOffset = CGPoint(x: point.x - item.center.x, y: point.y - item.center.y)
            let p = ControlPlacement(x: item.center.x / bounds.width, y: item.center.y / bounds.height,
                                     scale: placements[item.control.id]?.scale ?? 1)
            placements[item.control.id] = p
            onReference?(reference(for: item))
            onSelect?(item.control.id, item.label, p)
            setNeedsDisplay()
            return
        }
        for touch in touches {
            let point = touch.location(in: self)
            if let item = items.min(by: { distance($0.center, point) / $0.radius < distance($1.center, point) / $1.radius }),
               hit(item, point),
               !self.touches.values.contains(where: { $0.control == item.control }) {
                if item.control != .leftStick && item.control != .rightStick {
                    pressHaptic(item.control)
                }
                self.touches[ObjectIdentifier(touch)] = (item.control, point)
                if item.control == .radial { radialOrigin = point; radialChoice = nil }
                if item.control == .leftStick || item.control == .rightStick || item.control == .modeToggle {
                    let floating = item.control == .leftStick ? floatingLeft : floatingRight
                    stickGestures[item.control] = StickGesture(x: point.x, y: point.y, centerX: item.center.x, centerY: item.center.y,
                        floating: floating, now: ProcessInfo.processInfo.systemUptime)
                }
                if item.control == .leftStick || (item.control == .rightStick && !cursorMode) {
                    let control = item.control
                    stickClickHolds[control] = StickClickHold(now: ProcessInfo.processInfo.systemUptime)
                    let work = DispatchWorkItem { [weak self] in self?.refresh() }
                    stickHoldWork[control]?.cancel(); stickHoldWork[control] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.46, execute: work)
                }
                if item.control == .rightStick && cursorMode {
                    cancelTrackpad()
                    trackpad.begin(x: point.x, y: point.y, now: ProcessInfo.processInfo.systemUptime)
                    let touchID = ObjectIdentifier(touch)
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.cursorMode, self.touches[touchID]?.control == .rightStick else { return }
                        if let action = self.trackpad.hold(now: ProcessInfo.processInfo.systemUptime, delay: self.trackpadHoldDelay) {
                            self.onPointer?(action, 0, 0); self.setNeedsDisplay()
                        }
                    }
                    trackpadActivation = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + trackpadHoldDelay + 0.001, execute: work)
                }
                if item.control == .rightTrigger && holdAimEnabled {
                    cancelAim()
                    holdAim.begin(now: ProcessInfo.processInfo.systemUptime)
                    let touchID = ObjectIdentifier(touch)
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.touches[touchID]?.control == .rightTrigger else { return }
                        self.refresh()
                    }
                    aimActivation = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + holdAimDelay + 0.001, execute: work)
                }
            }
        }
        refresh()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing {
            guard let control = editControl, let touch = touches.first(where: { ObjectIdentifier($0) == editTouch }),
                  let base = presetItems.first(where: { $0.control == control }) else { return }
            let point = touch.location(in: self)
            let p = ControlPlacement(x: (point.x - dragOffset.x) / max(1, bounds.width),
                                     y: (point.y - dragOffset.y) / max(1, bounds.height),
                                     scale: placements[control.id]?.scale ?? 1)
                .fitting(width: bounds.width, height: bounds.height, baseRadius: base.radius)
            placements[control.id] = p; onPlacement?(control.id, p); setNeedsDisplay()
            return
        }
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if let previous = self.touches[id] {
                let point = touch.location(in: self)
                self.touches[id] = (previous.control, point)
                if previous.control == .radial {
                    radialChoice = RadialInput.direction(x: point.x - radialOrigin.x, y: point.y - radialOrigin.y, deadZone: 24, slots: radialSlots)
                }
                stickGestures[previous.control]?.move(x: point.x, y: point.y)
                if previous.control == .rightStick && cursorMode {
                    let delta = trackpad.move(x: point.x, y: point.y)
                    if delta.0 != 0 || delta.1 != 0 { onPointer?(.move, delta.0, delta.1) }
                }
            }
        }
        refresh()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { remove(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { remove(touches, cancelled: true) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { touches.removeAll(); cancelSticks(); cancelAim(); cancelTrackpad(); refresh() }
    }
    private func remove(_ touches: Set<UITouch>, cancelled: Bool = false) {
        if editing {
            if touches.contains(where: { ObjectIdentifier($0) == editTouch }) {
                editTouch = nil; editControl = nil; onEditEnded?()
            }
            return
        }
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if self.touches[id]?.control == .radial {
                let end = touch.location(in: self)
                let direction = RadialInput.direction(x: end.x - radialOrigin.x, y: end.y - radialOrigin.y, deadZone: 24, slots: radialSlots)
                if !cancelled, let direction, radialSlots.indices.contains(direction) { radialPulse(radialSlots[direction]) }
                radialChoice = nil
            }
            if let control = self.touches[id]?.control {
                stickClickHolds.removeValue(forKey: control)
                stickHoldWork.removeValue(forKey: control)?.cancel()
            }
            if let control = self.touches[id]?.control, var gesture = stickGestures.removeValue(forKey: control) {
                let end = touch.location(in: self); gesture.move(x: end.x, y: end.y)
                if !cancelled && gesture.isTap(now: ProcessInfo.processInfo.systemUptime) {
                    if control == .modeToggle {
                        self.touches.removeValue(forKey: id)
                        cancelSticks(); cancelAim(); cancelTrackpad(); onToggle?(); return
                    }
                    if control == .leftStick { pulse(leftTap) }
                    if control == .rightStick && !cursorMode { pulse(rightTap) }
                }
            }
            if self.touches[id]?.control == .rightStick && cursorMode {
                if !cancelled, let action = trackpad.end(now: ProcessInfo.processInfo.systemUptime, delay: trackpadHoldDelay) {
                    onPointer?(action, 0, 0)
                }
                cancelTrackpad()
            }
            self.touches.removeValue(forKey: id)
        }
        if !self.touches.values.contains(where: { $0.control == .rightTrigger }) { cancelAim() }
        refresh()
    }
    private func hit(_ item: Item, _ point: CGPoint) -> Bool {
        if item.control == .rightStick && cursorMode && !editing {
            return CGRect(x: item.center.x - item.radius, y: item.center.y - item.radius, width: item.radius * 2, height: item.radius * 2).contains(point)
        }
        return distance(item.center, point) <= item.radius * 1.15
    }
    private func cancelSticks() {
        radialChoice = nil
        radialEnds.values.forEach { $0.cancel() }; radialEnds.removeAll(); radialPulses.removeAll()
        stickGestures.removeAll()
        stickClickHolds.removeAll()
        stickHoldWork.values.forEach { $0.cancel() }; stickHoldWork.removeAll()
        pulseEnds.values.forEach { $0.cancel() }; pulseEnds.removeAll(); pulses.removeAll()
    }
    private func radialPulse(_ slot: Int) {
        guard (0..<16).contains(slot) else { return }
        radialEnds[slot]?.cancel(); radialPulses.insert(slot)
        let work = DispatchWorkItem { [weak self] in
            self?.radialPulses.remove(slot); self?.radialEnds[slot] = nil; self?.refresh()
        }
        radialEnds[slot] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func pulse(_ action: StickTapAction) {
        guard action != .off else { return }
        let id = UUID(); pulses[id] = action
        let work = DispatchWorkItem { [weak self] in
            self?.pulses[id] = nil; self?.pulseEnds[id] = nil; self?.refresh()
        }
        pulseEnds[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func cancelTrackpad() {
        trackpadActivation?.cancel(); trackpadActivation = nil; trackpad.cancel()
    }
    private func cancelAim() {
        aimActivation?.cancel(); aimActivation = nil; holdAim.reset()
    }
    private func aimRadius(_ item: Item) -> CGFloat { max(36, item.radius * 1.4) }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func refresh() {
        var next = GamepadState.neutral
        if editing { state = .paused; onState?(.paused); setNeedsDisplay(); return }
        for value in touches.values {
            guard let item = items.first(where: { $0.control == value.control }) else { continue }
            let gesture = stickGestures[value.control]
            let origin = CGPoint(x: gesture?.originX ?? item.center.x, y: gesture?.originY ?? item.center.y)
            let x = Double((value.point.x - origin.x) / (item.radius * 0.7))
            let y = Double((value.point.y - origin.y) / (item.radius * 0.7))
            let wasPressed = stickClickHolds[value.control]?.pressed == true
            stickClickHolds[value.control]?.update(x: x, y: y, now: ProcessInfo.processInfo.systemUptime)
            if !wasPressed && stickClickHolds[value.control]?.pressed == true {
                pressHaptic(.button(value.control == .leftStick ? .leftClick : .rightClick))
            }
            let inside = distance(value.point, item.center) <= item.radius * 1.3
            switch value.control {
            case .modeToggle, .radial: break
            case .leftStick: (next.leftX, next.leftY) = GamepadState.stick(x: x, y: y)
            case .rightStick:
                if !cursorMode { (next.rightX, next.rightY) = GamepadState.stick(x: x, y: y) }
            case .custom(let slot): next.setCustom(slot, pressed: inside)
            case .button(let button): next.set(button, pressed: inside)
            // A trigger owns its touch until lift/cancel. Finger drift while aiming
            // must not release a held attack or block (or create repeated edges).
            case .leftTrigger: next.leftTrigger = 255
            case .rightTrigger: next.rightTrigger = 255
            case .dpad:
                if hypot(x, y) > 0.18 / 0.7 {
                    let angle = atan2(x, -y)
                    next.hat = UInt8((Int((angle / (.pi / 4)).rounded()) + 8) % 8)
                }
            }
        }
        if stickClickHolds[.leftStick]?.pressed == true { next.set(.leftClick, pressed: true) }
        if !cursorMode, stickClickHolds[.rightStick]?.pressed == true { next.set(.rightClick, pressed: true) }
        if holdAimEnabled, let touch = touches.values.first(where: { $0.control == .rightTrigger }),
           let item = items.first(where: { $0.control == .rightTrigger }) {
            let axes = holdAim.update(x: touch.point.x, y: touch.point.y, now: ProcessInfo.processInfo.systemUptime,
                                      delay: holdAimDelay, radius: aimRadius(item))
            // Aiming attack owns the right axes until lift; dictionary order cannot
            // let a simultaneous ordinary right-stick touch overwrite this gesture.
            if holdAim.isAiming { (next.rightX, next.rightY) = axes }
        }
        if touches.values.contains(where: { $0.control == .radial }) { next.radialPreview = radialChoice.map { UInt8($0 + 2) } ?? 1 }
        for slot in radialPulses { next.setCustom(slot, pressed: true) }
        for action in pulses.values { action.apply(to: &next) }
        state = next; onState?(next); setNeedsDisplay()
    }

    private func contrastingText(on color: UIColor) -> UIColor {
        let resolved = color.resolvedColor(with: traitCollection)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.55 ? .black : .white
    }

    override func draw(_ rect: CGRect) {
        let muted = UIColor.secondaryLabel
        if editing, showGhost, let id = selectedID, let item = items.first(where: { $0.control.id == id }), let p = reference(for: item), let base = presetItems.first(where: { $0.control.id == id }) {
            let radius = base.radius * p.scale
            let ghost = UIBezierPath(ovalIn: CGRect(x: p.x * bounds.width - radius, y: p.y * bounds.height - radius, width: radius * 2, height: radius * 2))
            UIColor.label.withAlphaComponent(0.2).setStroke(); ghost.lineWidth = 1
            ghost.setLineDash([3, 5], count: 2, phase: 0); ghost.stroke()
            text("OTHER MODE", at: CGPoint(x: p.x * bounds.width, y: p.y * bounds.height - radius - 10), color: muted, size: 8)
        }
        for original in items {
            let tint = buttonFeedback[original.control.id]?.tint ?? .automatic
            let accent = tint.uiColor
            let idleFill = tint == .automatic ? UIColor.secondarySystemGroupedBackground : accent.withAlphaComponent(0.18)
            let idleStroke = tint == .automatic ? UIColor.separator.withAlphaComponent(0.45) : accent.withAlphaComponent(0.7)
            var item = original
            if !editing, (original.control == .leftStick || (original.control == .rightStick && !cursorMode)),
               let gesture = stickGestures[original.control] {
                item = Item(control: original.control, center: CGPoint(x: gesture.originX, y: gesture.originY), radius: original.radius, label: original.label)
            }
            if item.control == .rightTrigger && holdAim.isAiming { continue }
            let active: Bool
            switch item.control {
            case .custom(let slot): active = state.customButtons & (UInt16(1) << slot) != 0
            case .button(let b): active = state.buttons & b.mask != 0
            case .leftTrigger: active = state.leftTrigger > 0
            case .rightTrigger: active = state.rightTrigger > 0
            case .dpad: active = state.hat != 8
            default: active = touches.values.contains { $0.control == item.control }
            }
            if item.control == .rightStick && cursorMode && !editing {
                let pad = UIBezierPath(roundedRect: CGRect(x: item.center.x - item.radius, y: item.center.y - item.radius, width: item.radius * 2, height: item.radius * 2), cornerRadius: 14)
                (active ? accent.withAlphaComponent(0.3) : idleFill).setFill(); pad.fill()
                (active ? accent : (tint == .automatic ? muted : accent)).setStroke(); pad.lineWidth = 1.5; pad.stroke()
                text(trackpad.rightClicked ? "RIGHT CLICK" : "TRACKPAD", at: item.center, color: .label, size: 10, maxWidth: item.radius * 1.8)
                continue
            }
            let circle = UIBezierPath(ovalIn: CGRect(x: item.center.x - item.radius, y: item.center.y - item.radius, width: item.radius * 2, height: item.radius * 2))
            let context = UIGraphicsGetCurrentContext()
            context?.saveGState()
            context?.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: UIColor.black.withAlphaComponent(0.07).cgColor)
            (active && item.control != .dpad ? accent.withAlphaComponent(0.25) : idleFill).setFill(); circle.fill()
            context?.restoreGState()
            (unmapped.contains(item.control.id) ? UIColor.systemRed : (active && item.control != .dpad ? accent : idleStroke)).setStroke(); circle.lineWidth = unmapped.contains(item.control.id) ? 2 : 1; circle.stroke()
            if editing {
                let selected = selectedID == item.control.id
                (unmapped.contains(item.control.id) ? UIColor.systemRed : (selected ? accent : muted)).setStroke()
                circle.lineWidth = selected ? 3 : 1
                circle.stroke()
            }
            switch item.control {
            case .leftStick, .rightStick:
                let left = item.control == .leftStick
                let x = CGFloat(left ? state.leftX : state.rightX) / 32767
                let y = CGFloat(left ? state.leftY : state.rightY) / 32767
                let r = item.radius * 0.43
                let center = CGPoint(x: item.center.x + x * item.radius * 0.48, y: item.center.y + y * item.radius * 0.48)
                let thumb = UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                (active ? accent : UIColor.tertiarySystemFill).setFill(); thumb.fill()
                text(item.label, at: center, color: active ? contrastingText(on: accent) : muted, size: 14)
            case .dpad:
                // Inset, softly outlined keys keep the eight angular regions legible
                // without making the pad look like a separate wheel control.
                let inner = item.radius * 0.23
                for direction in 0..<8 {
                    let angle = CGFloat(direction) * .pi / 4
                    let start = angle - .pi / 2 - .pi / 8 + 0.045
                    let end = angle - .pi / 2 + .pi / 8 - 0.045
                    let segment = UIBezierPath()
                    segment.addArc(withCenter: item.center, radius: item.radius * 0.92, startAngle: start, endAngle: end, clockwise: true)
                    segment.addArc(withCenter: item.center, radius: inner, startAngle: end, endAngle: start, clockwise: false)
                    segment.close()
                    segment.lineJoinStyle = .round
                    let pressed = !editing && state.hat == UInt8(direction)
                    (pressed ? accent.withAlphaComponent(0.25) : idleFill).setFill(); segment.fill()
                    (pressed ? accent : idleStroke.withAlphaComponent(0.35)).setStroke()
                    segment.lineWidth = 1; segment.stroke()
                    let point = CGPoint(x: item.center.x + sin(angle) * item.radius * 0.64,
                                        y: item.center.y - cos(angle) * item.radius * 0.64)
                    context?.saveGState()
                    context?.translateBy(x: point.x, y: point.y)
                    context?.rotate(by: angle)
                    let chevron = UIBezierPath()
                    chevron.move(to: CGPoint(x: -3.5, y: 1.75))
                    chevron.addLine(to: CGPoint(x: 0, y: -1.75))
                    chevron.addLine(to: CGPoint(x: 3.5, y: 1.75))
                    chevron.lineWidth = 1.5; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
                    (pressed ? accent : UIColor.secondaryLabel).setStroke(); chevron.stroke()
                    context?.restoreGState()
                }
            default:
                text(item.label, at: item.center, color: .label, size: item.label.count > 3 ? 10 : 17, maxWidth: item.radius * 1.8)
            }
        }
        if holdAim.isAiming, let item = items.first(where: { $0.control == .rightTrigger }) {
            let accent = (buttonFeedback[item.control.id]?.tint ?? .automatic).uiColor
            let radius = aimRadius(item)
            let origin = CGPoint(x: holdAim.originX, y: holdAim.originY)
            let ring = UIBezierPath(ovalIn: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
            accent.withAlphaComponent(0.12).setFill(); ring.fill()
            accent.setStroke(); ring.lineWidth = 2; ring.stroke()
            let thumbRadius = item.radius * 0.65
            let point = CGPoint(x: origin.x + CGFloat(state.rightX) / 32767 * radius * 0.7,
                                y: origin.y + CGFloat(state.rightY) / 32767 * radius * 0.7)
            let thumb = UIBezierPath(ovalIn: CGRect(x: point.x - thumbRadius, y: point.y - thumbRadius, width: thumbRadius * 2, height: thumbRadius * 2))
            accent.setFill(); thumb.fill()
            text("AIM", at: point, color: contrastingText(on: accent), size: 10)
        }
        if !editing, touches.values.contains(where: { $0.control == .radial }) {
            let accent = (buttonFeedback[Control.radial.id]?.tint ?? .automatic).uiColor
            for i in 0..<8 where radialSlots.indices.contains(i) && radialSlots[i] >= 0 {
                let angle = Double(i) * .pi / 4
                let point = CGPoint(x: min(bounds.maxX - 20, max(20, radialOrigin.x + sin(angle) * 78)),
                                    y: min(bounds.maxY - 20, max(20, radialOrigin.y - cos(angle) * 78)))
                let ring = UIBezierPath(ovalIn: CGRect(x: point.x - 19, y: point.y - 19, width: 38, height: 38))
                (radialChoice == i ? accent : UIColor.secondarySystemGroupedBackground).setFill(); ring.fill()
                let slot = radialSlots.indices.contains(i) ? radialSlots[i] : i
                text(slot < 0 ? "—" : (labels["custom-\(slot)"] ?? (slot < 8 ? "\(slot + 1)" : "C\(slot + 1)")), at: point, color: radialChoice == i ? contrastingText(on: accent) : .label, size: 12, maxWidth: 34)
            }
        }
        text(editing ? "Editing · input paused" : "Pocket Pad", at: CGPoint(x: bounds.midX, y: bounds.height - 12), color: muted, size: 9)
    }
    private func text(_ value: String, at center: CGPoint, color: UIColor, size: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude) {
        let natural = (value as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium)]).width
        let fittedSize = size * min(1, maxWidth / max(1, natural))
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fittedSize, weight: .medium), .foregroundColor: color]
        let dimensions = (value as NSString).size(withAttributes: attributes)
        (value as NSString).draw(at: CGPoint(x: center.x - dimensions.width / 2, y: center.y - dimensions.height / 2), withAttributes: attributes)
    }
}

extension ButtonTint {
    var uiColor: UIColor {
        switch self {
        case .automatic: return .label
        case .mint: return UIColor(red: 0.44, green: 0.94, blue: 0.79, alpha: 1)
        case .blue: return .systemBlue
        case .violet: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .white: return .white
        }
    }
}
