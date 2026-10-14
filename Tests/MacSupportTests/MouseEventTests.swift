import XCTest
import CoreGraphics
@testable import MacSupport

final class MouseEventTests: XCTestCase {
    func testRelativeAimingCannotDriftOffScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        var point = CGPoint(x: 756, y: 507)
        for _ in 0..<10000 {
            point = MousePositioning.position(current: point, dx: 40, dy: -30, relative: true, displays: [screen])
        }
        XCTAssertEqual(point, CGPoint(x: 756, y: 507))
        let recovered = MousePositioning.position(current: CGPoint(x: 1559.984375, y: 469), relative: true, displays: [screen])
        XCTAssertEqual(recovered, CGPoint(x: 756, y: 491))
    }
    func testDesktopModeMovesButClampsAtDisplayBoundary() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(MousePositioning.position(current: CGPoint(x: 100, y: 100), dx: 5, dy: -2, relative: false, displays: [screen]), CGPoint(x: 105, y: 98))
        XCTAssertEqual(MousePositioning.position(current: CGPoint(x: 1510, y: 980), dx: 20, dy: 20, relative: false, displays: [screen]), CGPoint(x: 1511, y: 981))
        let second = CGRect(x: 1512, y: 0, width: 1000, height: 1000)
        XCTAssertEqual(MousePositioning.position(current: CGPoint(x: 1510, y: 500), dx: 20, relative: false, displays: [screen, second]), CGPoint(x: 1530, y: 500))
    }
    func testMouseDownDragUpHavePairedNumbersAndRealTimestamps() throws {
        var sequence = MouseEventSequence()
        let source = CGEventSource(stateID: .privateState)
        func event(_ type: CGEventType, _ button: CGMouseButton) throws -> CGEvent {
            try XCTUnwrap(CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: .zero, mouseButton: button))
        }
        let down = try event(.leftMouseDown, .left)
        sequence.prepare(down, button: .left, down: true)
        XCTAssertGreaterThan(down.timestamp, 0)
        let number = down.getIntegerValueField(.mouseEventNumber)
        XCTAssertGreaterThan(number, 0)
        let rightDown = try event(.rightMouseDown, .right)
        sequence.prepare(rightDown, button: .right, down: true)
        XCTAssertNotEqual(rightDown.getIntegerValueField(.mouseEventNumber), number)
        for _ in 0..<1000 {
            let drag = try event(.leftMouseDragged, .left)
            sequence.prepare(drag, button: .left, down: nil)
            XCTAssertEqual(drag.getIntegerValueField(.mouseEventNumber), number)
            XCTAssertGreaterThanOrEqual(drag.timestamp, down.timestamp)
            XCTAssertEqual(drag.getIntegerValueField(.mouseEventClickState), 1)
        }
        let up = try event(.leftMouseUp, .left)
        sequence.prepare(up, button: .left, down: false)
        XCTAssertEqual(up.getIntegerValueField(.mouseEventNumber), number)
        let rightUp = try event(.rightMouseUp, .right)
        sequence.prepare(rightUp, button: .right, down: false)
        XCTAssertEqual(rightUp.getIntegerValueField(.mouseEventNumber), rightDown.getIntegerValueField(.mouseEventNumber))
        let next = try event(.leftMouseDown, .left)
        sequence.prepare(next, button: .left, down: true)
        XCTAssertGreaterThan(next.getIntegerValueField(.mouseEventNumber), number)
    }
}
