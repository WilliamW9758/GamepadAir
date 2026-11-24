import SwiftUI

struct ConnectionChoices: View {
    @Binding var selection: LinkTransport

    var body: some View {
        HStack(spacing: 12) {
            ForEach(LinkTransport.allCases, id: \.self) { transport in
                Button { selection = transport } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: transport == .usb ? "cable.connector" : transport == .wifi ? "wifi" : "antenna.radiowaves.left.and.right")
                            Spacer()
                            Image(systemName: selection == transport ? "checkmark.circle.fill" : "circle")
                        }.foregroundStyle(selection == transport ? PadAppearance.accent : .secondary)
                        Text(transport.rawValue).font(.headline)
                        Text(transport == .usb ? "Direct & reliable" : transport == .wifi ? "Same Wi-Fi network" : "No Wi-Fi needed")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(transport == .usb ? "Recommended" : "Wireless")
                            .font(.callout).foregroundStyle(transport == .usb ? PadAppearance.accent : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(selection == transport ? PadAppearance.accent.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selection == transport ? PadAppearance.accent : Color.primary.opacity(0.1), lineWidth: selection == transport ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == transport ? .isSelected : [])
            }
        }
    }
}

/// Compact transport choices for everyday reconnection.
struct ConnectionPills: View {
    @Binding var selection: LinkTransport
    var body: some View {
        HStack(spacing: 8) {
            ForEach(LinkTransport.allCases, id: \.self) { transport in
                Button { selection = transport } label: {
                    Label(transport.rawValue, systemImage: transport == .usb ? "cable.connector" : transport == .wifi ? "wifi" : "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PadActionStyle(prominent: selection == transport))
                .accessibilityAddTraits(selection == transport ? .isSelected : [])
            }
        }
    }
}
