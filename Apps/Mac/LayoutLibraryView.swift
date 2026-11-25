import SwiftUI

struct LibraryConflict: Identifiable {
    let mac: LocalLayout
    let phone: LocalLayout
    var id: String { phone.id }
    var newerPlatform: String? {
        guard let a = mac.modifiedAt, let b = phone.modifiedAt, abs(a.timeIntervalSince(b)) > 1 else { return nil }
        return a > b ? "Mac" : "iPhone"
    }
}

extension HostModel {
    func refreshLibrary() {
        guard let store = layoutStore else { return }
        localLayouts = store.catalog.layouts; portable = store.selected; libraryModeID = store.activeModeID
    }
    func selectLibrary(_ id: String) {
        unreadGeneratedLayouts.remove(id)
        do { try layoutStore?.select(id); refreshLibrary() }
        catch { profileNotice = error.localizedDescription }
    }
    func createLibrary(_ layout: LocalLayout, aiPrompt: String? = nil) {
        do {
            guard let store = layoutStore else { throw LayoutDocumentError("Local library unavailable.") }
            try store.receive(layout, select: true); refreshLibrary()
            if let aiPrompt {
                aiPreviewRequests[layout.id] = aiPrompt
                generatingLayouts.insert(layout.id)
                // Preview only. A real service must validate its returned document before saving it.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, self.generatingLayouts.remove(layout.id) != nil,
                          self.localLayouts.contains(where: { $0.id == layout.id }) else { return }
                    self.unreadGeneratedLayouts.insert(layout.id)
                }
            } else { syncLibrarySelection() }
        }
        catch { profileNotice = error.localizedDescription }
    }
    func saveLibrary(_ value: LocalLayout, base: LocalLayout) {
        guard let store = layoutStore else { return }
        do {
            guard let existing = store.catalog.layouts.first(where: { $0.id == base.id }), existing.editRevision == base.editRevision, existing.document == base.document else { throw LayoutDocumentError("This layout changed. Reload it before saving.") }
            try store.select(base.id)
            if base.isPreset { try store.duplicate(name: value.name + " Copy") }
            try store.edit { $0 = value.document }; refreshLibrary()
            profileNotice = "Saved on Mac."
            syncLibrarySelection()
        } catch { profileNotice = error.localizedDescription }
    }
    func selectLibraryMode(_ id: String) {
        do {
            try layoutStore?.selectMode(id); refreshLibrary()
            if let local = portable, let phone = phoneLayouts[local.id], local.document == phone.document, update.connected {
                sendLayout(LayoutCommand(action: .selectMode, layoutID: phone.id, baseEditRevision: phone.editRevision, activeModeID: id))
            }
        } catch { profileNotice = error.localizedDescription }
    }
    func deleteLibrary(_ id: String) {
        do { try layoutStore?.delete(id); hiddenPhoneLayoutIDs.insert(id); UserDefaults.standard.set(Array(hiddenPhoneLayoutIDs), forKey: "library-hidden-phone-layouts"); refreshLibrary(); profileNotice = "Deleted from this Mac. The iPhone copy is unchanged." }
        catch { profileNotice = error.localizedDescription }
    }
    func syncLibrarySelection() {
        guard update.connected, let layout = portable, !generatingLayouts.contains(layout.id) else { return }
        guard !layoutConflicts.contains(where: { $0.mac.id == layout.id || $0.phone.id == layout.id }) else {
            profileNotice = "Choose which version to keep before syncing."; return
        }
        guard layoutCommandID == nil else { profileNotice = "Saved on Mac. Use Send to iPhone when the current update finishes."; return }
        if let phone = phoneLayouts[layout.id] {
            let action: LayoutCommand.Action = phone.document == layout.document ? .select : .save
            sendLayout(LayoutCommand(action: action, layoutID: phone.id, baseEditRevision: phone.editRevision, document: action == .save ? layout.document : nil))
        } else {
            sendLayout(LayoutCommand(action: .create, layoutID: layout.id, document: layout.document, provenance: layout.provenance))
        }
    }
    func receiveLibrarySnapshot(_ snapshot: DocumentLayoutSnapshot) {
        if let screen = snapshot.screen, screen != libraryScreen {
            libraryScreen = screen
            if let data = try? JSONEncoder().encode(screen) { UserDefaults.standard.set(data, forKey: "library-phone-screen") }
        }
        let ack = snapshot.acknowledgment
        let confirmed = pendingLibraryCommand.flatMap { command in ack?.commandID == command.id ? command : nil }
        if confirmed != nil { pendingLibraryCommand = nil }
        func ingest(_ phone: LocalLayout, accepted: Bool = false) {
            phoneLayouts[phone.id] = phone
            guard !hiddenPhoneLayoutIDs.contains(phone.id) else { return }
            guard let store = layoutStore else { return }
            if phone.isPreset && store.catalog.layouts.contains(where: { $0.isPreset && $0.id != phone.id && $0.document == phone.document }) { return }
            let local = store.catalog.layouts.first { $0.id == phone.id } ?? store.catalog.layouts.first { !$0.isPreset && !phone.isPreset && $0.name.caseInsensitiveCompare(phone.name) == .orderedSame }
            if let local, local.document != phone.document, !accepted {
                if !layoutConflicts.contains(where: { $0.id == phone.id && $0.mac == local && $0.phone == phone }) {
                    layoutConflicts.removeAll { $0.id == phone.id }
                    layoutConflicts.append(LibraryConflict(mac: local, phone: phone))
                }
                return
            }
            do {
                // Matching content can safely share the phone revision without creating an edit.
                try store.receive(phone, replacing: local?.id)
                refreshLibrary()
            } catch { profileNotice = error.localizedDescription }
        }
        let accepting = confirmed != nil && ack?.error == nil && (confirmed?.action == .save || confirmed?.action == .create)
        // An old telemetry frame must not become a conflict while our save awaits acknowledgment.
        if pendingLibraryCommand?.layoutID != snapshot.layout.id || pendingLibraryCommand?.action != .save {
            ingest(snapshot.layout, accepted: accepting && confirmed?.layoutID == snapshot.layout.id)
        }
        if let fetched = ack?.fetchedLayout { ingest(fetched) }
        if accepting, let id = ack?.layoutID {
            layoutConflicts.removeAll { $0.phone.id == id }
            if confirmed?.action == .save, snapshot.layout.id != id {
                sendLayout(LayoutCommand(action: .select, layoutID: id, baseEditRevision: ack?.editRevision))
            }
        }
        if layoutCommandID == nil, let summary = snapshot.catalog.first(where: { phoneLayouts[$0.id]?.editRevision != $0.editRevision }) {
            sendLayout(LayoutCommand(action: .fetch, layoutID: summary.id, baseEditRevision: summary.editRevision))
        }
    }
    func resolveLibraryConflict(_ conflict: LibraryConflict, keepMac: Bool) {
        guard let store = layoutStore else { return }
        do {
            guard let current = store.catalog.layouts.first(where: { $0.id == conflict.mac.id }), current == conflict.mac,
                  phoneLayouts[conflict.phone.id] == conflict.phone else { throw LayoutDocumentError("A version changed. Compare the updated copies before continuing.") }
            if keepMac {
                var chosen = conflict.phone
                chosen.document = conflict.mac.document; chosen.modifiedAt = conflict.mac.modifiedAt
                try store.receive(chosen, replacing: conflict.mac.id, select: true)
                layoutConflicts.removeAll { $0.id == conflict.id }; libraryEditorID = UUID(); refreshLibrary(); syncLibrarySelection()
            } else {
                try store.receive(conflict.phone, replacing: conflict.mac.id, select: true)
                layoutConflicts.removeAll { $0.id == conflict.id }; libraryEditorID = UUID(); refreshLibrary()
            }
        } catch { profileNotice = error.localizedDescription }
    }
    func keepBothLibraryVersions(_ conflict: LibraryConflict) {
        do {
            if conflict.mac.id == conflict.phone.id {
                let copy = try conflict.mac.duplicate(name: conflict.mac.name + " (Mac copy)")
                try layoutStore?.receive(copy)
            }
            try layoutStore?.receive(conflict.phone)
            layoutConflicts.removeAll { $0.id == conflict.id }; libraryEditorID = UUID(); refreshLibrary()
        } catch { profileNotice = error.localizedDescription }
    }
}

