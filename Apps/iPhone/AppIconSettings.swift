import SwiftUI

struct AppIconSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = UIApplication.shared.alternateIconName
    @State private var changing = false
    @State private var errorMessage: String?
    private let choices = ["Red", "White", "Graphite"]

    var body: some View {
        Section("App icon") {
            HStack(spacing: 24) {
                ForEach(choices, id: \.self) { name in
                    let iconName: String? = name == "Red" ? nil : "AppIcon" + name
                    Button { change(to: iconName) } label: {
                        VStack(spacing: 8) {
                            preview(name).resizable().renderingMode(.original).scaledToFit()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(selected == iconName ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected == iconName ? 3 : 1))
                            Text(name).font(.body)
                            Image(systemName: selected == iconName ? "checkmark.circle.fill" : "circle")
                        }.frame(minWidth: 74)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name + " app icon")
                    .accessibilityAddTraits(selected == iconName ? [.isSelected] : [])
                    .disabled(changing || !UIApplication.shared.supportsAlternateIcons)
                }
            }.padding(.vertical, 8)
            if changing { ProgressView("Changing icon…") }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .onAppear { selected = UIApplication.shared.alternateIconName }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { selected = UIApplication.shared.alternateIconName }
        }
    }

    private func preview(_ name: String) -> Image {
        // The SDK-only device installer bundles PNGs; Xcode uses Assets.car.
        if let url = Bundle.main.url(forResource: "IconPreview" + name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }
        return Image("IconPreview" + name)
    }

    private func change(to name: String?) {
        guard !changing, UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return }
        changing = true; errorMessage = nil
        UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                changing = false
                selected = UIApplication.shared.alternateIconName
                if let error { errorMessage = "Couldn’t change the icon. " + error.localizedDescription }
            }
        }
    }
}
