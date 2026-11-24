import XCTest
@testable import GamepadCore
final class ButtonFeedbackTests: XCTestCase {
    func testFeedbackOverridesAndCopiesStayIndependent() throws {
        var doc = LayoutDocument.starter(name: "Feedback", style: .xbox)
        doc.setModeSwitching(true)
        let id = doc.controls.first { $0.role == "rightTrigger" }!.id
        try doc.setFeedback(id, modeID: doc.modes[0].id, tint: "orange")
        var copy = doc
        try copy.setFeedback(id, modeID: copy.modes[0].id, tint: "blue")
        XCTAssertEqual(doc.resolvedControl(id, modeID: doc.modes[0].id)?.feedback?.tint, "orange")
        XCTAssertEqual(copy.resolvedControl(id, modeID: doc.modes[0].id)?.feedback?.tint, "blue")
        XCTAssertNil(doc.resolvedControl(id, modeID: doc.modes[1].id)?.feedback)
        XCTAssertEqual(try LayoutDocument.decode(doc.validatedData()), doc)
    }
}
