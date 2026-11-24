import XCTest
@testable import GamepadCore

final class LayoutInputTests: XCTestCase {
    func testEmulationLabelsPreserveExplicitNamesAndGeometry() throws {
        var doc = LayoutDocument.starter(name: "Custom", style: .xbox, input: .gamepad)
        try doc.renameControl("south", caption: "Jump")
        try doc.renameControl("east", caption: "B")
        try doc.renameControl("lefttrigger", caption: "Block")
        let controls = doc.controls
        doc.controllerStyle = "playstation"
        let labels = LocalLayout(document: doc).displayLabels(modeID: "play")
        XCTAssertEqual(labels["button-0"], "Jump"); XCTAssertEqual(labels["button-1"], "B")
        XCTAssertEqual(labels["button-2"], "□"); XCTAssertEqual(labels["button-6"], "Share")
        XCTAssertEqual(labels["button-7"], "Options"); XCTAssertEqual(labels["button-10"], "PS")
        XCTAssertEqual(labels["left-trigger"], "Block"); XCTAssertEqual(labels["right-trigger"], "R2")
        XCTAssertEqual(doc.controls, controls)
        XCTAssertEqual(try LayoutDocument.decode(doc.validatedData()), doc)
    }
    func testOneModeIsStoredAsOneAndModeSwitchingCopiesArrangement() throws {
        var doc = LayoutDocument.starter(name: "Modes", style: .xbox)
        XCTAssertEqual(doc.modes.count, 1)
        try doc.placeControl("leftstick", at: DocumentPlacement(x: 0.3, y: 0.4), modeID: "play")
        doc.setModeSwitching(true)
        XCTAssertEqual(doc.modes.count, 2)
        XCTAssertEqual(doc.modes[1].pointerMode, "cursor")
        XCTAssertEqual(doc.modes[1].overrides, doc.modes[0].overrides)
        XCTAssertEqual(doc.nextMode(after: doc.modes[1].id), "play")
        doc.setModeSwitching(false)
        XCTAssertEqual(doc.modes.count, 1)
        XCTAssertFalse(doc.controls.contains { $0.role == "modeSwitch" })
        XCTAssertEqual(try LayoutDocument.decode(doc.validatedData()), doc)
    }
    func testConversionLeavesCombosAndUnknownKeysInert() throws {
        let doc = LayoutDocument.starter(name: "Keys", style: .xbox)
        let converted = try doc.converted(to: .gamepad, name: "Controller")
        let profile = converted.compileInput().gamepad
        XCTAssertEqual(profile[.south], .south)
        XCTAssertNil(profile[.east]); XCTAssertNil(profile[.custom16])
        XCTAssertEqual(profile.disableLeftStick, false)
        var state = GamepadState(); state.set(.east, pressed: true); state.customButtons = 1 << 15
        XCTAssertEqual(profile.apply(state), .neutral)
        XCTAssertEqual(doc.inputType, "keyboardMouse")
        XCTAssertEqual(converted.actions.mapValues(\.label), doc.actions.mapValues(\.label))
    }
    func testNonWASDStickDoesNotBecomeActive() throws {
        var doc = LayoutDocument.starter(name: "Keys", style: .xbox)
        try doc.rebind(.control(id: "leftstick", direction: "up"), outputs: [])
        let converted = try doc.converted(to: .gamepad, name: "Controller")
        XCTAssertEqual(converted.gamepad?.disableLeftStick, true)
        var state = GamepadState(); state.leftX = 30000
        XCTAssertEqual(converted.compileInput().gamepad.apply(state).leftX, 0)
    }
    func testSameBackendPreservesSharedActionsAndIDs() throws {
        var doc = LayoutDocument.starter(name: "Controller", style: .xbox, input: .gamepad)
        let id = try doc.addControl(role: "customButton")
        try doc.rebind(.control(id: id, direction: "press"), outputs: ["gamepad.south"])
        try doc.rebind(.control(id: "east", direction: "press"), outputs: [])
        let copy = try doc.converted(to: .gamepad, name: doc.name)
        XCTAssertEqual(copy, doc)
        let keys = try copy.converted(to: .keyboardMouse, name: "Keys")
        XCTAssertTrue(keys.compileInput().keyboard[.east].outputs.isEmpty)
        XCTAssertEqual(keys.compileInput().keyboard[.custom1].outputs, [.space])
    }
}
