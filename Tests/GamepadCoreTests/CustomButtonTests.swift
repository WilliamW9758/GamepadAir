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
        XCTAssertEqual(try StateFrame(data: StateFrame(sequence: 8, state: state).encode()).state, state)
        state.isPaused = false
        for slot in 0..<16 { state.setCustom(slot, pressed: false) }
        state.setCustom(16, pressed: true); state.setCustom(-1, pressed: true)
        XCTAssertEqual(state, .neutral)
    }
    func testCustomHeldButtonPreventsRearm() {
        var gate = KeyboardInputGate()
        var state = GamepadState(); state.setCustom(0, pressed: true)
        XCTAssertEqual(gate.evaluate(state: state, lastInput: 0, now: 0, authorized: true, focused: true), .release)
    }
    func testCustomSlotsAllocateReuseAndNeverGainImplicitNumberKeys() throws {
        var doc = LayoutDocument.starter(name: "Custom", style: .xbox)
        var ids: [String] = []
        for _ in 0..<16 { ids.append(try doc.addControl(role: "customButton")) }
        XCTAssertThrowsError(try doc.addControl(role: "customButton"))
        for source in MappedControl.customControls { XCTAssertTrue(doc.compileInput().keyboard[source].outputs.isEmpty) }
        try doc.renameControl(ids[0], caption: "Sword")
        try doc.rebind(.control(id: ids[0], direction: "press"), outputs: ["key.shift", "key.e"])
        var mapper = KeyboardMapper(profile: doc.compileInput().keyboard)
        var state = GamepadState(); state.setCustom(0, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.shift)])
        XCTAssertEqual(mapper.tick(now: 0.04), [.down(.e)])
        XCTAssertEqual(mapper.reset(), [.up(.e), .up(.shift)])
        try doc.removeControl(ids[0]); let replacement = try doc.addControl(role: "customButton")
        XCTAssertEqual(doc.controls.first { $0.id == replacement }?.customSlot, 0)
        XCTAssertTrue(doc.compileInput().keyboard[.custom1].outputs.isEmpty)
        XCTAssertEqual(try LayoutDocument.decode(doc.validatedData()), doc)
    }
}
