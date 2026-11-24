import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class HostModel: ObservableObject {
    @Published var mode = OutputMode(rawValue: UserDefaults.standard.string(forKey: "last-output-mode") ?? "")
        .flatMap { $0 == .monitor ? nil : $0 } ?? .keyboardMouse
    @Published var gamepadProfile = GamepadProfile.restore(UserDefaults.standard.data(forKey: "gamepad-profile-v1")) {
        didSet { if let data = try? JSONEncoder().encode(gamepadProfile) { UserDefaults.standard.set(data, forKey: "gamepad-profile-v1") }; session?.updateMappings(keyboard: profile, gamepad: gamepadProfile) }
    }
    @Published var practicePressCount = 0
    @Published var practiceMoved = false
    private var practiceWasPressed = false
    @Published var running = false
    @Published var selectedPhone: String? = UserDefaults.standard.string(forKey: "last-phone-endpoint")
    @Published var transport = LinkTransport(rawValue: UserDefaults.standard.string(forKey: "last-transport") ?? "") ?? .usb
    @Published var wirelessHost = UserDefaults.standard.string(forKey: "wireless-host") ?? ""
    @Published var pairingCode: String = {
        let saved = UserDefaults.standard.string(forKey: "wireless-code") ?? ""
        return WirelessSettings.validCode(saved) ? saved : ""
    }()
    @Published var profile = KeyboardProfile.restore(UserDefaults.standard.data(forKey: "keyboard-profile-v1")) {
        didSet { if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "keyboard-profile-v1") }; session?.updateMappings(keyboard: profile, gamepad: gamepadProfile) }
    }
    @Published var portable: PortableProfile? = {
        guard let data = UserDefaults.standard.data(forKey: "portable-profile-v1") else { return nil }
        return try? PortableProfile.decode(data)
    }()
    @Published var profileNotice: String?
    func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let value = try PortableProfile.decode(Data(contentsOf: url))
            stop()
            if let keyboard = value.keyboard {
                UserDefaults.standard.set(try JSONEncoder().encode(profile), forKey: "keyboard-profile-before-import")
                profile = keyboard
            }
            portable = value
            UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "portable-profile-v1")
            profileNotice = value.keyboard == nil ? "Layout loaded. Export to bundle it with your current mappings." : "Profile loaded. Layout and mappings are ready to export together."
        } catch { profileNotice = "Import failed: \(error.localizedDescription)" }
    }
    func exportProfile() {
        guard var value = portable else { return }
        value.keyboard = profile; value.layout.keyboardProfile = profile
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = value.layout.name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(value).write(to: url, options: .atomic); profileNotice = "Saved layout and current mappings together." }
        catch { profileNotice = "Export failed: \(error.localizedDescription)" }
    }
    @Published var globalInput = UserDefaults.standard.object(forKey: "last-global-input") as? Bool ?? true
    @Published var targetPID: Int32?
    @Published var applications: [NSRunningApplication] = []
    @Published var update = HostUpdate(message: "Ready to connect", connected: false, state: .neutral, frames: 0)
    private var session: CableSession?
    private var outputPaused = false
    func pauseOutput(_ paused: Bool) {
        outputPaused = paused
        session?.setOutputPaused(paused)
    }
    private var setupStage: SetupStage?
    func syncSetup(_ stage: SetupStage) {
        setupStage = stage; session?.setSetupStage(stage)
    }
    @Published var layoutCommandID: String?
    @Published var layoutCommandNotice: String?
    func sendLayout(_ command: LayoutCommand) {
        guard let session, update.connected, layoutCommandID == nil else { return }
        do {
            try session.sendLayoutCommand(command)
            layoutCommandID = command.id; layoutCommandNotice = "Updating iPhone…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self, self.layoutCommandID == command.id else { return }
                self.layoutCommandID = nil; self.layoutCommandNotice = "No confirmation from iPhone. Check the connection before trying again."
            }
        } catch { layoutCommandNotice = error.localizedDescription }
    }
    private var attemptedLayoutMigration = false
    private var lastUIUpdate: TimeInterval = 0
    private var generation = UUID()

    func start() {
        stop()
        let token = UUID(); generation = token
        running = true
        practicePressCount = 0; practiceMoved = false; practiceWasPressed = false
        update = HostUpdate(message: "Connecting…", connected: false, state: .neutral, frames: 0)
        UserDefaults.standard.set(transport.rawValue, forKey: "last-transport")
        UserDefaults.standard.set(selectedPhone, forKey: "last-phone-endpoint")
        if mode != .monitor {
            UserDefaults.standard.set(mode.rawValue, forKey: "last-output-mode")
            UserDefaults.standard.set(globalInput, forKey: "last-global-input")
            UserDefaults.standard.set(applications.first(where: { $0.processIdentifier == targetPID })?.bundleIdentifier, forKey: "last-target-bundle")
        }
        UserDefaults.standard.set(wirelessHost, forKey: "wireless-host")
        UserDefaults.standard.set(pairingCode, forKey: "wireless-code")
        let session = CableSession(mode: mode, transport: transport, wirelessHost: selectedPhone ?? wirelessHost, pairingCode: pairingCode, keyboardProfile: profile, gamepadProfile: gamepadProfile, targetPID: targetPID, globalInput: globalInput) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let statusChanged = self.update.connected != event.connected || self.update.message != event.message || self.update.layout != event.layout
                if let id = self.layoutCommandID, event.layout?.commandID == id {
                    self.layoutCommandID = nil
                    self.layoutCommandNotice = event.layout?.commandError ?? "Updated on iPhone"
                }
                if self.outputPaused && !statusChanged && !event.finished { return }
                if self.mode != .monitor && !statusChanged && !event.finished && now - self.lastUIUpdate < 1.0 / 60 { return }
                self.lastUIUpdate = now
                let pressed = event.state.buttons & PadButton.south.mask != 0
                if pressed && !self.practiceWasPressed { self.practicePressCount += 1 }
                self.practiceWasPressed = pressed
                if abs(Int(event.state.leftX)) > 4000 || abs(Int(event.state.leftY)) > 4000 { self.practiceMoved = true }
                self.update = event
                if let type = event.layout?.layout.inputType, self.mode != .monitor, self.setupStage == .play {
                    let nextMode: OutputMode = type == .gamepad ? .gamepad : .keyboardMouse
                    if self.mode != nextMode { self.mode = nextMode }
                    if statusChanged { UserDefaults.standard.set(nextMode.rawValue, forKey: "last-output-mode") }
                }
                if let snapshot = event.layout, snapshot.layout.inputType == nil, self.layoutCommandID == nil, !self.attemptedLayoutMigration, self.mode != .monitor, self.setupStage == .play {
                    self.attemptedLayoutMigration = true
                    var value = snapshot.layout
                    value.inputType = self.mode == .gamepad ? .gamepad : .keyboardMouse
                    value.keyboardProfile = value.keyboardProfile ?? self.profile
                    value.gamepadProfile = value.gamepadProfile ?? self.gamepadProfile
                    self.sendLayout(LayoutCommand(action: .bindLegacy, layout: value, base: snapshot.layout))
                }
                if event.finished { self.running = false; self.session = nil }
            }
        }
        if let setupStage { session.setSetupStage(setupStage) }
        session.setOutputPaused(outputPaused)
        self.session = session; session.start()
    }
    func refreshApps() {
        applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        if let targetPID, !applications.contains(where: { $0.processIdentifier == targetPID }) { self.targetPID = nil }
        if targetPID == nil, let bundle = UserDefaults.standard.string(forKey: "last-target-bundle") {
            targetPID = applications.first(where: { $0.bundleIdentifier == bundle })?.processIdentifier
        }
    }
    func stop() {
        generation = UUID()
        session?.stop(); session = nil
        running = false
        update = HostUpdate(message: "Stopped; controls released", connected: false, state: .neutral, frames: 0)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var stop: (() -> Void)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stop?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MacGamepadApp: App {
    @StateObject private var model = HostModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        // Process-only appearance overrides for visual QA; ordinary launches follow macOS.
        if CommandLine.arguments.contains("--preview-dark") {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        } else if CommandLine.arguments.contains("--preview-light") {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
        if CommandLine.arguments.contains("--hid-self-test") {
            do {
                let output = try VirtualGamepadOutput()
                try output.submit(.neutral)
                print("HID self-test: device created; neutral report accepted.")
                fflush(stdout)
                RunLoop.current.run(until: Date().addingTimeInterval(5))
                output.close()
                print("HID self-test: device closed.")
                exit(0)
            } catch {
                fputs("HID self-test failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }
    var body: some Scene {
        WindowGroup("Pocket Pad · Mac") {
            HostView(model: model)
                .onAppear { delegate.stop = model.stop }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in model.stop() }
        }.defaultSize(width: 760, height: 740)
        .commands {
            CommandMenu("Layouts") {
                Button("Import profile…") { model.importProfile() }
                Button("Export profile…") { model.exportProfile() }.disabled(model.portable == nil || model.running)
                Divider()
                Button("Open Layout Studio") {
                    NotificationCenter.default.post(name: Notification.Name("PocketPadOpenLayoutStudio"), object: nil)
                }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}

struct HostView: View {
    @ObservedObject var model: HostModel
    @StateObject private var discovery = PhoneDiscovery()
    @State private var step: Int
    @State private var panel: Panel?
    @AppStorage("mac-onboarding-v1") private var tourComplete = false
    @State private var tour = false
    @State private var companionReady = false
    @AppStorage("mac-setup-complete-v2") private var setupComplete = UserDefaults.standard.bool(forKey: "connection-walkthrough-v1")
    @State private var replaySetup = false
    @State private var quickConnection = false
    @State private var showingSettings = false
    @State private var newLayoutName = ""
    @State private var newLayoutPrompt = false
    @State private var newLayoutType = LayoutInputType.keyboardMouse
    @State private var duplicateSource: SavedLayout?
    @State private var section: WorkspaceSection = .connection
    enum WorkspaceSection: String, CaseIterable, Identifiable {
        case connection = "Connection", layouts = "Layout & mappings", marketplace = "Marketplace", assistant = "AI helper", general = "General", diagnostics = "Diagnostics", about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .connection: "antenna.radiowaves.left.and.right"
            case .layouts: "rectangle.on.rectangle"
            case .marketplace: "square.grid.2x2"
            case .assistant: "sparkles"
            case .general: "gearshape"
            case .diagnostics: "waveform.path.ecg"
            case .about: "info.circle"
            }
        }
    }
    @AppStorage("connection-walkthrough-v1") private var connectionWalkthroughComplete = false
    @State private var pairingAttempt = false
    @State private var pairing = false
    @State private var manualAddress = false
    @State private var testing = false
    @State private var connectionHelp = false
    @State private var sawStick = false
    @State private var sawButton = false
    @State private var practiceFlash = false
    @State private var controlsPage = 0
    @State private var previousMode = OutputMode.keyboardMouse
    @State private var settingsTab = 0
    @State private var accessibilityAllowed = KeyboardMousePermissions.allowed
    private let accent = PadAppearance.accent
    enum Panel: String, Identifiable { case settings, mappings, gamepadMappings, layout; var id: String { rawValue } }
    init(model: HostModel, initialStep: Int = 0) {
        self.model = model; _step = State(initialValue: initialStep)
    }
    private var connectionReady: Bool {
        model.transport == .usb || (WirelessSettings.validCode(model.pairingCode) &&
            (model.selectedPhone != nil || (model.transport == .wifi && manualAddress && !model.wirelessHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
    }
    private var canStart: Bool {
        guard connectionReady else { return false }
        switch model.mode {
        case .keyboardMouse: return accessibilityAllowed && (model.globalInput || model.targetPID != nil)
        case .gamepad: return CableSession.gamepadAuthorized
        case .monitor: return true
        }
    }
    private var isSettingUp: Bool { !setupComplete || replaySetup }
    private var setupStage: Int { !companionReady ? 0 : testing ? 3 : step == 1 ? 4 : pairing ? 2 : 1 }

    private var setupHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["Get app", "Connect", "Pair", "Test", "Controls"].enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 8) {
                        if index < setupStage { Image(systemName: "checkmark.circle.fill") }
                        Text(title).fontWeight(index == setupStage ? .semibold : .regular)
                    }
                    .foregroundStyle(index <= setupStage ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(title), step \(index + 1) of 5\(index == setupStage ? ", current step" : "")")
                    if index < 4 { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }
            }.font(.callout).frame(maxWidth: 640).padding(.horizontal, 24).frame(maxWidth: .infinity).frame(height: 52)
            GeometryReader { geometry in
                Rectangle().fill(.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(accent).frame(width: geometry.size.width * CGFloat(setupStage + 1) / 5)
                    }
            }.frame(height: 2)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSettingUp {
                if showingSettings { workspaceView } else { liveControllerView }
            } else {
                setupHeader
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !isSettingUp {
                            if quickConnection { quickConnectionView } else { sessionView }
                        }
                        else if !companionReady {
                            CompanionSetupCard()
                            HStack {
                                Spacer()
                                Button("Already installed — continue") { companionReady = true }
                                    .buttonStyle(PadActionStyle(prominent: true))
                            }
                        }
                        else if testing { onboardingTest }
                        else if step == 1 { controlView }
                        else if model.running && !pairingAttempt { sessionView }
                        else {
                            if step == 0 { if pairing { pairingView } else { connectionView } } else { controlView }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padGlass()
                    .overlay(alignment: .topTrailing) {
                        if testing {
                            Button { connectionHelp.toggle() } label: {
                                Image(systemName: "questionmark.circle").font(.system(size: 16))
                                    .frame(width: 28, height: 28).contentShape(Circle())
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("Connection help")
                            .help("Connection help")
                            .popover(isPresented: $connectionHelp) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Connection help").font(.headline)
                                    Text("Keep Pocket Pad open on your iPhone. Both devices should show the practice screen.")
                                    Text("If controls don’t respond, go Back and reconnect using the same connection method on both devices.")
                                        .foregroundStyle(.secondary)
                                    Button("Got it") { connectionHelp = false }.buttonStyle(PadActionStyle())
                                }.padding(20).frame(width: 300)
                            }
                            .padding(12)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                }
            }
            }
        }.frame(minWidth: isSettingUp ? 680 : 900, minHeight: 700)
        .background { PadBackdrop() }.tint(accent).buttonStyle(PadActionStyle()).disclosureGroupStyle(RowDisclosureStyle())
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PocketPadOpenLayoutStudio"))) { _ in
            if isSettingUp { panel = .layout } else { section = .layouts; showingSettings = true }
        }
        .onAppear { model.refreshApps() }
        .sheet(isPresented: $newLayoutPrompt) {
            LayoutCreationView(name: $newLayoutName, type: $newLayoutType, source: $duplicateSource, style: model.update.layout?.layout.style ?? .xbox) { layout in
                model.sendLayout(LayoutCommand(action: .create, layout: layout))
                newLayoutPrompt = false
            }
        }
        .sheet(isPresented: $tour) { MacOnboarding(transport: $model.transport) { tourComplete = true; tour = false } }
        .onChange(of: model.update.frames) { _, _ in
            guard testing, model.update.connected else { return }
            let state = model.update.state
            sawStick = sawStick || abs(Int(state.leftX)) > 4000 || abs(Int(state.rightX)) > 4000 || abs(Int(state.leftY)) > 4000 || abs(Int(state.rightY)) > 4000
            sawButton = sawButton || state.buttons & PadButton.south.mask != 0
        }
        .onChange(of: model.update.connected) { _, connected in
            if connected && !isSettingUp && quickConnection && pairingAttempt {
                pairingAttempt = false
                quickConnection = false
                showingSettings = false
            }
        }
        .onChange(of: model.practiceMoved) { _, moved in if testing && moved { sawStick = true } }
        .task(id: model.practicePressCount) {
            guard testing, model.practicePressCount > 0 else { practiceFlash = false; return }
            sawButton = true; practiceFlash = true
            try? await Task.sleep(for: .milliseconds(160))
            if !Task.isCancelled { practiceFlash = false }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if model.mode == .keyboardMouse { accessibilityAllowed = KeyboardMousePermissions.allowed }
        }
        .onChange(of: model.transport) { _, transport in model.selectedPhone = nil; manualAddress = false; discovery.search(transport) }
        .onChange(of: model.running) { _, running in if running { discovery.stop() } }
        .onDisappear { discovery.stop(); AccessibilityHelper.shared.dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityAllowed = KeyboardMousePermissions.allowed
            if !model.running { model.refreshApps() }
        }
        .onChange(of: panel) { _, selected in model.pauseOutput(selected != nil || (!isSettingUp && showingSettings && section != .connection)) }
        .onChange(of: section) { _, selected in model.pauseOutput(showingSettings && selected != .connection) }
        .onChange(of: showingSettings) { _, showing in model.pauseOutput(showing && section != .connection) }
        .sheet(item: $panel, onDismiss: { model.pauseOutput(panel != nil || (!isSettingUp && showingSettings && section != .connection)) }) { selected in
            switch selected {
            case .mappings: MappingEditor(profile: $model.profile)
            case .gamepadMappings: GamepadMappingEditor(profile: $model.gamepadProfile)
            case .layout:
                LayoutEditor(layout: model.portable?.layout ?? SavedLayout(name: "New Controls", style: .xbox)) { layout, _ in
                    if let existing = model.portable, let data = try? JSONEncoder().encode(existing) {
                        UserDefaults.standard.set(data, forKey: "portable-profile-before-layout-edit")
                    }
                    var copy = layout; copy.isPreset = false
                    model.portable = PortableProfile(layout: copy, keyboard: model.profile)
                    if let data = try? JSONEncoder().encode(model.portable) { UserDefaults.standard.set(data, forKey: "portable-profile-v1") }
                    model.profileNotice = "Layout saved on this Mac. Export it, then import on your iPhone as a new layout."
                }
            case .settings: settingsView
            }
        }
    }
    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 29, weight: .medium))
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var connectionView: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Connect your iPhone.", "Open Pocket Pad on your phone and choose a connection.")
            ConnectionChoices(selection: $model.transport)
            HStack {
                Button("Back") { companionReady = false }
                Spacer()
                Button("Continue") {
                    pairing = true
                    discovery.search(model.transport)
                }.buttonStyle(PadActionStyle(prominent: true)).controlSize(.large)
            }
        }
    }

    private func openSettings(_ destination: WorkspaceSection) {
        section = destination; showingSettings = true
    }
    private var liveControllerView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Pocket Pad", systemImage: "gamecontroller").font(.title2.weight(.semibold))
                Spacer()
                Label(model.update.connected ? "Connected" : model.running ? "Connecting…" : "Not connected",
                      systemImage: model.update.connected ? "checkmark.circle.fill" : "iphone").foregroundStyle(.secondary)
                Button { openSettings(.assistant) } label: { Label("AI helper", systemImage: "sparkles") }
                    .help("Preview the layout assistant")
                Button { openSettings(.general) } label: { Image(systemName: "gearshape").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
            }.padding(24)
            Divider()
            if let snapshot = model.update.layout, model.update.connected {
                HStack {
                    Text(snapshot.layout.name).font(.headline)
                    if snapshot.layout.hasCursorSwitching {
                        Text(snapshot.layout.modes[snapshot.modeIndex].name).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 24).padding(.top, 20)
                LayoutEditor(layout: snapshot.layout, embedded: true, liveState: model.update.state,
                             modeIndex: snapshot.modeIndex, screen: snapshot.screen) { _, _ in }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "iphone.and.arrow.forward").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(model.update.connected ? "Loading your phone’s layout…" : "Your controller appears here when connected.").font(.title3)
                    if !model.update.connected { Button("Connect iPhone") { openSettings(.connection) }.buttonStyle(PadActionStyle(prominent: true)) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 16) {
                dashboardAction("Layout & mappings", icon: "rectangle.on.rectangle", detail: "Arrange and assign controls") { openSettings(.layouts) }
                dashboardAction("Marketplace", icon: "square.grid.2x2", detail: "Discover layouts") { openSettings(.marketplace) }
                dashboardAction("Connection", icon: "antenna.radiowaves.left.and.right", detail: model.transport.rawValue) { openSettings(.connection) }
            }.padding(24)
        }
    }

    private var workspaceView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button { showingSettings = false } label: { Label("Back to controller", systemImage: "chevron.left") }
                    .buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 20)
                List(WorkspaceSection.allCases, selection: Binding<WorkspaceSection?>(get: { section }, set: { if let value = $0 { section = value } })) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }.listStyle(.sidebar)
                Label(model.update.connected ? "Connected" : model.running ? "Connecting…" : "Not connected",
                      systemImage: model.update.connected ? "checkmark.circle.fill" : "iphone")
                    .foregroundStyle(.secondary).font(.callout).padding(16)
            }.frame(width: 180).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(section.rawValue).font(.title2.weight(.semibold))
                    Spacer()
                    if section != .connection && model.update.connected {
                        Text("Connected · input paused").foregroundStyle(.secondary)
                    }
                }.padding(24)
                Divider()
                workspaceDetail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder private var workspaceDetail: some View {
        switch section {
        case .connection:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if quickConnection || !model.running {
                        quickConnectionView
                    } else {
                        Label(model.update.connected ? "Ready to play" : model.update.message,
                              systemImage: model.update.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right").font(.title2)
                        LabeledContent("Connection", value: model.transport.rawValue)
                        LabeledContent("Input", value: model.mode == .keyboardMouse ? "Keyboard & mouse" : "Controller")
                        Divider()
                        Text(model.update.interpretedInput).font(.body.monospaced()).foregroundStyle(.secondary)
                        Button("Disconnect") { model.stop(); pairingAttempt = false; discovery.search(model.transport) }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.onAppear { if !model.running { discovery.search(model.transport) } }
        case .layouts:
            if let snapshot = model.update.layout, model.update.connected {
                VStack(spacing: 0) {
                    HStack {
                        Picker("Phone layout", selection: Binding(get: { snapshot.layout.id }, set: {
                            model.sendLayout(LayoutCommand(action: .select, layoutID: $0))
                        })) {
                            ForEach(snapshot.layouts ?? [LayoutSummary(snapshot.layout)]) { item in
                                Text(item.name + (item.isPreset ? " · preset" : "")).tag(item.id)
                            }
                        }
                        Button { section = .assistant } label: { Label("AI helper", systemImage: "sparkles") }
                        Button("New") { duplicateSource = nil; newLayoutType = .keyboardMouse; newLayoutName = ""; newLayoutPrompt = true }
                        Button("Duplicate") {
                            var source = snapshot.layout
                            if source.inputType == nil {
                                source.inputType = model.mode == .gamepad ? .gamepad : .keyboardMouse
                                source.keyboardProfile = source.keyboardProfile ?? model.profile
                                source.gamepadProfile = source.gamepadProfile ?? model.gamepadProfile
                            }
                            duplicateSource = source; newLayoutType = source.effectiveInputType
                            newLayoutName = source.name + " Copy"; newLayoutPrompt = true
                        }
                    }.disabled(model.layoutCommandID != nil).padding(.horizontal, 24).padding(.top, 16)
                    if let screen = snapshot.screen {
                        Text("\(screen.model) · \(Int(screen.width)) × \(Int(screen.height)) pt")
                            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24).padding(.top, 8)
                    }
                    if let notice = model.layoutCommandNotice {
                        Text(notice).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    LayoutEditor(layout: snapshot.layout, embedded: true, screen: snapshot.screen) { layout, base in
                        if base.isPreset {
                            var copy = layout; copy.name += " Copy"; copy.isPreset = false
                            model.sendLayout(LayoutCommand(action: .create, layout: copy))
                        } else {
                            model.sendLayout(LayoutCommand(action: .save, layout: layout, base: base))
                        }
                    }.id(snapshot.layout.id).disabled(model.layoutCommandID != nil)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Connect your iPhone to manage its layouts.").font(.title3)
                    Button("Connect iPhone") { section = .connection }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .assistant:
            LayoutAssistantView(model: model) { section = .marketplace }
        case .marketplace:
            MarketplaceView()
        case .general:
            Form {
                Section("Controls") {
                    LabeledContent("Layout input", value: model.update.layout?.layout.effectiveInputType.title ?? "Keyboard & mouse")
                    Button("Manage layouts") { section = .layouts }
                    if model.mode == .keyboardMouse {
                        Toggle("Control the active app", isOn: $model.globalInput).disabled(model.running)
                        if !model.globalInput {
                            Picker("App", selection: $model.targetPID) {
                                Text("Choose an app").tag(nil as Int32?)
                                ForEach(model.applications, id: \.processIdentifier) { app in
                                    Text(app.localizedName ?? "App").tag(Optional(app.processIdentifier))
                                }
                            }.disabled(model.running)
                        }
                    }
                    if model.running {
                        Button("Disconnect to change target app") { model.stop(); pairingAttempt = false }
                    }
                }
                Section("Permissions") {
                    Button("Accessibility settings") { AccessibilityHelper.shared.show() }
                }
                Section("Profiles") {
                    Button("Import profile…") { model.importProfile() }
                    Button("Export profile…") { model.exportProfile() }.disabled(model.portable == nil)
                    if let notice = model.profileNotice { Text(notice).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped)
        case .diagnostics:
            Form {
                LabeledContent("Status", value: model.update.message)
                LabeledContent("Transport", value: model.transport.rawValue)
                Button("Open input log") { NSWorkspace.shared.open(InputDiagnostics.url) }
                Text("Pocket Pad output only. Keeps the last five minutes, up to 512 KB; older entries are discarded.").foregroundStyle(.secondary)
                Button("Local Network settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!) }
            }.formStyle(.grouped)
        case .about:
            Form {
                Text("Pocket Pad").font(.title2)
                Text(AppInformation.privacy)
                Link("Support", destination: AppInformation.supportURL)
                Link("Source and setup", destination: AppInformation.projectURL)
                Button("Replay getting started") {
                    model.stop(); model.pauseOutput(false); testing = false; pairingAttempt = false
                    pairing = false; step = 0; companionReady = false; replaySetup = true
                }
            }.formStyle(.grouped)
        }
    }

    private var quickConnectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionPills(selection: $model.transport).disabled(pairingAttempt)
            pairingView
            if model.mode == .keyboardMouse && !accessibilityAllowed {
                Button("Allow keyboard & mouse control") { AccessibilityHelper.shared.show() }
            } else if model.mode == .keyboardMouse && !model.globalInput && model.targetPID == nil {
                Text("Open your selected game, or use the active app.").foregroundStyle(.secondary)
                Button("Use active app") { model.globalInput = true }
            } else if model.mode == .gamepad && !CableSession.gamepadAuthorized {
                Text("Controller input is unavailable in this build.").foregroundStyle(.secondary)
                Button("Use keyboard & mouse") { model.mode = .keyboardMouse }
            }
        }
    }

    private var pairingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading(model.transport == .usb ? "Connect your iPhone." : "Pair your iPhone.",
                    model.transport == .usb ? "Open Pocket Pad and plug your phone into this Mac." : "Choose \(model.transport.rawValue) in Pocket Pad on your iPhone.")
            if model.transport == .usb {
                Label("Unlock your iPhone and trust this Mac if asked.", systemImage: "cable.connector")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Your iPhone").font(.headline)
                        Spacer()
                        Button { discovery.search(model.transport) } label: {
                            Image(systemName: "arrow.clockwise").frame(width: 32, height: 32)
                        }.buttonStyle(.borderless).help("Search again").accessibilityLabel("Search again")
                    }
                    if discovery.phones.isEmpty && !manualAddress {
                        Label(discovery.status, systemImage: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ScrollView {
                    ForEach(discovery.phones) { phone in
                        Button {
                            model.selectedPhone = phone.id; manualAddress = false
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "iphone").font(.title2)
                                Text(phone.name).font(.headline)
                                Spacer()
                                Image(systemName: model.selectedPhone == phone.id && !manualAddress ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.selectedPhone == phone.id && !manualAddress ? accent : .secondary)
                            }.padding(12).contentShape(Rectangle())
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                    }.frame(height: discovery.phones.isEmpty ? 0 : min(CGFloat(discovery.phones.count) * 56, isSettingUp ? 112 : 56))
                    if model.transport == .wifi {
                        DisclosureGroup("Enter an address instead", isExpanded: $manualAddress) {
                            HStack(spacing: 12) {
                                Image(systemName: "network").foregroundStyle(.secondary)
                                TextField("iPhone address", text: $model.wirelessHost).textFieldStyle(.plain)
                            }.padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)).padding(.top, 8)
                        }.onChange(of: manualAddress) { _, manual in if manual { model.selectedPhone = nil } }
                    }
                    Divider()
                    Text("Pairing code").font(.headline)
                    PairingCodeField(code: $model.pairingCode)
                    if isSettingUp {
                        Text("Enter the six digits shown on your iPhone.").foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(pairingAttempt)
            }
            Label(pairingAttempt ? (model.update.connected ? "Connected to your iPhone" : model.update.message) : "Ready to connect",
                  systemImage: pairingAttempt && model.update.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                .font(.callout).foregroundStyle(pairingAttempt && model.update.connected ? accent : .secondary)
                .lineLimit(2).help(pairingAttempt ? model.update.message : "Choose your phone and select Connect.")
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: isSettingUp ? 48 : 32)
            HStack {
                if isSettingUp || pairingAttempt {
                Button(pairingAttempt ? "Cancel connection" : "Back") {
                    if !isSettingUp {
                        if pairingAttempt { model.stop(); pairingAttempt = false; discovery.search(model.transport) }
                        else { quickConnection = false }
                    }
                    else if pairingAttempt { model.stop(); model.mode = previousMode; pairingAttempt = false }
                    else { pairing = false }
                }.buttonStyle(PadActionStyle()).controlSize(.large)
                }
                Spacer()
                Button(pairingAttempt ? (model.update.connected ? "Test controls" : "Connecting…") : "Connect") {
                    if !isSettingUp {
                        quickConnection = true; pairingAttempt = true; model.syncSetup(.play); model.start()
                    } else if pairingAttempt && model.update.connected {
                        pairingAttempt = false; testing = true; sawStick = false; sawButton = false; model.syncSetup(.practice)
                    } else {
                        previousMode = model.mode; model.mode = .monitor; pairingAttempt = true; model.syncSetup(.pairing); model.start()
                    }
                }.buttonStyle(PadActionStyle(prominent: true)).controlSize(.large)
                    .disabled(isSettingUp ? (!connectionReady || (pairingAttempt && !model.update.connected)) : (!canStart || pairingAttempt))
            }
        }
    }
    private var onboardingTest: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Get a feel for it.", "Drag the stick and press A on your phone. Watch them respond here.")
            Label(model.update.connected ? "Phone connected" : model.update.message, systemImage: model.update.connected ? "checkmark.circle.fill" : "iphone")
            VStack(spacing: 24) {
                HStack(spacing: 28) {
                    PracticeStick(offset: CGSize(
                        width: Double(model.update.state.leftX) / 32767 * 35,
                        height: Double(model.update.state.leftY) / 32767 * 35))
                        .accessibilityLabel("Live practice stick")
                    PracticeButton(pressed: practiceFlash || model.update.state.buttons & PadButton.south.mask != 0)
                        .accessibilityLabel("Live A button")
                }.padding(.vertical, 12)
                HStack(spacing: 28) {
                    Label("Move the stick", systemImage: sawStick ? "checkmark.circle.fill" : "circle")
                    Label("Press A", systemImage: sawButton ? "checkmark.circle.fill" : "circle")
                }.foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
            Text(sawStick && sawButton ? "Your controls are reaching this Mac." : "Practice only. No input is sent to your game.")
                .foregroundStyle(.secondary)
            if !model.running { Button("Try again") { model.start() } }
            HStack {
                Button("Back") { model.stop(); model.mode = previousMode; testing = false }
                Spacer()
                Button(sawStick && sawButton ? "Choose controls" : "Skip test") {
                    connectionWalkthroughComplete = true; model.syncSetup(.controls); model.mode = previousMode == .monitor ? .keyboardMouse : previousMode; testing = false; controlsPage = 0; step = 1; model.refreshApps()
                }.buttonStyle(PadActionStyle(prominent: true))
            }


        }
    }
    private var controlView: some View {
        VStack(alignment: .leading, spacing: 24) {
            if controlsPage == 0 {
                heading("Choose your controls.", "How should your game receive input?")
                modeChoice(.keyboardMouse, title: "Emulate keyboard & mouse", detail: "Send key presses, clicks, and mouse movement.", icon: "keyboard")
                modeChoice(.gamepad, title: "Emulate controller", detail: "Send gamepad buttons and analog stick input.", icon: "gamecontroller")
            } else if controlsPage == 1 {
                heading("Allow keyboard & mouse.", "Enable Pocket Pad in macOS Accessibility settings.")
                Text("A small helper stays beside System Settings so you can drag Pocket Pad into the permissions list.")
                    .foregroundStyle(.secondary)
                Button("Open Accessibility Settings") {
                    AccessibilityHelper.shared.show()
                }.buttonStyle(PadActionStyle(prominent: true))
                Label(accessibilityAllowed ? "Permission granted" : "Waiting for permission…", systemImage: accessibilityAllowed ? "checkmark.circle.fill" : "lock")
                    .foregroundStyle(accessibilityAllowed ? accent : .secondary).frame(height: 28)
            } else if model.mode == .keyboardMouse {
                heading("Ready to play.", model.globalInput ? "Your phone controls whichever app is active." : "Your phone controls only the game you choose.")
                HStack {
                    Button("Active app") { model.globalInput = true }.buttonStyle(PadActionStyle(prominent: model.globalInput))
                    Button("One app only") { model.globalInput = false }.buttonStyle(PadActionStyle(prominent: !model.globalInput))
                }
                if !model.globalInput {
                    HStack {
                        Text("Running games & apps").font(.headline)
                        Spacer()
                        Button { model.refreshApps() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh apps")
                    }
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.applications, id: \.processIdentifier) { app in
                                Button { model.targetPID = app.processIdentifier } label: {
                                    HStack {
                                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                                        Text(app.localizedName ?? "App")
                                        Spacer()
                                        Image(systemName: model.targetPID == app.processIdentifier ? "checkmark.circle.fill" : "circle")
                                    }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain)
                            }
                            if model.applications.isEmpty { Text("Open your game, then refresh.").foregroundStyle(.secondary) }
                        }
                    }.frame(height: 168)
                }
            } else {
                heading("Ready for your game.", "Enable controller support in your game. Use Aim mode on your phone for the right stick.")
                if model.mode == .gamepad && !CableSession.gamepadAuthorized {
                    Label("Virtual gamepad is unavailable in this build. Choose keyboard & mouse to continue.", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Back") {
                    if controlsPage == 0 { model.stop(); step = 0; model.syncSetup(.pairing) }
                    else if controlsPage == 2 && model.mode == .keyboardMouse && !accessibilityAllowed { controlsPage = 1 }
                    else { controlsPage = 0 }
                }
                Spacer()
                Button(controlsPage < 2 ? "Continue" : "Start playing") {
                    accessibilityAllowed = KeyboardMousePermissions.allowed
                    if controlsPage == 0 { controlsPage = model.mode == .keyboardMouse && !accessibilityAllowed ? 1 : 2 }
                    else if controlsPage == 1 { if accessibilityAllowed { controlsPage = 2 } }
                    else if canStart { setupComplete = true; replaySetup = false; model.syncSetup(.play); step = 2; model.start() }
                    else if model.mode == .keyboardMouse && !accessibilityAllowed { controlsPage = 1 }
                }.buttonStyle(PadActionStyle(prominent: true))
                    .disabled(controlsPage == 1 ? !accessibilityAllowed : controlsPage == 2 ? !canStart : false)
            }
        }
    }

    private func modeChoice(_ mode: OutputMode, title: String, detail: String, icon: String) -> some View {
        Button { model.mode = mode } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: model.mode == mode ? "checkmark.circle.fill" : "circle").foregroundStyle(model.mode == mode ? accent : .secondary)
            }.padding(16).background(model.mode == mode ? accent.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(model.mode == mode ? accent : Color.primary.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    private var sessionView: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.update.connected ? "Ready to play." : model.running ? "Reconnecting…" : "Your controls are ready.").font(.system(size: 29, weight: .medium))
                    Text(model.portable?.layout.name ?? "Your iPhone controls").foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.transport.rawValue, systemImage: model.update.connected ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(model.update.connected ? accent : .secondary)
            }
            Divider()
            HStack(spacing: 16) {
                dashboardAction("Layouts", icon: "rectangle.on.rectangle", detail: "Arrange on your Mac") { panel = .layout }
                dashboardAction("Mappings", icon: "slider.horizontal.3", detail: "Buttons and behavior") { panel = model.mode == .gamepad ? .gamepadMappings : .mappings }
                dashboardAction("Connection", icon: "antenna.radiowaves.left.and.right", detail: "Connect or change phone") { model.stop(); quickConnection = true; discovery.search(model.transport) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Current input").font(.callout).foregroundStyle(.secondary)
                Text(model.running ? model.update.interpretedInput : "Input paused").font(.system(size: 20, weight: .medium, design: .monospaced))
                    .lineLimit(2).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }.padding(18).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            HStack {
                Text(model.mode == .keyboardMouse ? (model.globalInput ? "Active app · Keyboard & mouse" : "One app · Keyboard & mouse") : "Controller input")
                    .foregroundStyle(.secondary)
                Spacer()
                if model.running { Button("Disconnect") { model.stop() } }
                else {
                    Button("Connect") {
                        accessibilityAllowed = KeyboardMousePermissions.allowed; model.refreshApps()
                        if canStart { quickConnection = true; pairingAttempt = true; model.syncSetup(.play); model.start() }
                        else { quickConnection = true; discovery.search(model.transport) }
                    }.buttonStyle(PadActionStyle(prominent: true))
                }
            }
        }
    }
    private func dashboardAction(_ title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(accent)
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
        }.buttonStyle(.plain)
    }
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings").font(.title2.weight(.medium))
                Spacer()
                Button("Done") { panel = nil }.keyboardShortcut(.cancelAction)
            }
            HStack {
                ForEach(Array(["Controls", "Layouts", "Diagnostics", "About"].enumerated()), id: \.offset) { index, title in
                    Button(title) { settingsTab = index }.buttonStyle(PadActionStyle(prominent: settingsTab == index))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if settingsTab == 0 {
                        Text("Input mappings").font(.headline)
                        Text(model.mode == .gamepad ? "Remap controller buttons and adjust stick axes. Gamepad mappings are saved on this Mac, separately from keyboard mappings." : "Edit key combinations, mouse sensitivity, and automatic running. Arrange controls in the Layouts tab.").foregroundStyle(.secondary)
                        Button("Edit mappings") { panel = model.mode == .gamepad ? .gamepadMappings : .mappings }
                    } else if settingsTab == 1 {
                        Text(model.portable?.layout.name ?? "Your current controls").font(.headline)
                        Text("Import your iPhone profile to arrange it here. Export your changes and import them on your phone as a new layout.").foregroundStyle(.secondary)
                        Button("Open layout studio") { panel = .layout }
                        HStack {
                            Button("Import profile…") { model.importProfile() }.disabled(model.running)
                            Button("Export profile…") { model.exportProfile() }.disabled(model.running || model.portable == nil)
                        }
                        if model.running { Text("Disconnect before changing profiles.").font(.callout).foregroundStyle(.secondary) }
                        if let notice = model.profileNotice { Text(notice).font(.callout) }
                    } else if settingsTab == 3 {
                        Text("PocketPad").font(.headline)
                        Button("Replay getting started") { model.stop(); testing = false; pairingAttempt = false; connectionWalkthroughComplete = false; pairing = false; step = 0; panel = nil; companionReady = false; replaySetup = true }
                        HStack {
                            Link("Support", destination: AppInformation.supportURL)
                            Link("Source and setup", destination: AppInformation.projectURL)
                        }
                        Text(AppInformation.privacy).textSelection(.enabled)
                    } else {
                        Text(model.update.message).font(.callout).textSelection(.enabled)
                        Text("USB: unlock your phone, trust this Mac, and choose USB cable on the phone. Wi-Fi: use the same private network; hotel or guest networks may block devices from connecting.").foregroundStyle(.secondary)
                        HStack {
                            Button("Local Network settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!) }
                            Button("Accessibility settings") { AccessibilityHelper.shared.show() }
                            Button("Open input log") { NSWorkspace.shared.open(InputDiagnostics.url) }
                Text("Pocket Pad output only. Keeps the last five minutes, up to 512 KB; older entries are discarded.").foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("Live input").font(.headline)
                        Text("\(model.update.frames) frames · \(model.transport.rawValue)").font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 28) {
                            stick("Left stick", x: model.update.state.leftX, y: model.update.state.leftY)
                            stick("Right stick", x: model.update.state.rightX, y: model.update.state.rightY)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LT \(model.update.state.leftTrigger) · RT \(model.update.state.rightTrigger)")
                                Text("D-pad \(model.update.state.hat)")
                                Text("Buttons \(model.update.state.buttons)")
                                Text("Custom \(model.update.state.customButtons)")
                            }.font(.caption.monospaced())
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(width: 620, height: 510).background { PadBackdrop() }.tint(accent)
    }
    private func stick(_ title: String, x: Int16, y: Int16) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.primary.opacity(0.12), lineWidth: 1).frame(width: 90, height: 90)
                Circle().fill(accent).frame(width: 12, height: 12)
                    .offset(x: CGFloat(x) / 32767 * 38, y: CGFloat(y) / 32767 * 38)
            }
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}
