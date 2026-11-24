import SwiftUI

/// Keep setup focused; installation help is available without adding another step.
struct CompanionAppPrompt: View {
    @State private var showing = false
    #if os(macOS)
    private let device = "iPhone"
    private let symbol = "iphone"
    #else
    private let device = "Mac"
    private let symbol = "laptopcomputer"
    #endif

    var body: some View {
        Button { showing = true } label: {
            Label("Get the \(device) app", systemImage: symbol)
        }
        .buttonStyle(PadActionStyle())
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: symbol).font(.title)
                    Text("Pocket Pad for \(device)").font(.headline)
                    Spacer()
                    Button { showing = false } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }
                Text("Pocket Pad needs an app on both your iPhone and Mac.")
                Text("Public downloads are coming soon. For this preview, install the companion from the project’s setup guide.")
                    .foregroundStyle(.secondary)
                Link("Open setup guide", destination: AppInformation.projectURL)
                    .buttonStyle(PadActionStyle(prominent: true))
            }
            .padding(24).frame(width: 330)
            #if os(iOS)
            .presentationCompactAdaptation(.popover)
            #endif
        }
    }
}

/// The first setup step on both devices, before choosing a connection.
struct CompanionSetupCard: View {
    #if os(macOS)
    private let device = "iPhone"
    private let symbol = "iphone"
    #else
    private let device = "Mac"
    private let symbol = "laptopcomputer"
    #endif

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Get Pocket Pad on your \(device).")
                    .font(.system(size: 28, weight: .medium))
                Text("One app on each device. Then you’re ready to connect.")
                    .foregroundStyle(.secondary)
                CompanionAppPrompt()
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: symbol).font(.system(size: 52, weight: .light))
                .frame(width: 100).accessibilityHidden(true)
        }
    }
}
