import XCTest
@testable import GamepadCore

final class CustomButtonTests: XCTestCase {
    func testCustomBitsRoundTripAndPauseValidation() throws {
        var state = GamepadState()
        for slot in 0..<16 { state.setCustom(slot, pressed: true) }
        XCTAssertEqual(state.customButtons, 65535)
        let frame = StateFrame(sequence: 7, state: state)
        XCTAssertEqual(try StateFrame(data: frame.encode()), frame)
        XCTAssertEqual(Array(frame.encode().suffix(2)), [255, 255])
        state.isPaused = true
        XCTAssertThrowsError(try StateFrame(data: StateFrame(sequence: 8, state: state).encode()))
        state.isPaused = false
        for slot in 0..<16 { state.setCustom(slot, pressed: false) }
        state.setCustom(16, pressed: true); state.setCustom(-1, pressed: true)
        XCTAssertEqual(state, .neutral)
    }
    func testQuickBarKeysAndCustomCombo() {
        let keys: [OutputToken] = [.one, .two, .three, .four, .five, .six, .seven, .eight]
        for slot in 0..<8 {
            var mapper = KeyboardMapper(profile: .starter)
            var state = GamepadState(); state.setCustom(slot, pressed: true)
            XCTAssertEqual(mapper.receive(state, now: 0), [.down(keys[slot])])
            XCTAssertEqual(mapper.tick(now: 0.13), [.up(keys[slot])])
        }
        var profile = KeyboardProfile.starter
        profile[.custom16] = KeyBinding([.shift, .e])
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.setCustom(15, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.shift)])
        XCTAssertEqual(mapper.tick(now: 0.04), [.down(.e)])
        XCTAssertEqual(mapper.reset(), [.up(.e), .up(.shift)])
    }
    func testCustomHeldButtonPreventsRearm() {
        var gate = KeyboardInputGate()
        var state = GamepadState(); state.setCustom(0, pressed: true)
        XCTAssertEqual(gate.evaluate(state: state, lastInput: 0, now: 0, authorized: true, focused: true), .release)
    }
    func testLayoutNamesAndSlotsSurviveAndStayIndependent() throws {
        var library = LayoutLibrary()
        library.addQuickBar(style: .xbox)
        library.rename("custom-0", to: "Sword", style: .xbox)
        library.rename("button-0", to: "Jump", style: .xbox)
        library.addQuickBar(style: .xbox)
        XCTAssertEqual(library.labels(for: .xbox)["custom-0"], "Sword")
        XCTAssertEqual(library.addCustom(style: .xbox), 8)
        for _ in 9..<16 { _ = library.addCustom(style: .xbox) }
        XCTAssertNil(library.addCustom(style: .xbox))
        let loaded = LayoutLibrary.restore(try JSONEncoder().encode(library))
        XCTAssertEqual(loaded, library)
        XCTAssertEqual(loaded.labels(for: .xbox)["button-0"], "Jump")
        XCTAssertTrue(loaded.customButtons(for: .playStation).isEmpty)
        library.removeCustom(0, style: .xbox)
        XCTAssertNil(library.labels(for: .xbox)["custom-0"])
        XCTAssertEqual(library.addCustom(style: .xbox), 0)
        library.rename("button-0", to: " ", style: .xbox)
        XCTAssertNil(library.labels(for: .xbox)["button-0"])
        library.reset(style: .xbox)
        XCTAssertTrue(library.customButtons(for: .xbox).isEmpty)
    }
    func testOldLayoutsAndProfilesKeepTheirValues() throws {
        let data = Data(#"{"version":1,"presets":{"Xbox":{"button-0":{"x":0.4,"y":0.5,"scale":1.2}}}}"#.utf8)
        let layout = LayoutLibrary.restore(data)
        XCTAssertEqual(layout.controls(for: .xbox)["button-0"]?.scale, 1.2)
        XCTAssertTrue(layout.customButtons(for: .xbox).isEmpty)
        var profile = KeyboardProfile.starter; profile[.south] = KeyBinding([.z])
        let restored = KeyboardProfile.restore(try JSONEncoder().encode(profile))
        XCTAssertEqual(restored[.south].outputs, [.z])
        XCTAssertEqual(restored[.custom8].outputs, [.eight])
        profile[.custom1] = KeyBinding()
        XCTAssertTrue(KeyboardProfile.restore(try JSONEncoder().encode(profile))[.custom1].outputs.isEmpty)
    }
}
