import Foundation
import CoreFoundation

/// The transport envelope is separate from the downloadable layout document.
/// Its byte bound includes catalog summaries and local provenance.
public enum DocumentLayoutTransport {
    public static let maximumBytes = 768 * 1024
    private static func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard data.count <= maximumBytes,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: keys) else { throw LayoutDocumentError("Invalid layout sync envelope") }
        guard let version = root["protocolVersion"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version == 5 else {
            throw LayoutDocumentError("Update Gamepad Air on both devices: layout sync versions differ")
        }
        return root
    }
    public static func decodeCommand(_ data: Data) throws -> DocumentLayoutCommand {
        let root = try object(data, keys: ["protocolVersion", "id", "action", "layoutID", "baseEditRevision", "document", "activeModeID", "catalogRevisions", "provenance"])
        if let document = root["document"], !(document is NSNull) {
            _ = try LayoutDocument.decode(JSONSerialization.data(withJSONObject: document))
        }
        let value = try JSONDecoder().decode(DocumentLayoutCommand.self, from: data)
        try value.validate(); return value
    }
    public static func decodeSnapshot(_ data: Data) throws -> DocumentLayoutSnapshot {
        let root = try object(data, keys: ["protocolVersion", "layout", "activeModeID", "screen", "catalog", "acknowledgment"])
        guard let layout = root["layout"] as? [String: Any],
              Set(layout.keys).isSubset(of: ["id", "document", "provenance", "editRevision", "isPreset", "modifiedAt"]),
              let document = layout["document"] else { throw LayoutDocumentError("Missing layout") }
        _ = try LayoutDocument.decode(JSONSerialization.data(withJSONObject: document))
        if let ack = root["acknowledgment"] as? [String: Any], let fetched = ack["fetchedLayout"] as? [String: Any], let document = fetched["document"] {
            _ = try LayoutDocument.decode(JSONSerialization.data(withJSONObject: document))
        }
        let value = try JSONDecoder().decode(DocumentLayoutSnapshot.self, from: data)
        if let fetched = value.acknowledgment?.fetchedLayout {
            guard UUID(uuidString: fetched.id) != nil else { throw LayoutDocumentError("Invalid fetched layout identity") }
            try fetched.document.validate()
        }
        try value.validate(); return value
    }
}

extension DocumentLayoutCommand {
    public func validate() throws {
        guard protocolVersion == 5 else { throw LayoutDocumentError("Update Gamepad Air on both devices: layout sync versions differ") }
        guard UUID(uuidString: id) != nil else { throw LayoutDocumentError("Invalid command ID") }
        guard action == .create || provenance == nil else { throw LayoutDocumentError("Source provenance cannot be changed by an edit") }
        guard action == .clear || catalogRevisions == nil else { throw LayoutDocumentError("Unexpected catalog revisions") }
        if action == .clear && catalogRevisions == nil { throw LayoutDocumentError("Missing catalog revisions") }
        if action == .create {
            guard (layoutID == nil || UUID(uuidString: layoutID!) != nil), baseEditRevision == nil, activeModeID == nil, let document else { throw LayoutDocumentError("Invalid create command") }
            try document.validate()
        } else {
            guard let layoutID, UUID(uuidString: layoutID) != nil, baseEditRevision != nil else { throw LayoutDocumentError("Missing layout or base revision") }
            if action == .save {
                guard let document, activeModeID == nil else { throw LayoutDocumentError("Missing saved document") }
                try document.validate()
            } else if action == .selectMode {
                guard document == nil, let activeModeID, !activeModeID.isEmpty else { throw LayoutDocumentError("Missing active mode") }
            } else if document != nil || activeModeID != nil { throw LayoutDocumentError("Unexpected command payload") }
        }
    }
    public func encodedPayload() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        _ = try DocumentLayoutTransport.decodeCommand(data)
        return data
    }
}

extension DocumentLayoutSnapshot {
    public func encodedPayload() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        _ = try DocumentLayoutTransport.decodeSnapshot(data)
        return data
    }
}
