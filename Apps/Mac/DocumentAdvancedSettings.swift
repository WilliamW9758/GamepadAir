import SwiftUI

struct DocumentAdvancedSettings: View {
    @Binding var document: LayoutDocument
    @State private var error: String?
    private func keyboard<T>(_ key: WritableKeyPath<DocumentKeyboardSettings, T?>, _ fallback: T) -> Binding<T> {
        Binding(get: { document.keyboard?[keyPath: key] ?? fallback }, set: { value in
            var next = document; if next.keyboard == nil { next.keyboard = DocumentKeyboardSettings() }
            next.keyboard?[keyPath: key] = value; document = next
        })
    }
    private func gamepad(_ key: WritableKeyPath<DocumentGamepadSettings, Bool?>) -> Binding<Bool> {
        Binding(get: { document.gamepad?[keyPath: key] ?? false }, set: { value in
            var next = document; if next.gamepad == nil { next.gamepad = DocumentGamepadSettings() }
            next.gamepad?[keyPath: key] = value; document = next
        })
    }
    var body: some View {
        Form {
            Picker("Button haptics", selection: Binding(get: { document.haptics ?? "medium" }, set: { document.haptics = $0 })) {
                Text("Off").tag("off"); Text("Light").tag("light"); Text("Medium").tag("medium"); Text("Strong").tag("strong")
            }
            if document.inputType == "gamepad" {
                Toggle("Swap sticks", isOn: gamepad(\.swapSticks))
                Toggle("Invert left Y", isOn: gamepad(\.invertLeftY))
                Toggle("Invert right Y", isOn: gamepad(\.invertRightY))
            } else {
                Toggle("Auto-run beyond left-stick threshold", isOn: Binding(get: { document.keyboard?.autoRunEnabled ?? false }, set: { enabled in
                    var next = document
                    if next.keyboard == nil { next.keyboard = DocumentKeyboardSettings() }
                    if enabled && next.keyboard?.autoRunAction == nil {
                        do { try next.rebind(.autoRun, outputs: ["key.shift"]) } catch { self.error = error.localizedDescription; return }
                    }
                    next.keyboard?.autoRunEnabled = enabled; document = next
                }))
                if document.keyboard?.autoRunEnabled == true {
                    Slider(value: keyboard(\.autoRunThreshold, 0.8), in: 0.2...0.95) { Text("Run threshold") }
                    ComboBindingEditor(binding: Binding(get: {
                        let action = document.keyboard?.autoRunAction.flatMap { document.actions[$0] }
                        return KeyBinding(action?.outputs.compactMap(OutputToken.init(documentOutput:)) ?? [])
                    }, set: { value in
                        do { var next = document; try next.rebind(.autoRun, outputs: value.outputs.map(\.documentOutput)); document = next }
                        catch { self.error = error.localizedDescription }
                    }))
                }
                Toggle("Relative game aiming", isOn: keyboard(\.relativeGameAim, true))
                Toggle("Invert vertical aiming", isOn: keyboard(\.invertMouseY, false))
                Slider(value: keyboard(\.mouseSpeed, 900), in: 100...2400) { Text("Mouse speed") }
                Slider(value: keyboard(\.mouseSmoothing, 0.025), in: 0...0.08) { Text("Aim smoothing") }
                Picker("Mouse updates", selection: keyboard(\.mouseUpdateRate, 1000)) { ForEach([250, 500, 1000], id: \.self) { Text("\($0) Hz").tag($0) } }
                Slider(value: keyboard(\.stickThreshold, 0.35), in: 0.15...0.8) { Text("Direction threshold") }
                Slider(value: keyboard(\.comboGap, 0.03), in: 0.01...0.1) { Text("Combo spacing") }
                Slider(value: keyboard(\.tapDuration, 0.12), in: 0.05...0.5) { Text("Tap duration") }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.formStyle(.grouped)
    }
}

struct DocumentMotionSettingsView: View {
    @Binding var document: LayoutDocument
    var body: some View {
        Form {
            Section("Motion") {
                Picker("Motion behavior", selection: Binding(get: { document.motion?.mode ?? "off" }, set: { value in
                    if document.motion == nil { document.motion = DocumentMotionSettings() }
                    document.motion?.mode = value
                    if value != "off" { try? document.revealMotionActivation(modeID: document.initialMode) }
                })) {
                    Text("Off").tag("off"); Text("Gyro aim").tag("aim")
                    if document.inputType == "gamepad" { Text("Analog steering").tag("steering") }
                }
                if (document.motion?.mode ?? "off") != "off" {
                Picker("Activation button", selection: Binding(get: { document.motionActivationControl?.id ?? "" }, set: { value in
                    if document.motion == nil { document.motion = DocumentMotionSettings() }
                    document.motion?.activationControl = value
                    try? document.revealMotionActivation(modeID: document.initialMode)
                })) {
                    ForEach(document.motionActivationControls, id: \.id) { control in
                        Text(LocalLayout(document: document).displayLabels(modeID: document.initialMode)[control.runtimeID] ?? control.id).tag(control.id)
                    }
                }
                Slider(value: Binding(get: { document.motion?.sensitivity ?? 1 }, set: { if document.motion == nil { document.motion = DocumentMotionSettings() }; document.motion?.sensitivity = $0 }), in: 0.1...4) { Text("Sensitivity") }
                Slider(value: Binding(get: { document.motion?.deadZone ?? 0.03 }, set: { if document.motion == nil { document.motion = DocumentMotionSettings() }; document.motion?.deadZone = $0 }), in: 0...0.3) { Text("Dead zone") }
                Text("Hold the selected button to calibrate and activate motion. Release to stop; hold again to recalibrate. The button keeps its normal mapping. Aim moves the mouse or right stick; steering controls left X. Requires a physical iPhone.").foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
}
