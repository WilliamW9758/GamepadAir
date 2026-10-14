import XCTest
@testable import GamepadCore

final class HoldAimTests: XCTestCase {
    func testThresholdAndFloatingCenterPreventActivationJump() {
        var aim = HoldAimGesture(); aim.begin(now: 10)
        let early = aim.update(x: 40, y: 50, now: 10.2, delay: 0.3, radius: 40)
        XCTAssertEqual(early.0, 0); XCTAssertEqual(early.1, 0)
        XCTAssertFalse(aim.isAiming)
        let activation = aim.update(x: 60, y: 70, now: 10.31, delay: 0.3, radius: 40)
        XCTAssertTrue(aim.isAiming)
        XCTAssertEqual(activation.0, 0); XCTAssertEqual(activation.1, 0)
        XCTAssertEqual(aim.originX, 60); XCTAssertEqual(aim.originY, 70)
        let moved = aim.update(x: 100, y: 70, now: 10.4, delay: 0.3, radius: 40)
        XCTAssertEqual(moved.0, 32767); XCTAssertEqual(moved.1, 0)
        let center = aim.update(x: 60, y: 70, now: 10.5, delay: 0.3, radius: 40)
        XCTAssertEqual(center.0, 0); XCTAssertEqual(center.1, 0)
    }
    func testReleaseCancelAndNewPressStartAsButton() {
        var aim = HoldAimGesture(); aim.begin(now: 0)
        _ = aim.update(x: 0, y: 0, now: 0.31, delay: 0.3, radius: 40)
        aim.reset()
        XCTAssertFalse(aim.isAiming)
        XCTAssertEqual(aim.update(x: 80, y: 0, now: 2, delay: 0.3, radius: 40).0, 0)
        aim.begin(now: 3)
        XCTAssertEqual(aim.update(x: 80, y: 0, now: 3.2, delay: 0.3, radius: 40).0, 0)
        XCTAssertFalse(aim.isAiming)
        aim.reset() // quick tap canceled before activation
        XCTAssertEqual(aim.update(x: 80, y: 0, now: 4, delay: 0.3, radius: 40).0, 0)
        XCTAssertFalse(aim.isAiming)
    }
    func testAttackRemainsDownDuringAimAndReleasesTogether() {
        var aim = HoldAimGesture(); aim.begin(now: 0)
        var mapper = KeyboardMapper(profile: .starter)
        var state = GamepadState(); state.rightTrigger = 255
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.mouseLeft)])
        _ = aim.update(x: 10, y: 10, now: 0.31, delay: 0.3, radius: 40)
        (state.rightX, state.rightY) = aim.update(x: 50, y: -30, now: 0.4, delay: 0.3, radius: 40)
        XCTAssertEqual(mapper.receive(state, now: 0.4), [])
        _ = mapper.tick(now: 0.4)
        XCTAssertTrue(mapper.tick(now: 0.41).contains { if case .mouse = $0 { return true }; return false })
        aim.reset()
        XCTAssertEqual(mapper.receive(.neutral, now: 0.42), [.up(.mouseLeft)])
        XCTAssertEqual(mapper.tick(now: 0.43), [])
    }
}
