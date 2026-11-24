import XCTest
@testable import GamepadCore

final class LocalLayoutCatalogTests: XCTestCase {
    func testDPadDirectionStyles() {
        for style in DPadStyle.allCases {
            XCTAssertEqual(style.hat(x: 0, y: 0), 8)
            XCTAssertEqual(style.hat(x: 0.1, y: 0), 8)
            XCTAssertEqual(style.hat(x: 0, y: -1), 0)
            XCTAssertEqual(style.hat(x: 1, y: 0), 2)
            XCTAssertEqual(style.hat(x: 0, y: 1), 4)
            XCTAssertEqual(style.hat(x: -1, y: 0), 6)
        }
        XCTAssertEqual(DPadStyle.eightWay.hat(x: 1, y: -1), 1)
        XCTAssertEqual(DPadStyle.fourWay.hat(x: 0.8, y: -1), 0)
        XCTAssertEqual(DPadStyle.fourWay.hat(x: 1, y: -0.8), 2)
        for degree in 0..<360 {
            let angle = Double(degree) * .pi / 180
            XCTAssertTrue([0, 2, 4, 6].contains(Int(DPadStyle.fourWay.hat(x: sin(angle), y: -cos(angle)))))
        }
    }
    func testFloatingOriginsStartNeutralAndTapRejectsDragReturnAndHold() {
        var floating = StickGesture(x: 180, y: 150, centerX: 100, centerY: 100, floating: true, now: 0)
        XCTAssertEqual(floating.originX, 180); XCTAssertEqual(floating.originY, 150)
        XCTAssertEqual(GamepadState.stick(x: (180 - floating.originX) / 62, y: (150 - floating.originY) / 62).0, 0)
        XCTAssertTrue(floating.isTap(now: 0.2))
        floating.move(x: 200, y: 150); floating.move(x: 180, y: 150)
        XCTAssertFalse(floating.isTap(now: 0.2))
        let fixed = StickGesture(x: 180, y: 150, centerX: 100, centerY: 100, floating: false, now: 0)
        XCTAssertEqual(fixed.originX, 100)
        XCTAssertFalse(fixed.isTap(now: 0.5))
        let next = StickGesture(x: 120, y: 100, centerX: 100, centerY: 100, floating: true, now: 1)
        XCTAssertEqual(next.originX, 120)
    }
    func testTapPulseSharesAttackAndSneakMappingWithoutChangingOtherButtons() {
        var state = GamepadState(); state.set(.south, pressed: true)
        StickTapAction.leftClick.apply(to: &state)
        StickTapAction.rightTrigger.apply(to: &state)
        var mapper = KeyboardMapper(profile: .starter)
        let down = mapper.receive(state, now: 0)
        XCTAssertTrue(down.contains(.down(.mouseLeft)))
        XCTAssertTrue(down.contains(.down(.control)))
        XCTAssertTrue(down.contains(.down(.space)))
        let up = mapper.receive(.neutral, now: 0.12)
        XCTAssertTrue(up.contains(.up(.mouseLeft)))
        XCTAssertTrue(up.contains(.up(.control)))
    }
    func testDeleteProtectsPresetsAndRestoresSelection() throws {
        var catalog = LocalLayoutCatalog.fresh()
        let presets = catalog.layouts
        let copy = try catalog.layouts[0].duplicate(name: "Personal")
        catalog.layouts.append(copy); catalog.selectedID = copy.id
        try catalog.delete(copy.id)
        XCTAssertEqual(catalog.layouts, presets)
        XCTAssertTrue(catalog.layouts.contains { $0.id == catalog.selectedID })
        XCTAssertThrowsError(try catalog.delete(catalog.selectedID))
        XCTAssertThrowsError(try catalog.delete("missing"))
        catalog.layouts = [copy]; catalog.selectedID = copy.id
        try catalog.delete(copy.id)
        XCTAssertTrue(catalog.layouts.allSatisfy { $0.isPreset })
        try catalog.validate()
    }
    func testDPadStyleIsStoredInDocument() throws {
        var doc = LayoutDocument.starter(name: "Dpad", style: .xbox)
        XCTAssertEqual(LocalLayout(document: doc).resolvedMode(doc.initialMode).effectiveDPadStyle, .eightWay)
        doc.modes[0].dpadStyle = "fourWay"
        XCTAssertEqual(try LayoutDocument.decode(doc.validatedData()), doc)
        XCTAssertEqual(LocalLayout(document: doc).resolvedMode(doc.initialMode).effectiveDPadStyle, .fourWay)
    }
}
