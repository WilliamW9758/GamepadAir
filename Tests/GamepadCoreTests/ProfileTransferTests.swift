import XCTest
@testable import GamepadCore

final class ProfileTransferTests: XCTestCase {
    func catalog() -> LayoutCatalog {
        LayoutCatalog(legacy: LayoutLibrary(), style: .xbox, showDPad: true, holdAimEnabled: true, holdAimDelay: 0.3, trackpadHoldDelay: 0.5)
    }
    func testUnlinkedPositionsStayIndependentAndLinkedSizesCompensate() {
        var l = SavedLayout(name: "Tuned", style: .xbox)
        let p = ControlPlacement(x: 0.4, y: 0.6, scale: 1.2)
        l.place(p, control: "right-trigger", mode: 0)
        XCTAssertNil(l.modes[1].controls.controls(for: .xbox)["right-trigger"])
        l.linkedControls = ["right-trigger"]; l.modes[0].sizeFactor = 0.8
        l.place(p, control: "right-trigger", mode: 0)
        XCTAssertEqual(l.modes[1].controls.controls(for: .xbox)["right-trigger"]?.scale ?? 0, 0.96, accuracy: 0.00001)
        XCTAssertEqual(l.modes[1].controls.controls(for: .xbox)["right-trigger"]?.x, 0.4)
        l.linkedControls = []
        l.place(ControlPlacement(x: 0.1, y: 0.1), control: "right-trigger", mode: 0)
        XCTAssertEqual(l.modes[1].controls.controls(for: .xbox)["right-trigger"]?.x, 0.4)
    }
    func testUndoRedoAndNewEditDropsRedo() {
        var h = LayoutHistory(); let a = catalog(); var b = a
        b.layouts[0].name = "Edited"; h.record(a)
        XCTAssertEqual(h.undo(b), a); XCTAssertEqual(h.redo(a), b)
        _ = h.undo(b); h.record(a)
        XCTAssertFalse(h.canRedo)
    }
    func testPortableRoundTripWithMappingsAndHaptics() throws {
        var l = SavedLayout(name: "Valheim", style: .xbox)
        l.modes[0].buttonFeedback = ["right-trigger": ButtonFeedback(haptic: .medium, tint: .red)]
        let p = PortableProfile(layout: l, keyboard: .starter)
        let decoded = try PortableProfile.decode(JSONEncoder().encode(p))
        XCTAssertEqual(decoded.layout, l)
        XCTAssertEqual(decoded.keyboard, KeyboardProfile.starter.sanitized)
    }
    func testPortableRejectsUnknownVersionAndInvalidSlots() throws {
        var p = PortableProfile(layout: SavedLayout(name: "Bad", style: .xbox))
        p.version = 2
        XCTAssertThrowsError(try PortableProfile.decode(JSONEncoder().encode(p)))
        p.version = 1; p.layout.modes[0].controls.customSlots = ["Xbox": [99]]
        XCTAssertThrowsError(try PortableProfile.decode(JSONEncoder().encode(p)))
    }
    func testLegacyCatalogRoundTripPreservesAbsenceOfNewPreferences() throws {
        let c = catalog(); let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try LayoutCatalog.decode(data), c)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("linkedControls"))
    }
}