struct LayoutLibraryView: View {
    @ObservedObject var model: HostModel
    let create: () -> Void
    let duplicate: (LocalLayout) -> Void
    let delete: (LocalLayout) -> Void
    @State private var isDirty = false
    @State private var notification: String?
    @State private var notificationIsWarning = false
    @State private var lastEditorNotice: String?
    private func showStatus(_ text: String?) {
        guard let text else { return }
        notification = text; notificationIsWarning = false
    }
    private func showEditorNotice(_ text: String?) {
        if let text { notification = text; notificationIsWarning = true }
        else if notificationIsWarning && notification == lastEditorNotice { notification = nil; notificationIsWarning = false }
        lastEditorNotice = text
    }
    @State private var pendingSelection: String?
    @State private var olderChoice: (LibraryConflict, Bool)?
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("My layouts").font(.headline); Spacer(); Button(action: create) { Image(systemName: "plus") }.help("New layout") }.padding(.horizontal, 12)
                List(selection: Binding(get: { model.portable?.id }, set: { if let id = $0 { model.unreadGeneratedLayouts.remove(id); if id != model.portable?.id { if isDirty { pendingSelection = id } else { model.selectLibrary(id) } } } })) {
                    ForEach(model.localLayouts) { layout in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(layout.name).font(.headline)
                                Spacer()
                                if model.generatingLayouts.contains(layout.id) { Image(systemName: "sparkles").symbolEffect(.pulse, options: .repeating).accessibilityLabel("Generating preview") }
                                else if model.unreadGeneratedLayouts.contains(layout.id) { Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel("New layout ready") }
                            }
                            Text(layout.isPreset ? "Preset" : layout.effectiveInputType.title).font(.callout).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(layout.id)
                            .simultaneousGesture(TapGesture().onEnded { model.unreadGeneratedLayouts.remove(layout.id) })
                    }
                }.listStyle(.sidebar)
            }.padding(.top, 16).frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
            VStack(alignment: .leading, spacing: 0) {
                if let conflict = model.layoutConflicts.first {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Two versions of “\(conflict.mac.name)”").font(.headline)
                        Text(conflict.newerPlatform.map { "\($0) has the newer edit, based on the saved edit times." } ?? "These edits cannot be reliably ordered.")
                        Text("Mac: \(date(conflict.mac.modifiedAt)) · iPhone: \(date(conflict.phone.modifiedAt))").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Keep Mac version") { choose(conflict, mac: true) }
                            Button("Keep iPhone version") { choose(conflict, mac: false) }
                            Button("Keep both") { model.keepBothLibraryVersions(conflict) }
                        }.disabled(model.layoutCommandID != nil)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12))
                }
                if let layout = model.portable, model.generatingLayouts.contains(layout.id) {
                    VStack(spacing: 20) {
                        Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(Color.accentColor).symbolEffect(.pulse, options: .repeating)
                        Text("Preparing your layout preview…").font(.title2)
                        Text(model.aiPreviewRequests[layout.id] ?? "").foregroundStyle(.secondary)
                        Text("AI generation preview · No AI request is sent yet.").font(.callout).foregroundStyle(.secondary)
                    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let layout = model.portable {
                    if model.aiPreviewRequests[layout.id] != nil {
                        Text("AI preview complete · This is a sample starter layout, not an AI-generated result.").font(.callout).foregroundStyle(.secondary).padding(16)
                    }
                    HStack {
                        Spacer()
                        Button("Duplicate") { duplicate(layout) }
                        Button("Delete…", role: .destructive) { delete(layout) }.disabled(layout.isPreset)
                        if model.update.connected { Button("Send to iPhone") { model.syncLibrarySelection() }.disabled(model.layoutCommandID != nil) }
                    }.padding(16)
                    Text(notification ?? "Saved on Mac.")
                        .font(.callout)
                        .foregroundStyle(notificationIsWarning ? Color.orange : Color.secondary)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
                        .help(notification ?? "Saved on Mac.")
                        .padding(.horizontal, 16)
                    LayoutEditor(layout: layout, embedded: true, modeID: model.libraryModeID, screen: model.libraryScreen, selectMode: model.selectLibraryMode, dirtyChanged: { isDirty = $0 }, noticeChanged: showEditorNotice) { edited, base in
                        model.saveLibrary(edited, base: base)
                    }.id(layout.id + model.libraryEditorID.uuidString)
                } else { ContentUnavailableView("Local library unavailable", systemImage: "exclamationmark.triangle", description: Text(model.profileNotice ?? "Saved data could not be opened.")) }
            }.frame(minWidth: 500)
        }
        .onReceive(model.$profileNotice) { showStatus($0) }
        .onReceive(model.$layoutCommandNotice) { showStatus($0) }
        .onChange(of: model.portable?.id) { _, _ in
            notification = nil; notificationIsWarning = false; lastEditorNotice = nil
        }
        .confirmationDialog("Discard unsaved layout edits?", isPresented: Binding(get: { pendingSelection != nil }, set: { if !$0 { pendingSelection = nil } }), titleVisibility: .visible) {
            Button("Discard edits", role: .destructive) { if let id = pendingSelection { model.selectLibrary(id) }; pendingSelection = nil; isDirty = false }
        }
        .confirmationDialog("Keep the older version?", isPresented: Binding(get: { olderChoice != nil }, set: { if !$0 { olderChoice = nil } }), titleVisibility: .visible) {
            if let choice = olderChoice { Button("Replace newer version", role: .destructive) { model.resolveLibraryConflict(choice.0, keepMac: choice.1); olderChoice = nil } }
        } message: { Text("This replaces the newer edits. Choose Keep both if you want to preserve both versions.") }
    }
    private func choose(_ conflict: LibraryConflict, mac: Bool) {
        if let newer = conflict.newerPlatform, (mac ? "Mac" : "iPhone") != newer { olderChoice = (conflict, mac) }
        else { model.resolveLibraryConflict(conflict, keepMac: mac) }
    }
    private func date(_ value: Date?) -> String { value?.formatted(date: .abbreviated, time: .shortened) ?? "Edit time unavailable" }
}
