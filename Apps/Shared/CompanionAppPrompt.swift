import SwiftUI

/// Keep setup focused; installation help is available without adding another step.
struct CompanionAppPrompt: View {
    @State private var showing = false
    #if os(macOS)
    private let device = "iPhone"
    private let symbol = "iphone"
    private let downloadURL = AppInformation.iPhoneBetaURL
    private let downloadTitle = "Join the iPhone beta"
    private let instructions = "Open this link on your iPhone, install TestFlight, then install Gamepad Air. Requires iOS 17 or later."
    #else
    private let device = "Mac"
    private let symbol = "laptopcomputer"
    private let downloadURL = AppInformation.macDownloadURL
    private let downloadTitle = "Get the Mac download"
    private let instructions = "Open the download page on your Mac, download the DMG, and drag Gamepad Air to Applications. Requires macOS 15 or later."
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
                    Text("Gamepad Air for \(device)").font(.headline)
                    Spacer()
                    Button { showing = false } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }
                Text("Gamepad Air needs an app on both your iPhone and Mac.")
                Text(instructions)
                    .foregroundStyle(.secondary)
                Link(downloadTitle, destination: downloadURL)
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
                Text("Get Gamepad Air on your \(device).")
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
