import Foundation

public enum LayoutBindingReference: Equatable {
    case control(id: String, direction: String)
    case autoRun
}

extension LayoutDocument {
    public func actionID(for reference: LayoutBindingReference) -> String? {
        switch reference {
        case .autoRun: return keyboard?.autoRunAction
        case .control(let id, let direction): return controls.first { $0.id == id }?.bindings?[direction]
        }
    }
    public func references(to actionID: String) -> Int {
        controls.reduce(0) { $0 + ($1.bindings ?? [:]).values.filter { $0 == actionID }.count }
            + (keyboard?.autoRunAction == actionID ? 1 : 0)
    }
    /// A radial aliases a custom control, so it deliberately does not count as an independent action reference.
    public mutating func rebind(_ reference: LayoutBindingReference, outputs: [String], behavior: String = "hold") throws {
        var next = self
        let oldID = actionID(for: reference)
        let id: String
        if let oldID, references(to: oldID) == 1 { id = oldID }
        else { id = next.uniqueActionID(base: oldID ?? "action") }
        next.actions[id] = DocumentAction(label: oldID.flatMap { actions[$0]?.label } ?? "Input", outputs: outputs, behavior: behavior)
        switch reference {
        case .autoRun:
            if next.keyboard == nil { next.keyboard = DocumentKeyboardSettings() }
            next.keyboard?.autoRunAction = id
        case .control(let controlID, let direction):
            guard let i = next.controls.firstIndex(where: { $0.id == controlID }) else { throw LayoutDocumentError("Unknown control") }
            if next.controls[i].bindings == nil { next.controls[i].bindings = [:] }
            next.controls[i].bindings?[direction] = id
        }
        try next.validate(); self = next
    }
    private func uniqueActionID(base: String) -> String {
        let stem = String(base.prefix(38))
        if actions[stem] == nil { return stem }
        var index = 2
        while actions["\(stem)-\(index)"] != nil { index += 1 }
        return "\(stem)-\(index)"
    }
    public mutating func renameControl(_ id: String, caption: String?, modeID: String? = nil) throws {
        var next = self
        guard let i = next.controls.firstIndex(where: { $0.id == id }) else { throw LayoutDocumentError("Unknown control") }
        if let modeID {
            guard let m = next.modes.firstIndex(where: { $0.id == modeID }) else { throw LayoutDocumentError("Unknown mode") }
            var overrides = next.modes[m].overrides ?? [:]
            var value = overrides[id] ?? DocumentOverride()
            value.label = caption.map { .value($0) } ?? .null
            overrides[id] = value; next.modes[m].overrides = overrides
        } else { next.controls[i].label = caption }
        try next.validate(); self = next
    }
    public mutating func placeControl(_ id: String, at placement: DocumentPlacement, modeID: String) throws {
        var next = self
        guard controls.contains(where: { $0.id == id }), let selected = modes.first(where: { $0.id == modeID }) else { throw LayoutDocumentError("Unknown control or mode") }
        for i in next.modes.indices where next.modes[i].id == modeID || (linkedControls ?? []).contains(id) {
            var p = placement
            let previous = resolvedControl(id, modeID: modeID)?.placement
            if p.width == nil { p.width = previous?.width; p.height = previous?.height }
            if next.modes[i].id != modeID && p.width == nil && controls.first(where: { $0.id == id })?.role != "trackpad" {
                p.scale = (placement.scale ?? 1) * (selected.sizeFactor ?? 1) / (next.modes[i].sizeFactor ?? 1)
                // Linked edits must remain representable; never silently clamp stored geometry.
            }
            var overrides = next.modes[i].overrides ?? [:]
            var value = overrides[id] ?? DocumentOverride(); value.placement = .value(p)
            overrides[id] = value; next.modes[i].overrides = overrides
        }
        try next.validate(); self = next
    }
    public mutating func removeControl(_ id: String) throws {
        var next = self
        if next.motionActivationControl?.id == id { next.motion?.activationControl = nil; next.motion?.mode = "off" }
        next.controls.removeAll { $0.id == id }
        next.linkedControls?.removeAll { $0 == id }
        for i in next.modes.indices { next.modes[i].overrides?[id] = nil }
        for i in next.controls.indices { next.controls[i].radialSlots = next.controls[i].radialSlots?.filter { $0.value != id } }
        try next.validate(); self = next
    }
    /// Explicit cleanup only. Decoding and ordinary edits preserve unreferenced action metadata.
    public mutating func removeUnusedActions() { actions = actions.filter { references(to: $0.key) > 0 } }
    public func nextMode(after id: String) -> String {
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return initialMode }
        return modes[(index + 1) % modes.count].id
    }
    public func resolvedControl(_ id: String, modeID: String) -> DocumentControl? {
        guard var value = controls.first(where: { $0.id == id }) else { return nil }
        guard let override = modes.first(where: { $0.id == modeID })?.overrides?[id] else { return value }
        if let p = override.placement { switch p { case .null: value.placement = nil; case .value(let p): value.placement = p } }
        if let label = override.label { switch label { case .null: value.label = nil; case .value(let label): value.label = label } }
        if let feedback = override.feedback { switch feedback { case .null: value.feedback = nil; case .value(let f): value.feedback = f } }
        if let hidden = override.hidden { value.hidden = hidden }
        return value
    }
}

public struct LayoutProvenance: Codable, Equatable {
    public var publicationID: String
    public var revisionID: String
    /// Origin digest, never recomputed to pretend an edited copy still matches its publication.
    public var digest: String
    public init(publicationID: String, revisionID: String, digest: String) {
        self.publicationID = publicationID; self.revisionID = revisionID; self.digest = digest
    }
}

public struct LocalLayout: Codable, Equatable, Identifiable {
    public var id: String
    public var document: LayoutDocument
    public var provenance: LayoutProvenance?
    public var editRevision: UInt64
    public var modifiedAt: Date?
    public var isPreset: Bool
    public init(document: LayoutDocument, provenance: LayoutProvenance? = nil, isPreset: Bool = false) {
        id = UUID().uuidString; self.document = document; self.provenance = provenance
        editRevision = 0; self.isPreset = isPreset; modifiedAt = Date()
    }
    public func duplicate(name: String) throws -> Self {
        var value = LocalLayout(document: document, provenance: provenance)
        value.document.name = name; try value.document.validate(); return value
    }
    public mutating func edit(baseRevision: UInt64, _ command: (inout LayoutDocument) throws -> Void) throws {
        guard !isPreset, baseRevision == editRevision, editRevision < UInt64.max else { throw LayoutDocumentError("Layout changed; reload before editing") }
        var next = document; try command(&next); try next.validate()
        if next != document { document = next; editRevision += 1; modifiedAt = Date() }
    }
    public static func importDocument(_ data: Data, provenance: LayoutProvenance? = nil) throws -> Self {
        Self(document: try LayoutDocument.decode(data), provenance: provenance)
    }
}
