import Foundation

/// All mutations are validated and durably written before becoming visible to callers.
/// This store intentionally never reads the old development layout/preferences keys.
public final class LayoutDocumentStore {
    public private(set) var catalog: LocalLayoutCatalog
    public private(set) var history = DocumentLayoutHistory()
    public let url: URL
    private var commands = DocumentLayoutCommandProcessor()
    private var editStart: LocalLayoutCatalog?

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 16 * 1024 * 1024 else {
                throw LayoutDocumentError("Local catalog is too large")
            }
            catalog = try LocalLayoutCatalog.decode(Data(contentsOf: url))
        } else {
            catalog = .fresh()
            try catalog.save(to: url)
        }
    }
    public var selected: LocalLayout { catalog.layouts.first { $0.id == catalog.selectedID }! }
    public var activeModeID: String { catalog.activeMode(for: selected) }

    public func beginEdit() { if editStart == nil { editStart = catalog } }
    public func endEdit() {
        if let start = editStart, start != catalog { history.record(start) }
        editStart = nil
    }
    private func commit(_ next: LocalLayoutCatalog, record: Bool = true) throws {
        guard next != catalog else { return }
        try next.save(to: url)
        if record && editStart == nil { history.record(catalog) }
        catalog = next
    }
    public func edit(_ command: (inout LayoutDocument) throws -> Void) throws {
        var next = catalog
        guard let index = next.layouts.firstIndex(where: { $0.id == next.selectedID }) else { throw LayoutDocumentError("No selected layout") }
        let revision = next.layouts[index].editRevision
        try next.layouts[index].edit(baseRevision: revision, command)
        if let mode = next.activeModes[next.selectedID], !next.layouts[index].document.modes.contains(where: { $0.id == mode }) {
            next.activeModes[next.selectedID] = nil
        }
        try commit(next)
    }
    public func select(_ id: String) throws {
        endEdit()
        guard catalog.layouts.contains(where: { $0.id == id }) else { throw LayoutDocumentError("Unknown layout") }
        var next = catalog; next.selectedID = id
        try commit(next, record: false)
    }
    public func selectMode(_ id: String) throws {
        endEdit()
        guard selected.document.modes.contains(where: { $0.id == id }) else { throw LayoutDocumentError("Unknown mode") }
        var next = catalog; next.activeModes[selected.id] = id
        try commit(next, record: false)
    }
    public func duplicate(name: String) throws {
        let copy = try selected.duplicate(name: name)
        var next = catalog; next.layouts.append(copy); next.selectedID = copy.id
        try commit(next)
    }
    public func create(_ document: LayoutDocument, provenance: LayoutProvenance? = nil) throws {
        try importDocument(document.validatedData(), provenance: provenance)
    }
    public func importDocument(_ data: Data, provenance: LayoutProvenance? = nil) throws {
        var next = catalog; try next.importDocument(data, provenance: provenance)
        try commit(next)
    }
    public func delete(_ id: String) throws {
        var next = catalog; try next.delete(id)
        try commit(next)
    }
    /// Reconcile a confirmed device copy, retaining its shared identity and edit timestamp.
    public func receive(_ layout: LocalLayout, replacing oldID: String? = nil, select: Bool = false) throws {
        var next = catalog
        if let oldID, oldID != layout.id { next.layouts.removeAll { $0.id == oldID }; next.activeModes[oldID] = nil }
        if let index = next.layouts.firstIndex(where: { $0.id == layout.id }) { next.layouts[index] = layout }
        else { next.layouts.append(layout) }
        if select || !next.layouts.contains(where: { $0.id == next.selectedID }) { next.selectedID = layout.id }
        if let mode = next.activeModes[layout.id], !layout.document.modes.contains(where: { $0.id == mode }) { next.activeModes[layout.id] = nil }
        try commit(next)
    }
    public func resetLayouts() throws {
        try commit(.fresh(), record: false)
        history = DocumentLayoutHistory(); editStart = nil
    }
    public func undo() throws {
        endEdit(); var nextHistory = history
        if let next = try nextHistory.undo(catalog) {
            try commit(next, record: false); history = nextHistory
        }
    }
    public func redo() throws {
        endEdit(); var nextHistory = history
        if let next = try nextHistory.redo(catalog) {
            try commit(next, record: false); history = nextHistory
        }
    }
    public func apply(_ command: DocumentLayoutCommand) -> DocumentLayoutAcknowledgment {
        // Keep the idempotency ledger in step with the durable catalog. A failed disk
        // write must never produce a successful acknowledgment or poison a retry.
        var nextCommands = commands; var next = catalog
        let result = nextCommands.apply(command, to: &next)
        guard result.error == nil else { commands = nextCommands; return result }
        do {
            try commit(next)
            commands = nextCommands
            return result
        } catch {
            return DocumentLayoutAcknowledgment(commandID: command.id, error: error.localizedDescription)
        }
    }
}
