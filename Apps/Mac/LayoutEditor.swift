import SwiftUI

/// Drafts contain only the canonical document. Runtime mappings are read-only projections.
struct LayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layout: LocalLayout
    @State private var baseLayout: LocalLayout
    @State private var modeID: String
    @State private var selected: String?
    @State private var past: [LayoutDocument] = []
    @State private var future: [LayoutDocument] = []
    @GestureState private var dragPreview: ControlDragPreview?
    @State private var dragBaseDocument: LayoutDocument?
    @State private var error: String?
    @State private var saved = false
    @State private var advanced = false
    @State private var snap = false
    @State private var preview = "current"
    let embedded: Bool
    let liveState: GamepadState?
    let sourceLayout: LocalLayout
    let sourceMode: String
    let screen: PhoneScreen?
    let dirtyChanged: ((Bool) -> Void)?
    let selectMode: ((String) -> Void)?
    let noticeChanged: ((String?) -> Void)?
    let save: (LocalLayout, LocalLayout) -> Void
    init(layout: LocalLayout, embedded: Bool = false, liveState: GamepadState? = nil, modeID: String? = nil, screen: PhoneScreen? = nil, selectMode: ((String) -> Void)? = nil, dirtyChanged: ((Bool) -> Void)? = nil, noticeChanged: ((String?) -> Void)? = nil, save: @escaping (LocalLayout, LocalLayout) -> Void) {
        _layout = State(initialValue: layout); _baseLayout = State(initialValue: layout)
        let mode = modeID ?? layout.document.initialMode
        _modeID = State(initialValue: mode); sourceMode = mode
        sourceLayout = layout; self.embedded = embedded; self.liveState = liveState; self.screen = screen; self.selectMode = selectMode; self.dirtyChanged = dirtyChanged; self.noticeChanged = noticeChanged; self.save = save
    }
    private var editorNotice: String? {
        if let error { return error }
        let count = LayoutGeometry.overlappingIDs(items, width: width, height: height).count
        return count == 0 ? nil : "\(count) controls overlap."
    }
    private var hasChanges: Bool { layout.document != baseLayout.document }
    private var width: Double { preview == "compact" ? 667 : preview == "wide" ? 932 : screen?.width ?? 800 }
    private var height: Double { preview == "compact" ? 375 : preview == "wide" ? 430 : screen?.height ?? 360 }
    private var mode: DocumentMode { layout.document.modes.first { $0.id == modeID } ?? layout.document.modes[0] }
    private var storedItems: [ResolvedLayoutControl] { LayoutGeometry.resolve(layout.document, modeID: mode.id, width: width, height: height).filter { !$0.hidden } }
    private var items: [ResolvedLayoutControl] {
        storedItems.map { item in
            guard let dragPreview, dragPreview.id == item.id else { return item }
            var preview = item; preview.placement = dragPreview.placement; return preview
        }
    }
    private func draggedPlacement(_ item: ResolvedLayoutControl, translation: CGSize, others: [ResolvedLayoutControl]) -> ControlPlacement {
        var p = ControlPlacement(x: item.placement.x + translation.width / width,
                                 y: item.placement.y + translation.height / height, scale: item.placement.scale)
        if snap { p = LayoutGeometry.snapped(p, others: others.filter { $0.id != item.id }.map(\.placement)) }
        return LayoutGeometry.fitted(p, canvasWidth: width, canvasHeight: height, controlWidth: item.width, controlHeight: item.height)
    }
    private func change(record: Bool = true, _ edit: (inout LayoutDocument) throws -> Void) {
        do {
            var next = layout.document; try edit(&next); try next.validate()
            guard next != layout.document else { return }
            if record { past.append(layout.document); if past.count > 50 { past.removeFirst() }; future.removeAll() }
            layout.document = next; saved = false; error = nil; dirtyChanged?(next != baseLayout.document)
            if !next.modes.contains(where: { $0.id == modeID }) { modeID = next.initialMode }
        } catch { self.error = error.localizedDescription }
    }
    private func pressed(_ item: ResolvedLayoutControl) -> Bool {
        guard let state = liveState else { return false }
        switch item.role {
        case "radial": return state.radialPreview != 0 || layout.document.radialSlots().contains { (0..<16).contains($0) && state.customButtons & (1 << $0) != 0 }
        case "leftTrigger": return state.leftTrigger > 0
        case "rightTrigger": return state.rightTrigger > 0
        case "dpad": return state.hat != 8
        case "customButton":
            guard let slot = layout.document.controls.first(where: { $0.id == item.id })?.customSlot else { return false }
            return state.customButtons & (1 << slot) != 0
        default: return PadButton.allCases.first { String(describing: $0) == item.role }.map { state.buttons & $0.mask != 0 } ?? false
        }
    }
    var body: some View {
        Group {
            if liveState != nil {
                GeometryReader { geometry in
                    let available = max(1, min(geometry.size.width - 48, (geometry.size.height - 48) * width / height))
                    canvas.frame(width: available, height: available * height / width).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if noticeChanged == nil {
                            Text(editorNotice ?? " ").font(.callout).foregroundStyle(.orange)
                                .lineLimit(1).frame(height: 20).help(editorNotice ?? "")
                        }
                        canvas.aspectRatio(width / height, contentMode: .fit).frame(maxWidth: .infinity)
                        inspector
                        mappingOverview
                        HStack { Text(layout.effectiveInputType.title).foregroundStyle(.secondary); Spacer(); Button("Advanced settings") { advanced = true } }
                    }.padding(24)
                }.frame(width: embedded ? nil : 848)
            }
        }.background { PadBackdrop() }.buttonStyle(PadActionStyle())
            .onAppear { if liveState == nil { noticeChanged?(editorNotice) } }
            .onChange(of: dragPreview == nil) { _, ended in if ended { dragBaseDocument = nil } }
            .onChange(of: editorNotice) { _, value in if liveState == nil { noticeChanged?(value) } }
            .onChange(of: sourceLayout) { _, value in
                if liveState != nil || value.document == layout.document || layout.document == baseLayout.document { layout = value; baseLayout = value; saved = true; dirtyChanged?(false) }
            }
            .onChange(of: layout.document) { _, _ in dirtyChanged?(hasChanges) }
            .onChange(of: sourceMode) { _, value in if liveState != nil { modeID = value } }
            .onChange(of: modeID) { _, value in selected = nil; dragBaseDocument = nil; if liveState == nil { selectMode?(value) } }
            .sheet(isPresented: $advanced) {
                VStack {
                    HStack { Text("Advanced settings").font(.headline); Spacer(); Button("Done") { advanced = false } }.padding()
                    DocumentAdvancedSettings(document: Binding(get: { layout.document }, set: { value in change { $0 = value } }))
                }.frame(width: 760, height: 640).buttonStyle(PadActionStyle())
            }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu("Add control") {
                    ForEach(["customButton", "leftStick", "rightStick", "dpad", "radial"] + (layout.effectiveInputType == .keyboardMouse ? ["trackpad"] : []), id: \.self) { role in
                        Button(["customButton": "Button", "leftStick": "Left joystick", "rightStick": "Right joystick", "dpad": "D-pad", "radial": "Radial", "trackpad": "Trackpad"][role]!) {
                            change { selected = try $0.addControl(role: role) }
                        }.disabled(role != "customButton" && layout.document.controls.contains { $0.role == role })
                    }
                }
                TextField("Layout name", text: Binding(get: { layout.name }, set: { value in change { $0.name = value } })).font(.headline)
                if layout.document.modes.count > 1 { Picker("Mode", selection: $modeID) { ForEach(layout.document.modes, id: \.id) { Text($0.name).tag($0.id) } }.frame(width: 180) }
                Button { if let value = past.popLast() { future.append(layout.document); layout.document = value; saved = false } } label: { Image(systemName: "arrow.uturn.backward") }.disabled(past.isEmpty)
                Button { if let value = future.popLast() { past.append(layout.document); layout.document = value; saved = false } } label: { Image(systemName: "arrow.uturn.forward") }.disabled(future.isEmpty)
                if !embedded { Button("Cancel") { dismiss() } }
                Button("Save") { save(layout, baseLayout); if !embedded { dismiss() } }.buttonStyle(PadActionStyle(prominent: hasChanges)).disabled(!hasChanges)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Snap and align", isOn: $snap).fixedSize()
                    Spacer()
                    Button("Gyro & motion…") { advanced = true }.fixedSize()
                }
                HStack {
                Picker("Preview", selection: $preview) {
                    Text(screen == nil ? "Default canvas" : "Connected phone").tag("current")
                    Text("Compact · 667 × 375").tag("compact")
                    Text("Wide · 932 × 430").tag("wide")
                }.frame(maxWidth: 300)
                Text("\(Int(width)) × \(Int(height))").foregroundStyle(.secondary).fixedSize()
                }
            }
            if layout.effectiveInputType == .gamepad {
                Picker("Emulate controller", selection: Binding(get: { layout.document.controllerStyle ?? "xbox" }, set: { value in change { $0.controllerStyle = value } })) {
                    Text("Xbox").tag("xbox"); Text("PlayStation").tag("playstation")
                }.frame(width: 320)
            }
        }
    }
    private var canvas: some View {
        GeometryReader { geometry in
            let scale = max(0.01, min(geometry.size.width / width, geometry.size.height / height))
            let baseItems = storedItems
            let displayItems = items
            let overlaps = LayoutGeometry.overlappingIDs(displayItems, width: width, height: height)
            let unmapped = Set(layout.unmappedControls.map(\.canvasID))
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(PadAppearance.surface).contentShape(Rectangle()).onTapGesture { selected = nil }
                if snap && liveState == nil {
                    Path { path in
                        for i in 1..<40 { let x = Double(i) * width / 40; path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: height)) }
                        for i in 1..<20 { let y = Double(i) * height / 20; path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y)) }
                    }.stroke(Color.secondary.opacity(0.15), lineWidth: 0.5).allowsHitTesting(false)
                    if let selected, let chosen = displayItems.first(where: { $0.id == selected }) {
                        Path { path in
                            path.move(to: CGPoint(x: chosen.placement.x * width, y: 0)); path.addLine(to: CGPoint(x: chosen.placement.x * width, y: height))
                            path.move(to: CGPoint(x: 0, y: chosen.placement.y * height)); path.addLine(to: CGPoint(x: width, y: chosen.placement.y * height))
                        }.stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4])).allowsHitTesting(false)
                    }
                }
                ForEach(baseItems) { item in
                    let position = dragPreview?.id == item.id ? dragPreview!.placement : item.placement
                    let diameter = item.radius * 2
                    let four = item.role == "dpad" && mode.dpadStyle == "fourWay"
                    let invalid = unmapped.contains(item.runtimeID)
                    let color = invalid ? Color.red : selected == item.id ? Color.accentColor : overlaps.contains(item.id) && liveState == nil ? Color.orange : Color.primary.opacity(0.16)
                    ZStack {
                        if item.rectangular || (item.role == "rightStick" && mode.pointerMode == "cursor") { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial); RoundedRectangle(cornerRadius: 14).strokeBorder(color, lineWidth: 2) }
                        else if four { DPadCross().fill(.regularMaterial); DPadCross().stroke(color, lineWidth: 2) }
                        else { Circle().fill(.regularMaterial); Circle().strokeBorder(color, lineWidth: 2) }
                        if item.role != "dpad" && pressed(item) { Circle().fill(Color.accentColor.opacity(0.65)) }
                        if let state = liveState, ["leftStick", "rightStick"].contains(item.role) {
                            let left = item.role == "leftStick"
                            Circle().fill(Color.accentColor).frame(width: diameter * 0.32, height: diameter * 0.32)
                                .offset(x: CGFloat(left ? state.leftX : state.rightX) / 32767 * diameter * 0.3, y: CGFloat(left ? state.leftY : state.rightY) / 32767 * diameter * 0.3)
                        }
                        if item.role == "radial", let state = liveState, state.radialPreview > 1 {
                            let angle = Double(state.radialPreview - 2) * .pi / 4
                            Circle().fill(Color.accentColor).frame(width: 18, height: 18).offset(x: sin(angle) * diameter * 0.42, y: -cos(angle) * diameter * 0.42)
                        }
                        if item.role == "dpad" { DPadPreview(hat: liveState?.hat ?? 8, style: DPadStyle(rawValue: mode.dpadStyle ?? "eightWay") ?? .eightWay) }
                        else { Text(item.label).font(.system(size: 14 / scale, weight: .medium)).fixedSize() }
                    }.frame(width: item.width, height: item.height).position(x: position.x * width, y: position.y * height)
                        .onTapGesture { selected = item.id }
                        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                            .updating($dragPreview) { value, preview, transaction in
                                transaction.disablesAnimations = true
                                preview = ControlDragPreview(id: item.id, placement: draggedPlacement(item, translation: value.translation, others: baseItems))
                            }
                            .onChanged { _ in
                                if dragBaseDocument == nil { dragBaseDocument = layout.document }
                                if selected != item.id { selected = item.id }
                            }
                            .onEnded { value in
                                defer { dragBaseDocument = nil }
                                guard dragBaseDocument == layout.document else {
                                    error = "Layout changed during dragging. Try again."; return
                                }
                                let p = draggedPlacement(item, translation: value.translation, others: baseItems)
                                // Only the final placement enters validation, history and dirty-state notifications.
                                change { try $0.placeControl(item.id, at: DocumentPlacement(x: p.x, y: p.y, scale: p.scale), modeID: mode.id) }
                            })
                }
            }.frame(width: width, height: height).coordinateSpace(name: "canvas")
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.4), lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 24)).scaleEffect(scale, anchor: .topLeading).allowsHitTesting(liveState == nil)
        }
    }
    private func summary(_ item: ResolvedLayoutControl) -> String? {
        guard let control = layout.document.controls.first(where: { $0.id == item.id }) else { return nil }
        if control.role == "trackpad" { return "Pointer · tap to click · hold for right-click" }
        if control.role == "modeSwitch" { return "Switch modes" }
        if control.role == "rightStick", layout.effectiveInputType == .keyboardMouse, layout.document.keyboard?.rightStickMouse != false { return "Mouse" }
        if layout.effectiveInputType == .gamepad && ["leftStick", "rightStick"].contains(control.role) {
            let disabled = control.role == "leftStick" ? layout.document.gamepad?.disableLeftStick : layout.document.gamepad?.disableRightStick
            return disabled == true ? "Unmapped" : "Analog stick"
        }
        if control.role == "radial" { return "\(control.radialSlots?.count ?? 0) directions" }
        let directions = ["leftStick", "rightStick", "dpad"].contains(control.role) ? ["up", "right", "down", "left"] : ["press"]
        return directions.map { direction in
            guard let id = control.bindings?[direction], let action = layout.document.actions[id], !action.outputs.isEmpty else { return "Unmapped" }
            return action.outputs.map { output in
                OutputToken(documentOutput: output)?.label ?? MappedControl(rawValue: String(output.dropFirst("gamepad.".count)))?.label ?? output
            }.joined(separator: " + ")
        }.joined(separator: " / ")
    }
    private var mappingOverview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                Button { selected = item.id } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.label).fontWeight(.semibold)
                        Text(summary(item) ?? "Unmapped").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(selected == item.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private var inspector: some View {
        if let selected, let item = items.first(where: { $0.id == selected }), let control = layout.document.controls.first(where: { $0.id == selected }) {
            HStack {
                TextField("Control name", text: Binding(get: { item.label }, set: { value in change { try $0.renameControl(selected, caption: value, modeID: mode.id) } })).frame(width: 180)
                Button("Remove", role: .destructive) { change { try $0.removeControl(selected) }; self.selected = nil }.fixedSize()
                Text(item.rectangular ? "Rectangle" : "Size")
                if !item.rectangular { Slider(value: Binding(get: { item.placement.scale }, set: { value in change { try $0.placeControl(selected, at: DocumentPlacement(x: item.placement.x, y: item.placement.y, scale: value), modeID: mode.id) } }), in: 0.65...1.8).frame(width: 160) }
                if layout.document.modes.count > 1 {
                    Toggle("Keep position in both modes", isOn: Binding(get: { layout.document.linkedControls?.contains(selected) == true }, set: { linked in change { try $0.linkControl(selected, linked: linked, modeID: mode.id, placement: DocumentPlacement(x: item.placement.x, y: item.placement.y, scale: item.placement.scale)) } }))
                }
            }
            if ["customButton", "trackpad"].contains(control.role) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rectangle dimensions")
                    ForEach(["Width", "Height"], id: \.self) { axis in
                        Slider(value: Binding(get: { axis == "Width" ? item.width / width : item.height / height }, set: { value in
                            change { try $0.placeControl(selected, at: DocumentPlacement(x: item.placement.x, y: item.placement.y, scale: item.placement.scale,
                                width: axis == "Width" ? value : item.width / width, height: axis == "Height" ? value : item.height / height), modeID: mode.id) }
                        }), in: 0.03...1) { Text(axis) }
                    }
                    Button("Reset shape and position") { change { try $0.resetPlacement(selected, modeID: mode.id) } }
                }
            }
            if control.role == "trackpad" {
                Toggle("Two-finger scrolling", isOn: Binding(get: { mode.trackpadScroll ?? true }, set: { value in change { doc in let i = doc.modes.firstIndex { $0.id == mode.id }!; doc.modes[i].trackpadScroll = value } }))
                Text("Drag to move, tap to click, hold for right-click. Available in either pointer mode.").foregroundStyle(.secondary)
            }
            if control.role == "dpad" {
                Picker("D-pad style", selection: Binding(get: { mode.dpadStyle ?? "eightWay" }, set: { value in change { doc in let i = doc.modes.firstIndex { $0.id == mode.id }!; doc.modes[i].dpadStyle = value } })) {
                    Text("4 directions").tag("fourWay"); Text("8 directions").tag("eightWay")
                }.pickerStyle(.segmented).frame(width: 320)
            }
            if control.role == "rightStick" && layout.effectiveInputType == .keyboardMouse {
                Toggle("Move the mouse", isOn: Binding(get: { layout.document.keyboard?.rightStickMouse ?? true }, set: { enabled in change { doc in
                    if doc.keyboard == nil { doc.keyboard = DocumentKeyboardSettings() }
                    doc.keyboard?.rightStickMouse = enabled
                    if enabled, let i = doc.controls.firstIndex(where: { $0.id == selected }) { doc.controls[i].bindings = nil }
                } }))
                Toggle("Allow cursor switching", isOn: Binding(get: { layout.hasCursorSwitching }, set: { enabled in change { $0.setModeSwitching(enabled) } }))
            }
            if control.role == "radial" {
                ForEach(Array(LayoutDocument.radialDirections.enumerated()), id: \.offset) { index, direction in
                    Picker(direction, selection: Binding(get: { layout.document.radialSlots()[index] }, set: { slot in change { try $0.assignRadial(direction: index, customSlot: slot) } })) {
                        Text("Unmapped").tag(-1)
                        ForEach(layout.document.controls.filter { $0.role == "customButton" }, id: \.id) { source in Text(source.label ?? "Custom \((source.customSlot ?? 0) + 1)").tag(source.customSlot!) }
                    }
                    if let sourceID = control.radialSlots?[direction] { bindingEditor(controlID: sourceID, direction: "press", caption: direction) }
                }
            } else if ["leftStick", "rightStick"].contains(control.role) && layout.effectiveInputType == .gamepad {
                Toggle("Enable analog stick", isOn: Binding(get: { control.role == "leftStick" ? layout.document.gamepad?.disableLeftStick != true : layout.document.gamepad?.disableRightStick != true }, set: { enabled in change { doc in
                    if doc.gamepad == nil { doc.gamepad = DocumentGamepadSettings() }
                    if control.role == "leftStick" { doc.gamepad?.disableLeftStick = !enabled } else { doc.gamepad?.disableRightStick = !enabled }
                } }))
            } else if !["modeSwitch", "trackpad"].contains(control.role) && !(control.role == "rightStick" && layout.document.keyboard?.rightStickMouse != false) {
                ForEach(["leftStick", "rightStick", "dpad"].contains(control.role) ? ["up", "right", "down", "left"] : ["press"], id: \.self) { direction in
                    bindingEditor(controlID: selected, direction: direction, caption: item.label + (direction == "press" ? "" : " · " + direction.capitalized))
                }
            }
        } else { Text("Select a control to edit it.").foregroundStyle(.secondary) }
    }
    @ViewBuilder private func bindingEditor(controlID: String, direction: String, caption: String) -> some View {
        let reference = LayoutBindingReference.control(id: controlID, direction: direction)
        let action = layout.document.actionID(for: reference).flatMap { layout.document.actions[$0] }
        VStack(alignment: .leading, spacing: 10) {
            Text(caption).fontWeight(.semibold)
            if layout.effectiveInputType == .keyboardMouse {
                ComboBindingEditor(binding: Binding(get: { KeyBinding(action?.outputs.compactMap(OutputToken.init(documentOutput:)) ?? [], behavior: action?.behavior == "tap" ? .tap : .hold) }, set: { value in
                    change { try $0.rebind(reference, outputs: value.outputs.map(\.documentOutput), behavior: value.behavior.rawValue) }
                }))
            } else {
                Picker("Controller input", selection: Binding(get: { action?.outputs.first ?? "none" }, set: { value in change { try $0.rebind(reference, outputs: value == "none" ? [] : [value]) } })) {
                    Text("Unmapped").tag("none")
                    ForEach(GamepadProfile.destinations, id: \.self) { Text($0.label).tag("gamepad." + $0.rawValue) }
                }
            }
        }.font(.system(size: 14)).padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DPadPreview: View {
    let hat: UInt8
    let style: DPadStyle
    var body: some View {
        GeometryReader { geometry in
            let radius = geometry.size.width / 2
            let center = CGPoint(x: radius, y: radius)
            ZStack {
                ForEach(style.directions, id: \.self) { direction in
                    let angle = Double(direction) * .pi / 4
                    let start = angle - .pi / 2 - style.sectorHalfAngle + 0.045
                    let end = angle - .pi / 2 + style.sectorHalfAngle - 0.045
                    let segment = style == .fourWay ? Path(roundedRect: CGRect(x: -radius * 0.29, y: -radius * 0.89, width: radius * 0.58, height: radius * 0.59), cornerRadius: radius * 0.08)
                        .applying(CGAffineTransform(rotationAngle: angle))
                        .applying(CGAffineTransform(translationX: radius, y: radius)) : Path { path in
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

struct DPadCross: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let points: [(CGFloat, CGFloat)] = [(-0.32,-0.92),(0.32,-0.92),(0.32,-0.32),(0.92,-0.32),(0.92,0.32),(0.32,0.32),(0.32,0.92),(-0.32,0.92),(-0.32,0.32),(-0.92,0.32),(-0.92,-0.32),(-0.32,-0.32)]
        return Path { path in
            for (index, point) in points.enumerated() {
                let p = CGPoint(x: rect.midX + point.0 * r, y: rect.midY + point.1 * r)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}


private struct ControlDragPreview: Equatable {
    let id: String
    let placement: ControlPlacement
}
