import SwiftUI

/// Edits a draft only. Saving and importing on the phone never replace its existing layout.
struct LayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layout: SavedLayout
    @State private var baseLayout: SavedLayout
    @State private var modeIndex = 0
    @State private var selected: String?
    @State private var past: [SavedLayout] = []
    @State private var future: [SavedLayout] = []
    @State private var dragOrigin: ControlPlacement?
    var embedded = false
    var liveState: GamepadState?
    var sourceLayout: SavedLayout
    var sourceMode: Int
    var screen: PhoneScreen?
    private var canvasWidth: Double { screen?.width ?? 800 }
    private var canvasHeight: Double { screen?.height ?? 360 }
    private var unit: Double { min(canvasHeight / 320, canvasWidth / 800) * mode.sizeFactor }
    @State private var saved = false
    @State private var advancedMappings = false
    @State private var mappingDirection = MappedControl.leftUp
    let save: (SavedLayout, SavedLayout) -> Void
    init(layout: SavedLayout, embedded: Bool = false, liveState: GamepadState? = nil, modeIndex: Int = 0, screen: PhoneScreen? = nil, save: @escaping (SavedLayout, SavedLayout) -> Void) {
        _layout = State(initialValue: layout); _baseLayout = State(initialValue: layout); self.embedded = embedded; self.save = save
        self.liveState = liveState; self.screen = screen; sourceLayout = layout; sourceMode = modeIndex
        _modeIndex = State(initialValue: modeIndex)
    }
    private var mode: LayoutMode { layout.modes[modeIndex] }
    private struct Item: Identifiable {
        let id: String; let label: String; let x: Double; let y: Double; let radius: Double
    }
    private var items: [Item] {
        let ps = layout.style == .playStation
        var result: [Item] = []
        func add(_ id: String, _ label: String, _ x: Double, _ y: Double, _ radius: Double) {
            result.append(Item(id: id, label: layout.displayLabels(modeIndex: modeIndex)[id] ?? label, x: x, y: y, radius: radius))
        }
        if layout.hasCursorSwitching { add("mode-toggle", mode.name, 0.5, 0.15, 25) }
        add("left-trigger", ps ? "L2" : "LT", 0.12, 0.12, 27)
        add("right-trigger", ps ? "R2" : "RT", 0.88, 0.12, 27)
        add("left-stick", "L", ps ? 0.30 : 0.18, ps ? 0.69 : 0.43, 62)
        add("right-stick", "R", 0.65, 0.70, 62)
        for (b, x, y, r) in [(PadButton.leftShoulder, 0.26, 0.12, 27.0), (.rightShoulder, 0.74, 0.12, 27), (.back, 0.445, 0.24, 22), (.start, 0.545, 0.24, 22), (.leftClick, 0.435, 0.78, 22), (.rightClick, 0.525, 0.78, 22)] {
            add("button-\(b.rawValue)", layout.style.label(b), x, y, r)
        }
        // The preview uses an 800 × 360 landscape canvas, matching the phone's sizing rules.
        for (b, dx, dy) in [(PadButton.south, 0.0, 1.0), (.east, 1, 0), (.west, -1, 0), (.north, 0, -1)] {
            add("button-\(b.rawValue)", layout.style.label(b), 0.85 + dx * 48 * unit / canvasWidth, 0.44 + dy * 48 * unit / canvasHeight, 23)
        }
        if layout.effectiveInputType == .gamepad { add("button-\(PadButton.guide.rawValue)", layout.effectiveControllerStyle.label(.guide), 0.5, 0.35, 20) }
        if mode.showDPad { add("dpad", "✣", ps ? 0.14 : 0.355, ps ? 0.43 : 0.66, 50) }
        for slot in mode.controls.customButtons(for: layout.style) {
            add("custom-\(slot)", "C\(slot + 1)", 0.10 + Double(slot % 8) * 0.11, slot < 8 ? 0.91 : 0.51, 19)
        }
        if mode.radialEnabled == true { add("radial", mode.radialTitle ?? "Quick bar", 0.5, 0.5, 30) }
        return result.filter { !(mode.hiddenControls ?? []).contains($0.id) }
    }
    private func isPressed(_ id: String) -> Bool {
        guard let state = liveState else { return false }
        if id == "radial" { return state.radialPreview != 0 || (mode.radialSlots ?? Array(0..<8)).contains { (0..<16).contains($0) && state.customButtons & (1 << $0) != 0 } }
        if id == "left-trigger" { return state.leftTrigger > 0 }
        if id == "right-trigger" { return state.rightTrigger > 0 }
        if id == "dpad" { return state.hat != 8 }
        if id.hasPrefix("button-"), let raw = Int(id.dropFirst(7)), let button = PadButton(rawValue: raw) { return state.buttons & button.mask != 0 }
        if id.hasPrefix("custom-"), let slot = Int(id.dropFirst(7)) { return state.customButtons & (1 << slot) != 0 }
        return false
    }
    private func placement(_ item: Item) -> ControlPlacement {
        (mode.controls.controls(for: layout.style)[item.id] ?? ControlPlacement(x: item.x, y: item.y))
            .fitting(width: canvasWidth, height: canvasHeight, baseRadius: item.radius * unit)
    }
    private func record() { past.append(layout); if past.count > 50 { past.removeFirst() }; future.removeAll() }
    private func change(_ edit: (inout SavedLayout) -> Void) { record(); edit(&layout) }
    var body: some View {
        Group {
            if liveState != nil {
                GeometryReader { geometry in
                    let width = max(1, min(geometry.size.width - 48, (geometry.size.height - 48) * canvasWidth / canvasHeight))
                    controllerCanvas
                        .frame(width: width, height: width * canvasHeight / canvasWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                editorContent
            }
        }
        .onChange(of: sourceLayout) { _, value in if liveState != nil { layout = value }; if value == layout { baseLayout = value } }
        .onChange(of: sourceMode) { _, value in if liveState != nil { modeIndex = value } }
    }
    private var controllerCanvas: some View {
GeometryReader { geometry in
            let scale = max(0.01, min(geometry.size.width / canvasWidth, geometry.size.height / canvasHeight))
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(PadAppearance.surface)
                    .contentShape(Rectangle()).onTapGesture { selected = nil; dragOrigin = nil }
                ForEach(items) { item in
                    let p = placement(item)
                    let diameter = item.radius * unit * p.scale * 2
                    ZStack {
                        Circle().fill(.regularMaterial)
                        if item.id != "dpad" && isPressed(item.id) { Circle().fill(Color.accentColor.opacity(0.65)) }
                        if let state = liveState, item.id == "left-stick" || item.id == "right-stick" {
                            let left = item.id == "left-stick"
                            Circle().fill(Color.accentColor).frame(width: diameter * 0.32, height: diameter * 0.32)
                                .offset(x: CGFloat(left ? state.leftX : state.rightX) / 32767 * diameter * 0.3,
                                        y: CGFloat(left ? state.leftY : state.rightY) / 32767 * diameter * 0.3)
                        }
                        if item.id == "radial", let state = liveState, state.radialPreview > 1 {
                            let direction = Int(state.radialPreview) - 2
                            let angle = Double(direction) * .pi / 4
                            Circle().fill(Color.accentColor).frame(width: 18, height: 18)
                                .offset(x: sin(angle) * diameter * 0.42, y: -cos(angle) * diameter * 0.42)
                        }
                        Circle().strokeBorder(layout.unmappedControls.contains(where: { $0.canvasID == item.id }) ? Color.red : (selected == item.id ? Color.accentColor : Color.primary.opacity(0.16)), lineWidth: 2)
                        // Compensate for canvas scaling: labels remain 14 pt on screen.
                        if item.id == "dpad" {
                            DPadPreview(hat: liveState?.hat ?? 8)
                        } else {
                            Text(item.label).font(.system(size: 14 / scale, weight: .medium))
                                .fixedSize().help(item.label)
                        }
                    }
                    .frame(width: diameter, height: diameter)
                    .position(x: p.x * canvasWidth, y: p.y * canvasHeight)
                    .onTapGesture { selected = item.id }
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("controllerCanvas")).onChanged { value in
                        if dragOrigin == nil { record(); dragOrigin = p; selected = item.id }
                        guard let origin = dragOrigin else { return }
                        let next = ControlPlacement(x: origin.x + value.translation.width / canvasWidth, y: origin.y + value.translation.height / canvasHeight, scale: origin.scale)
                            .fitting(width: canvasWidth, height: canvasHeight, baseRadius: item.radius * unit)
                        layout.place(next, control: item.id, mode: modeIndex)
                    }.onEnded { _ in dragOrigin = nil })
                    .accessibilityLabel(item.label)
                }
            }.frame(width: canvasWidth, height: canvasHeight)
                .coordinateSpace(name: "controllerCanvas")
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.4), lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .scaleEffect(scale, anchor: .topLeading)
                .allowsHitTesting(liveState == nil && !mode.legacyCanvas)
            }
    }
    private var editorContent: some View {
        ScrollView {
        VStack(spacing: 14) {
            if liveState == nil {
            HStack {
                addControlMenu
                TextField("Layout name", text: $layout.name).textFieldStyle(.plain).font(.headline)
                Spacer()
                if layout.hasCursorSwitching { Picker("Mode", selection: $modeIndex) {
                    ForEach(layout.modes.indices, id: \.self) { Text(layout.modes[$0].name).tag($0) }
                }.frame(width: 180) }
                Button { if let previous = past.popLast() { future.append(layout); layout = previous } } label: { Image(systemName: "arrow.uturn.backward") }.disabled(past.isEmpty).help("Undo")
                Button { if let next = future.popLast() { past.append(layout); layout = next } } label: { Image(systemName: "arrow.uturn.forward") }.disabled(future.isEmpty).help("Redo")
                if !embedded { Button("Cancel") { dismiss() } }
                Button(saved ? "Saved" : "Save") { save(layout, baseLayout); saved = true; if !embedded { dismiss() } }
                    .buttonStyle(PadActionStyle(prominent: true)).disabled(mode.legacyCanvas)
            }
            if layout.effectiveInputType == .gamepad {
                HStack {
                    Picker("Emulate controller", selection: Binding(get: { layout.effectiveControllerStyle }, set: { value in
                        change { $0.emulatedController = value }
                    })) {
                        ForEach(PadStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.frame(width: 300)
                    Text("Applies when you save. Restart your game if it doesn't detect the change.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if mode.legacyCanvas {
                Text("Open this layout on your iPhone once, then export it again to update its canvas coordinates.").foregroundStyle(.secondary)
            }
            }
            controllerCanvas.aspectRatio(canvasWidth / canvasHeight, contentMode: .fit).frame(maxWidth: 600)
            if liveState == nil {
            HStack(spacing: 20) {
                if let selected, let item = items.first(where: { $0.id == selected }) {
                    TextField("Control name", text: Binding(get: { item.label }, set: { name in
                        let style = layout.style
                        change {
                            if selected == "mode-toggle" { $0.modes[modeIndex].name = String(name.prefix(20)) }
                            else { $0.modes[modeIndex].controls.rename(selected, to: name, style: style) }
                        }
                    })).frame(width: 160)
                    Button("Remove", role: .destructive) { removeControl(selected) }
                    Text("Size").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { placement(item).scale }, set: { scale in
                        var p = placement(item); p.scale = scale; layout.place(p, control: selected, mode: modeIndex)
                    }), in: 0.65...1.8, onEditingChanged: { if $0 { record() } }).frame(width: 160)
                    if layout.hasCursorSwitching { Toggle("Keep position in both modes", isOn: Binding(get: { layout.linkedControls?.contains(selected) == true }, set: { linked in
                        let current = placement(item)
                        change { value in
                            if value.linkedControls == nil { value.linkedControls = [] }
                            if linked { value.linkedControls?.insert(selected); value.place(current, control: selected, mode: modeIndex) }
                            else { value.linkedControls?.remove(selected) }
                        }
                    })) }
                } else { Text("Select a control to edit it.").foregroundStyle(.secondary) }
                Spacer()
            }.frame(height: 36)
            mappingInspector
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(items.filter { mappingSummary($0.id) != nil }) { item in
                    Button { selected = item.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.label).fontWeight(.semibold)
                            Text(mappingSummary(item.id) ?? "Unmapped")
                                .foregroundStyle(layout.unmappedControls.contains(where: { $0.canvasID == item.id }) ? Color.red : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(selected == item.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Text(layout.effectiveInputType.title).foregroundStyle(.secondary)
                Spacer()
                Button("Advanced settings") { advancedMappings = true }
            }
            }
        }.padding(24)
        }.frame(width: embedded ? nil : 848).background { PadBackdrop() }.buttonStyle(PadActionStyle())
            .sheet(isPresented: $advancedMappings) {
                VStack {
                    HStack { Text("Advanced settings").font(.headline); Spacer(); Button("Done") { advancedMappings = false } }.padding()
                    if layout.effectiveInputType == .gamepad {
                        GamepadMappingEditor(profile: gamepadBinding, embedded: true, advancedOnly: true, labels: controlLabels)
                    } else { MappingEditor(profile: keyboardBinding, embedded: true, advancedOnly: true, labels: controlLabels) }
                }.frame(width: 760, height: 640).buttonStyle(PadActionStyle())
            }
            .onChange(of: sourceLayout) { _, value in if liveState != nil { layout = value }; if value == layout { baseLayout = value } }
            .onChange(of: sourceMode) { _, value in if liveState != nil { modeIndex = value } }
            .onChange(of: layout) { _, _ in saved = false }
            .onChange(of: modeIndex) { _, _ in selected = nil; dragOrigin = nil }
    }
    private var addControlMenu: some View {
        Menu("Add control") {
            Button("Button") {
                record()
                if let slot = layout.modes[modeIndex].controls.addCustom(style: layout.style) {
                    let id = "custom-\(slot)"
                    layout.modes[modeIndex].hiddenControls?.remove(id)
                    layout.modes[modeIndex].controls.set(ControlPlacement(x: 0.5, y: 0.5), control: id, style: layout.style)
                    selected = id
                }
            }.disabled(mode.controls.customButtons(for: layout.style).count >= 16)
            Menu("Joystick") {
                Button("Left joystick") { restoreControl("left-stick") }.disabled(items.contains { $0.id == "left-stick" })
                Button("Right joystick") { restoreControl("right-stick") }.disabled(items.contains { $0.id == "right-stick" })
            }
            Button("D-pad") { restoreControl("dpad") }.disabled(items.contains { $0.id == "dpad" })
            Button("Radial") { restoreControl("radial") }.disabled(items.contains { $0.id == "radial" })
            if !(mode.hiddenControls ?? []).isEmpty {
                Menu("Restore removed control") {
                    ForEach(Array(mode.hiddenControls ?? []).sorted(), id: \.self) { id in
                        Button(layout.displayLabels(modeIndex: modeIndex)[id] ?? id) { restoreControl(id) }
                    }
                }
            }
        }
    }
    private func restoreControl(_ id: String) {
        record()
        layout.modes[modeIndex].hiddenControls?.remove(id)
        if id == "dpad" { layout.modes[modeIndex].showDPad = true }
        if id == "radial" { layout.modes[modeIndex].radialEnabled = true }
        layout.modes[modeIndex].controls.set(ControlPlacement(x: 0.5, y: 0.5), control: id, style: layout.style)
        selected = id
    }
    private func removeControl(_ id: String) {
        record()
        if id.hasPrefix("custom-"), let slot = Int(id.dropFirst(7)) {
            layout.modes[modeIndex].controls.removeCustom(slot, style: layout.style)
        } else {
            if layout.modes[modeIndex].hiddenControls == nil { layout.modes[modeIndex].hiddenControls = [] }
            layout.modes[modeIndex].hiddenControls?.insert(id)
        }
        selected = nil; dragOrigin = nil
    }
    private var controlLabels: [MappedControl: String] {
        Dictionary(uniqueKeysWithValues: MappedControl.allCases.map { ($0, layout.controlLabel($0, modeIndex: modeIndex)) })
    }
    private var keyboardBinding: Binding<KeyboardProfile> {
        Binding(get: { layout.keyboardProfile ?? .starter }, set: { layout.keyboardProfile = $0 })
    }
    private var gamepadBinding: Binding<GamepadProfile> {
        Binding(get: { layout.gamepadProfile ?? GamepadProfile() }, set: { layout.gamepadProfile = $0 })
    }
    private func mappingSummary(_ id: String) -> String? {
        let controls = MappedControl.allCases.filter { $0.canvasID == id && $0 != .autoRun }
        if id == "right-stick", layout.effectiveInputType == .keyboardMouse, keyboardBinding.wrappedValue.rightStickMouse { return "Mouse" }
        if layout.effectiveInputType == .gamepad {
            if id == "left-stick" { return gamepadBinding.wrappedValue.disableLeftStick == true ? "Unmapped" : "Left stick" }
            if id == "right-stick" { return gamepadBinding.wrappedValue.disableRightStick == true ? "Unmapped" : "Right stick" }
            return controls.isEmpty ? nil : controls.map { gamepadBinding.wrappedValue[$0]?.label ?? "Unmapped" }.joined(separator: " / ")
        }
        return controls.isEmpty ? nil : controls.map { keyboardBinding.wrappedValue[$0].summary }.joined(separator: " / ")
    }
    @ViewBuilder private var mappingInspector: some View {
        if let selected {
            let controls = MappedControl.allCases.filter { $0.canvasID == selected && $0 != .autoRun }
            VStack(alignment: .leading, spacing: 16) {
                if selected == "right-stick", layout.effectiveInputType == .keyboardMouse {
                    Toggle("Move the mouse", isOn: Binding(get: { keyboardBinding.wrappedValue.rightStickMouse }, set: { keyboardBinding.wrappedValue.rightStickMouse = $0 }))
                    Toggle("Allow cursor switching", isOn: Binding(get: { layout.hasCursorSwitching }, set: { enabled in
                        change { $0.setCursorSwitching(enabled) }
                        if !enabled { modeIndex = 0 }
                    }))
                    Text("Adds an Aim / Cursor button to the phone. Aim moves the camera; Cursor works like a trackpad. Other controls keep their mappings.")
                        .foregroundStyle(.secondary)
                }
                if selected == "radial" {
                    Text("Eight-way selector").fontWeight(.semibold)
                    ForEach(0..<8) { index in
                        Picker(["Up", "Up right", "Right", "Down right", "Down", "Down left", "Left", "Up left"][index], selection: Binding(get: {
                            (layout.modes[modeIndex].radialSlots ?? Array(0..<8))[index]
                        }, set: { slot in
                            var slots = layout.modes[modeIndex].radialSlots ?? Array(0..<8)
                            slots[index] = slot; layout.modes[modeIndex].radialSlots = slots
                        })) {
                            Text("None").tag(-1)
                            ForEach(0..<16) { slot in Text("Custom \(slot + 1)").tag(slot) }
                        }
                        let slot = (layout.modes[modeIndex].radialSlots ?? Array(0..<8))[index]
                        if (0..<16).contains(slot) {
                            let control = MappedControl.customControls[slot]
                            if layout.effectiveInputType == .keyboardMouse {
                                ComboBindingEditor(binding: Binding(get: { keyboardBinding.wrappedValue[control] }, set: { value in
                                    var profile = keyboardBinding.wrappedValue; profile[control] = value
                                    keyboardBinding.wrappedValue = profile.sanitized
                                }))
                            } else {
                                Picker("Controller input", selection: Binding(get: { gamepadBinding.wrappedValue[control]?.rawValue ?? "none" }, set: { gamepadBinding.wrappedValue[control] = MappedControl(rawValue: $0) })) {
                                    Text("Unmapped").tag("none")
                                    ForEach(GamepadProfile.destinations, id: \.self) { Text($0.label).tag($0.rawValue) }
                                }
                            }
                        }
                        Divider()
                    }
                } else if layout.effectiveInputType == .gamepad && (selected == "left-stick" || selected == "right-stick") {
                    Toggle("Enable analog stick", isOn: Binding(get: {
                        selected == "left-stick" ? gamepadBinding.wrappedValue.disableLeftStick != true : gamepadBinding.wrappedValue.disableRightStick != true
                    }, set: { enabled in
                        if selected == "left-stick" { gamepadBinding.wrappedValue.disableLeftStick = !enabled }
                        else { gamepadBinding.wrappedValue.disableRightStick = !enabled }
                    }))
                    Text("Analog sticks send all directions continuously.").foregroundStyle(.secondary)
                } else {
                    ForEach(controls, id: \.self) { control in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(controlLabels[control] ?? control.label).fontWeight(.semibold)
                            if layout.effectiveInputType == .keyboardMouse {
                                ComboBindingEditor(binding: Binding(get: { keyboardBinding.wrappedValue[control] }, set: { value in
                                    var profile = keyboardBinding.wrappedValue; profile[control] = value
                                    keyboardBinding.wrappedValue = profile.sanitized
                                }))
                            } else {
                                Picker("Controller input", selection: Binding(get: { gamepadBinding.wrappedValue[control]?.rawValue ?? "none" }, set: { gamepadBinding.wrappedValue[control] = MappedControl(rawValue: $0) })) {
                                    Text("Unmapped").tag("none")
                                    ForEach(GamepadProfile.destinations, id: \.self) { Text($0.label).tag($0.rawValue) }
                                }
                            }
                        }
                        if control != controls.last { Divider() }
                    }
                }
            }.font(.system(size: 14)).padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}


private struct DPadPreview: View {
    let hat: UInt8
    var body: some View {
        GeometryReader { geometry in
            let radius = geometry.size.width / 2
            let center = CGPoint(x: radius, y: radius)
            ZStack {
                ForEach(0..<8) { direction in
                    let angle = Double(direction) * .pi / 4
                    let start = angle - .pi / 2 - .pi / 8 + 0.045
                    let end = angle - .pi / 2 + .pi / 8 - 0.045
                    let segment = Path { path in
                        path.addArc(center: center, radius: radius * 0.92, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
                        path.addArc(center: center, radius: radius * 0.23, startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
                        path.closeSubpath()
                    }
                    segment.fill(hat == UInt8(direction) ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.025))
                    segment.stroke(hat == UInt8(direction) ? Color.accentColor : Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(hat == UInt8(direction) ? Color.accentColor : Color.secondary)
                        .rotationEffect(.radians(angle))
                        .position(x: radius + sin(angle) * radius * 0.64, y: radius - cos(angle) * radius * 0.64)
                }
            }
        }.allowsHitTesting(false)
    }
}
