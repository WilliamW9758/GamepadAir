import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class HostModel: ObservableObject {
    @Published var mode = OutputMode.keyboardMouse
    @Published var running = false
    @Published var selectedPhone: String?
    @Published var transport = LinkTransport.usb
    @Published var wirelessHost = UserDefaults.standard.string(forKey: "wireless-host") ?? ""
    @Published var pairingCode: String = {
        let saved = UserDefaults.standard.string(forKey: "wireless-code") ?? ""
        return WirelessSettings.validCode(saved) ? saved : ""
    }()
    @Published var profile = KeyboardProfile.restore(UserDefaults.standard.data(forKey: "keyboard-profile-v1")) {
        didSet { if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "keyboard-profile-v1") } }
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
    @Published var globalInput = false
    @Published var targetPID: Int32?
    @Published var applications: [NSRunningApplication] = []
    @Published var update = HostUpdate(message: "Ready to connect", connected: false, state: .neutral, frames: 0)
    private var session: CableSession?
    private var generation = UUID()

    func start() {
        stop()
        let token = UUID(); generation = token
        running = true
        update = HostUpdate(message: "Connecting…", connected: false, state: .neutral, frames: 0)
        UserDefaults.standard.set(wirelessHost, forKey: "wireless-host")
        UserDefaults.standard.set(pairingCode, forKey: "wireless-code")
        let session = CableSession(mode: mode, transport: transport, wirelessHost: selectedPhone ?? wirelessHost, pairingCode: pairingCode, keyboardProfile: profile, targetPID: targetPID, globalInput: globalInput) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.update = event
                if event.finished { self.running = false; self.session = nil }
            }
        }
        self.session = session; session.start()
    }
    func refreshApps() {
        applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        if let targetPID, !applications.contains(where: { $0.processIdentifier == targetPID }) { self.targetPID = nil }
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
    var body: some Scene {
        WindowGroup("Pocket Pad · Mac") {
            HostView(model: model)
                .onAppear { delegate.stop = model.stop }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in model.stop() }
        }.defaultSize(width: 640, height: 650)
    }
}

