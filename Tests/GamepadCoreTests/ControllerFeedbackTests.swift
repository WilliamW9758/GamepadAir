import XCTest
@testable import GamepadCore

final class ControllerFeedbackTests: XCTestCase {
    func testSparseRadialSplitsAtMappedDirectionMidpoints() {
        let vertical = [0, -1, -1, -1, 4, -1, -1, -1]
        XCTAssertEqual(RadialInput.direction(x: 100, y: -1, deadZone: 0, slots: vertical), 0)
        XCTAssertEqual(RadialInput.direction(x: -100, y: 1, deadZone: 0, slots: vertical), 4)
        let horizontal = [-1, -1, 2, -1, -1, -1, 6, -1]
        XCTAssertEqual(RadialInput.direction(x: 1, y: -100, deadZone: 0, slots: horizontal), 2)
        XCTAssertEqual(RadialInput.direction(x: -1, y: 100, deadZone: 0, slots: horizontal), 6)
        XCTAssertNil(RadialInput.direction(x: 100, y: 0, deadZone: 0, slots: Array(repeating: -1, count: 8)))
        XCTAssertNil(RadialInput.direction(x: 0, y: 0, deadZone: 24, slots: vertical))
        XCTAssertEqual(RadialInput.direction(x: -100, y: 0, deadZone: 24, slots: [0]), 0)
        // Wrap-around neighbor at upper-left wins just left of north.
        XCTAssertEqual(RadialInput.direction(x: -1, y: -100, deadZone: 0, slots: [-1, 1, -1, -1, -1, -1, -1, 7]), 7)
    }
    func testRadialTelemetryRoundTripsWithoutPressingGameButtons() throws {
        for value in UInt8(0)...9 {
            var state = GamepadState.neutral
            state.radialPreview = value
            let decoded = try StateFrame(data: StateFrame(sequence: 1, state: state).encode())
            XCTAssertEqual(decoded.state, state)
            XCTAssertFalse(decoded.state.hasActiveControls)
        }
        var invalid = StateFrame(sequence: 0, state: .neutral).encode()
        invalid[15] = 10
        XCTAssertThrowsError(try StateFrame(data: invalid))
    }
    func testCenterHoldLatchesThroughMovement() {
        var hold = StickClickHold(now: 10)
        hold.update(x: 0.1, y: 0, now: 10.4); XCTAssertFalse(hold.pressed)
        hold.update(x: 0.1, y: 0, now: 10.46); XCTAssertTrue(hold.pressed)
        hold.update(x: 1, y: -1, now: 11); XCTAssertTrue(hold.pressed)
    }
    func testMovingBeforeHoldCancelsUntilNextTouch() {
        var hold = StickClickHold(now: 0)
        hold.update(x: 0.21, y: 0, now: 0.1)
        hold.update(x: 0, y: 0, now: 1); XCTAssertFalse(hold.pressed)
        hold = StickClickHold(now: 1)
        hold.update(x: 0, y: 0, now: 1.46); XCTAssertTrue(hold.pressed)
    }
    func testRumbleFramesDoNotOverlapSetupCommands() {
        let rumble = RumbleFrame(low: 42, high: 255)
        XCTAssertEqual(RumbleFrame(data: rumble.data), rumble)
        XCTAssertNil(RumbleFrame(data: SetupStage.play.encode()))
        XCTAssertNil(RumbleFrame(data: Data([0x49,0x52,1])))
    }
    func testMotorReportsAndLightingOnlyWrites() {
        XCTAssertEqual(RumbleFrame.decodeHID(Data([5,1,0,0,100,200,0]), reportID: 5, style: .playStation), RumbleFrame(low: 200, high: 100))
        XCTAssertNil(RumbleFrame.decodeHID(Data([5,2,0,0,100,200,0]), reportID: 5, style: .playStation))
        XCTAssertEqual(RumbleFrame.decodeHID(Data([3,15,0,0,100,50,255,0,0]), reportID: 3, style: .xbox), RumbleFrame(low: 255, high: 127))
        XCTAssertEqual(RumbleFrame.decodeHID(Data([3,0,0,0,100,100,255,0,0]), reportID: 3, style: .xbox), RumbleFrame())
    }
    func testViewUsesSeriesControllerBitTen() {
        var state = GamepadState(); state.set(.back, pressed: true)
        let bytes = XboxHIDReport.encode(state)
        XCTAssertEqual(bytes[15], 4); XCTAssertEqual(bytes[16], 0)
    }
    func testLayoutHapticsDefaultToMediumAndRoundTrip() throws {
        var layout = LocalLayout(name: "Test", style: .xbox)
        XCTAssertEqual(layout.effectiveTouchHaptic, .medium)
        layout.document.haptics = "off"
        let restored = LocalLayout(document: try LayoutDocument.decode(layout.document.validatedData()))
        XCTAssertEqual(restored.effectiveTouchHaptic, .off)
    }
}
