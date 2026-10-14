import XCTest
@testable import GamepadCore

final class SavedLayoutTests: XCTestCase {
    func testMigrationPreservesBothStylesAndSettingsAndFreshPresets() throws {
        var legacy = LayoutLibrary()
        for style in PadStyle.allCases {
            legacy.set(ControlPlacement(x: 0.76, y: 0.24, scale: 1.65), control: "right-stick", style: style)
            legacy.addQuickBar(style: style)
            legacy.rename("right-stick", to: "My Look", style: style)
        }
        let original = try JSONEncoder().encode(legacy)
        let catalog = LayoutCatalog(legacy: legacy, style: .xbox, showDPad: false, holdAimEnabled: false, holdAimDelay: 0.8, trackpadHoldDelay: 0.7)
        XCTAssertEqual(catalog.layouts.count, 4)
        let saved = catalog.layouts[0]
        XCTAssertEqual(saved.name, "Valheim Controls")
        XCTAssertEqual(catalog.selectedID, saved.id)
        for mode in saved.modes {
            XCTAssertEqual(mode.controls, legacy)
            XCTAssertFalse(mode.showDPad); XCTAssertFalse(mode.holdAimEnabled)
            XCTAssertEqual(mode.holdAimDelay, 0.8); XCTAssertEqual(mode.trackpadHoldDelay, 0.7)
            XCTAssertTrue(mode.legacyCanvas)
        }
        XCTAssertFalse(saved.modes[0].cursor); XCTAssertTrue(saved.modes[1].cursor)
        for preset in catalog.layouts.suffix(2) {
            XCTAssertTrue(preset.isPreset)
            XCTAssertTrue(preset.modes[0].controls.presets.isEmpty)
        }
        XCTAssertEqual(LayoutLibrary.restore(original), legacy)
        XCTAssertEqual(try LayoutCatalog.decode(JSONEncoder().encode(catalog)), catalog)
    }
    func testCopiesAndModesNeverShareMutableLayouts() {
        var catalog = LayoutCatalog(legacy: LayoutLibrary(), style: .xbox, showDPad: true, holdAimEnabled: true, holdAimDelay: 0.3, trackpadHoldDelay: 0.5)
        let before = catalog.layouts[0]
        let id = catalog.duplicate(before.id, name: "Bow Controls")
        XCTAssertEqual(catalog.selectedID, id)
        let i = catalog.layouts.count - 1
        XCTAssertNotEqual(catalog.layouts[i].modes[0].id, before.modes[0].id)
        catalog.layouts[i].modes[0].controls.set(ControlPlacement(x: 0.1, y: 0.9), control: "right-stick", style: .xbox)
        catalog.layouts[i].modes[0].floatingRight = true
        XCTAssertEqual(catalog.layouts[0], before)
        XCTAssertTrue(catalog.layouts[i].modes[1].controls.presets.isEmpty)
        XCTAssertFalse(catalog.layouts[i].modes[1].floatingRight)
        let preset = catalog.layouts.first { $0.isPreset }!
        catalog.duplicate(preset.id, name: "Custom Xbox")
        XCTAssertFalse(catalog.layouts.last!.isPreset)
        XCTAssertEqual(catalog.layouts.first { $0.id == preset.id }, preset)
    }
    func testInvalidCatalogFailsInsteadOfSilentlyResetting() throws {
        XCTAssertThrowsError(try LayoutCatalog.decode(Data("broken".utf8)))
        var catalog = LayoutCatalog(legacy: LayoutLibrary(), style: .xbox, showDPad: true, holdAimEnabled: true, holdAimDelay: 0.3, trackpadHoldDelay: 0.5)
        catalog.layouts[0].modes = []
        XCTAssertThrowsError(try LayoutCatalog.decode(JSONEncoder().encode(catalog)))
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
}