struct HostView: View {
    @ObservedObject var model: HostModel
    @StateObject private var discovery = PhoneDiscovery()
    @State private var step: Int
    @State private var panel: Panel?
    @State private var settingsTab = 0
    @State private var advanced = false
    @State private var accessibilityAllowed = KeyboardMousePermissions.allowed
    private let accent = Color(red: 0.75, green: 0.86, blue: 0.81)
    enum Panel: String, Identifiable { case settings, mappings; var id: String { rawValue } }
    init(model: HostModel, initialStep: Int = 0) {
        self.model = model; _step = State(initialValue: initialStep)
    }
    private var connectionReady: Bool {
        model.transport == .usb || (WirelessSettings.validCode(model.pairingCode) &&
            (model.selectedPhone != nil || (model.transport == .wifi && !model.wirelessHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
    }
    private var canStart: Bool {
        guard connectionReady else { return false }
        switch model.mode {
        case .keyboardMouse: return accessibilityAllowed && (model.globalInput || model.targetPID != nil)
        case .gamepad: return CableSession.gamepadAuthorized
        case .monitor: return true
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Pocket Pad", systemImage: "gamecontroller").font(.system(size: 19, weight: .medium))
                Spacer()
                Button { panel = .settings } label: { Image(systemName: "gearshape").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
            }.padding(.horizontal, 28).padding(.vertical, 20)
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.running { sessionView }
                    else {
                        HStack(spacing: 10) {
                            Text("1  Connect your phone").foregroundStyle(step == 0 ? accent : .secondary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            Text("2  Choose controls").foregroundStyle(step == 1 ? accent : .secondary)
                        }.font(.caption)
                        if step == 0 { connectionView } else { controlView }
                    }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(minWidth: 600, minHeight: 590)
        .background(Color(red: 0.075, green: 0.078, blue: 0.078)).tint(accent).preferredColorScheme(.dark)
        .onAppear { model.refreshApps() }
        .onChange(of: model.transport) { _, transport in model.selectedPhone = nil; discovery.search(transport) }
        .onChange(of: model.running) { _, running in if running { discovery.stop() } }
        .onDisappear { discovery.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityAllowed = KeyboardMousePermissions.allowed
            if !model.running { model.refreshApps() }
        }
        .sheet(item: $panel) { selected in
            switch selected {
            case .mappings: MappingEditor(profile: $model.profile)
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
            heading("Turn your phone into a controller.", "Open Pocket Pad on your iPhone, then choose how to connect.")
            Picker("Connection", selection: $model.transport) {
                ForEach(LinkTransport.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if model.transport == .usb {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Plug your iPhone into this Mac.", systemImage: "cable.connector")
                    Label("Keep Pocket Pad open on the phone.", systemImage: "iphone")
                    Text("Choose USB cable in the phone’s settings. If asked, unlock your phone and trust this Mac.").font(.callout).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.transport == .wifi ? "Choose Wi-Fi in the phone’s settings. Both devices need a network that allows them to connect to each other." : "Choose Bluetooth in the phone’s settings and keep the app open.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Picker("Phone", selection: $model.selectedPhone) {
                            Text(model.transport == .wifi ? "Use an address" : "Choose a phone").tag(nil as String?)
                            ForEach(discovery.phones) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Button("Search again") { discovery.search(model.transport) }
                    }
                    if model.transport == .wifi && model.selectedPhone == nil {
                        TextField("Address shown on your iPhone", text: $model.wirelessHost).textFieldStyle(.roundedBorder)
                    }
                    TextField("Six-digit code shown on your iPhone", text: $model.pairingCode).textFieldStyle(.roundedBorder)
                    Text(discovery.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("We’ll connect when you start.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Continue") { step = 1; model.refreshApps() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!connectionReady)
            }
        }
    }
    private var controlView: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("What would you like to control?", model.mode == .keyboardMouse ? "Your phone’s buttons will act as keyboard and mouse inputs." : "Choose where your phone’s input goes.")
            if model.mode == .keyboardMouse {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Control", selection: $model.globalInput) {
                        Text("One app").tag(false)
                        Text("Any active app").tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                    if model.globalInput {
                        Text("Input follows the active app. Use Cursor mode on your phone to move the desktop pointer.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Picker("App", selection: $model.targetPID) {
                                Text("Choose a running game or app").tag(nil as Int32?)
                                ForEach(model.applications, id: \.processIdentifier) { app in
                                    Text(app.localizedName ?? "App").tag(Optional(app.processIdentifier))
                                }
                            }
                            Button { model.refreshApps() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh running apps").accessibilityLabel("Refresh running apps")
                        }
                        Text("Open your game if it isn’t listed. Input pauses when you switch away from it.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                if !accessibilityAllowed {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Allow Pocket Pad to send input").font(.headline)
                        Text("In Accessibility settings, turn on Pocket Pad, then return here.").font(.callout).foregroundStyle(.secondary)
                        Button("Open Accessibility Settings") {
                            accessibilityAllowed = KeyboardMousePermissions.request()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
            DisclosureGroup("Other control modes", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Mode", selection: $model.mode) {
                        Text("Keyboard & mouse").tag(OutputMode.keyboardMouse)
                        Text("Test input only").tag(OutputMode.monitor)
                        Text("Virtual gamepad").tag(OutputMode.gamepad).disabled(!CableSession.gamepadAuthorized)
                    }
                    Text(model.mode == .monitor ? "See incoming controls without sending any keyboard or mouse input." : "Virtual gamepad output needs Apple’s restricted authorization. Keyboard & mouse works with ordinary Accessibility permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }.font(.callout)
            if model.update.finished {
                Label(model.update.message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                Button("Review connection") { step = 0 }
            }
            HStack {
                Button("Back") { step = 0 }
                Spacer()
                Button(model.mode == .monitor ? "Start input test" : "Start playing") {
                    accessibilityAllowed = KeyboardMousePermissions.allowed
                    if canStart { model.start() }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!canStart)
            }
            Text("You can customize buttons and mappings later in Settings.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var sessionView: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(model.update.connected ? (model.mode == .monitor ? "Input test is ready." : "You’re connected.") : "Connecting to your phone…",
                    model.update.connected ? "Keep Pocket Pad open on your iPhone." : "Keep your phone unlocked with Pocket Pad open.")
            VStack(alignment: .leading, spacing: 16) {
                Label(model.update.message, systemImage: model.update.connected ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                    .font(.callout).textSelection(.enabled)
                Divider().opacity(0.4)
                Text("CURRENT INPUT").font(.caption2).foregroundStyle(.secondary)
                Text(model.mode == .keyboardMouse ? model.update.interpretedInput : (model.update.frames > 0 ? "Receiving controls" : "Waiting for input")).font(.system(size: 21, weight: .medium, design: .monospaced)).foregroundStyle(accent).textSelection(.enabled)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            Text(model.mode == .keyboardMouse ? (model.globalInput ? "Controlling the active app." : "Switch to your selected app to play.") : "Input pauses automatically if the connection stops.")
                .foregroundStyle(.secondary)
            if model.mode != .keyboardMouse {
                Button("View live input") { settingsTab = 2; panel = .settings }
            }
            HStack {
                Text(model.transport.rawValue).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.update.connected ? "Disconnect" : "Cancel connection") { model.stop() }.controlSize(.large)
            }
        }
    }
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings").font(.title2.weight(.medium))
                Spacer()
                Button("Done") { panel = nil }.keyboardShortcut(.cancelAction)
            }
            Picker("Settings", selection: $settingsTab) {
                Text("Controls").tag(0); Text("Profiles").tag(1); Text("Troubleshooting").tag(2)
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if settingsTab == 0 {
                        Text("Make it yours").font(.headline)
                        Text("Edit key combinations, mouse sensitivity, and automatic running. Arrange buttons and adjust haptics on your iPhone.").foregroundStyle(.secondary)
                        Button(model.running ? "Disconnect & edit mappings" : "Edit mappings") { model.stop(); panel = .mappings }
                    } else if settingsTab == 1 {
                        Text(model.portable?.layout.name ?? "Your current controls").font(.headline)
                        Text("Bring a layout over from your iPhone, then export it with this Mac’s mappings as one profile. Importing always keeps the phone’s existing layouts.").foregroundStyle(.secondary)
                        HStack {
                            Button("Import profile…") { model.importProfile() }.disabled(model.running)
                            Button("Export profile…") { model.exportProfile() }.disabled(model.running || model.portable == nil)
                        }
                        if model.running { Text("Disconnect before changing profiles.").font(.caption).foregroundStyle(.secondary) }
                        if let notice = model.profileNotice { Text(notice).font(.callout) }
                    } else {
                        Text(model.update.message).font(.callout).textSelection(.enabled)
                        Text("USB: unlock your phone, trust this Mac, and choose USB cable on the phone. Wi-Fi: use the same private network; hotel or guest networks may block devices from connecting.").foregroundStyle(.secondary)
                        HStack {
                            Button("Local Network settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!) }
                            Button("Accessibility settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                            Button("Open input log") { NSWorkspace.shared.open(InputDiagnostics.url) }
                        }
                        Divider()
                        Text("Live input").font(.headline)
                        Text("\(model.update.frames) frames · \(model.transport.rawValue)").font(.caption).foregroundStyle(.secondary)
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
        }.padding(24).frame(width: 570, height: 450).tint(accent).preferredColorScheme(.dark)
    }
    private func stick(_ title: String, x: Int16, y: Int16) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 1).frame(width: 90, height: 90)
                Circle().fill(accent).frame(width: 12, height: 12)
                    .offset(x: CGFloat(x) / 32767 * 38, y: CGFloat(y) / 32767 * 38)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
