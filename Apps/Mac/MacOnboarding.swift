import SwiftUI

struct MacOnboarding: View {
    @Binding var transport: LinkTransport
    let finish: () -> Void
    @State private var step = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Label("Gamepad Air", systemImage: "gamecontroller")
                Spacer()
                Button("Skip tour", action: finish)
            }
            HStack(spacing: 8) {
                ForEach(0..<4) { index in Capsule().fill(index <= step ? Color.primary : Color.primary.opacity(0.08)).frame(height: 3) }
            }.accessibilityLabel("Step \(step + 1) of 4")
            Spacer()
            if step == 1 {
                Text("Choose your connection.").font(.system(size: 32, weight: .medium))
                ConnectionChoices(selection: $transport)
                Text("Choose the same connection on your iPhone.").foregroundStyle(.secondary)
            } else {
            Image(systemName: ["iphone.and.arrow.forward", "", "checkmark.circle", "slider.horizontal.3"][step])
                .font(.system(size: 56, weight: .light)).foregroundStyle(.primary)
            Text(["Your next controller is already in your pocket.", "", "Try it before you play.", "Start simple. Make it yours."][step])
                .font(.system(size: 32, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text([
                "Open Gamepad Air on your iPhone. We’ll connect the devices, check your controls, and help you choose how your game receives input.",
                "",
                "Move a stick and press a button on your phone. The Mac will show what arrives, without sending input to your game. Then choose a virtual gamepad or keyboard and mouse.",
                "Use your current layout to get started. Later, hold the gear on your phone to arrange controls. On your Mac, open Settings to change mappings. Your saved layouts are preserved."
            ][step]).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                if step == 0 { CompanionAppPrompt() }
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Button(step == 3 ? "Connect my phone" : "Continue") {
                    if step == 3 { finish() } else { step += 1 }
                }.buttonStyle(PadActionStyle(prominent: true)).controlSize(.large)
            }
        }.padding(32).frame(width: 610, height: 470).padGlass().padding(30).frame(width: 670, height: 530)
            .background { PadBackdrop() }.tint(PadAppearance.accent)
            .interactiveDismissDisabled().buttonStyle(PadActionStyle())
    }
}
