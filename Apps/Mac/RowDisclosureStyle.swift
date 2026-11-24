import SwiftUI

struct RowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                    configuration.label
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}
