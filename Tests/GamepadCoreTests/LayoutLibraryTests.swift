import XCTest
@testable import GamepadCore

final class LayoutLibraryTests: XCTestCase {
    func testReadFetchDoesNotSwitchPhoneOrModifyCatalog() throws {
        var catalog = LocalLayoutCatalog.fresh()
        let selected = catalog.selectedID
        let other = catalog.layouts[1]
        let original = catalog
        var processor = DocumentLayoutCommandProcessor()
        let command = DocumentLayoutCommand(action: .fetch, layoutID: other.id, baseEditRevision: other.editRevision)
        let ack = processor.apply(command, to: &catalog)
        XCTAssertNil(ack.error); XCTAssertEqual(ack.fetchedLayout, other)
        XCTAssertEqual(catalog, original); XCTAssertEqual(catalog.selectedID, selected)
        var snapshot = DocumentLayoutSnapshot(layout: catalog.layouts[0], activeModeID: catalog.layouts[0].document.initialMode)
        snapshot.acknowledgment = ack
        XCTAssertEqual(try DocumentLayoutTransport.decodeSnapshot(snapshot.encodedPayload()), snapshot)
    }
    func testCreatePreservesSharedIDAndRefusesOverwrite() throws {
        let layout = LocalLayout(name: "Local layout", style: .xbox)
        var catalog = LocalLayoutCatalog.fresh()
        var processor = DocumentLayoutCommandProcessor()
        let command = DocumentLayoutCommand(action: .create, layoutID: layout.id, document: layout.document)
        XCTAssertNil(processor.apply(command, to: &catalog).error)
        XCTAssertEqual(catalog.selectedID, layout.id)
        XCTAssertEqual(catalog.layouts.last?.document, layout.document)
        let count = catalog.layouts.count
        XCTAssertNil(processor.apply(command, to: &catalog).error)
        XCTAssertEqual(catalog.layouts.count, count)
        XCTAssertNotNil(processor.apply(DocumentLayoutCommand(action: .create, layoutID: layout.id, document: layout.document), to: &catalog).error)
    }
    func testOfflinePersistenceAndConfirmedDeviceReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("layouts.json")
        let store = try LayoutDocumentStore(url: url)
        try store.create(.starter(name: "Offline", style: .xbox))
        let id = store.selected.id
        try store.edit { $0.name = "Edited on Mac" }
        let saved = store.selected
        XCTAssertNotNil(saved.modifiedAt)
        let reopened = try LayoutDocumentStore(url: url)
        XCTAssertEqual(reopened.selected, saved)
        var phone = saved
        try phone.edit(baseRevision: phone.editRevision) { $0.name = "Edited on iPhone" }
        // Reading remote content alone never edits the store. Only explicit resolution receives it.
        XCTAssertEqual(reopened.selected.name, "Edited on Mac")
        try reopened.receive(phone)
        XCTAssertEqual(reopened.selected.id, id); XCTAssertEqual(reopened.selected, phone)
        try reopened.undo()
        XCTAssertEqual(reopened.selected.name, "Edited on Mac")
        XCTAssertGreaterThan(reopened.selected.editRevision, phone.editRevision)
    }
    func testOldLocalWrapperWithoutTimestampStillLoads() throws {
        let catalog = LocalLayoutCatalog.fresh()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        var layouts = try XCTUnwrap(root["layouts"] as? [[String: Any]])
        for i in layouts.indices { layouts[i].removeValue(forKey: "modifiedAt") }
        root["layouts"] = layouts
        let decoded = try LocalLayoutCatalog.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertNil(decoded.layouts[0].modifiedAt)
    }
}
