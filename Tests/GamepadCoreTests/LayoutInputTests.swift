import XCTest
@testable import GamepadCore

final class LayoutInputTests: XCTestCase {
    func testEmulationLabelsPreserveExplicitNamesAndPositions() throws {
        var layout = SavedLayout(name: "Custom", style: .xbox)
        layout.inputType = .gamepad
        layout.modes[0].controls.rename("button-0", to: "Jump", style: .xbox)
        // Even an explicitly chosen name equal to a default remains custom.
        layout.modes[0].controls.rename("button-1", to: "B", style: .xbox)
        layout.modes[0].controls.rename("left-trigger", to: "Block", style: .xbox)
        let before = layout.modes
        layout.emulatedController = .playStation
        let labels = layout.displayLabels(modeIndex: 0)
        XCTAssertEqual(labels["button-0"], "Jump")
        XCTAssertEqual(labels["button-1"], "B")
        XCTAssertEqual(labels["button-2"], "□")
        XCTAssertEqual(labels["button-6"], "Share")
        XCTAssertEqual(labels["button-7"], "Options")
        XCTAssertEqual(labels["button-10"], "PS")
        XCTAssertEqual(labels["left-trigger"], "Block")
        XCTAssertEqual(labels["right-trigger"], "R2")
        XCTAssertEqual(layout.controlLabel(.west, modeIndex: 0), "□")
        XCTAssertEqual(layout.controlLabel(.south, modeIndex: 0), "Jump")
        XCTAssertEqual(layout.modes, before)
        let restored = try JSONDecoder().decode(SavedLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored.displayLabels(modeIndex: 0), labels)
        layout.emulatedController = .xbox
        XCTAssertEqual(layout.displayLabels(modeIndex: 0)["button-2"], "X")
        XCTAssertEqual(layout.displayLabels(modeIndex: 0)["button-0"], "Jump")
    }

    func testCursorSwitchingPreservesLegacyAndCopiesNewArrangement() throws {
        var layout = SavedLayout(name: "Test", style: .xbox)
        XCTAssertTrue(layout.hasCursorSwitching)
        layout.cursorSwitching = false
        layout.modes[0].controls.set(ControlPlacement(x: 0.3, y: 0.4), control: "left-stick", style: .xbox)
        layout.setCursorSwitching(true)
        XCTAssertTrue(layout.modes[1].cursor)
        XCTAssertEqual(layout.modes[0].controls, layout.modes[1].controls)
        XCTAssertTrue(layout.linkedControls?.contains("left-stick") == true)
        layout.setCursorSwitching(false)
        let decoded = try JSONDecoder().decode(SavedLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertFalse(decoded.hasCursorSwitching)
    }

    func testConversionLeavesCombosAndUnknownKeysInert() {
        var layout = SavedLayout(name: "Keys", style: .xbox)
        layout.inputType = .keyboardMouse; layout.keyboardProfile = .starter
        let converted = layout.converted(to: .gamepad)
        XCTAssertEqual(converted.gamepadProfile?[.south], .south)
        XCTAssertNil(converted.gamepadProfile?[.east])
        XCTAssertNil(converted.gamepadProfile?[.custom16])
        XCTAssertEqual(converted.gamepadProfile?.disableLeftStick, false)
        var state = GamepadState(); state.set(.east, pressed: true); state.customButtons = 1 << 15
        XCTAssertEqual(converted.gamepadProfile?.apply(state), .neutral)
        XCTAssertEqual(layout.inputType, .keyboardMouse)
    }
    func testNonWASDStickRequiresManualMapping() {
        var layout = SavedLayout(name: "Keys", style: .xbox)
        var keyboard = KeyboardProfile.starter; keyboard[.leftUp] = KeyBinding()
        layout.keyboardProfile = keyboard
        let converted = layout.converted(to: .gamepad)
        XCTAssertTrue(converted.unmappedControls.contains(.leftUp))
        var state = GamepadState(); state.leftX = 30000
        XCTAssertEqual(converted.gamepadProfile?.apply(state).leftX, 0)
    }
    func testSameTypeCopyPreservesProfilesAndRoundTrips() throws {
        var layout = SavedLayout(name: "Controller", style: .xbox)
        layout.inputType = .gamepad
        var profile = GamepadProfile(); profile[.custom16] = .south; profile[.east] = nil
        layout.gamepadProfile = profile
        let copy = layout.converted(to: .gamepad)
        XCTAssertEqual(copy.gamepadProfile, profile)
        XCTAssertEqual(try JSONDecoder().decode(SavedLayout.self, from: JSONEncoder().encode(copy)), copy)
        let keys = copy.converted(to: .keyboardMouse)
        XCTAssertTrue(keys.keyboardProfile![.east].outputs.isEmpty)
        XCTAssertEqual(keys.keyboardProfile![.custom16].outputs, [.space])
    }
    func testRenamedControlLabelMatchesMappingAndMode() {
        var layout = SavedLayout(name: "Named", style: .xbox)
        layout.modes[0].controls.rename("button-0", to: "ABC", style: .xbox)
        layout.modes[0].controls.rename("left-stick", to: "Walk", style: .xbox)
        XCTAssertEqual(layout.controlLabel(.south, modeIndex: 0), "ABC")
        XCTAssertEqual(layout.controlLabel(.leftUp, modeIndex: 0), "Walk · Up")
        XCTAssertEqual(layout.controlLabel(.south, modeIndex: 1), MappedControl.south.label)
        XCTAssertEqual(layout.keyboardProfile ?? .starter, KeyboardProfile.starter)
    }
    func testLegacyLayoutWithoutTypeStillDecodes() throws {
        let layout = SavedLayout(name: "Old", style: .xbox)
        let decoded = try JSONDecoder().decode(SavedLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertNil(decoded.inputType)
        XCTAssertEqual(decoded.effectiveInputType, .keyboardMouse)
    }
}
