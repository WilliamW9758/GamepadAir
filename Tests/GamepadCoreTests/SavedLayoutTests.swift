import XCTest
@testable import GamepadCore

final class SavedLayoutTests: XCTestCase {
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
    func testDPadStyleStorageAndLegacyDefault() throws {
        var mode = LayoutMode(name: "Default", cursor: false)
        let legacyData = try JSONEncoder().encode(mode)
        XCTAssertFalse(String(decoding: legacyData, as: UTF8.self).contains("dpadStyle"))
        XCTAssertEqual(try JSONDecoder().decode(LayoutMode.self, from: legacyData).effectiveDPadStyle, .eightWay)
        mode.dpadStyle = .fourWay
        XCTAssertEqual(try JSONDecoder().decode(LayoutMode.self, from: JSONEncoder().encode(mode)), mode)
    }
    func testDeleteSelectedLayoutLeavesValidSelectionAndPreservesOthers() throws {
        var catalog = LayoutCatalog.fresh()
        let presets = catalog.layouts
        let id = catalog.duplicate(catalog.selectedID, name: "Personal")!
        try catalog.delete(id)
        XCTAssertEqual(catalog.layouts, presets)
        XCTAssertTrue(catalog.layouts.contains { $0.id == catalog.selectedID })
        XCTAssertEqual(try LayoutCatalog.decode(JSONEncoder().encode(catalog)), catalog)
        XCTAssertThrowsError(try catalog.delete(catalog.selectedID))
        XCTAssertThrowsError(try catalog.delete("missing"))
    }
    func testDeletingOnlyPersonalLayoutRestoresUsablePresets() throws {
        var catalog = LayoutCatalog.fresh()
        var layout = catalog.layouts[0]; layout.isPreset = false
        catalog.layouts = [layout]; catalog.selectedID = layout.id
        try catalog.delete(layout.id)
        XCTAssertEqual(catalog.layouts.count, PadStyle.allCases.count)
        XCTAssertTrue(catalog.layouts.allSatisfy { $0.isPreset && !$0.hasCursorSwitching })
        _ = try LayoutCatalog.decode(JSONEncoder().encode(catalog))
    }
    func testDeleteCommandCarriesConflictCheckOverWire() throws {
        let layout = LayoutCatalog.fresh().layouts[0]
        let command = LayoutCommand(action: .delete, layoutID: layout.id, base: layout)
        let data = try command.encode()
        var receiver = LayoutCommandReceiver()
        var received: LayoutCommand?
        for start in stride(from: 0, to: data.count, by: 4) {
            if let value = try receiver.accept(data.subdata(in: start..<start+4)) { received = value }
        }
        XCTAssertEqual(received, command)
    }

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
