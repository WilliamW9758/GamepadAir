import XCTest
@testable import GamepadCore

final class ButtonFeedbackTests: XCTestCase {
    func testLegacyModeDecodesWithoutFeedbackAndPreservesPlacements() throws {
        var mode = LayoutMode(name: "Aim", cursor: false)
        mode.controls.set(ControlPlacement(x: 0.234, y: 0.789, scale: 1.45), control: "right-trigger", style: .xbox)
        let data = try JSONEncoder().encode(mode)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("buttonFeedback"))
        let decoded = try JSONDecoder().decode(LayoutMode.self, from: data)
        XCTAssertEqual(mode, decoded)
        XCTAssertNil(decoded.buttonFeedback)
    }
    func testFeedbackPersistsAndStaysIndependentAcrossModesAndCopies() throws {
        var layout = SavedLayout(name: "Tuned", style: .xbox)
        layout.modes[0].buttonFeedback = ["right-trigger": ButtonFeedback(haptic: .light, tint: .orange)]
        var copy = layout
        copy.modes[0].buttonFeedback?["right-trigger"]?.tint = .blue
        let decoded = try JSONDecoder().decode(SavedLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(decoded, layout)
        XCTAssertNil(decoded.modes[1].buttonFeedback)
        XCTAssertEqual(decoded.modes[0].buttonFeedback?["right-trigger"]?.tint, .orange)
        XCTAssertEqual(copy.modes[0].buttonFeedback?["right-trigger"]?.tint, .blue)
    }
}
