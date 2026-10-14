import XCTest
@testable import GamepadCore

final class KeyboardMappingTests: XCTestCase {
    func testDodgeOrderAndQuickLiftCompletesTap() {
        var mapper = KeyboardMapper(profile: .starter)
        var state = GamepadState(); state.set(.east, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.mouseRight)])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.01), [])
        XCTAssertEqual(mapper.tick(now: 0.031), [.down(.space)])
        XCTAssertEqual(mapper.tick(now: 0.151), [.up(.space), .up(.mouseRight)])
        XCTAssertEqual(mapper.tick(now: 1), [])
    }
    func testSharedRMBRemainsHeldAfterDodge() {
        var mapper = KeyboardMapper(profile: .starter)
        var state = GamepadState(); state.leftTrigger = 255
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.mouseRight)])
        state.set(.east, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0.1), [])
        XCTAssertEqual(mapper.tick(now: 0.131), [.down(.space)])
        XCTAssertEqual(mapper.tick(now: 0.251), [.up(.space)])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.3), [.up(.mouseRight)])
    }
    func testHoldComboCancellationNeverPressesDelayedKey() {
        var profile = KeyboardProfile(); profile[.south] = KeyBinding([.shift, .w])
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.set(.south, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.shift)])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.01), [.up(.shift)])
        XCTAssertEqual(mapper.tick(now: 1), [])
    }
    func testHoldComboReleasesInReverseAndDoesNotRepeat() {
        var profile = KeyboardProfile(); profile[.south] = KeyBinding([.control, .shift, .a])
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.set(.south, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.control)])
        XCTAssertEqual(mapper.tick(now: 0.031), [.down(.shift)])
        XCTAssertEqual(mapper.tick(now: 0.061), [.down(.a)])
        XCTAssertEqual(mapper.receive(state, now: 0.5), [])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.6), [.up(.a), .up(.shift), .up(.control)])
    }
    func testResetAndEditPauseCancelPendingTap() throws {
        var mapper = KeyboardMapper(profile: .starter)
        var state = GamepadState(); state.set(.east, pressed: true)
        _ = mapper.receive(state, now: 0)
        XCTAssertEqual(mapper.receive(.paused, now: 0.01), [.up(.mouseRight)])
        XCTAssertEqual(mapper.tick(now: 1), [])
        XCTAssertEqual(try StateFrame(data: StateFrame(sequence: 0, state: .paused).encode()).state, .paused)
        state.isPaused = true
        XCTAssertThrowsError(try StateFrame(data: StateFrame(sequence: 0, state: state).encode()))
    }
    func testSharedKeyboardKeyUsesAllOwners() {
        var profile = KeyboardProfile()
        profile[.south] = KeyBinding([.space]); profile[.west] = KeyBinding([.space])
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.set(.south, pressed: true); state.set(.west, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.space)])
        state.set(.south, pressed: false)
        XCTAssertEqual(mapper.receive(state, now: 0.1), [])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.2), [.up(.space)])
    }
    func testLeftStickHysteresisAndDiagonal() {
        var mapper = KeyboardMapper(profile: .starter)
        var state = GamepadState(); state.leftY = -20000; state.leftX = 20000
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.w), .down(.d)])
        state.leftY = -10000; state.leftX = 10000
        XCTAssertEqual(mapper.receive(state, now: 0.1), [])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.2), [.up(.d), .up(.w)])
    }
    func testMouseSpeedDoesNotDependOnReceiveRateAndStopsOnReset() {
        var profile = KeyboardProfile.starter; profile.mouseSmoothing = 0
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.rightX = 32767
        _ = mapper.receive(state, now: 0); _ = mapper.tick(now: 0)
        for n in 1...20 { XCTAssertEqual(mapper.receive(state, now: Double(n) / 2000), []) }
        XCTAssertEqual(mapper.tick(now: 0.02), [.mouse(dx: 18, dy: 0)])
        _ = mapper.reset()
        XCTAssertEqual(mapper.tick(now: 1), [])
    }
    func testSmoothMotionIsIndependentOfTickRateAndStopsImmediately() {
        func travel(step: Double) -> Double {
            var mapper = KeyboardMapper(profile: .starter)
            var state = GamepadState(); state.rightX = 32767
            _ = mapper.receive(state, now: 0); _ = mapper.tick(now: 0)
            var distance = 0.0
            for n in 1...Int((0.1 / step).rounded()) {
                for event in mapper.tick(now: Double(n) * step) {
                    if case .mouse(let dx, _) = event { distance += dx }
                }
            }
            _ = mapper.receive(.neutral, now: 0.101)
            XCTAssertEqual(mapper.tick(now: 0.104), [])
            return distance
        }
        let fast = travel(step: 0.004)
        XCTAssertEqual(fast, travel(step: 0.01), accuracy: 0.000001)
        XCTAssertEqual(fast, 900 * (0.1 - 0.025 * (1 - exp(-4))), accuracy: 0.000001)
    }
    func testSmoothAimRampsAndResetClearsVelocity() {
        var mapper = KeyboardMapper(profile: .starter)
        var state = GamepadState(); state.rightX = 32767
        _ = mapper.receive(state, now: 0); _ = mapper.tick(now: 0)
        let first = mapper.tick(now: 0.004)
        guard case .mouse(let dx, _) = first.first else { return XCTFail("Missing motion") }
        XCTAssertGreaterThan(dx, 0); XCTAssertLessThan(dx, 3.6)
        _ = mapper.tick(now: 0.02); _ = mapper.reset()
        _ = mapper.receive(state, now: 1); _ = mapper.tick(now: 1)
        guard case .mouse(let restarted, _) = mapper.tick(now: 1.004).first else { return XCTFail("Missing motion") }
        XCTAssertEqual(dx, restarted, accuracy: 0.000001)
    }
    func testOldProfileKeepsMappingsWithDefaultSmoothing() throws {
        var profile = KeyboardProfile.starter
        profile[.south] = KeyBinding([.z])
        let data = try JSONEncoder().encode(profile)
        let restored = KeyboardProfile.restore(data)
        XCTAssertEqual(restored[.south].outputs, [.z])
        XCTAssertEqual(restored.smoothingTime, 0.025)
    }
    func testAutoRunIsRadialAndHasHysteresis() {
        var profile = KeyboardProfile.starter; profile.autoRunEnabled = true
        var state = GamepadState(); state.leftX = 20000; state.leftY = 20000
        let active = profile.activeControls(state, previous: [])
        XCTAssertTrue(active.contains(.autoRun)) // radius 86%, each axis only 61%
        state.leftX = 25558; state.leftY = 0 // 78%: inside start, outside release
        XCTAssertFalse(profile.activeControls(state, previous: []).contains(.autoRun))
        XCTAssertTrue(profile.activeControls(state, previous: active).contains(.autoRun))
        state.leftX = 24000
        XCTAssertFalse(profile.activeControls(state, previous: active).contains(.autoRun))
        profile.autoRunThreshold = 0.9
        state.leftX = 20000; state.leftY = 20000
        XCTAssertFalse(profile.activeControls(state, previous: []).contains(.autoRun))
        profile.autoRunEnabled = false; state.leftX = 32767
        XCTAssertFalse(profile.activeControls(state, previous: []).contains(.autoRun))
    }
    func testAutoRunSharesShiftAndReleasesOnReset() {
        var profile = KeyboardProfile.starter; profile.autoRunEnabled = true
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.leftX = 32767
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.d), .down(.shift)])
        state.set(.leftShoulder, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0.1), [])
        state.leftX = 0
        XCTAssertEqual(mapper.receive(state, now: 0.2), [.up(.d)])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.3), [.up(.shift)])
        state.set(.leftShoulder, pressed: false); state.leftX = 32767
        _ = mapper.receive(state, now: 0.4)
        XCTAssertEqual(mapper.reset(), [.up(.shift), .up(.d)])
    }
    func testRunMappingIsCustomizableAndAlwaysHeld() {
        var profile = KeyboardProfile.starter; profile.autoRunEnabled = true
        profile[.autoRun] = KeyBinding([.control], behavior: .tap)
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.leftX = 32767
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.d), .down(.control)])
        XCTAssertEqual(mapper.tick(now: 1), [])
        XCTAssertEqual(mapper.receive(.neutral, now: 1.1), [.up(.control), .up(.d)])
    }
    func testNewSettingsKeepOldProfilesAndSanitize() throws {
        let restored = KeyboardProfile.restore(try JSONEncoder().encode(KeyboardProfile.starter))
        XCTAssertEqual(restored.updateRate, 1000)
        XCTAssertEqual(restored.runThreshold, 0.8)
        XCTAssertNil(restored.autoRunEnabled)
        XCTAssertEqual(restored[.autoRun].outputs, [.shift])
        var profile = restored; profile.autoRunEnabled = true
        profile.autoRunThreshold = 4; profile.mouseUpdateRate = 9
        let loaded = KeyboardProfile.restore(try JSONEncoder().encode(profile))
        XCTAssertEqual(loaded.runThreshold, 0.95)
        XCTAssertEqual(loaded.updateRate, 1000)
        XCTAssertEqual(loaded.autoRunEnabled, true)
    }
    func testAttackRemainsHeldWhileMovingAimingAndAutoRunning() {
        var profile = KeyboardProfile.starter; profile.autoRunEnabled = true
        var mapper = KeyboardMapper(profile: profile)
        var state = GamepadState(); state.rightTrigger = 255
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.mouseLeft)])
        for n in 1...1000 {
            let t = Double(n) / 1000
            state.leftX = n % 2 == 0 ? 32767 : 16000
            state.rightX = n % 2 == 0 ? -23000 : 23000
            let events = mapper.receive(state, now: t) + mapper.tick(now: t)
            XCTAssertFalse(events.contains(.up(.mouseLeft)))
            XCTAssertFalse(events.contains(.down(.mouseLeft)))
        }
        let released = mapper.receive(.neutral, now: 1.1)
        XCTAssertTrue(released.contains(.up(.mouseLeft)))
        XCTAssertEqual(mapper.reset(), [])
    }
    func testFocusTimeoutAndPauseRequireNeutralToRearm() {
        var gate = KeyboardInputGate()
        var held = GamepadState(); held.set(.south, pressed: true)
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0, now: 0, authorized: true, focused: true), .release)
        XCTAssertEqual(gate.evaluate(state: .neutral, lastInput: 0, now: 0, authorized: true, focused: true), .active)
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0, now: 0.1, authorized: true, focused: true), .active)
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0, now: 0.1, authorized: true, focused: false), .focus)
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0, now: 0.1, authorized: true, focused: true), .release)
        XCTAssertEqual(gate.evaluate(state: .neutral, lastInput: 0, now: 0.25, authorized: true, focused: true), .stale)
        XCTAssertEqual(gate.evaluate(state: .paused, lastInput: 1, now: 1, authorized: true, focused: true), .editing)
        XCTAssertEqual(gate.evaluate(state: .neutral, lastInput: 1, now: 1, authorized: false, focused: true), .permission)
    }
    func testAttackCanRearmAfterStallWhileMovementStaysHeld() {
        var gate = KeyboardInputGate()
        _ = gate.evaluate(state: .neutral, lastInput: 0, now: 0, authorized: true, focused: true)
        var held = GamepadState(); held.leftX = 32767; held.rightTrigger = 255
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0.1, now: 0.1, authorized: true, focused: true), .active)
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0.1, now: 0.4, authorized: true, focused: true), .stale)
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0.5, now: 0.5, authorized: true, focused: true), .release)
        held.rightTrigger = 0
        _ = gate.evaluate(state: held, lastInput: 0.6, now: 0.6, authorized: true, focused: true)
        held.rightTrigger = 255
        XCTAssertEqual(gate.evaluate(state: held, lastInput: 0.7, now: 0.7, authorized: true, focused: true), .active)
        XCTAssertEqual(gate.filteredState.rightTrigger, 255)
        XCTAssertEqual(gate.filteredState.leftX, 0) // no replay of old held movement
        var mapper = KeyboardMapper(profile: .starter)
        XCTAssertEqual(mapper.receive(gate.filteredState, now: 0.7), [.down(.mouseLeft)])
        held.leftX = 0
        _ = gate.evaluate(state: held, lastInput: 0.8, now: 0.8, authorized: true, focused: true)
        held.leftX = 32767
        _ = gate.evaluate(state: held, lastInput: 0.9, now: 0.9, authorized: true, focused: true)
        XCTAssertEqual(gate.filteredState.leftX, 32767)
    }
    func testFocusRecoveryDoesNotReplayOtherHeldControls() {
        var gate = KeyboardInputGate()
        var state = GamepadState(); state.set(.south, pressed: true); state.setCustom(0, pressed: true)
        state.leftTrigger = 255; state.rightX = 32767; state.hat = 0
        _ = gate.evaluate(state: state, lastInput: 0, now: 0, authorized: true, focused: false)
        _ = gate.evaluate(state: state, lastInput: 1, now: 1, authorized: true, focused: true)
        XCTAssertEqual(gate.filteredState, .neutral)
        state.rightTrigger = 255
        XCTAssertEqual(gate.evaluate(state: state, lastInput: 1.1, now: 1.1, authorized: true, focused: true), .active)
        var expected = GamepadState(); expected.rightTrigger = 255
        XCTAssertEqual(gate.filteredState, expected)
        state.setCustom(0, pressed: false)
        _ = gate.evaluate(state: state, lastInput: 1.2, now: 1.2, authorized: true, focused: true)
        state.setCustom(0, pressed: true)
        _ = gate.evaluate(state: state, lastInput: 1.3, now: 1.3, authorized: true, focused: true)
        expected.setCustom(0, pressed: true)
        XCTAssertEqual(gate.filteredState, expected)
    }
    func testProfilePersistenceAndSanitization() throws {
        var profile = KeyboardProfile.starter
        profile[.east] = KeyBinding([.mouseRight, .space, .space, .shift, .a, .b], behavior: .tap)
        profile.comboGap = -1; profile.mouseSpeed = 9000
        let restored = KeyboardProfile.restore(try JSONEncoder().encode(profile))
        XCTAssertEqual(restored[.east].outputs, [.mouseRight, .space, .shift, .a])
        XCTAssertEqual(restored.comboGap, 0.01); XCTAssertEqual(restored.mouseSpeed, 2400)
        XCTAssertEqual(KeyboardProfile.restore(Data("bad".utf8)), .starter)
        XCTAssertEqual(OutputToken.w.keyCode, 13); XCTAssertNil(OutputToken.mouseRight.keyCode)
    }
}
