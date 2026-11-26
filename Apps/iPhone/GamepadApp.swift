import SwiftUI
import UniformTypeIdentifiers

final class LayoutStore: ObservableObject {
    @Published private(set) var catalog: LocalLayoutCatalog = .fresh()
    @Published var storageError: String?
    @Published private(set) var history = DocumentLayoutHistory()
    private var store: LayoutDocumentStore?
    private var storageURL: URL?
    init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = directory.appendingPathComponent("PocketPad/layout-documents-v1.json")
            storageURL = url
            store = try LayoutDocumentStore(url: url)
            refresh()
        } catch { storageError = "Saved layouts could not be opened and have not been overwritten: " + error.localizedDescription }
    }
    private func refresh() { if let store { catalog = store.catalog; history = store.history } }
    private func perform(_ action: (LayoutDocumentStore) throws -> Void) {
        guard let store else { return }
        do { try action(store); refresh(); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    var selected: LocalLayout { catalog.layouts.first { $0.id == catalog.selectedID }! }
    var activeModeID: String { catalog.activeMode(for: selected) }
    func beginEdit() { store?.beginEdit() }
    func endEdit() { store?.endEdit(); refresh() }
    func undo() { perform { try $0.undo() } }
    func redo() { perform { try $0.redo() } }
    func save() { endEdit() }
    func change(_ update: (inout LayoutDocument) throws -> Void) { perform { try $0.edit(update) } }
    func importData(_ data: Data) throws {
        guard let store else { throw LayoutDocumentError("Layout storage is unavailable") }
        try store.importDocument(data); refresh()
    }
    func apply(_ command: DocumentLayoutCommand) -> DocumentLayoutAcknowledgment {
        guard let store else { return DocumentLayoutAcknowledgment(commandID: command.id, error: "Layout storage is unavailable") }
        let result = store.apply(command); refresh(); return result
    }
    func delete(_ id: String) throws {
        guard let store else { throw LayoutDocumentError("Layout storage is unavailable") }
        try store.delete(id); refresh()
    }
    func clearLayouts() {
        if store != nil { perform { try $0.resetLayouts() }; return }
        // Only the explicit, confirmed reset action may replace unreadable storage.
        do {
            guard let url = storageURL else { throw LayoutDocumentError("Layout storage is unavailable") }
            try LocalLayoutCatalog.fresh().save(to: url)
            store = try LayoutDocumentStore(url: url); refresh(); storageError = nil
        } catch { storageError = error.localizedDescription }
    }
    func select(_ id: String) { perform { try $0.select(id) } }
    func selectMode(_ id: String) { perform { try $0.selectMode(id) } }
    func copy(name: String) { perform { try $0.duplicate(name: name) } }
    func create(_ document: LayoutDocument, provenance: LayoutProvenance? = nil) { perform { try $0.create(document, provenance: provenance) } }
}

@main
struct PhoneGamepadApp: App {
    @StateObject private var server = CableServer()
    @StateObject private var layouts = LayoutStore()
    @Environment(\.scenePhase) private var phase
    @State private var resetID = UUID()
    @State private var canvasSize = CGSize.zero
    @State private var editing = false
    @AppStorage("phone-onboarding-v1") private var tourComplete = false
    @State private var tour = false
    @State private var settings = false
    @AppStorage("settings-button-size") private var settingsButtonSize = 48.0
    @AppStorage("settings-button-fade-delay") private var settingsFadeDelay = 3.0
    @AppStorage("settings-button-inactive-opacity") private var settingsInactiveOpacity = 0.35
    @AppStorage("layout-snap") private var snapLayout = false
    @State private var connectionScreen = false
    @State private var lastAcknowledgment: DocumentLayoutAcknowledgment?
    @State private var lastLayoutCommand: String?
    @State private var layoutCommandError: String?
    @State private var buttonOptions = false
    @State private var showGhost = true
    @State private var exporting = false
    @State private var importing = false
    @State private var document = ProfileDocument()
    @State private var transferMessage: String?
    @State private var exportName = "Gamepad Air"
    @State private var selectedReference: ControlPlacement?
    @State private var selectedID: String?
    @State private var selectedLabel = ""
    @State private var nameDraft = ""
    @State private var naming = false
    @State private var nameAction = "copy"
    @State private var newStyle = PadStyle.xbox
    @State private var newInputType = LayoutInputType.keyboardMouse
    @State private var confirmReset = false
    @State private var confirmDataAction = false
    @State private var dataAction = "delete"
    private var layout: LocalLayout { layouts.selected }
    private var modeID: String { layouts.activeModeID }
    private var otherModeID: String { layout.document.modes.first { $0.id != modeID }?.id ?? modeID }
    private var mode: ResolvedLayoutMode { layout.resolvedMode(modeID) }
    private var padStyle: PadStyle { layout.style }
    private var placements: [String: ControlPlacement] { mode.controls.controls(for: padStyle) }
    private func changeMode(_ update: (inout DocumentMode) -> Void) {
        layouts.change { document in
            guard let index = document.modes.firstIndex(where: { $0.id == modeID }) else { return }
            update(&document.modes[index])
        }
    }
    private func binding<T>(_ key: WritableKeyPath<DocumentMode, T>) -> Binding<T> {
        Binding(get: { layout.document.modes.first { $0.id == modeID }![keyPath: key] }, set: { value in changeMode { $0[keyPath: key] = value }; release() })
    }
    private func optionBinding<T>(_ key: WritableKeyPath<DocumentMode, T?>, default fallback: T) -> Binding<T> {
        Binding(get: { layout.document.modes.first { $0.id == modeID }?[keyPath: key] ?? fallback }, set: { value in
            if layout.isPreset { layouts.copy(name: layout.name + " Custom") }
            changeMode { $0[keyPath: key] = value }; release()
        })
    }
    private func place(_ p: ControlPlacement, runtimeID: String) {
        guard let id = layout.controlID(runtimeID: runtimeID) else { return }
        layouts.change { try $0.placeControl(id, at: DocumentPlacement(x: p.x, y: p.y, scale: p.scale), modeID: modeID) }
    }
    private var selectedItem: ResolvedLayoutControl? {
        LayoutGeometry.resolve(layout.document, modeID: modeID, width: max(1, canvasSize.width), height: max(1, canvasSize.height)).first { $0.runtimeID == selectedID }
    }
    private var selectedDiameter: Binding<Double> {
        Binding(get: { selectedItem?.width ?? 44 }, set: { value in
            guard let item = selectedItem else { return }
            layouts.change { try $0.placeControl(item.id, at: DocumentPlacement(x: item.placement.x, y: item.placement.y, scale: item.placement.scale, diameter: value), modeID: modeID) }
        })
    }
    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                ControllerSurface(document: layout.document, activeModeID: modeID, referenceModeID: otherModeID, style: padStyle, mode: mode, displayLabels: layout.displayLabels(modeID: modeID), touchHaptic: layout.effectiveTouchHaptic, showsGuideButton: layout.effectiveInputType == .gamepad, guideLabel: layout.effectiveControllerStyle.label(.guide), showsModeSwitch: layout.hasCursorSwitching, placements: placements, unmapped: Set(layout.unmappedControls.map(\.canvasID)),
                    referenceMode: layout.resolvedMode(otherModeID), showGhost: showGhost,
                    onReference: { selectedReference = $0 }, onCanvasSize: { size in
                        guard canvasSize != size else { return }
                        canvasSize = size
                        publishLayout(canvas: size)
                    }, onEditEnded: { layouts.endEdit() },
                    editing: editing, inputEnabled: !settings && !naming && !tour && !connectionScreen && phase == .active, selectedID: selectedID, onState: { server.update(settings || editing || naming || tour || connectionScreen ? .paused : $0) }, onPointer: { action, dx, dy in if !settings && !editing && !naming && !tour && !connectionScreen && phase == .active { server.pointer(action, dx: dx, dy: dy) } },
                    onToggle: toggleMode,
                    onRename: { id, label in selectedID = id; selectedLabel = label; nameDraft = label; nameAction = "control"; naming = true },
                    onSelect: { id, label, p in
                        layouts.beginEdit(); selectedID = id; selectedLabel = label
                    }, onPlacement: { id, p in place(p, runtimeID: id) })
                    .id(resetID).ignoresSafeArea()
                if !editing {
                    MovableSettingsButton(connected: server.connected,
                        openSettings: { settings = true; release() }, editLayout: startEditing)
                    if !server.connected {
                        HStack {
                            Button("Connect") { connectionScreen = true; release() }
                                .buttonStyle(PadActionStyle())
                            Spacer()
                        }.padding(.horizontal, 12).padding(.top, 4)
                    }
                }
                if editing {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            if selectedID == nil {
                                Text("Drag controls").font(.callout).fixedSize(horizontal: true, vertical: false)
                            } else {
                                Text(selectedLabel).font(.callout).lineLimit(1).frame(width: 90)
                                if selectedItem?.rectangular == false {
                                    Text("\(Int(selectedDiameter.wrappedValue.rounded())) pt").font(.callout.monospacedDigit()).fixedSize()
                                    Button { selectedDiameter.wrappedValue = max(44, selectedDiameter.wrappedValue.rounded() - 1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                                        .disabled(selectedDiameter.wrappedValue <= 44).accessibilityLabel("Decrease size by one point")
                                    Slider(value: selectedDiameter, in: 44...240, step: 1, onEditingChanged: { active in if active { layouts.beginEdit() } else { layouts.endEdit() } }).frame(width: 90)
                                    Button { selectedDiameter.wrappedValue = min(240, selectedDiameter.wrappedValue.rounded() + 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                                        .disabled(selectedDiameter.wrappedValue >= 240).accessibilityLabel("Increase size by one point")
                                }
                                Button { buttonOptions = true } label: {
                                    Label("Control options", systemImage: "slider.horizontal.3")
                                        .frame(minWidth: 110, minHeight: 44)
                                }
                            }
                        }.padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 4)
                    }.allowsHitTesting(true)
                    HStack(spacing: 12) {
                        Button { layouts.undo(); selectedID = nil; release() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(!layouts.history.canUndo)
                        Button { layouts.redo(); selectedID = nil; release() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(!layouts.history.canRedo)
                        if layout.hasCursorSwitching { Picker("Mode", selection: Binding(get: { modeID }, set: { layouts.selectMode($0); selectedID = nil; release() })) {
                            ForEach(layout.document.modes, id: \.id) { Text($0.name).tag($0.id) }
                        }.pickerStyle(.segmented).frame(width: 180) }
                        Menu("Add control") {
                            ForEach(["customButton", "leftStick", "rightStick", "dpad", "radial"] + (layout.effectiveInputType == .keyboardMouse ? ["trackpad"] : []), id: \.self) { role in
                                Button(["customButton": "Button", "leftStick": "Left joystick", "rightStick": "Right joystick", "dpad": "D-pad", "radial": "Radial", "trackpad": "Trackpad"][role]!) {
                                    layouts.change { doc in
                                        if doc.controls.contains(where: { $0.role == role }) && role != "customButton" {
                                            try doc.setControlVisible(role: role, visible: true, modeID: modeID)
                                        } else { _ = try doc.addControl(role: role) }
                                    }; release()
                                }.disabled(role == "customButton" ? layout.document.controls.filter { $0.role == role }.count >= 16 : layout.document.controls.contains { $0.role == role && layout.document.resolvedControl($0.id, modeID: modeID)?.hidden != true })
                            }
                        }
                        Spacer()
                        Button("Done editing") { editing = false; selectedID = nil; release() }
                            .buttonStyle(PadActionStyle(prominent: true)).frame(minWidth: 120, minHeight: 44)
                    }.padding(.horizontal, 55).padding(.top, 4)
                }
                if connectionScreen && !tour {
                    PhoneConnectionView(server: server) { connectionScreen = false; release() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background { PadBackdrop() }
                }
            }
            .background { PadBackdrop() }
            .tint(PadAppearance.accent)
            .statusBarHidden().persistentSystemOverlays(.hidden).defersSystemGestures(on: .all)
            .fullScreenCover(isPresented: $tour, onDismiss: release) { PhoneOnboarding(server: server) { tourComplete = true; tour = false; release() } }
            .sheet(isPresented: $settings, onDismiss: release) { settingsView }
            .sheet(isPresented: $buttonOptions, onDismiss: release) { buttonOptionsView }
            .sheet(isPresented: $naming) {
                LayoutNameSheet(name: $nameDraft, action: nameAction, type: $newInputType, style: $newStyle, currentType: layout.effectiveInputType) {
                    saveName(); naming = false
                }
            }
            .confirmationDialog("Reset only this mode's arrangement?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset mode arrangement", role: .destructive) {
                    layouts.change { try $0.resetArrangement(modeID: modeID) }
                    selectedID = nil; release()
                }
            }
            .onChange(of: layouts.catalog) { _, _ in publishLayout() }
            .onChange(of: modeID) { _, _ in publishLayout() }
            .onChange(of: settings) { _, _ in release() }
            .onChange(of: naming) { _, _ in release() }
            .onChange(of: server.setupStage) { _, stage in
                if stage == .play && server.connected { connectionScreen = false; release() }
                if stage == .practice || stage == .controls { connectionScreen = false; tour = true; release() }
            }
            .onChange(of: server.connected) { wasConnected, connected in
                if connected && server.setupStage == .play { connectionScreen = false; release() }
                else if wasConnected && phase == .active && !tour && !settings && !editing && !naming {
                    connectionScreen = true; release()
                }
            }
            .onAppear { tour = !tourComplete; connectionScreen = tourComplete && !server.connected; activate() }
            .onChange(of: phase) { _, phase in
                layouts.save(); release()
                if phase == .active {
                    if tourComplete && !server.connected && !tour && !settings && !editing && !naming {
                        connectionScreen = true
                    }
                    activate()
                }
                else { server.stop(); UIApplication.shared.isIdleTimerDisabled = false }
            }
        }
    }
    private var tintBinding: Binding<ButtonTint> {
        Binding(get: { mode.buttonFeedback?[selectedID ?? ""]?.tint ?? .automatic }, set: { value in
            guard let runtimeID = selectedID, let id = layout.controlID(runtimeID: runtimeID) else { return }
            layouts.change { try $0.setFeedback(id, modeID: modeID, tint: value.rawValue.lowercased()) }
        })
    }
    private var buttonOptionsView: some View {
        NavigationStack {
            Form {
                Toggle("Snap and align", isOn: $snapLayout)
                if let id = selectedID, let controlID = layout.controlID(runtimeID: id),
                   let control = layout.document.controls.first(where: { $0.id == controlID }), ["trackpad", "customButton"].contains(control.role) {
                    Section(control.role == "trackpad" ? "Trackpad area · relative to screen" : "Button dimensions · minimum 44 pt") {
                        ForEach(["Width", "Height"], id: \.self) { axis in
                            Slider(value: Binding(get: {
                                let p = layout.document.resolvedControl(controlID, modeID: modeID)?.placement
                                return axis == "Width" ? p?.width ?? 0.28 : p?.height ?? 0.4
                            }, set: { value in
                                let p = layout.document.resolvedControl(controlID, modeID: modeID)?.placement ?? DocumentPlacement(x: 0.5, y: 0.5)
                                layouts.change { try $0.placeControl(controlID, at: DocumentPlacement(x: p.x, y: p.y, scale: p.scale, width: axis == "Width" ? value : p.width ?? 0.28, height: axis == "Height" ? value : p.height ?? 0.4), modeID: modeID) }
                            }), in: 0.03...1) { Text(axis) }
                        }

                    }
                }
                if layout.hasCursorSwitching { Section("Position across modes") {
                    Toggle("Link position and size", isOn: Binding(get: { selectedID.map { layout.document.linkedControls?.contains(layout.controlID(runtimeID: $0) ?? "") == true } ?? false }, set: { linked in
                        guard let id = selectedID, let p = placements[id] else { return }
                        guard let controlID = layout.controlID(runtimeID: id) else { return }
                        layouts.change { try $0.linkControl(controlID, linked: linked, modeID: modeID, placement: DocumentPlacement(x: p.x, y: p.y, scale: p.scale)) }
                    }))
                    Button("Copy position from \(layout.resolvedMode(otherModeID).name)") {
                        guard let id = selectedID, let p = selectedReference else { return }
                        place(p, runtimeID: id)
                    }.disabled(selectedReference == nil)
                    Toggle("Show other mode outline", isOn: $showGhost)
                    Text("Keep this button’s position and size matched across modes.").font(.callout).foregroundStyle(.secondary)
                } }
                if selectedID == "dpad" {
                    Section {
                        Picker("Directions", selection: Binding(get: { mode.effectiveDPadStyle }, set: { value in
                            changeMode { $0.dpadStyle = value.rawValue }
                        })) {
                            ForEach(DPadStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    } header: { Text("D-pad style") } footer: {
                        Text("4 directions selects one direction at a time. 8 directions also allows diagonals.")
                    }
                }
                if selectedID == "radial" {
                    Section("Radial directions") {
                    Text("Hold, swipe, and release to select. Return to the center to cancel.").font(.callout)
                    if mode.radialEnabled == true {
                        Button("Hide separate buttons used by the radial") {
                            layouts.change { try $0.hideRadialSources(modeID: modeID) }; release()
                        }
                        ForEach(0..<8, id: \.self) { i in
                            Picker(["↑ Up", "↗ Upper right", "→ Right", "↘ Lower right", "↓ Down", "↙ Lower left", "← Left", "↖ Upper left"][i], selection: Binding(get: { (mode.radialSlots ?? Array(repeating: -1, count: 8))[i] }, set: { slot in
                                layouts.change { try $0.assignRadial(direction: i, customSlot: slot) }; release()
                            })) {
                                Text("None").tag(-1)
                                ForEach(layout.document.controls.filter { $0.role == "customButton" }, id: \.id) { control in Text(control.label ?? "Custom \((control.customSlot ?? 0) + 1)").tag(control.customSlot!) }
                            }
                        }
                    }
                    }
                }
                if selectedID == "left-stick" || (selectedID == "right-stick" && !mode.cursor) {
                    Section("Stick behavior") {
                        let left = selectedID == "left-stick"
                        Picker("Position", selection: optionBinding(left ? \.floatingLeft : \.floatingRight, default: false)) {
                            Text("Center on touch").tag(true)
                            Text("Fixed position").tag(false)
                        }
                        Picker("Tap action", selection: Binding(get: { left ? mode.leftTap : mode.rightTap }, set: { value in
                            changeMode { if left { $0.leftTap = value.rawValue } else { $0.rightTap = value.rawValue } }; release()
                        })) {
                            ForEach(StickTapAction.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Text("A quick tap sends the selected control's input. Holding near the center triggers L3 or R3.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if selectedID == "right-trigger" && !mode.cursor {
                    Section("Hold and drag") {
                        if (layout.document.motion?.mode ?? "off") == "off" {
                            Toggle("Drag to aim while holding", isOn: optionBinding(\.holdAimEnabled, default: true))
                            if mode.holdAimEnabled {
                                Picker("Hold delay", selection: optionBinding(\.holdAimDelay, default: 0.3)) {
                                    ForEach([0.2, 0.3, 0.5, 0.8], id: \.self) { Text("\($0, specifier: "%.1f") seconds").tag($0) }
                                }
                            }
                            Text("After holding this trigger, drag your finger to aim. This is a touch gesture, not gyro motion.").font(.callout)
                        } else {
                            Text("Hold-and-drag aiming is unavailable while gyro or steering is enabled.").font(.callout)
                        }
                    }
                }
                if selectedID == "trackpad" || (selectedID == "right-stick" && mode.cursor) {
                    Section("Trackpad gestures") {
                        if selectedID == "trackpad" {
                            Toggle("Two-finger scrolling", isOn: optionBinding(\.trackpadScroll, default: true))
                        }
                        Picker("Hold for right-click", selection: optionBinding(\.trackpadHoldDelay, default: 0.5)) {
                            ForEach([0.3, 0.5, 0.7], id: \.self) { Text("\($0, specifier: "%.1f") seconds").tag($0) }
                        }
                    }
                }
                Section("Appearance") {
                    Picker("Button color", selection: tintBinding) {
                        ForEach(ButtonTint.allCases, id: \.self) { tint in
                            Label { Text(tint.rawValue) } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(Color(tint.uiColor))
                            }.tag(tint)
                        }
                    }
                }
                Section {
                    Button("Rename control") { buttonOptions = false; nameAction = "control"; nameDraft = selectedLabel; naming = true }
                    Button("Reset position and size") {
                        guard let id = selectedID else { return }
                        if let controlID = layout.controlID(runtimeID: id) { layouts.change { try $0.resetPlacement(controlID, modeID: modeID) } }
                        buttonOptions = false; selectedID = nil; release()
                    }
                    if let id = selectedID, let controlID = layout.controlID(runtimeID: id) {
                        Button("Remove control", role: .destructive) {
                            layouts.change { try $0.removeControl(controlID) }
                            buttonOptions = false; selectedID = nil; release()
                        }
                    }
                }
            }.navigationTitle(selectedLabel).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Back to editor") { buttonOptions = false } }
            }
        }
    }
    private var settingsView: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(layout.name).font(.title2.weight(.medium))
                            }
                            Spacer()
                            Label(server.connected ? "Connected" : "Disconnected", systemImage: server.connected ? "checkmark.circle.fill" : "circle")
                                .font(.callout).foregroundStyle(server.connected ? PadAppearance.accent : .secondary)
                        }
                        HStack(spacing: 16) {
                            Text("Hold the Settings button to quickly edit your layout.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button { startEditing() } label: { Label("Edit layout", systemImage: "slider.horizontal.3") }
                                .buttonStyle(PadActionStyle(prominent: true))
                        }
                    }.padding(.vertical, 8)
                }

                if let error = layouts.storageError { Text(error).foregroundStyle(.red) }
                DisclosureGroup("Connection") {
                    Picker("Connection", selection: Binding(get: { server.transport }, set: { server.selectTransport($0); release() })) {
                        ForEach(LinkTransport.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Text(server.status).font(.callout)
                    if server.transport != .usb {
                        if server.transport == .wifi { LabeledContent("iPhone address", value: server.wifiAddress) }
                        PhoneNameEditor(server: server)
                        LabeledContent("6-digit pairing code", value: WirelessSettings.formattedCode(server.pairingCode)).textSelection(.enabled)
                        Text(server.transport == .wifi ? "Use the same Wi-Fi network. Find this phone on the Mac, or enter its address, then enter the six-digit code." : "Select Bluetooth on the Mac, find this phone, and enter the six-digit code. Accept Bluetooth permission and pairing prompts on both devices. Keep this app open.").font(.callout)
                        Button("New pairing code") { server.newPairingCode(); release() }
                    }
                }
                Section("Saved layouts") {
                    Picker("Layout", selection: Binding(get: { layouts.catalog.selectedID }, set: {
                        layouts.select($0); selectedID = nil; editing = false; release()
                    })) {
                        ForEach(layouts.catalog.layouts) { Text($0.name + ($0.isPreset ? " · preset" : "")).tag($0.id) }
                    }
                    Button("Save a copy…") { beginName("copy", value: layout.name + " Copy") }
                    Button("New layout…") { beginName("new", value: "New Controls") }
                    if !layout.isPreset { Button("Rename layout…") { beginName("rename", value: layout.name) } }
                    if !layout.isPreset {
                        Button("Delete layout…", role: .destructive) { dataAction = "delete"; confirmDataAction = true }
                    }
                    if layout.isPreset { Text("Presets stay unchanged. Save a copy to customize.").font(.callout) }
                }
                Section("Current layout") {
                    NavigationLink("Layout options") {
                        Form {
                            if layout.effectiveInputType == .gamepad {
                                Section("Controller emulation") {
                                    Picker("Emulate controller", selection: Binding(get: { layout.effectiveControllerStyle }, set: { value in
                                        if layout.isPreset { layouts.copy(name: layout.name + " Custom") }
                                        release()
                                        layouts.change { $0.controllerStyle = value == .xbox ? "xbox" : "playstation" }
                                    })) {
                                        ForEach(PadStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                    Text("Changes the controller seen by your game. Your button positions and mappings stay the same. You may need to restart the game.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            Section("Layout touch feedback") {
                                Picker("Button haptics", selection: Binding(get: { layout.effectiveTouchHaptic }, set: { value in
                                    if layout.isPreset { layouts.copy(name: layout.name + " Custom") }
                                    layouts.change { $0.haptics = value.rawValue.lowercased() }
                                    TouchPadView.playHaptic(value)
                                })) {
                                    ForEach(ButtonHaptic.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                Text("Applies to all buttons and L3/R3 in this layout. Stick movement stays silent. Game rumble is separate.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            if layout.effectiveInputType == .keyboardMouse && layout.document.controls.contains(where: { $0.role == "rightStick" }) {
                            DisclosureGroup("Right-stick cursor switching") {
                                Toggle("Allow switching between aim and cursor", isOn: Binding(get: { layout.hasCursorSwitching }, set: { enabled in
                                    layouts.change { $0.setModeSwitching(enabled) }; release()
                                }))
                                if layout.hasCursorSwitching { Picker("Edit mode", selection: Binding(get: { modeID }, set: { layouts.selectMode($0); selectedID = nil; release() })) {
                                    ForEach(layout.document.modes, id: \.id) { Text($0.name).tag($0.id) }
                                }
                                }
                                if layout.hasCursorSwitching { TextField("Mode name", text: binding(\.name)) }
                                Picker("Right control behavior", selection: Binding(get: { mode.cursor }, set: { value in changeMode { $0.pointerMode = value ? "cursor" : "aim" }; release() })) {
                                    Text("Camera aim · analog stick").tag(false)
                                    Text("Menu pointer · trackpad").tag(true)
                                }
                            }.disabled(layout.isPreset)
                            }
                            DisclosureGroup("Motion") {
                                Picker("Motion behavior", selection: Binding(get: { layout.document.motion?.mode ?? "off" }, set: { value in
                                    layouts.change { doc in
                                        if doc.motion == nil { doc.motion = DocumentMotionSettings() }
                                        doc.motion?.mode = value
                                        if value != "off" { try doc.revealMotionActivation(modeID: modeID) }
                                    }; release()
                                })) {
                                    Text("Off").tag("off"); Text("Gyro aim").tag("aim")
                                    if layout.effectiveInputType == .gamepad { Text("Analog steering").tag("steering") }
                                }
                                if (layout.document.motion?.mode ?? "off") != "off" {
                                Picker("Activation button", selection: Binding(get: { layout.document.motionActivationControl?.id ?? "" }, set: { value in
                                    layouts.change { doc in
                                        if doc.motion == nil { doc.motion = DocumentMotionSettings() }
                                        doc.motion?.activationControl = value
                                        try doc.revealMotionActivation(modeID: modeID)
                                    }; release()
                                })) {
                                    ForEach(layout.document.motionActivationControls, id: \.id) { control in
                                        Text(layout.displayLabels(modeID: modeID)[control.runtimeID] ?? control.id).tag(control.id)
                                    }
                                }
                                Slider(value: Binding(get: { layout.document.motion?.sensitivity ?? 1 }, set: { value in layouts.change { if $0.motion == nil { $0.motion = DocumentMotionSettings() }; $0.motion?.sensitivity = value } }), in: 0.1...4) { Text("Sensitivity") }
                                Slider(value: Binding(get: { layout.document.motion?.deadZone ?? 0.03 }, set: { value in layouts.change { if $0.motion == nil { $0.motion = DocumentMotionSettings() }; $0.motion?.deadZone = value } }), in: 0...0.3) { Text("Dead zone") }
                                Text("Hold the selected button to calibrate your current angle. Release to stop, then hold again to recalibrate. The button keeps its mapping. Aim moves the mouse or right stick; steering controls left X.").font(.callout)
                                }
                            }.disabled(layout.isPreset)
                            Section {
                                Button("Reset mode arrangement…", role: .destructive) { settings = false; confirmReset = true }
                                    .disabled(layout.isPreset)
                            }
                        }.navigationTitle("Layout options")
                    }
                }
                DisclosureGroup("Settings button") {
                    Slider(value: $settingsButtonSize, in: 44...80, step: 2) { Text("Size") }
                    Text("Size: \(Int(settingsButtonSize)) points")
                    Slider(value: $settingsFadeDelay, in: 0...10, step: 0.5) { Text("Fade delay") }
                    Text(settingsFadeDelay == 0 ? "Always visible" : "Fade after \(settingsFadeDelay, specifier: "%.1f") seconds")
                    Slider(value: $settingsInactiveOpacity, in: 0.15...1) { Text("Inactive opacity") }
                    Text("Inactive opacity: \(Int(settingsInactiveOpacity * 100))%")
                }
                Section("Help") {
                    Button("Show setup again") { settings = false; tour = true; release() }
                }
                DisclosureGroup("About Gamepad Air") {

                    Link("Get the Mac app", destination: AppInformation.macDownloadURL)
                    Link("Support", destination: AppInformation.supportURL)
                    NavigationLink("Privacy policy") {
                        ScrollView { Text(AppInformation.privacy).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled) }
                            .navigationTitle("Privacy")
                    }
                }
                DisclosureGroup("Layout backups") {
                    Button("Export layout…") { exportProfile() }
                    Button("Import layout…") { importing = true }
                    Text("Layout files include controls, mappings and settings. Import creates a new local copy.").font(.callout).foregroundStyle(.secondary)
                }
                Section("Local data") {
                    Button("Clear saved layouts…", role: .destructive) { dataAction = "clear"; confirmDataAction = true }
                    Button("Erase all local data…", role: .destructive) { dataAction = "erase"; confirmDataAction = true }
                    Text("Built-in presets remain available. Exported files and data on your Mac are not deleted.").font(.callout).foregroundStyle(.secondary)
                }
                AppIconSettingsSection()
            }.scrollContentBackground(.hidden).background { PadBackdrop() }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { settings = false } }
        }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: exportName) { result in
                if case .failure(let error) = result { transferMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let value = try LayoutDocumentFile.read(url)
                    try layouts.importData(value.document.validatedData()); selectedID = nil; release()
                    transferMessage = "Imported as a new layout. Your existing layouts are unchanged."
                } catch { transferMessage = "Could not import: \(error.localizedDescription)" }
            }
            .confirmationDialog(dataAction == "delete" ? "Delete \(layout.name)?" : dataAction == "clear" ? "Clear all saved layouts?" : "Erase all Gamepad Air data on this iPhone?", isPresented: $confirmDataAction, titleVisibility: .visible) {
                Button(dataAction == "delete" ? "Delete layout" : dataAction == "clear" ? "Clear saved layouts" : "Erase local data", role: .destructive) {
                    release(); editing = false; selectedID = nil
                    if dataAction == "delete" {
                        do { try layouts.delete(layout.id) } catch { transferMessage = "Could not delete this layout." }
                    } else if dataAction == "clear" { layouts.clearLayouts() }
                    else {
                        server.stop()
                        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
                        layouts.clearLayouts()
                        lastLayoutCommand = nil; layoutCommandError = nil; document = ProfileDocument()
                        transferMessage = nil; selectedReference = nil; nameDraft = ""
                        settings = false; tourComplete = false; tour = true; connectionScreen = false
                        server.selectTransport(.usb); server.newPairingCode()
                    }
                    release(); publishLayout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(dataAction == "erase" ? "Deletes layouts, local backups, preferences, and pairing settings on this iPhone. System permissions, the Home Screen icon, and exported files remain unchanged. This cannot be undone." : "Deletes personal layout data and local recovery history. Built-in presets and exported files remain. This cannot be undone.")
            }
            .alert("Profiles", isPresented: Binding(get: { transferMessage != nil }, set: { if !$0 { transferMessage = nil } })) {
                Button("OK") { transferMessage = nil }
            } message: { Text(transferMessage ?? "") }
    }
    private func exportProfile() {
        do {
            document = ProfileDocument(data: try layout.document.validatedData())
            exportName = layout.name; exporting = true
        } catch { transferMessage = error.localizedDescription }
    }
    private func startEditing() {
        if layout.isPreset { layouts.copy(name: layout.name + " Custom") }
        settings = false; editing = true; selectedID = nil; release()
    }
    private func beginName(_ action: String, value: String) {
        nameAction = action; nameDraft = value; newInputType = layout.effectiveInputType; settings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { naming = true }
    }
    private func saveName() {
        let name = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { return }
        switch nameAction {
        case "copy":
            do { layouts.create(try layout.document.converted(to: newInputType, name: name), provenance: layout.provenance) }
            catch { transferMessage = error.localizedDescription }
        case "new": layouts.create(.starter(name: name, style: newStyle, input: newInputType))
        case "rename": layouts.change { $0.name = name }
        default:
            if let runtimeID = selectedID, let id = layout.controlID(runtimeID: runtimeID) {
                layouts.change { try $0.renameControl(id, caption: name, modeID: modeID) }
                selectedLabel = name
            }
        }
        release()
    }
    private func toggleMode() { guard layout.hasCursorSwitching else { return }; layouts.selectMode(layout.document.nextMode(after: modeID)); selectedID = nil; release() }
    private func release() {
        layouts.endEdit()
        server.setPointerMode(mode.cursor ? .cursor : .aim)
        server.update(settings || editing || naming || tour || connectionScreen ? .paused : .neutral)
        resetID = UUID()
    }
    private func publishLayout(canvas: CGSize? = nil) {
        var snapshot = DocumentLayoutSnapshot(layout: layout, activeModeID: modeID)
        let size = canvas ?? canvasSize
        var hardware = utsname(); uname(&hardware)
        let model = withUnsafeBytes(of: &hardware.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        // Mirror the actual controller canvas, including display/pose changes.
        // A global screen can describe a different display or compatibility size.
        if size.width > 0 && size.height > 0 {
            snapshot.screen = PhoneScreen(model: model, width: size.width, height: size.height)
        }
        snapshot.catalog = layouts.catalog.layouts.map(DocumentLayoutSummary.init)
        snapshot.acknowledgment = lastAcknowledgment
        server.updateLayout(snapshot)
    }
    private func receiveLayoutCommand(_ command: DocumentLayoutCommand) {
        if command.action == .fetch {
            lastAcknowledgment = layouts.apply(command); publishLayout(); return
        }
        guard !editing && !naming else {
            lastAcknowledgment = DocumentLayoutAcknowledgment(commandID: command.id, error: "Finish editing on the phone before applying Mac changes.")
            publishLayout(); return
        }
        server.update(.paused)
        lastAcknowledgment = layouts.apply(command)
        release(); publishLayout()
    }
    private func activate() { server.onLayoutCommand = receiveLayoutCommand; publishLayout(); UIApplication.shared.isIdleTimerDisabled = true; release(); server.start() }
}

struct ControllerSurface: UIViewRepresentable {
    let document: LayoutDocument
    let activeModeID: String
    let referenceModeID: String

    let style: PadStyle
    let mode: ResolvedLayoutMode
    let displayLabels: [String: String]
    let touchHaptic: ButtonHaptic
    let showsGuideButton: Bool
    let guideLabel: String
    let showsModeSwitch: Bool
    let placements: [String: ControlPlacement]
    let unmapped: Set<String>
    let referenceMode: ResolvedLayoutMode
    let showGhost: Bool
    let onReference: (ControlPlacement?) -> Void
    let onCanvasSize: (CGSize) -> Void
    let onEditEnded: () -> Void
    let editing: Bool
    let inputEnabled: Bool
    let selectedID: String?
    let onState: (GamepadState) -> Void
    let onPointer: (PointerAction, Double, Double) -> Void
    let onToggle: () -> Void
    let onRename: (String, String) -> Void
    let onSelect: (String, String, ControlPlacement) -> Void
    let onPlacement: (String, ControlPlacement) -> Void
    func makeUIView(context: Context) -> TouchPadView { let view = TouchPadView(); configure(view); return view }
    func updateUIView(_ view: TouchPadView, context: Context) { configure(view) }
    private func configure(_ view: TouchPadView) {
        view.inputEnabled = inputEnabled; view.document = document; view.activeModeID = activeModeID; view.referenceModeID = referenceModeID
        view.showsModeSwitch = showsModeSwitch
        view.hiddenControls = mode.hiddenControls ?? []
        view.unmapped = unmapped
        view.referencePlacements = referenceMode.controls.controls(for: style)
        view.referenceSizeFactor = referenceMode.sizeFactor
        view.referenceAvailable = showsModeSwitch
        view.showGhost = showsModeSwitch && showGhost
        view.onReference = onReference
        view.onCanvasSize = onCanvasSize
        view.buttonFeedback = mode.buttonFeedback ?? [:]
        view.dpadStyle = mode.effectiveDPadStyle
        view.style = style; view.showDPad = mode.showDPad; view.onState = onState
        view.cursorMode = mode.cursor; view.trackpadHoldDelay = mode.trackpadHoldDelay; view.onPointer = onPointer
        view.holdAimEnabled = mode.holdAimEnabled && !mode.cursor && (document.motion?.mode ?? "off") == "off"; view.holdAimDelay = mode.holdAimDelay
        view.floatingLeft = mode.floatingLeft; view.floatingRight = mode.floatingRight
        view.touchHaptic = touchHaptic
        view.showsGuideButton = showsGuideButton
        view.guideLabel = guideLabel
        view.leftTap = mode.leftTap; view.rightTap = mode.rightTap
        view.modeName = mode.name; view.onToggle = onToggle; view.onRename = onRename
        view.radialEnabled = mode.radialEnabled ?? false
        view.radialSlots = mode.radialSlots ?? Array(repeating: -1, count: 8); view.radialTitle = mode.radialTitle ?? "Quick bar"
        view.sizeFactor = mode.sizeFactor
        view.customSlots = mode.controls.customButtons(for: style); view.labels = displayLabels
        view.placements = placements; view.editing = editing; view.selectedID = selectedID
        view.onSelect = onSelect; view.onPlacement = onPlacement; view.onEditEnded = onEditEnded
        view.setNeedsLayout(); view.setNeedsDisplay()
    }
}

struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct PhoneNameEditor: View {
    @ObservedObject var server: CableServer
    @State private var name = WirelessSettings.deviceName()
    var body: some View {
        TextField("Phone name", text: $name)
            .onSubmit { server.renameDevice(name) }
            .onDisappear { if name != WirelessSettings.deviceName() { server.renameDevice(name) } }
    }
}

private struct LayoutNameSheet: View {
    @Binding var name: String
    let action: String
    @Binding var type: LayoutInputType
    @Binding var style: PadStyle
    let currentType: LayoutInputType
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch action {
        case "new": return "New layout"
        case "copy": return "Duplicate layout"
        case "control": return "Rename control"
        default: return "Rename layout"
        }
    }
    private var saveTitle: String {
        action == "new" ? "Create" : action == "copy" ? "Duplicate" : "Save"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(action == "control" ? "Control name" : "Layout name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { save() } }
                }
                if action == "new" || action == "copy" {
                    Section {
                        Picker("Input type", selection: $type) {
                            ForEach(LayoutInputType.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Input type")
                    } footer: {
                        if action == "copy", type != currentType {
                            Text("Controls that cannot be converted will need to be remapped before use.")
                        }
                    }
                }
                if action == "new" {
                    Section("Starting layout") {
                        Picker("Starting layout", selection: $style) {
                            ForEach(PadStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Stored in safe-area-relative coordinates so the handle remains reachable after resizing.
private struct MovableSettingsButton: View {
    let connected: Bool
    let openSettings: () -> Void
    let editLayout: () -> Void
    @AppStorage("settings-button-position-x") private var savedX = 0.5
    @AppStorage("settings-button-position-y") private var savedY = 0.0
    @State private var dragTranslation = CGSize.zero
    @AppStorage("settings-button-size") private var buttonSize = 48.0
    @AppStorage("settings-button-fade-delay") private var fadeDelay = 3.0
    @AppStorage("settings-button-inactive-opacity") private var inactiveOpacity = 0.35
    @State private var active = true
    @State private var activity = UUID()
    private func wake() { active = true; activity = UUID() }

    var body: some View {
        GeometryReader { geometry in
            let insetX = min(buttonSize / 2 + 8, geometry.size.width / 2)
            let insetY = min(buttonSize / 2 + 4, geometry.size.height / 2)
            let travelX = max(0, geometry.size.width - insetX * 2)
            let travelY = max(0, geometry.size.height - insetY * 2)
            let resting = CGPoint(x: insetX + min(1, max(0, savedX)) * travelX,
                                  y: insetY + min(1, max(0, savedY)) * travelY)
            let center = CGPoint(
                x: min(insetX + travelX, max(insetX, resting.x + dragTranslation.width)),
                y: min(insetY + travelY, max(insetY, resting.y + dragTranslation.height)))
            ZStack {
                // Fade only the artwork. Keep the UIKit touch surface fully opaque
                // so SwiftUI never excludes the faded handle from hit testing.
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(connected ? PadAppearance.accent : Color.secondary)
                    .frame(width: buttonSize, height: max(44, buttonSize * 0.92))
                    .background(.ultraThinMaterial, in: Capsule())
                    .opacity(active || fadeDelay == 0 ? 1 : inactiveOpacity)
                    .animation(.easeInOut(duration: 0.25), value: active)
                    .allowsHitTesting(false)
                SettingsHandleGestures(onTap: { wake(); openSettings() }, onHold: { wake(); editLayout() },
                    onDrag: { wake(); dragTranslation = $0 }, onEnd: { translation in
                        if let translation {
                            if travelX > 0 { savedX = min(1, max(0, (resting.x + translation.width - insetX) / travelX)) }
                            if travelY > 0 { savedY = min(1, max(0, (resting.y + translation.height - insetY) / travelY)) }
                        }
                        dragTranslation = .zero; wake()
                    })
                    .frame(width: buttonSize, height: max(44, buttonSize * 0.92))
                    .allowsHitTesting(true)
            }
            .frame(width: buttonSize, height: max(44, buttonSize * 0.92))
                .position(center)
                .accessibilityLabel("Settings")
                .accessibilityHint("Tap to open settings, drag to reposition, or hold to edit the layout.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { openSettings() }
                .accessibilityAction(named: "Edit layout") { editLayout() }
                .accessibilityAction(named: "Reset settings button position") { savedX = 0.5; savedY = 0 }
        }.coordinateSpace(name: "settings-button-canvas")
            .task(id: activity) {
                guard fadeDelay > 0 else { return }
                try? await Task.sleep(for: .seconds(fadeDelay))
                if !Task.isCancelled { active = false }
            }
            .onChange(of: fadeDelay) { _, _ in wake() }
            .onChange(of: connected) { _, _ in wake() }
    }
}
