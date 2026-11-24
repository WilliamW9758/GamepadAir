import XCTest
@testable import GamepadCore

final class RadialTests: XCTestCase {
    func testEightDirectionsAndCenterCancellation() {
        for direction in 0..<8 {
            let angle = Double(direction) * .pi / 4
            XCTAssertEqual(RadialInput.direction(x: sin(angle) * 60, y: -cos(angle) * 60, deadZone: 24), direction)
        }
        XCTAssertNil(RadialInput.direction(x: 10, y: 10, deadZone: 24))
        XCTAssertNil(RadialInput.direction(x: 0, y: 0, deadZone: 24))
        XCTAssertNil(RadialInput.direction(x: .nan, y: 10, deadZone: 24))
    }
    func testHiddenCustomSourceAndSparseRadialUseOneBinding() throws {
        var doc = LayoutDocument.starter(name: "Radial", style: .xbox)
        let source = try doc.addControl(role: "customButton")
        _ = try doc.addControl(role: "radial")
        try doc.assignRadial(direction: 0, customSlot: 0)
        try doc.assignRadial(direction: 4, customSlot: 0)
        try doc.rebind(.control(id: source, direction: "press"), outputs: ["key.one"], behavior: "tap")
        try doc.hideRadialSources(modeID: doc.initialMode)
        XCTAssertEqual(doc.radialSlots(), [0, -1, -1, -1, 0, -1, -1, -1])
        XCTAssertTrue(doc.resolvedControl(source, modeID: doc.initialMode)?.hidden == true)
        var mapper = KeyboardMapper(profile: doc.compileInput().keyboard)
        var state = GamepadState(); state.setCustom(0, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.one)])
        XCTAssertEqual(mapper.tick(now: 0.2), [.up(.one)])
        XCTAssertThrowsError(try doc.assignRadial(direction: 2, customSlot: 16))
        try doc.removeControl(source)
        XCTAssertEqual(doc.radialSlots(), Array(repeating: -1, count: 8))
    }
}
