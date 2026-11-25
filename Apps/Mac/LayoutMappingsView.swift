import SwiftUI

struct LayoutCreationView: View {
    @Binding var name: String
    @Binding var type: LayoutInputType
    @Binding var source: LocalLayout?
    let style: PadStyle
    var startWithAI = false
    let create: (LocalLayout, String?) -> Void
    @State private var useAI = false
    @State private var prompt = ""
    @State private var error: String?
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
            if source == nil {
                Toggle(isOn: $useAI) { Label("Start with AI help", systemImage: "sparkles") }.toggleStyle(.button)
                if useAI {
                    TextField("What game and scenario? For example, Valheim building with quick access to tools…", text: $prompt, axis: .vertical)
                        .lineLimit(3...5).textFieldStyle(.roundedBorder)
                    Text("UI preview · AI generation isn’t connected yet. This creates a sample starter layout, not a tailored result.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    do {
                        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let document = try source?.document.converted(to: type, name: title) ?? LayoutDocument.starter(name: title, style: style, input: type)
                        create(LocalLayout(document: document, provenance: source?.provenance), useAI ? prompt.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
                    } catch { self.error = error.localizedDescription }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (useAI && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(24).frame(width: 420).buttonStyle(PadActionStyle()).onAppear { useAI = startWithAI }
    }
}
