import SwiftUI

/// Local interaction prototype. No model request or marketplace search is sent.
struct LayoutAssistantView: View {
    @ObservedObject var model: HostModel
    let openMarketplace: () -> Void
    @State private var request = ""
    @State private var response = "Describe the layout you want, or try a sample edit below."
    @State private var draft: LocalLayout?
    @State private var base: LocalLayout?
    @State private var summary: String?
    private var snapshot: ControllerSnapshot? { model.update.layout }
    private var canApply: Bool {
        model.update.connected && model.layoutCommandID == nil && draft != nil && base == snapshot?.layout
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(draft == nil ? "On your iPhone" : "Proposed layout", systemImage: "iphone")
                        .font(.headline)
                    Spacer()
                    Text(model.update.connected ? "Connected" : "Disconnected").foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.top, 20)
                if let layout = draft ?? snapshot?.layout {
                    Text(layout.name).font(.title3).padding(.horizontal, 24)
                    LayoutEditor(layout: layout, embedded: true, liveState: draft == nil ? model.update.state : .neutral,
                                 modeID: snapshot?.activeModeID, screen: snapshot?.screen) { _, _ in }
                    if let summary {
                        Text(summary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                        HStack {
                            Button("Discard") { draft = nil; base = nil; self.summary = nil }
                            Spacer()
                            Button(base?.isPreset == true ? "Apply as a copy on iPhone" : "Apply to iPhone", action: apply)
                                .buttonStyle(PadActionStyle(prominent: true)).disabled(!canApply)
                        }.padding(24)
                    }
                    if draft != nil && base != snapshot?.layout {
                        Text("The phone’s layout changed. Choose a sample again to refresh the preview.")
                            .foregroundStyle(.orange).padding(.horizontal, 24)
                    }
                } else {
                    ContentUnavailableView("Connect your iPhone", systemImage: "iphone",
                        description: Text("Your layout and proposed changes will appear here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let notice = model.layoutCommandNotice {
                    Text(notice).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 16)
                }
            }.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Layout assistant", systemImage: "sparkles").font(.title3.weight(.semibold))
                    Spacer()
                    Text("Preview").font(.callout).foregroundStyle(.secondary)
                }
                Text("AI isn’t connected yet. Sample edits work locally; applying them sends the layout to your paired iPhone.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(response).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Try a sample").font(.headline)
                        Button("Make controls 15% larger") { preview(larger: true) }
                        Button("Use lighter button feedback") { preview(larger: false) }
                        Button("Find community layouts") { openMarketplace() }
                        Button("Manage account") { openMarketplace() }
                        Text("AI generation is not available yet. It will require sign-in; community browsing and downloads do not.").font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                TextField("Ask about your layout…", text: $request, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("Preview request", action: submit).disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Preview changes here, apply them, then try them on your iPhone.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
    }

    private func submit() {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        response = "Free-form requests will be available when the AI service is connected. For now, try one of the sample edits to preview and apply a real layout change."
    }
    private func preview(larger: Bool) {
        guard let source = snapshot?.layout, model.update.connected else {
            response = "Connect your iPhone first so I can show a sample using your current layout."; return
        }
        var next = source
        if larger {
            for index in next.document.modes.indices { next.document.modes[index].sizeFactor = min(3, (next.document.modes[index].sizeFactor ?? 1) * 1.15) }
            summary = "Increase all control sizes by 15% (up to the size limit). Positions and mappings stay the same."
        } else {
            next.document.haptics = "light"
            summary = "Use Light touch feedback for this layout. Game rumble stays the same."
        }
        base = source; draft = next
        response = "Here’s a local sample preview. Apply it to update your phone, or discard it to keep your current layout."
    }
    private func apply() {
        guard canApply, var draft, let base else { return }
        if base.isPreset {
            draft.name += " Custom"; draft.isPreset = false
            model.sendLayout(LayoutCommand(action: .create, document: draft.document, provenance: draft.provenance))
        } else {
            model.sendLayout(LayoutCommand(action: .save, layoutID: base.id, baseEditRevision: base.editRevision, document: draft.document))
        }
        guard model.layoutCommandID != nil else { return }
        self.draft = nil; self.base = nil; summary = nil
        response = "Sent to your iPhone. The preview will reflect its confirmed layout when it replies."
    }
}
