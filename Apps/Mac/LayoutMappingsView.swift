import SwiftUI

/// Edits a draft; the phone acknowledges and persists the complete layout atomically.
struct LayoutMappingsView: View {
    let source: SavedLayout
    @State private var draft: SavedLayout
    let save: (SavedLayout, SavedLayout) -> Void
    init(source: SavedLayout, fallbackType: LayoutInputType, keyboard: KeyboardProfile, gamepad: GamepadProfile, save: @escaping (SavedLayout, SavedLayout) -> Void) {
        self.source = source; self.save = save
        var value = source
        value.inputType = value.inputType ?? fallbackType
        value.keyboardProfile = value.keyboardProfile ?? keyboard
        value.gamepadProfile = value.gamepadProfile ?? gamepad
        _draft = State(initialValue: value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(draft.name) · \(draft.effectiveInputType.title)").font(.headline)
                Spacer()
                Button(source.isPreset ? "Save as copy" : "Save mappings") { save(draft, source) }
            }.padding(.horizontal, 24).padding(.top, 16)
            if !draft.unmappedControls.isEmpty {
                Text("Needs mapping: " + draft.unmappedControls.map(\.label).joined(separator: ", "))
                    .foregroundStyle(.red).padding(.horizontal, 24)
            }
            if draft.effectiveInputType == .gamepad {
                GamepadMappingEditor(profile: Binding(get: { draft.gamepadProfile ?? GamepadProfile() }, set: { draft.gamepadProfile = $0 }), embedded: true)
            } else {
                MappingEditor(profile: Binding(get: { draft.keyboardProfile ?? .starter }, set: { draft.keyboardProfile = $0 }), embedded: true)
            }
        }.onChange(of: source) { _, value in draft = value }
    }
}

struct LayoutCreationView: View {
    @Binding var name: String
    @Binding var type: LayoutInputType
    @Binding var source: SavedLayout?
    let style: PadStyle
    let create: (SavedLayout) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(source == nil ? "New layout" : "Duplicate layout").font(.title2)
            TextField("Layout name", text: $name)
            Picker("Input type", selection: $type) {
                ForEach(LayoutInputType.allCases) { Text($0.title).tag($0) }
            }
            if let source, source.effectiveInputType != type {
                Text("Compatible inputs carry over. Red controls need a mapping before they can send input.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    var layout = source?.converted(to: type) ?? SavedLayout(name: name, style: style)
                    layout.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    layout.inputType = type
                    if source == nil { layout.cursorSwitching = false; layout.keyboardProfile = .starter; layout.gamepadProfile = GamepadProfile() }
                    create(layout)
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 420).buttonStyle(PadActionStyle())
    }
}
