import SwiftUI
import AppKit
import Carbon

/// Additional slots are a chord, not separate controller inputs.
struct ComboBindingEditor: View {
    @Binding var binding: KeyBinding
    @State private var adding = false
    @State private var recording = false
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
                Button("Record shortcut…") { recording = true }
                if !binding.outputs.isEmpty && binding.outputs.count < 4 {
                    Button("Add to combo") { adding = true }.disabled(adding)
                }
                Spacer()
                ForEach([KeyBinding.Behavior.hold, .tap], id: \.self) { behavior in
                    Button(behavior == .hold ? "Hold" : "Tap") { binding.behavior = behavior }
                        .buttonStyle(PadActionStyle(prominent: binding.behavior == behavior))
                }
            }
            if SystemShortcutConflict.matches(binding.outputs) {
                Label("This shortcut conflicts with a macOS system shortcut.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if binding.outputs.count > 1 {
                Text("Combo: " + binding.outputs.map(\.label).joined(separator: " + "))
                    .foregroundStyle(.secondary)
            }
        }.font(.system(size: 14))
            .sheet(isPresented: $recording) {
                ShortcutRecorder { outputs in binding.outputs = outputs; adding = false }
            }
    }
}

/// A local event monitor consumes key events before menu shortcuts or text fields see them.
/// The surrounding mapping editor pauses Pocket Pad output throughout this sheet.
private struct ShortcutRecorder: View {
    @Environment(\.dismiss) private var dismiss
    let save: ([OutputToken]) -> Void
    @State private var outputs: [OutputToken] = []
    @State private var monitor: Any?
    @State private var captured = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record shortcut").font(.headline)
            if !message.isEmpty { Text(message).foregroundStyle(.orange) }
            Text(outputs.isEmpty ? "Waiting for keys…" : outputs.map(\.label).joined(separator: " + "))
                .font(.title2).frame(minHeight: 40)
            if SystemShortcutConflict.matches(outputs) {
                Label("This shortcut conflicts with a macOS system shortcut.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Button("Start over") { outputs = []; captured = false; message = "" }
                Spacer()
                Button("Use shortcut") { save(outputs); dismiss() }.disabled(outputs.isEmpty)
            }
        }.padding(24).frame(width: 480)
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
                    if event.type == .keyDown && event.keyCode == 53 { dismiss(); return nil }
                    if event.type == .keyDown && !event.isARepeat && !captured {
                        let modifiers: [(NSEvent.ModifierFlags, OutputToken)] = [(.control, .control), (.option, .option), (.shift, .shift), (.command, .command)]
                        for (flag, token) in modifiers where event.modifierFlags.contains(flag) { append(token) }
                        if let token = OutputToken.allCases.first(where: { $0.keyCode == event.keyCode }) { append(token) }
                        else { message = "This key is unsupported. Choose another key or Cancel." }
                    } else if event.type == .flagsChanged && !captured {
                        let pairs: [(NSEvent.ModifierFlags, OutputToken)] = [(.control, .control), (.option, .option), (.shift, .shift), (.command, .command)]
                        for (flag, token) in pairs where event.modifierFlags.contains(flag) { append(token) }
                    }
                    if !outputs.isEmpty && (event.type == .keyUp || (event.type == .flagsChanged && event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty)) {
                        captured = true
                    }
                    return nil
                }
            }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in dismiss() }
    }
    private func append(_ token: OutputToken) {
        guard !outputs.contains(token) else { return }
        guard outputs.count < 4 else { message = "Four-key limit reached. Start over to replace the shortcut."; return }
        outputs.append(token)
    }
}


/// Reads enabled, user-configured macOS shortcuts rather than assuming defaults.
private enum SystemShortcutConflict {
    static func matches(_ outputs: [OutputToken]) -> Bool {
        let modifierTokens: Set<OutputToken> = [.command, .shift, .option, .control]
        let keys = outputs.filter { !modifierTokens.contains($0) }
        guard keys.count == 1, let key = keys[0].keyCode else { return false }
        var modifiers = 0
        for (token, flag) in [(OutputToken.command, cmdKey), (.shift, shiftKey), (.option, optionKey), (.control, controlKey)] where outputs.contains(token) { modifiers |= flag }
        var hotKeys: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&hotKeys) == noErr, let entries = hotKeys?.takeRetainedValue() as? [[String: Any]] {
            if entries.contains(where: {
                ($0[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
                ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.intValue == Int(key) &&
                ($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.intValue == modifiers
            }) { return true }
        }
        // App switching and force-quit are not listed among configurable symbolic hotkeys.
        return (key == 48 && (modifiers == cmdKey || modifiers == cmdKey | shiftKey)) ||
            (key == 53 && modifiers == cmdKey | optionKey)
    }
}
