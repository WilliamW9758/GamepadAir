import SwiftUI

struct PhoneOnboarding: View {
    @ObservedObject var server: CableServer
    let finish: () -> Void
    @State private var deviceName = WirelessSettings.deviceName()
    @State private var step = 0
    @State private var moved = false
    @State private var tapped = false
    @State private var pressed = false
    @State private var offset = CGSize.zero
    private let titles = ["Your phone. Your controller.", "Choose your connection.", "Bring your Mac along.", "Get a feel for it.", "Make room for your thumbs."]
    private let details = [
        "Play on your Mac with controls that fit your hands. Open Pocket Pad on both devices to start.",
        "", "",
        "Drag the stick, then press A. Watch the matching controls on your Mac.",
        "Hold the gear to move and resize controls. Double-tap a button while editing to rename it."
    ]
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 400
            VStack(spacing: compact ? 8 : 16) {
                HStack {
                    Label("Pocket Pad", systemImage: "gamecontroller").font(.headline)
                    Spacer()
                    Button("Skip tour", action: finish).frame(minHeight: 44)
                }
                HStack(spacing: 6) {
                    ForEach(0..<5) { index in
                        Capsule().fill(index <= step ? Color.primary : Color.primary.opacity(0.08)).frame(height: 3)
                    }
                }.accessibilityLabel("Step \(step + 1) of 5")
                Group {
                    if step == 0 {
                        CompanionSetupCard()
                    } else if step == 1 {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(titles[step]).font(.system(size: compact ? 25 : 32, weight: .medium))
                            ConnectionChoices(selection: Binding(get: { server.transport }, set: {
                                if server.transport != $0 { server.selectTransport($0) }
                            }))
                        }
                    } else {
                        page(compact: compact)
                    }
                }
                .padding(compact ? 16 : 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padGlass()
                HStack(spacing: 16) {
                    Spacer()
                    if step > 0 && server.setupStage == nil { Button("Back") { step -= 1 }.frame(minWidth: 44, minHeight: 44) }
                    Button(server.connected && server.setupStage != nil ? "Continue on your Mac" : step == 0 ? "Already installed — continue" : step == 4 ? "Open controller" : step == 2 ? "Test controls" : "Continue") {
                        if step == 4 { finish() } else { step += 1 }
                    }.buttonStyle(PadActionStyle(prominent: true)).controlSize(.large).frame(minHeight: 44).disabled((step == 2 && !server.connected) || (server.connected && server.setupStage != nil))
                }
            }.padding(.horizontal, 24).padding(.vertical, compact ? 8 : 20)
        }
        .background { PadBackdrop() }
        .tint(PadAppearance.accent).interactiveDismissDisabled()
        .onAppear { followMac(server.setupStage) }
        .onChange(of: server.setupStage) { _, stage in followMac(stage) }
        .onChange(of: step) { _, _ in offset = .zero; pressed = false; server.update(.paused) }
        .onDisappear { server.update(.paused) }
    }

    private func followMac(_ stage: SetupStage?) {
        guard server.connected, let stage else { return }
        offset = .zero; pressed = false; server.update(.paused)
        switch stage {
        case .pairing: step = 2
        case .practice: step = 3
        case .controls: step = 4
        case .play: finish()
        }
    }

    private var connectionInstructions: String {
        switch server.transport {
        case .usb: return "Plug into your Mac, unlock your iPhone, and trust the Mac if asked. Choose USB cable in Pocket Pad on your Mac."
        case .wifi: return "Join the same Wi-Fi network. Choose Wi-Fi on your Mac, select this phone, and enter the code."
        case .bluetooth: return "Choose Bluetooth on your Mac, select this phone, and enter the code. Allow Bluetooth when asked."
        }
    }

    private func page(compact: Bool) -> some View {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                        Text(step == 4 && server.setupStage == .controls ? "Finish setup on your Mac." : titles[step]).font(.system(size: compact ? 25 : 32, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(step == 4 && server.setupStage == .controls ? "Choose your controls on your Mac. Your controller will open when you start playing." : step == 2 ? connectionInstructions : step == 3 && moved && tapped ? "Nice. Check your Mac to finish the connection test." : details[step]).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if step == 2 {
                            Label(server.connected ? "Connected to your Mac" : server.status,
                                  systemImage: server.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                                .font(.headline).foregroundStyle(server.connected ? PadAppearance.accent : .secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if step == 2 && server.transport != .usb {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Phone name", text: $deviceName).textFieldStyle(.plain).font(.headline)
                                    .onSubmit { server.renameDevice(deviceName) }
                                    .onDisappear { if deviceName != WirelessSettings.deviceName() { server.renameDevice(deviceName) } }
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                            Text(server.pairingCode).font(.system(size: 32, weight: .medium, design: .monospaced))
                            if server.transport == .wifi { Text(server.wifiAddress).font(.callout).foregroundStyle(.secondary) }
                        }.frame(width: 238)
                    } else {
                        illustration.frame(width: step == 3 ? 238 : 140)
                    }
                }
    }

    private func sendPractice() {
        // Paused frames are visible in the Mac monitor but never submitted to game output.
        var state = GamepadState.paused
        if step == 3 {
            state.leftX = GamepadState.axis(Double(offset.width / 35))
            state.leftY = GamepadState.axis(Double(-offset.height / 35))
            state.set(.south, pressed: pressed)
        }
        server.update(state)
    }

    @ViewBuilder private var illustration: some View {
        if step == 3 {
            HStack(spacing: 28) {
                PracticeStick(offset: offset)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let length = hypot(value.translation.width, value.translation.height)
                        let scale = length > 35 ? 35 / length : 1
                        offset = CGSize(width: value.translation.width * scale, height: value.translation.height * scale)
                        if length > 15 { moved = true }
                        sendPractice()
                    }.onEnded { _ in offset = .zero; sendPractice() })
                    .accessibilityLabel("Practice stick")
                    .accessibilityAction(named: "Move stick") {
                        moved = true; offset = CGSize(width: 25, height: 0); sendPractice()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            offset = .zero; sendPractice()
                        }
                    }
                PracticeButton(pressed: pressed)
                    .accessibilityHidden(true)
                    .overlay {
                        PracticeTouchButton { down in
                            pressed = down
                            if down { tapped = true }
                            sendPractice()
                        }
                    }
            }
        } else {
            Image(systemName: ["iphone.and.arrow.forward", "", "cable.connector", "", "slider.horizontal.3"][step])
                .font(.system(size: 52, weight: .light)).foregroundStyle(.primary)
                .accessibilityHidden(true)
        }
    }
}
