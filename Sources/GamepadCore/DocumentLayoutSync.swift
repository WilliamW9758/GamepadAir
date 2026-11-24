import Foundation

public struct DocumentLayoutSnapshot: Codable, Equatable {
    public var protocolVersion = 2
    public var layout: LocalLayout
    public var activeModeID: String
    public var screen: PhoneScreen?
    public var catalog: [DocumentLayoutSummary]
    public var acknowledgment: DocumentLayoutAcknowledgment?
    public init(layout: LocalLayout, activeModeID: String, catalog: [DocumentLayoutSummary] = []) {
        self.layout = layout; self.activeModeID = activeModeID; self.catalog = catalog
    }
    public func validate() throws {
        guard protocolVersion == 2 else { throw LayoutDocumentError("Update Pocket Pad on both devices: layout sync versions differ") }
        guard UUID(uuidString: layout.id) != nil, catalog.count <= 500, Set(catalog.map(\.id)).count == catalog.count,
              catalog.allSatisfy({ UUID(uuidString: $0.id) != nil }) else { throw LayoutDocumentError("Invalid layout identity") }
        try layout.document.validate()
        guard layout.document.modes.contains(where: { $0.id == activeModeID }) else { throw LayoutDocumentError("Unknown active mode") }
        if let screen {
            guard screen.width.isFinite, screen.height.isFinite, (200...3000).contains(screen.width), (200...3000).contains(screen.height) else { throw LayoutDocumentError("Invalid phone canvas") }
        }
    }
}
public struct DocumentLayoutSummary: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var isPreset: Bool
    public var editRevision: UInt64
    public init(_ layout: LocalLayout) { id = layout.id; name = layout.name; isPreset = layout.isPreset; editRevision = layout.editRevision }
}
public struct DocumentLayoutAcknowledgment: Codable, Equatable {
    public var commandID: String
    public var error: String?
    public var layoutID: String?
    public var editRevision: UInt64?
    public init(commandID: String, error: String? = nil, layoutID: String? = nil, editRevision: UInt64? = nil) {
        self.commandID = commandID; self.error = error; self.layoutID = layoutID; self.editRevision = editRevision
    }
}
public struct DocumentLayoutCommand: Codable, Equatable {
    public enum Action: String, Codable { case select, create, save, delete, selectMode, clear }
    public var protocolVersion = 2
    public var id = UUID().uuidString
    public var action: Action
    public var layoutID: String?
    public var baseEditRevision: UInt64?
    public var document: LayoutDocument?
    public var provenance: LayoutProvenance?
    public var activeModeID: String?
    public var catalogRevisions: [String: UInt64]?
    public init(action: Action, layoutID: String? = nil, baseEditRevision: UInt64? = nil, document: LayoutDocument? = nil, activeModeID: String? = nil, catalogRevisions: [String: UInt64]? = nil, provenance: LayoutProvenance? = nil) {
        self.action = action; self.layoutID = layoutID; self.baseEditRevision = baseEditRevision
        self.document = document; self.activeModeID = activeModeID; self.catalogRevisions = catalogRevisions; self.provenance = provenance
    }
}

/// Session-scoped idempotency. A repeated command ID is acknowledged without replaying a mutation.
public struct DocumentLayoutCommandProcessor {
    private var acknowledgments: [String: DocumentLayoutAcknowledgment] = [:]
    public init() {}
    public mutating func apply(_ command: DocumentLayoutCommand, to catalog: inout LocalLayoutCatalog) -> DocumentLayoutAcknowledgment {
        if let previous = acknowledgments[command.id] { return previous }
        guard acknowledgments.count < 4096 else { return DocumentLayoutAcknowledgment(commandID: command.id, error: "Reconnect to start a new layout editing session") }
        var result = DocumentLayoutAcknowledgment(commandID: command.id)
        do {
            try command.validate()
            var next = catalog
            if command.action == .create {
                guard let document = command.document else { throw LayoutDocumentError("Missing layout document") }
                try document.validate()
                let local = LocalLayout(document: document, provenance: command.provenance)
                next.layouts.append(local); next.selectedID = local.id; result.layoutID = local.id; result.editRevision = 0
            } else {
                guard let id = command.layoutID, let index = next.layouts.firstIndex(where: { $0.id == id }) else { throw LayoutDocumentError("Layout no longer exists") }
                guard command.baseEditRevision == next.layouts[index].editRevision else { throw LayoutDocumentError("Layout changed on the phone. Refresh before editing.") }
                switch command.action {
                case .save:
                    guard let document = command.document else { throw LayoutDocumentError("Missing layout document") }
                    try next.layouts[index].edit(baseRevision: command.baseEditRevision!) { $0 = document }
                    let allowed = next.layouts[index].document.modes.map(\.id)
                    if let selected = next.activeModes[id], !allowed.contains(selected) { next.activeModes[id] = nil }
                case .delete: try next.delete(id)
                case .clear:
                    guard command.catalogRevisions == Dictionary(uniqueKeysWithValues: next.layouts.map { ($0.id, $0.editRevision) }) else { throw LayoutDocumentError("Layouts changed on the phone. Refresh before clearing.") }
                    next = .fresh()
                case .select: next.selectedID = id
                case .selectMode:
                    guard let mode = command.activeModeID, next.layouts[index].document.modes.contains(where: { $0.id == mode }) else { throw LayoutDocumentError("Unknown mode") }
                    next.activeModes[id] = mode
                case .create: break
                }
                result.layoutID = id; result.editRevision = next.layouts.first { $0.id == id }?.editRevision
            }
            try next.validate(); catalog = next
        } catch { result.error = error.localizedDescription }
        acknowledgments[command.id] = result
        return result
    }
}
