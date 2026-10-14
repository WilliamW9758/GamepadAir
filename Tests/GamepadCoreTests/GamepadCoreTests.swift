import XCTest
@testable import GamepadCore

final class GamepadCoreTests: XCTestCase {
    func testFrameHasStableLittleEndianRepresentation() throws {
        var state = GamepadState()
        state.set(.south, pressed: true); state.set(.rightClick, pressed: true)
        state.leftX = -32767; state.leftY = 32767; state.rightX = -123; state.rightY = 456
        state.hat = 7; state.rightTrigger = 255
        let frame = StateFrame(sequence: 0x12345678, state: state)
        let data = frame.encode()
        XCTAssertEqual(data.count, 28)
        XCTAssertEqual(Array(data[8..<16]), [0x78, 0x56, 0x34, 0x12, 0x01, 0x02, 7, 0])
        XCTAssertEqual(Array(data[16..<20]), [0x01, 0x80, 0xff, 0x7f])
        XCTAssertEqual(try StateFrame(data: data), frame)
    }

    func testMalformedFramesAreRejected() {
        let good = StateFrame(sequence: 0, state: .neutral).encode()
        XCTAssertThrowsError(try StateFrame(data: good.dropLast()))
        for (index, byte) in [(0, UInt8(0)), (4, 2), (6, 2), (13, 0xff), (14, 9), (15, 1), (24, 128)] {
            var bad = good; bad[index] = byte
            XCTAssertThrowsError(try StateFrame(data: bad), "offset \(index)")
        }
        var badAxis = good; badAxis[16] = 0; badAxis[17] = 0x80
        XCTAssertThrowsError(try StateFrame(data: badAxis))
    }

    func testPointerModesRoundTripIncludingPausedFrames() throws {
        for mode in [PointerMode.profile, .cursor, .aim] {
            var state = GamepadState(); state.pointerMode = mode
            XCTAssertFalse(state.hasActiveControls)
            XCTAssertEqual(try StateFrame(data: StateFrame(sequence: 1, state: state).encode()).state, state)
            state.isPaused = true
            XCTAssertEqual(try StateFrame(data: StateFrame(sequence: 2, state: state).encode()).state, state)
            state.rightTrigger = 255
            XCTAssertThrowsError(try StateFrame(data: StateFrame(sequence: 3, state: state).encode()))
        }
        var bad = StateFrame(sequence: 0, state: .neutral).encode(); bad[7] = 3
        XCTAssertThrowsError(try StateFrame(data: bad))
    }
    func testPhonePointerModeOverridesProfileWithoutReconnection() {
        XCTAssertFalse(PointerMode.cursor.usesRelativeAim(profile: true))
        XCTAssertTrue(PointerMode.aim.usesRelativeAim(profile: false))
        XCTAssertFalse(PointerMode.profile.usesRelativeAim(profile: false))
        XCTAssertTrue(PointerMode.profile.usesRelativeAim(profile: true))
    }
    func testPointerModeDoesNotBypassInputRearming() {
        var gate = KeyboardInputGate()
        var state = GamepadState(); state.pointerMode = .cursor; state.rightTrigger = 255
        XCTAssertEqual(gate.evaluate(state: state, lastInput: 0, now: 0, authorized: true, focused: true), .release)
        XCTAssertFalse(gate.filteredState.hasActiveControls)
        XCTAssertEqual(gate.filteredState.pointerMode, .cursor)
        state.rightTrigger = 0
        XCTAssertEqual(gate.evaluate(state: state, lastInput: 0.1, now: 0.1, authorized: true, focused: true), .active)
    }
    func testSequenceWrapAndRejectDuplicateOrSkippedPackets() throws {
        var guardrail = SequenceGuard()
        try guardrail.accept(UInt32.max); try guardrail.accept(0); try guardrail.accept(1)
        XCTAssertThrowsError(try guardrail.accept(1))
        XCTAssertThrowsError(try guardrail.accept(3))
        try guardrail.accept(2)
    }

    func testRadialStickDeadZoneAndClamping() {
        XCTAssertEqual(GamepadState.stick(x: 0.05, y: 0.05).0, 0)
        let diagonal = GamepadState.stick(x: 2, y: -2)
        XCTAssertEqual(diagonal.0, 23170); XCTAssertEqual(diagonal.1, -23170)
        XCTAssertEqual(GamepadState.stick(x: 0, y: -1).1, -32767)
        XCTAssertEqual(GamepadState.axis(.infinity), 0)
        XCTAssertEqual(GamepadState.axis(.nan), 0)
    }

    func testHIDNeutralAndControls() {
        XCTAssertEqual(Array(HIDReport.encode(.neutral)), [0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        var s = GamepadState()
        for button in PadButton.allCases { s.set(button, pressed: true) }
        s.hat = 3; s.leftTrigger = 255; s.rightTrigger = 255; s.rightX = 32767
        XCTAssertEqual(Array(HIDReport.encode(s)), [255, 3, 3, 0, 0, 0, 0, 255, 127, 0, 0, 255, 255])
        for button in PadButton.allCases { s.set(button, pressed: false) }
        XCTAssertEqual(s.buttons, 0)
    }

    func testDescriptorInputSizeMatchesReports() {
        let bytes = Array(HIDReport.descriptor)
        var i = 0, size = 0, count = 0, bits = 0
        while i < bytes.count {
            let prefix = bytes[i]; i += 1
            let length = [0, 1, 2, 4][Int(prefix & 3)]
            XCTAssertLessThanOrEqual(i + length, bytes.count)
            let value = (0..<length).reduce(0) { $0 | Int(bytes[i + $1]) << ($1 * 8) }
            switch prefix & 0xfc {
            case 0x74: size = value
            case 0x94: count = value
            case 0x80: bits += size * count
            default: break
            }
            i += length
        }
        XCTAssertEqual(bits, HIDReport.byteCount * 8)
    }
}
