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
    func testOldModesDecodeWithoutRadialSettingsAndPreserveControls() throws {
        var mode = LayoutMode(name: "Valheim", cursor: false)
        mode.controls.set(ControlPlacement(x: 0.2, y: 0.7, scale: 1.4), control: "right-stick", style: .xbox)
        let old = try JSONEncoder().encode(mode)
        let restored = try JSONDecoder().decode(LayoutMode.self, from: old)
        XCTAssertNil(restored.radialEnabled); XCTAssertNil(restored.radialSlots)
        XCTAssertEqual(restored.controls, mode.controls)
        mode.radialEnabled = true; mode.radialSlots = Array((0..<8).reversed())
        XCTAssertEqual(try JSONDecoder().decode(LayoutMode.self, from: JSONEncoder().encode(mode)), mode)
    }
    func testRadialSlotsUseExistingQuickbarMappingsEvenWithoutVisibleButtons() {
        for slot in 0..<8 {
            var mapper = KeyboardMapper(profile: .starter)
            var state = GamepadState(); state.setCustom(slot, pressed: true)
            let token: OutputToken = [.one, .two, .three, .four, .five, .six, .seven, .eight][slot]
            XCTAssertEqual(mapper.receive(state, now: 0), [.down(token)])
            XCTAssertEqual(mapper.activeOutputs, [token])
            _ = mapper.receive(.neutral, now: 0.05)
            XCTAssertEqual(mapper.tick(now: 0.2), [.up(token)])
        }
    }
}

extension RadialTests {
    func testUnusedDirectionsAndInvalidSlotsAreValidated() throws {
        var catalog = LayoutCatalog(legacy: LayoutLibrary(), style: .xbox, showDPad: true, holdAimEnabled: true, holdAimDelay: 0.3, trackpadHoldDelay: 0.5)
        catalog.layouts[0].modes[0].radialSlots = [0, -1, 1, -1, 2, -1, 3, -1]
        XCTAssertNoThrow(try LayoutCatalog.decode(JSONEncoder().encode(catalog)))
        catalog.layouts[0].modes[0].radialSlots = [0, 1]
        XCTAssertThrowsError(try LayoutCatalog.decode(JSONEncoder().encode(catalog)))
        catalog.layouts[0].modes[0].radialSlots = Array(repeating: 16, count: 8)
        XCTAssertThrowsError(try LayoutCatalog.decode(JSONEncoder().encode(catalog)))
    }
}
