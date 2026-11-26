import SwiftUI

/// Returning users can connect immediately or dismiss this card to edit offline.
struct PhoneConnectionView: View {
    @ObservedObject var server: CableServer
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Connect to your Mac.").font(.title2.weight(.semibold))
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "chevron.down").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Minimize connection")
            }
            ConnectionPills(selection: Binding(get: { server.transport }, set: {
                server.selectTransport($0)
                server.update(.paused)
            }))
            if server.transport == .usb {
                Label("Plug into your Mac, then open Gamepad Air.", systemImage: "cable.connector")
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(WirelessSettings.deviceName()).font(.headline)
                        Text("Select this iPhone on your Mac.").foregroundStyle(.secondary)
                        if server.transport == .wifi {
                            Text(server.wifiAddress).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pairing code").foregroundStyle(.secondary)
                        Text(WirelessSettings.formattedCode(server.pairingCode))
                            .font(.system(size: 28, weight: .medium, design: .monospaced))
                    }
                }.frame(minHeight: 72)
            }
            if let issue = server.connectionIssue {
                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { server.selectTransport(server.transport) }
            }
            HStack {
                Spacer()
                Button("Use disconnected", action: dismiss).buttonStyle(PadActionStyle())
            }.frame(height: 44)
        }
        .padding(20).frame(maxWidth: 620).padGlass().padding(16)
    }
}
