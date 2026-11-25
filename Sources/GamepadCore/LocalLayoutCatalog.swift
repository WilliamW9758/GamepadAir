import Foundation

public struct LocalLayoutCatalog: Codable, Equatable {
    public var storageVersion = 1
    public var layouts: [LocalLayout]
    public var selectedID: String
    public var activeModes: [String: String]
    public static func fresh() -> Self {
        let values = PadStyle.allCases.map { style -> LocalLayout in
            var value = LocalLayout(name: style.rawValue, style: style)
            value.isPreset = true; return value
        }
        return Self(layouts: values, selectedID: values[0].id, activeModes: [:])
    }
    public func validate() throws {
        guard storageVersion == 1, !layouts.isEmpty, layouts.count <= 500,
              Set(layouts.map(\.id)).count == layouts.count,
              layouts.contains(where: { $0.id == selectedID }),
              layouts.allSatisfy({ UUID(uuidString: $0.id) != nil }) else { throw LayoutDocumentError("Invalid local layout catalog") }
        for layout in layouts { try layout.document.validate() }
        for (id, modeID) in activeModes {
            guard let layout = layouts.first(where: { $0.id == id }), layout.document.modes.contains(where: { $0.id == modeID }) else { throw LayoutDocumentError("Invalid active mode") }
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16 * 1024 * 1024 else { throw LayoutDocumentError("Local catalog is too large") }
        // Validate original document bytes before Codable has a chance to discard unknown fields.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: ["storageVersion", "layouts", "selectedID", "activeModes"]),
              let values = root["layouts"] as? [[String: Any]] else { throw LayoutDocumentError("Invalid local catalog") }
        for value in values {
            guard Set(value.keys).isSubset(of: ["id", "document", "provenance", "editRevision", "isPreset", "modifiedAt"]), let doc = value["document"] else { throw LayoutDocumentError("Invalid local layout") }
            _ = try LayoutDocument.decode(JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys, .withoutEscapingSlashes]))
        }
        let result = try JSONDecoder().decode(Self.self, from: data); try result.validate(); return result
    }
    public func save(to url: URL) throws {
        try validate()
        let data = try JSONEncoder().encode(self)
        _ = try Self.decode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    public mutating func importDocument(_ data: Data, provenance: LayoutProvenance? = nil) throws {
        let layout = try LocalLayout.importDocument(data, provenance: provenance)
        var next = self; next.layouts.append(layout); next.selectedID = layout.id
        try next.validate(); self = next
    }
    public mutating func delete(_ id: String) throws {
        guard let index = layouts.firstIndex(where: { $0.id == id }), !layouts[index].isPreset else { throw LayoutDocumentError("Preset layouts cannot be deleted") }
        layouts.remove(at: index); activeModes[id] = nil
        if layouts.isEmpty { self = .fresh() }
        else if selectedID == id { selectedID = layouts[min(index, layouts.count - 1)].id }
    }
    public func activeMode(for layout: LocalLayout) -> String { activeModes[layout.id] ?? layout.document.initialMode }
}

public struct DocumentLayoutHistory {
    private var past: [LocalLayoutCatalog] = []
    private var future: [LocalLayoutCatalog] = []
    private var highWater: [String: UInt64] = [:]
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    private mutating func remember(_ value: LocalLayoutCatalog) {
        for layout in value.layouts { highWater[layout.id] = max(highWater[layout.id] ?? 0, layout.editRevision) }
    }
    public mutating func record(_ value: LocalLayoutCatalog) {
        remember(value)
        if past.last != value { past.append(value) }
        if past.count > 50 { past.removeFirst() }
        future.removeAll()
    }
    // Undo restores content, not revision counters. Revisions must never go backwards.
    private func restoring(_ snapshot: LocalLayoutCatalog, current: LocalLayoutCatalog) throws -> LocalLayoutCatalog {
        var result = snapshot
        for i in result.layouts.indices {
            let id = result.layouts[i].id
            let previous = current.layouts.first { $0.id == id }?.editRevision ?? 0
            let revision = max(previous, max(highWater[id] ?? 0, result.layouts[i].editRevision))
            guard revision < UInt64.max else { throw LayoutDocumentError("Layout revision limit reached") }
            result.layouts[i].editRevision = revision + 1
            result.layouts[i].modifiedAt = Date()
        }
        return result
    }
    public mutating func undo(_ current: LocalLayoutCatalog) throws -> LocalLayoutCatalog? {
        guard let value = past.last else { return nil }
        let restored = try restoring(value, current: current)
        remember(current); remember(restored); past.removeLast(); future.append(current); return restored
    }
    public mutating func redo(_ current: LocalLayoutCatalog) throws -> LocalLayoutCatalog? {
        guard let value = future.last else { return nil }
        let restored = try restoring(value, current: current)
        remember(current); remember(restored); future.removeLast(); past.append(current); return restored
    }
}
