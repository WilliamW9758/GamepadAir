import SwiftUI

struct MappingEditor: View {
    @Binding var profile: KeyboardProfile
    @Environment(\.dismiss) private var dismiss
    @State private var selection: MappedControl? = .east
    @State private var confirmReset = false
    private var control: MappedControl { selection ?? .east }
    private var binding: KeyBinding { profile[control] }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Keyboard & mouse mappings").font(.title2.bold())
                    Text("Changes save automatically. USB output is stopped while you edit.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { profile = profile.sanitized; dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack(alignment: .top, spacing: 20) {
                List(MappedControl.allCases, id: \.self, selection: $selection) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.label)
                        Text(profile[item].summary).font(.caption).foregroundStyle(.secondary)
                    }.tag(item)
                }.frame(width: 205, height: 410)
                VStack(alignment: .leading, spacing: 16) {
                    Text(control.label).font(.title3.bold())
                    if MappedControl.customControls.contains(control) {
                        Text("Add this numbered custom slot in iPhone Edit layout → Buttons. Its phone label can be renamed independently. Slots 1–8 default to quick-bar keys 1–8.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Press inputs in this order; release them in reverse. Up to four keys or mouse buttons can be combined.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Scroll up/down: Tap scrolls one step; Hold repeats after a short delay.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(0..<4) { index in
                        Picker("Input \(index + 1)", selection: token(at: index)) {
                            Text("None").tag(nil as OutputToken?)
                            ForEach(OutputToken.allCases, id: \.self) { token in Text(token.label).tag(Optional(token)) }
                        }
                    }
                    if control != .autoRun {
                    Picker("Behavior", selection: Binding(get: { binding.behavior }, set: { value in
                        var b = binding; b.behavior = value; profile[control] = b
                    })) {
                        Text("Hold while pressed").tag(KeyBinding.Behavior.hold)
                        Text("Tap once per press").tag(KeyBinding.Behavior.tap)
                    }.pickerStyle(.segmented)
                    Text(binding.behavior == .tap ? "A tap completes even if you lift your finger quickly. Holding the button does not repeat it." : "All inputs release when you lift your finger. Shared inputs stay held if another virtual control still needs them.")
                        .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Auto-run holds these inputs while the stick is outside the run threshold. Enable it below.").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("RMB + Space (dodge)") { profile[control] = KeyBinding([.mouseRight, .space], behavior: .tap) }
                        Button("Clear") { profile[control] = KeyBinding() }
                    }
                    if [.rightUp, .rightRight, .rightDown, .rightLeft].contains(control) && profile.rightStickMouse {
                        Text("Right-stick direction mappings are inactive while right-stick mouse aiming is enabled.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-run beyond left-stick threshold", isOn: Binding(get: { profile.autoRunEnabled ?? false }, set: { profile.autoRunEnabled = $0 }))
                HStack {
                    ZStack {
                        Circle().stroke(.secondary.opacity(0.4), lineWidth: 1)
                        Circle().stroke(.mint, style: StrokeStyle(lineWidth: 2, dash: [3]))
                            .scaleEffect(profile.runThreshold)
                    }.frame(width: 42, height: 42).accessibilityLabel("Circular run threshold")
                    Text("Run radius")
                    Slider(value: Binding(get: { profile.runThreshold }, set: { profile.autoRunThreshold = $0 }), in: 0.2...0.95, step: 0.01)
                    Text("\(Int((profile.runThreshold * 100).rounded()))%").monospacedDigit().frame(width: 45)
                    Button("Run mapping…") { selection = .autoRun }
                }.disabled(!(profile.autoRunEnabled ?? false))
                Text("Holds \(profile[.autoRun].summary) beyond the circle in any direction. Releases 5% inside it to prevent flicker.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Right stick moves the mouse", isOn: $profile.rightStickMouse)
                    Picker("Mouse updates", selection: Binding(get: { profile.updateRate }, set: { profile.mouseUpdateRate = $0 })) {
                        Text("250 Hz").tag(250)
                        Text("500 Hz").tag(500)
                        Text("1000 Hz").tag(1000)
                    }
                    Toggle("Relative game aiming (prevent cursor drift)", isOn: Binding(get: { profile.usesRelativeGameAim }, set: { profile.relativeGameAim = $0 }))
                    Text("On for camera aiming. Turn off to move the visible cursor in menus.").font(.caption2).foregroundStyle(.secondary)
                    Toggle("Invert vertical aiming", isOn: $profile.invertMouseY)
                    HStack {
                        Text("Mouse speed").frame(width: 100, alignment: .leading)
                        Slider(value: $profile.mouseSpeed, in: 100...2400, step: 50)
                        Text("\(Int(profile.mouseSpeed)) px/s").monospacedDigit().frame(width: 85)
                    }
                    HStack {
                        Text("Stick threshold").frame(width: 100, alignment: .leading)
                        Slider(value: $profile.stickThreshold, in: 0.15...0.8, step: 0.05)
                        Text("\(Int((profile.stickThreshold * 100).rounded()))%").monospacedDigit().frame(width: 85)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    timing("Aim smoothing", value: Binding(get: { profile.smoothingTime }, set: { profile.mouseSmoothing = $0 }), range: 0...0.08)
                    timing("Combo spacing", value: $profile.comboGap, range: 0.01...0.1)
                    timing("Tap duration", value: $profile.tapDuration, range: 0.05...0.5)
                }.frame(width: 230)
            }.font(.caption)
            HStack {
                Text("Key names use US physical positions. Match bindings to your game settings.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore starter bindings", role: .destructive) { confirmReset = true }
            }
        }
        .padding(24)
        }.frame(width: 790, height: 760)
        .confirmationDialog("Replace all mappings with the starter bindings?", isPresented: $confirmReset) {
            Button("Restore starter bindings", role: .destructive) { profile = .starter }
        }
    }
    private func token(at index: Int) -> Binding<OutputToken?> {
        Binding(get: { index < binding.outputs.count ? binding.outputs[index] : nil }, set: { value in
            var slots = binding.outputs.map(Optional.some)
            while slots.count < 4 { slots.append(nil) }
            slots[index] = value
            profile[control] = KeyBinding(slots.compactMap { $0 }, behavior: binding.behavior)
            profile = profile.sanitized
        })
    }
    private func timing(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label): \(Int((value.wrappedValue * 1000).rounded())) ms")
            Slider(value: value, in: range, step: 0.01)
        }
    }
}
