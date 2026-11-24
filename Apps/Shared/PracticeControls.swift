import SwiftUI

struct PracticeStick: View {
    var offset = CGSize.zero
    var body: some View {
        Circle().fill(.primary.opacity(0.05)).frame(width: 110, height: 110)
            .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
            .overlay(Circle().fill(PadAppearance.accent).frame(width: 40, height: 40).offset(offset))
    }
}

struct PracticeButton: View {
    var pressed = false
    var body: some View {
        Text("A").font(.title).foregroundStyle(pressed ? Color.white : Color.primary)
            .frame(width: 70, height: 70)
            .background(pressed ? PadAppearance.accent : PadAppearance.accent.opacity(0.15), in: Circle())
            .overlay(Circle().strokeBorder(PadAppearance.accent.opacity(0.35)))
    }
}
