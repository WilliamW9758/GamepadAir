import SwiftUI

struct GamepadMappingEditor: View {
    @Binding var profile: GamepadProfile
    var embedded = false
    var advancedOnly = false
    var labels: [MappedControl: String] = [:]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !advancedOnly { HStack {
                Text("Gamepad controls").font(.title2)
                Spacer()
                if !embedded { Button("Done") { dismiss() } }
            }
            Text("Mappings affect virtual gamepad mode only. Sticks retain analog movement. Custom and radial buttons can reuse a gamepad input; keyboard hotkeys require keyboard/mouse mode.").font(.callout).foregroundStyle(.secondary)
            }
            Form {
                if !advancedOnly {
                Toggle("Enable left stick", isOn: Binding(get: { profile.disableLeftStick != true }, set: { profile.disableLeftStick = !$0 }))
                Toggle("Enable right stick", isOn: Binding(get: { profile.disableRightStick != true }, set: { profile.disableRightStick = !$0 }))
                }
                Toggle("Swap left and right sticks", isOn: $profile.swapSticks)
                Toggle("Invert left stick Y", isOn: $profile.invertLeftY)
                Toggle("Invert right stick Y", isOn: $profile.invertRightY)
                if !advancedOnly { ForEach(GamepadProfile.controls, id: \.self) { source in
                    Picker(labels[source] ?? source.label, selection: Binding(get: { profile[source]?.rawValue ?? "none" }, set: { profile[source] = MappedControl(rawValue: $0) })) {
                        Text("Unassigned").tag("none")
                        ForEach(GamepadProfile.destinations, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                }
                }
            }.formStyle(.grouped)
        }.padding(24).frame(width: embedded ? nil : 560, height: embedded ? nil : 620).background { PadBackdrop() }.buttonStyle(PadActionStyle())
    }
}
