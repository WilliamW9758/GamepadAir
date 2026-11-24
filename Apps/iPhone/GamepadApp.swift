import SwiftUI
import UniformTypeIdentifiers

final class LayoutStore: ObservableObject {
    @Published var catalog: LayoutCatalog
    @Published var storageError: String?
    private let key = "named-control-layouts-v2"
    @Published private(set) var history = LayoutHistory()
    private var editStart: LayoutCatalog?
    func beginEdit() { if editStart == nil { editStart = catalog } }
    func endEdit() {
        if let before = editStart, before != catalog { history.record(before) }
        editStart = nil
    }
    func undo() { endEdit(); if let previous = history.undo(catalog) { catalog = previous; save() } }
    func redo() { endEdit(); if let next = history.redo(catalog) { catalog = next; save() } }
    func checkpoint() { if editStart == nil { history.record(catalog) } }
    func importData(_ data: Data) throws {
        guard storageError == nil, data.count <= 4_000_000 else { throw ProtocolError.invalidState }
        let incoming: [SavedLayout]
        if let profile = try? PortableProfile.decode(data) {
            var layout = profile.layout; layout.keyboardProfile = profile.keyboard ?? layout.keyboardProfile
            incoming = [layout]
        } else {
            incoming = try LayoutCatalog.decode(data).layouts.filter { !$0.isPreset }.map { layout in
                try PortableProfile.decode(JSONEncoder().encode(PortableProfile(layout: layout))).layout
            }
        }
        checkpoint()
        for var layout in incoming {
            layout.id = UUID().uuidString; layout.isPreset = false; layout.name += " · imported"
            for i in layout.modes.indices { layout.modes[i].id = UUID().uuidString }
            catalog.layouts.append(layout); catalog.selectedID = layout.id
        }
        save()
    }
    init() {
        let defaults = UserDefaults.standard
        let legacyData = defaults.data(forKey: "control-layouts-v1")
        // Never overwrite the old key, including on subsequent launches.
        if defaults.data(forKey: "control-layouts-v1-backup") == nil, let legacyData {
            defaults.set(legacyData, forKey: "control-layouts-v1-backup")
        }
        let imported = LayoutCatalog(legacy: LayoutLibrary.restore(legacyData),
            style: PadStyle(rawValue: defaults.string(forKey: "padStyle") ?? "") ?? .xbox,
            showDPad: defaults.object(forKey: "showDPad") as? Bool ?? true,
            holdAimEnabled: defaults.object(forKey: "holdAimEnabled") as? Bool ?? true,
            holdAimDelay: defaults.object(forKey: "holdAimDelay") as? Double ?? 0.3,
            trackpadHoldDelay: defaults.object(forKey: "trackpadHoldDelay") as? Double ?? 0.5)
        if let data = defaults.data(forKey: key) {
            if defaults.data(forKey: "named-control-layouts-before-modern-editor") == nil {
                defaults.set(data, forKey: "named-control-layouts-before-modern-editor")
            }
            do { catalog = try LayoutCatalog.decode(data) }
            catch {
                catalog = imported
                storageError = "Saved layouts could not be read. They have not been overwritten. Close the app and contact support to recover them."
            }
        } else { catalog = imported }
        save()
    }
    var selected: SavedLayout { catalog.layouts.first { $0.id == catalog.selectedID }! }
    func save() {
        guard storageError == nil, let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
    func change(_ update: (inout SavedLayout) -> Void) {
        guard storageError == nil, let index = catalog.layouts.firstIndex(where: { $0.id == catalog.selectedID }), !catalog.layouts[index].isPreset else { return }
        let before = catalog
        update(&catalog.layouts[index])
        if catalog != before, editStart == nil { history.record(before) }
        save()
    }
    func apply(_ command: LayoutCommand) throws {
        guard storageError == nil else { throw ProtocolError.invalidState }
        switch command.action {
        case .bindLegacy:
            guard let layout = command.layout, let type = layout.inputType,
                  command.base == catalog.layouts.first(where: { $0.id == catalog.selectedID }) else { throw ProtocolError.invalidState }
            checkpoint()
            for index in catalog.layouts.indices where catalog.layouts[index].inputType == nil {
                catalog.layouts[index].inputType = type
                catalog.layouts[index].keyboardProfile = catalog.layouts[index].keyboardProfile ?? layout.keyboardProfile
                catalog.layouts[index].gamepadProfile = catalog.layouts[index].gamepadProfile ?? layout.gamepadProfile
            }
            save()
        case .select:
            guard let id = command.layoutID, catalog.layouts.contains(where: { $0.id == id }) else { throw ProtocolError.invalidState }
            select(id)
        case .create:
            guard var layout = command.layout else { throw ProtocolError.invalidState }
            _ = try PortableProfile.decode(JSONEncoder().encode(PortableProfile(layout: layout)))
            checkpoint(); layout.id = UUID().uuidString; layout.isPreset = false
            catalog.layouts.append(layout); catalog.selectedID = layout.id; save()
        case .save:
            guard let layout = command.layout, let base = command.base,
                  let index = catalog.layouts.firstIndex(where: { $0.id == layout.id }),
                  catalog.layouts[index] == base, !base.isPreset else { throw ProtocolError.invalidState }
            _ = try PortableProfile.decode(JSONEncoder().encode(PortableProfile(layout: layout)))
            checkpoint()
            if let data = try? JSONEncoder().encode(catalog) { UserDefaults.standard.set(data, forKey: "layouts-before-mac-save") }
            var updated = layout; updated.isPreset = false
            catalog.layouts[index] = updated; save()
        }
    }
    func select(_ id: String) { endEdit(); catalog.selectedID = id; save() }
    func copy(name: String) { guard storageError == nil else { return }; checkpoint(); catalog.duplicate(catalog.selectedID, name: name); save() }
    func create(name: String, style: PadStyle) {
        guard storageError == nil else { return }
        checkpoint()
        let layout = SavedLayout(name: name, style: style)
        catalog.layouts.append(layout); catalog.selectedID = layout.id; save()
    }
}

@main
struct PhoneGamepadApp: App {
    @StateObject private var server = CableServer()
    @StateObject private var layouts = LayoutStore()
    @Environment(\.scenePhase) private var phase
    @AppStorage("touch-floating-left") private var touchFloatingLeft = true
    @AppStorage("touch-floating-right") private var touchFloatingRight = true
    @State private var resetID = UUID()
    @State private var canvasSize = CGSize.zero
    @State private var modeIndex = 0
    @State private var editing = false
    @AppStorage("phone-onboarding-v1") private var tourComplete = false
    @State private var tour = false
    @State private var settings = false
    @State private var connectionScreen = false
    @State private var lastLayoutCommand: String?
    @State private var layoutCommandError: String?
    @State private var buttonOptions = false
    @State private var showGhost = true
    @State private var exporting = false
    @State private var importing = false
    @State private var document = ProfileDocument()
    @State private var transferMessage: String?
    @State private var exportName = "Pocket Pad"
    @State private var selectedReference: ControlPlacement?
    @State private var selectedID: String?
    @State private var selectedLabel = ""
    @State private var nameDraft = ""
    @State private var naming = false
    @State private var nameAction = "copy"
    @State private var newStyle = PadStyle.xbox
    @State private var newInputType = LayoutInputType.keyboardMouse
    @State private var confirmReset = false
    private var layout: SavedLayout { layouts.selected }
    private var mode: LayoutMode { layout.modes[modeIndex] }
    private var padStyle: PadStyle { layout.style }
    private var placements: [String: ControlPlacement] { mode.controls.controls(for: padStyle) }
    private func changeMode(_ update: (inout LayoutMode) -> Void) {
        layouts.change { update(&$0.modes[modeIndex]) }
    }
    private func binding<T>(_ key: WritableKeyPath<LayoutMode, T>) -> Binding<T> {
        Binding(get: { mode[keyPath: key] }, set: { value in changeMode { $0[keyPath: key] = value }; release() })
    }
    private var selectedScale: Binding<Double> {
        Binding(get: { selectedID.flatMap { placements[$0]?.scale } ?? 1 }, set: { value in
            guard let id = selectedID, var p = placements[id] else { return }
            p.scale = value; layouts.change { $0.place(p, control: id, mode: modeIndex) }
        })
    }
    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                ControllerSurface(style: padStyle, mode: mode, displayLabels: layout.displayLabels(modeIndex: modeIndex), touchHaptic: layout.effectiveTouchHaptic, showsGuideButton: layout.effectiveInputType == .gamepad, guideLabel: layout.effectiveControllerStyle.label(.guide), showsModeSwitch: layout.hasCursorSwitching, placements: placements, unmapped: Set(layout.unmappedControls.map(\.canvasID)),
                    referenceMode: layout.modes[1 - modeIndex], showGhost: showGhost,
                    onReference: { selectedReference = $0 }, onCanvasSize: { size in
                        guard canvasSize != size else { return }
                        canvasSize = size
                        publishLayout(canvas: size)
                    }, onEditEnded: { layouts.endEdit() },
                    editing: editing, selectedID: selectedID, onState: { server.update(settings || editing || naming || tour || connectionScreen ? .paused : $0) }, onPointer: server.pointer,
                    onToggle: toggleMode,
                    onRename: { id, label in selectedID = id; selectedLabel = label; nameDraft = label; nameAction = "control"; naming = true },
                    onSelect: { id, label, p in
                        layouts.beginEdit(); selectedID = id; selectedLabel = label
                        changeMode { $0.controls.set(p, control: id, style: padStyle) }
                    }, onPlacement: { id, p in layouts.change { $0.place(p, control: id, mode: modeIndex) } },
                    onMigration: { modeID, converted, factor in
                        changeMode { m in
                            guard m.id == modeID, m.legacyCanvas else { return }
                            for (id, p) in converted { m.controls.set(p, control: id, style: padStyle) }
                            m.sizeFactor = factor; m.legacyCanvas = false
                        }
                    })
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
                            Text(selectedID == nil ? "Drag controls" : selectedLabel).font(.callout).lineLimit(1).frame(width: 90)
                            Slider(value: selectedScale, in: 0.65...1.8, step: 0.05, onEditingChanged: { active in if active { layouts.beginEdit() } else { layouts.endEdit() } }).frame(width: 110).disabled(selectedID == nil)
                            Button { buttonOptions = true } label: {
                                Label("Button options", systemImage: "slider.horizontal.3")
                                    .frame(minWidth: 110, minHeight: 44)
                            }.disabled(selectedID == nil)
                        }.padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 4)
                    }.allowsHitTesting(true)
                    HStack(spacing: 12) {
                        Button { layouts.undo(); selectedID = nil; release() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(!layouts.history.canUndo)
                        Button { layouts.redo(); selectedID = nil; release() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(!layouts.history.canRedo)
                        if layout.hasCursorSwitching { Picker("Mode", selection: Binding(get: { modeIndex }, set: { modeIndex = $0; selectedID = nil; release() })) {
                            ForEach(0..<2, id: \.self) { Text(layout.modes[$0].name).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 180) }
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
                LayoutNameSheet(name: $nameDraft, action: $nameAction, type: $newInputType, currentType: layout.effectiveInputType) {
                    saveName(); naming = false
                }
            }
            .confirmationDialog("Reset only this mode's arrangement?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset mode arrangement", role: .destructive) {
                    layouts.change { l in l.linkedControls = nil; l.modes[modeIndex].controls.reset(style: padStyle); l.modes[modeIndex].sizeFactor = 1; l.modes[modeIndex].legacyCanvas = false }
                    selectedID = nil; release()
                }
            }
            .onChange(of: layouts.catalog) { _, _ in publishLayout() }
            .onChange(of: modeIndex) { _, _ in publishLayout() }
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
    private func feedbackBinding<T>(_ key: WritableKeyPath<ButtonFeedback, T>) -> Binding<T> {
        Binding(get: { (mode.buttonFeedback?[selectedID ?? ""] ?? ButtonFeedback(haptic: .light))[keyPath: key] }, set: { value in
            guard let id = selectedID else { return }
            changeMode { m in
                var prefs = m.buttonFeedback?[id] ?? ButtonFeedback(haptic: .light)
                prefs[keyPath: key] = value
                if m.buttonFeedback == nil { m.buttonFeedback = [:] }
                m.buttonFeedback?[id] = prefs
            }
        })
    }
    private var buttonOptionsView: some View {
        NavigationStack {
            Form {
                if layout.hasCursorSwitching { Section("Position across modes") {
                    Toggle("Link position and size", isOn: Binding(get: { selectedID.map { layout.linkedControls?.contains($0) == true } ?? false }, set: { linked in
                        guard let id = selectedID, let p = placements[id] else { return }
                        layouts.change { l in
                            if l.linkedControls == nil { l.linkedControls = [] }
                            if linked { l.linkedControls?.insert(id); l.place(p, control: id, mode: modeIndex) }
                            else { l.linkedControls?.remove(id) }
                        }
                    })).disabled(mode.legacyCanvas || layout.modes[1 - modeIndex].legacyCanvas)
                    Button("Copy position from \(layout.modes[1 - modeIndex].name)") {
                        guard let id = selectedID, let p = selectedReference else { return }
                        layouts.change { $0.place(p, control: id, mode: modeIndex) }
                    }.disabled(selectedReference == nil || layout.modes[1 - modeIndex].legacyCanvas)
                    Toggle("Show other mode outline", isOn: $showGhost)
                    Text("Keep this button’s position and size matched across modes.").font(.callout).foregroundStyle(.secondary)
                } }
                Section("Appearance") {
                    Picker("Button color", selection: feedbackBinding(\.tint)) {
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
                        layouts.change { l in l.linkedControls?.remove(id); l.modes[modeIndex].controls.presets[padStyle.rawValue]?[id] = nil }
                        buttonOptions = false; selectedID = nil; release()
                    }
                    if let id = selectedID, id.hasPrefix("custom-"), let slot = Int(id.dropFirst(7)) {
                        Button("Remove button", role: .destructive) {
                            layouts.change { l in l.linkedControls?.remove(id); l.modes[modeIndex].controls.removeCustom(slot, style: padStyle); l.modes[modeIndex].buttonFeedback?[id] = nil }
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
                                if layout.hasCursorSwitching { Text(mode.name).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Label(server.connected ? "Connected" : "Offline", systemImage: server.connected ? "checkmark.circle.fill" : "circle")
                                .font(.callout).foregroundStyle(server.connected ? PadAppearance.accent : .secondary)
                        }
                        Button { startEditing() } label: { Label("Edit layout", systemImage: "slider.horizontal.3") }
                            .buttonStyle(PadActionStyle(prominent: true))
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
                if layout.effectiveInputType == .gamepad {
                    Section("Controller emulation") {
                        Picker("Emulate controller", selection: Binding(get: { layout.effectiveControllerStyle }, set: { value in
                            if layout.isPreset { layouts.copy(name: layout.name + " Custom") }
                            release()
                            layouts.change { $0.emulatedController = value }
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
                        layouts.change { $0.touchHaptic = value }
                        TouchPadView.playHaptic(value)
                    })) {
                        ForEach(ButtonHaptic.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Text("Applies to all buttons and L3/R3 in this layout. Stick movement stays silent. Game rumble is separate.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Stick positioning") {
                    Picker("Left stick", selection: $touchFloatingLeft) {
                        Text("Center on touch").tag(true)
                        Text("Fixed position").tag(false)
                    }
                    Picker("Right stick", selection: $touchFloatingRight) {
                        Text("Center on touch").tag(true)
                        Text("Fixed position").tag(false)
                    }
                    Text("Applies to all layouts on this iPhone. Center on touch places the stick's neutral point where your finger first lands.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Saved layouts") {
                    Picker("Layout", selection: Binding(get: { layouts.catalog.selectedID }, set: {
                        layouts.select($0); modeIndex = 0; selectedID = nil; editing = false; release()
                    })) {
                        ForEach(layouts.catalog.layouts) { Text($0.name + ($0.isPreset ? " · preset" : "")).tag($0.id) }
                    }
                    Button("Save a copy…") { beginName("copy", value: layout.name + " Copy") }
                    Picker("New layout base", selection: $newStyle) { ForEach(PadStyle.allCases, id: \.self) { Text($0.rawValue) } }
                    Button("New layout…") { beginName("new", value: "New Controls") }
                    if !layout.isPreset { Button("Rename layout…") { beginName("rename", value: layout.name) } }
                    if layout.isPreset { Text("Presets stay unchanged. Save a copy to customize.").font(.callout) }
                }
                DisclosureGroup("Right-stick cursor switching") {
                    Toggle("Allow switching between aim and cursor", isOn: Binding(get: { layout.hasCursorSwitching }, set: { enabled in
                        layouts.change { $0.setCursorSwitching(enabled) }; modeIndex = 0; release()
                    }))
                    if layout.hasCursorSwitching { Picker("Edit mode", selection: Binding(get: { modeIndex }, set: { modeIndex = $0; selectedID = nil; release() })) {
                        ForEach(0..<2, id: \.self) { Text(layout.modes[$0].name).tag($0) }
                    }
                    }
                    if layout.hasCursorSwitching { TextField("Mode name", text: binding(\.name)) }
                    Picker("Right control behavior", selection: binding(\.cursor)) {
                        Text("Camera aim · analog stick").tag(false)
                        Text("Menu pointer · trackpad").tag(true)
                    }
                }.disabled(layout.isPreset)
                DisclosureGroup("Add and manage controls") {
                    Toggle("D-pad", isOn: binding(\.showDPad))
                    Button("Add custom button") {
                        changeMode { m in
                            if let slot = m.controls.addCustom(style: padStyle) {
                                m.controls.set(ControlPlacement(x: 0.5, y: 0.5), control: "custom-\(slot)", style: padStyle)
                            }
                        }; settings = false; editing = true; release()
                    }.disabled(mode.controls.customButtons(for: padStyle).count >= 16)
                    Button("Add quick bar 1–8") { changeMode { $0.controls.addQuickBar(style: padStyle) }; release() }
                    Button("Reset mode arrangement…", role: .destructive) { settings = false; confirmReset = true }
                }.disabled(layout.isPreset)
                DisclosureGroup("Radial quick bar") {
                    Toggle("Show radial button", isOn: Binding(get: { mode.radialEnabled ?? false }, set: { value in
                        changeMode { $0.radialEnabled = value }; release()
                    }))
                    Text("Hold, swipe, and release to select. Return to the center to cancel.").font(.callout)
                    if mode.radialEnabled == true {
                        Button("Hide separate buttons used by the radial") {
                            changeMode { m in
                                var slots = m.controls.customSlots ?? [:]
                                let radial = m.radialSlots ?? Array(0..<8)
                                slots[padStyle.rawValue] = (slots[padStyle.rawValue] ?? []).filter { !radial.contains($0) }
                                m.controls.customSlots = slots
                            }; release()
                        }
                        ForEach(0..<8, id: \.self) { i in
                            Picker(["↑ Up", "↗ Upper right", "→ Right", "↘ Lower right", "↓ Down", "↙ Lower left", "← Left", "↖ Upper left"][i], selection: Binding(get: { (mode.radialSlots ?? Array(0..<8))[i] }, set: { slot in
                                changeMode { m in var slots = m.radialSlots ?? Array(0..<8); slots[i] = slot; m.radialSlots = slots }; release()
                            })) {
                                Text("None").tag(-1)
                                ForEach(0..<16, id: \.self) { slot in Text("Custom \(slot + 1)").tag(slot) }
                            }
                        }
                    }
                }.disabled(layout.isPreset)
                DisclosureGroup("Stick behavior") {
                    Picker("Left stick tap", selection: binding(\.leftTap)) {
                        ForEach(StickTapAction.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Right stick tap", selection: binding(\.rightTap)) {
                        ForEach(StickTapAction.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text("Tap actions use your Mac mappings.").font(.callout)
                }.disabled(layout.isPreset)
                DisclosureGroup("Hold gestures") {
                    Toggle("RT hold-to-aim", isOn: binding(\.holdAimEnabled))
                    Picker("Aim hold delay", selection: binding(\.holdAimDelay)) {
                        ForEach([0.2, 0.3, 0.5, 0.8], id: \.self) { Text("\($0, specifier: "%.1f") seconds").tag($0) }
                    }
                    Picker("Trackpad right-click hold", selection: binding(\.trackpadHoldDelay)) {
                        ForEach([0.3, 0.5, 0.7], id: \.self) { Text("\($0, specifier: "%.1f") seconds").tag($0) }
                    }
                }.disabled(layout.isPreset)
                DisclosureGroup("About Pocket Pad") {
                    Button("Replay getting started") { settings = false; tour = true; release() }
                    Link("Mac companion and setup", destination: AppInformation.projectURL)
                    Link("Support", destination: AppInformation.supportURL)
                    NavigationLink("Privacy policy") {
                        ScrollView { Text(AppInformation.privacy).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled) }
                            .navigationTitle("Privacy")
                    }
                }
                Section("Profiles & backups") {
                    Button("Export this profile") { exportProfile() }
                    Button("Back up all layouts") {
                        do { document = ProfileDocument(data: try JSONEncoder().encode(layouts.catalog)); exportName = "Pocket Pad layouts"; exporting = true }
                        catch { transferMessage = error.localizedDescription }
                    }
                    Button("Import profile or backup") { importing = true }
                    Text("Import always creates copies. To bundle Mac mappings: export a profile, open it on the Mac, then export it there with your mappings. Import that file here to keep a complete backup.").font(.callout).foregroundStyle(.secondary)
                }
                AppIconSettingsSection()
            }.scrollContentBackground(.hidden).background { PadBackdrop() }.navigationTitle("Pocket Pad").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { settings = false } }
        }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: exportName) { result in
                if case .failure(let error) = result { transferMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try layouts.importData(Data(contentsOf: url)); modeIndex = 0; selectedID = nil; release()
                    transferMessage = "Imported as a new layout. Your existing layouts are unchanged."
                } catch { transferMessage = "Could not import: \(error.localizedDescription)" }
            }
            .alert("Profiles", isPresented: Binding(get: { transferMessage != nil }, set: { if !$0 { transferMessage = nil } })) {
                Button("OK") { transferMessage = nil }
            } message: { Text(transferMessage ?? "") }
    }
    private func exportProfile() {
        do {
            document = ProfileDocument(data: try JSONEncoder().encode(PortableProfile(layout: layout, keyboard: layout.keyboardProfile)))
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
            var copy = layout.converted(to: newInputType); copy.name = name
            try? layouts.apply(LayoutCommand(action: .create, layout: copy))
        case "new":
            var value = SavedLayout(name: name, style: newStyle); value.inputType = newInputType
            value.cursorSwitching = false; value.keyboardProfile = .starter; value.gamepadProfile = GamepadProfile()
            try? layouts.apply(LayoutCommand(action: .create, layout: value)); modeIndex = 0
        case "rename": layouts.change { $0.name = name }
        default:
            if let id = selectedID {
                changeMode { if id == "mode-toggle" { $0.name = name } else if id == "radial" { $0.radialTitle = name; $0.controls.rename(id, to: name, style: padStyle) } else { $0.controls.rename(id, to: name, style: padStyle) } }
                selectedLabel = name
            }
        }
        release()
    }
    private func toggleMode() { guard layout.hasCursorSwitching else { return }; modeIndex = 1 - modeIndex; selectedID = nil; release() }
    private func release() {
        layouts.endEdit()
        server.setPointerMode(mode.cursor ? .cursor : .aim)
        server.update(settings || editing || naming || tour || connectionScreen ? .paused : .neutral)
        resetID = UUID()
    }
    private func publishLayout(canvas: CGSize? = nil) {
        var snapshot = ControllerSnapshot(layout: layout, modeIndex: modeIndex)
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
        snapshot.layouts = layouts.catalog.layouts.map(LayoutSummary.init)
        snapshot.commandID = lastLayoutCommand; snapshot.commandError = layoutCommandError
        server.updateLayout(snapshot)
    }
    private func receiveLayoutCommand(_ command: LayoutCommand) {
        guard lastLayoutCommand != command.id else { publishLayout(); return }
        lastLayoutCommand = command.id
        do {
            guard !editing && !naming else { throw ProtocolError.invalidState }
            try layouts.apply(command)
            modeIndex = layout.hasCursorSwitching ? min(modeIndex, layout.modes.count - 1) : 0
            layoutCommandError = nil
        } catch {
            layoutCommandError = "Layout changed on iPhone or is being edited. Refresh and try again."
        }
        release(); publishLayout()
    }
    private func activate() { server.onLayoutCommand = receiveLayoutCommand; publishLayout(); UIApplication.shared.isIdleTimerDisabled = true; release(); server.start() }
}

struct ControllerSurface: UIViewRepresentable {
    @AppStorage("touch-floating-left") private var touchFloatingLeft = true
    @AppStorage("touch-floating-right") private var touchFloatingRight = true

    let style: PadStyle
    let mode: LayoutMode
    let displayLabels: [String: String]
    let touchHaptic: ButtonHaptic
    let showsGuideButton: Bool
    let guideLabel: String
    let showsModeSwitch: Bool
    let placements: [String: ControlPlacement]
    let unmapped: Set<String>
    let referenceMode: LayoutMode
    let showGhost: Bool
    let onReference: (ControlPlacement?) -> Void
    let onCanvasSize: (CGSize) -> Void
    let onEditEnded: () -> Void
    let editing: Bool
    let selectedID: String?
    let onState: (GamepadState) -> Void
    let onPointer: (PointerAction, Double, Double) -> Void
    let onToggle: () -> Void
    let onRename: (String, String) -> Void
    let onSelect: (String, String, ControlPlacement) -> Void
    let onPlacement: (String, ControlPlacement) -> Void
    let onMigration: (String, [String: ControlPlacement], Double) -> Void
    func makeUIView(context: Context) -> TouchPadView { let view = TouchPadView(); configure(view); return view }
    func updateUIView(_ view: TouchPadView, context: Context) { configure(view) }
    private func configure(_ view: TouchPadView) {
        view.showsModeSwitch = showsModeSwitch
        view.hiddenControls = mode.hiddenControls ?? []
        view.unmapped = unmapped
        view.referencePlacements = referenceMode.controls.controls(for: style)
        view.referenceSizeFactor = referenceMode.sizeFactor
        view.referenceAvailable = showsModeSwitch && !referenceMode.legacyCanvas
        view.showGhost = showsModeSwitch && showGhost
        view.onReference = onReference
        view.onCanvasSize = onCanvasSize
        view.buttonFeedback = mode.buttonFeedback ?? [:]
        view.style = style; view.showDPad = mode.showDPad; view.onState = onState
        view.cursorMode = mode.cursor; view.trackpadHoldDelay = mode.trackpadHoldDelay; view.onPointer = onPointer
        view.holdAimEnabled = mode.holdAimEnabled && !mode.cursor; view.holdAimDelay = mode.holdAimDelay
        view.floatingLeft = touchFloatingLeft; view.floatingRight = touchFloatingRight
        view.touchHaptic = touchHaptic
        view.showsGuideButton = showsGuideButton
        view.guideLabel = guideLabel
        view.leftTap = mode.leftTap; view.rightTap = mode.rightTap
        view.modeName = mode.name; view.onToggle = onToggle; view.onRename = onRename
        view.radialEnabled = mode.radialEnabled ?? false
        view.radialSlots = mode.radialSlots ?? Array(0..<8); view.radialTitle = mode.radialTitle ?? "Quick bar"
        view.legacyCanvas = mode.legacyCanvas; view.sizeFactor = mode.sizeFactor; view.onMigration = { onMigration(mode.id, $0, $1) }
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
    @Binding var action: String
    @Binding var type: LayoutInputType
    let currentType: LayoutInputType
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Text(action == "control" ? "Rename control" : "Layout name").font(.title2)
            TextField("Name", text: $name)
            if action == "copy" || action == "new" {
                Picker("Input type", selection: $type) {
                    ForEach(LayoutInputType.allCases) { Text($0.title).tag($0) }
                }
                if action == "copy", type != currentType {
                    Text("Unmapped controls stay disabled. Remap them on your Mac.").foregroundStyle(.secondary)
                }
            }
            Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { dismiss() }
        }.padding(24)
    }
}

/// Stored in safe-area-relative coordinates so the handle remains reachable after resizing.
private struct MovableSettingsButton: View {
    let connected: Bool
    let openSettings: () -> Void
    let editLayout: () -> Void
    @AppStorage("settings-button-position-x") private var savedX = 0.5
    @AppStorage("settings-button-position-y") private var savedY = 0.0
    @GestureState private var dragTranslation = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let insetX = min(32.0, geometry.size.width / 2)
            let insetY = min(26.0, geometry.size.height / 2)
            let travelX = max(0, geometry.size.width - insetX * 2)
            let travelY = max(0, geometry.size.height - insetY * 2)
            let resting = CGPoint(x: insetX + min(1, max(0, savedX)) * travelX,
                                  y: insetY + min(1, max(0, savedY)) * travelY)
            let center = CGPoint(
                x: min(insetX + travelX, max(insetX, resting.x + dragTranslation.width)),
                y: min(insetY + travelY, max(insetY, resting.y + dragTranslation.height)))
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(connected ? PadAppearance.accent : Color.secondary)
                .frame(width: 48, height: 44)
                .background(.ultraThinMaterial, in: Capsule())
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("settings-button-canvas"))
                    .updating($dragTranslation) { drag, translation, _ in translation = drag.translation }
                    .exclusively(before: LongPressGesture(minimumDuration: 0.5, maximumDistance: 8)
                        .exclusively(before: TapGesture()))
                    .onEnded { value in
                        switch value {
                        case .first(let drag):
                            let start = resting
                            if travelX > 0 { savedX = min(1, max(0, (start.x + drag.translation.width - insetX) / travelX)) }
                            if travelY > 0 { savedY = min(1, max(0, (start.y + drag.translation.height - insetY) / travelY)) }
                        case .second(.first): editLayout()
                        case .second(.second): openSettings()
                        }
                    })
                .position(center)
                .accessibilityLabel("Settings")
                .accessibilityHint("Tap to open settings, drag to reposition, or hold to edit the layout.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { openSettings() }
                .accessibilityAction(named: "Edit layout") { editLayout() }
                .accessibilityAction(named: "Reset settings button position") { savedX = 0.5; savedY = 0 }
        }.coordinateSpace(name: "settings-button-canvas")
    }
}
