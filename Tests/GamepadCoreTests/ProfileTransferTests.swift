import XCTest
@testable import GamepadCore

final class ProfileTransferTests: XCTestCase {
    func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("catalog.json") }
    func testStoreRoundTripUndoAndDuplicatePreserveActionsAndIDs() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LayoutDocumentStore(url: url)
        let preset = store.selected
        try store.duplicate(name: "Personal")
        let copy = store.selected
        XCTAssertNotEqual(copy.id, preset.id)
        XCTAssertEqual(copy.document.actions, preset.document.actions)
        XCTAssertEqual(copy.document.controls.map(\.id), preset.document.controls.map(\.id))
        try store.edit { try $0.renameControl("south", caption: "Jump") }
        XCTAssertEqual(store.selected.editRevision, 1)
        try store.undo()
        XCTAssertEqual(store.selected.document, copy.document)
        XCTAssertGreaterThan(store.selected.editRevision, 1)
        try store.redo()
        XCTAssertEqual(store.selected.document.controls.first { $0.id == "south" }?.label, "Jump")
        XCTAssertEqual(try LayoutDocumentStore(url: url).catalog, store.catalog)
        try store.undo(); try store.edit { $0.name = "Another edit" }
        XCTAssertFalse(store.history.canRedo)
    }
    func testCorruptStorageIsNotOverwrittenAndInvalidImportIsAtomic() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LayoutDocumentStore(url: url)
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.importDocument(Data("{\"format\":\"pocketpad-profile\"}".utf8)))
        XCTAssertEqual(try Data(contentsOf: url), before)
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try LayoutDocumentStore(url: url))
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
    }
    func testFileAndDownloadBodyUseSameDocumentAndFreshWrappers() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = LocalLayout(name: "Export", style: .playStation)
        try LayoutDocumentFile.write(original, to: url)
        let file = try LayoutDocumentFile.read(url)
        let download = try LocalLayout.importDocument(Data(contentsOf: url), provenance: LayoutProvenance(publicationID: "pub", revisionID: "rev", digest: "origin"))
        XCTAssertEqual(file.document, download.document)
        XCTAssertNotEqual(file.id, download.id)
        XCTAssertNotEqual(file.id, original.id)
        let json = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(json.contains("editRevision")); XCTAssertFalse(json.contains("provenance"))
        XCTAssertEqual(download.provenance?.digest, "origin")
    }
    func testSaveAcknowledgmentFollowsDiskWriteAndRetriesAreIdempotent() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LayoutDocumentStore(url: url)
        let create = DocumentLayoutCommand(action: .create, document: .starter(name: "Remote", style: .xbox))
        let ack = store.apply(create)
        XCTAssertNil(ack.error)
        let count = store.catalog.layouts.count
        XCTAssertEqual(store.apply(create), ack); XCTAssertEqual(store.catalog.layouts.count, count)
        let current = store.selected
        var document = current.document; document.name = "Updated"
        let save = DocumentLayoutCommand(action: .save, layoutID: current.id, baseEditRevision: current.editRevision, document: document)
        XCTAssertNil(store.apply(save).error)
        XCTAssertEqual(try LayoutDocumentStore(url: url).selected.document, document)
        let stale = DocumentLayoutCommand(action: .save, layoutID: current.id, baseEditRevision: current.editRevision, document: current.document)
        XCTAssertNotNil(store.apply(stale).error)
        // A directory at the destination makes an atomic file replacement fail.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let before = store.catalog
        let retry = DocumentLayoutCommand(action: .create, document: document)
        XCTAssertNotNil(store.apply(retry).error); XCTAssertEqual(store.catalog, before)
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(store.apply(retry).error)
        XCTAssertEqual(store.catalog.layouts.count, before.layouts.count + 1)
    }
    func testUndoResurrectionNeverReusesAnOldRevision() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LayoutDocumentStore(url: url)
        try store.duplicate(name: "Personal")
        try store.edit { $0.name = "Changed" }
        let previous = store.selected
        try store.delete(previous.id)
        try store.undo()
        XCTAssertEqual(store.selected.id, previous.id)
        XCTAssertGreaterThan(store.selected.editRevision, previous.editRevision)
        XCTAssertNotNil(store.apply(DocumentLayoutCommand(action: .save, layoutID: previous.id, baseEditRevision: previous.editRevision, document: previous.document)).error)
    }
    func testSourceProvenanceSurvivesCreateDuplicateAndEditing() throws {
        var catalog = LocalLayoutCatalog.fresh(); var processor = DocumentLayoutCommandProcessor()
        let provenance = LayoutProvenance(publicationID: "publication", revisionID: "revision", digest: "original-digest")
        let create = DocumentLayoutCommand(action: .create, document: .starter(name: "Downloaded", style: .xbox), provenance: provenance)
        XCTAssertNil(processor.apply(create, to: &catalog).error)
        var local = catalog.layouts.last!
        try local.edit(baseRevision: local.editRevision) { $0.name = "Edited" }
        XCTAssertEqual(local.provenance, provenance)
        XCTAssertEqual(try local.duplicate(name: "Copy").provenance, provenance)
        let corrupt = DocumentLayoutCommand(action: .save, layoutID: local.id, baseEditRevision: local.editRevision, document: local.document, provenance: provenance)
        XCTAssertThrowsError(try corrupt.validate())
    }
    func testWireRejectsUnknownDocumentFieldsAndProtocolVersions() throws {
        let command = DocumentLayoutCommand(action: .create, document: .starter(name: "Wire", style: .xbox))
        let data = try command.encodedPayload()
        XCTAssertEqual(try DocumentLayoutTransport.decodeCommand(data), command)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var doc = json["document"] as! [String: Any]; doc["surprise"] = true; json["document"] = doc
        XCTAssertThrowsError(try DocumentLayoutTransport.decodeCommand(JSONSerialization.data(withJSONObject: json)))
        json["document"] = try JSONSerialization.jsonObject(with: command.document!.validatedData())
        json["protocolVersion"] = 1
        XCTAssertThrowsError(try DocumentLayoutTransport.decodeCommand(JSONSerialization.data(withJSONObject: json)))
    }
}
