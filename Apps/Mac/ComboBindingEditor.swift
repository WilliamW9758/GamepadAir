import SwiftUI

/// Additional slots are a chord, not separate controller inputs.
struct ComboBindingEditor: View {
    @Binding var binding: KeyBinding
    @State private var adding = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<max(1, binding.outputs.count + (adding && binding.outputs.count < 4 ? 1 : 0)), id: \.self) { index in
                HStack(spacing: 12) {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
                    Text(index == 0 ? "Key or mouse button" : "Together with").frame(width: 155, alignment: .leading)
                    Picker("Key or mouse button", selection: Binding<OutputToken?>(get: {
                        index < binding.outputs.count ? binding.outputs[index] : nil
                    }, set: { token in
                        if index < binding.outputs.count {
                            if let token { binding.outputs[index] = token } else { binding.outputs.remove(at: index) }
                        } else if let token { binding.outputs.append(token) }
                        adding = false
                    })) {
                        Text("Unmapped").tag(nil as OutputToken?)
                        ForEach(OutputToken.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }.labelsHidden().frame(maxWidth: 220)
                    if index < binding.outputs.count || adding {
                        Button("Remove", role: .destructive) {
                            if index < binding.outputs.count { binding.outputs.remove(at: index) }
                            adding = false
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                if index + 1 < max(1, binding.outputs.count + (adding && binding.outputs.count < 4 ? 1 : 0)) { Divider() }
            }
            HStack {
                if !binding.outputs.isEmpty && binding.outputs.count < 4 {
                    Button("Add to combo") { adding = true }.disabled(adding)
                }
                Spacer()
                ForEach([KeyBinding.Behavior.hold, .tap], id: \.self) { behavior in
                    Button(behavior == .hold ? "Hold" : "Tap") { binding.behavior = behavior }
                        .buttonStyle(PadActionStyle(prominent: binding.behavior == behavior))
                }
            }
            if binding.outputs.count > 1 {
                Text("Combo: " + binding.outputs.map(\.label).joined(separator: " + "))
                    .foregroundStyle(.secondary)
            }
        }.font(.system(size: 14))
    }
}
