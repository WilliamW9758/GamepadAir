import XCTest
@testable import GamepadCore

final class LayoutTests: XCTestCase {
    func testResizeAndDragStayOnSurface() {
        let p = ControlPlacement(x: -1, y: 3, scale: 1.8).fitting(width: 800, height: 280, baseRadius: 62)
        XCTAssertGreaterThanOrEqual(p.x * 800, 62 * 1.8)
        XCTAssertLessThanOrEqual(p.y * 280 + 62 * 1.8, 280)
        let rotated = p.fitting(width: 280, height: 800, baseRadius: 62)
        XCTAssertGreaterThanOrEqual(rotated.x * 280, 62 * 1.8)
    }
    func testResetUsesExplicitNullWithoutTouchingOtherModesOrControls() throws {
        var doc = LayoutDocument.starter(name: "Geometry", style: .xbox)
        doc.setModeSwitching(true)
        let id = doc.controls.first { $0.role == "south" }!.id
        let other = doc.controls.first { $0.role == "leftStick" }!.id
        let p = DocumentPlacement(x: 0.3, y: 0.7, scale: 1.4)
        try doc.placeControl(id, at: p, modeID: doc.modes[0].id)
        try doc.placeControl(other, at: p, modeID: doc.modes[0].id)
        try doc.placeControl(id, at: p, modeID: doc.modes[1].id)
        try doc.resetPlacement(id, modeID: doc.modes[0].id)
        XCTAssertNil(doc.resolvedControl(id, modeID: doc.modes[0].id)?.placement)
        XCTAssertEqual(doc.resolvedControl(other, modeID: doc.modes[0].id)?.placement, p)
        XCTAssertEqual(doc.resolvedControl(id, modeID: doc.modes[1].id)?.placement, p)
        XCTAssertEqual(try LayoutDocument.decode(doc.validatedData()), doc)
    }
}
