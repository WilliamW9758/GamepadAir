import XCTest
@testable import GamepadCore

final class GamepadMappingTests: XCTestCase {
    func testDefaultPreservesEveryControllerInput() {
        let profile = GamepadProfile()
        for hat in UInt8(0)...8 {
            var state = GamepadState()
            state.buttons = 2047; state.hat = hat
            state.leftX = -32767; state.leftY = 1234
            state.rightX = 32767; state.rightY = -2345
            state.leftTrigger = 255; state.rightTrigger = 255
            XCTAssertEqual(profile.apply(state), state)
        }
    }
    func testGuidePresencePreservesBothTriggers() {
        var layout = SavedLayout(name: "Guide", style: .xbox)
        layout.inputType = .gamepad
        XCTAssertTrue(layout.presentControls.contains(.guide))
        XCTAssertTrue(layout.presentControls.contains(.leftTrigger))
        XCTAssertTrue(layout.presentControls.contains(.rightTrigger))
        layout.inputType = .keyboardMouse
        XCTAssertFalse(layout.presentControls.contains(.guide))
        XCTAssertTrue(layout.presentControls.contains(.rightTrigger))
        XCTAssertEqual(layout.converted(to: .gamepad).gamepadProfile?[.guide], .guide)
    }

    func testGuideRoundTripMappingAndRelease() throws {
        var state = GamepadState()
        state.set(.guide, pressed: true)
        let decoded = try StateFrame(data: StateFrame(sequence: 9, state: state).encode()).state
        XCTAssertEqual(decoded.buttons, 1 << 10)
        XCTAssertEqual(GamepadProfile().apply(decoded), state)
        XCTAssertEqual(MappedControl.guide.canvasID, "button-10")
        XCTAssertEqual(KeyboardProfile.starter.activeControls(decoded, previous: []), [.guide])
        var profile = GamepadProfile()
        profile[.guide] = .start
        XCTAssertEqual(profile.apply(decoded).buttons, PadButton.start.mask)
        state.set(.guide, pressed: false)
        XCTAssertEqual(profile.apply(state), .neutral)
        state.buttons = 1 << 11
        XCTAssertThrowsError(try StateFrame(data: StateFrame(sequence: 10, state: state).encode()))
    }

    func testSharedBindingRemainsHeldUntilBothSourcesRelease() {
        var profile = GamepadProfile()
        profile[.south] = .rightTrigger; profile[.custom1] = .rightTrigger
        var state = GamepadState()
        state.set(.south, pressed: true); state.customButtons = 1
        XCTAssertEqual(profile.apply(state).rightTrigger, 255)
        state.set(.south, pressed: false)
        XCTAssertEqual(profile.apply(state).rightTrigger, 255)
        state.customButtons = 0
        XCTAssertEqual(profile.apply(state), .neutral)
    }
    func testCustomDirectionsCombineAndOppositesCancel() {
        var profile = GamepadProfile()
        profile[.custom1] = .dpadUp; profile[.custom2] = .dpadRight
        profile[.custom3] = .dpadDown
        var state = GamepadState(); state.customButtons = 3
        XCTAssertEqual(profile.apply(state).hat, 1)
        state.customButtons = 5
        XCTAssertEqual(profile.apply(state).hat, 8)
    }
    func testPauseReleasesAndStickTransformClamps() {
        var profile = GamepadProfile()
        profile.swapSticks = true; profile.invertLeftY = true
        var state = GamepadState()
        state.rightY = .min; state.leftX = 123
        XCTAssertEqual(profile.apply(state).leftY, 32767)
        XCTAssertEqual(profile.apply(state).rightX, 123)
        state.isPaused = true
        XCTAssertEqual(profile.apply(state), .neutral)
    }
    func testPersistenceAndUnassignedButtons() throws {
        var profile = GamepadProfile(); profile[.south] = nil
        profile[.custom16] = .east
        XCTAssertEqual(GamepadProfile.restore(try JSONEncoder().encode(profile)), profile)
        var state = GamepadState(); state.set(.south, pressed: true)
        XCTAssertEqual(profile.apply(state), .neutral)
        state.customButtons = 1 << 15
        XCTAssertEqual(profile.apply(state).buttons, 2)
        profile.version = 99
        XCTAssertEqual(GamepadProfile.restore(try JSONEncoder().encode(profile)), GamepadProfile())
    }
}
