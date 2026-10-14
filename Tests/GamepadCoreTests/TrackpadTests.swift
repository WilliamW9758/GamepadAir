import XCTest
@testable import GamepadCore

final class TrackpadTests: XCTestCase {
    func testTapAndStationaryHoldClickOnlyOnce() {
        var pad = TrackpadGesture()
        pad.begin(x: 100, y: 100, now: 0)
        _ = pad.move(x: 102, y: 102)
        XCTAssertNil(pad.hold(now: 0.49, delay: 0.5))
        XCTAssertEqual(pad.end(now: 0.49, delay: 0.5), .leftClick)
        XCTAssertNil(pad.end(now: 1, delay: 0.5))
        pad.begin(x: 100, y: 100, now: 2)
        XCTAssertEqual(pad.hold(now: 2.5, delay: 0.5), .rightClick)
        XCTAssertNil(pad.hold(now: 3, delay: 0.5))
        XCTAssertNil(pad.end(now: 3, delay: 0.5))
        pad.begin(x: 0, y: 0, now: 4)
        // Delayed UI timer must still recognize a long hold on release.
        XCTAssertEqual(pad.end(now: 4.6, delay: 0.5), .rightClick)
    }
    func testSwipeIsRelativeAndNeverClicksEvenAfterReturningToOrigin() {
        var pad = TrackpadGesture()
        pad.begin(x: 100, y: 100, now: 0)
        XCTAssertEqual(pad.move(x: 110, y: 100).0, 10)
        XCTAssertEqual(pad.move(x: 110, y: 100).0, 0)
        XCTAssertEqual(pad.move(x: 105, y: 100).0, -5)
        _ = pad.move(x: 100, y: 100)
        XCTAssertNil(pad.hold(now: 1, delay: 0.5))
        XCTAssertNil(pad.end(now: 2, delay: 0.5))
        pad.begin(x: 0, y: 0, now: 3)
        pad.cancel()
        XCTAssertNil(pad.end(now: 3.1, delay: 0.5))
        XCTAssertNil(pad.hold(now: 4, delay: 0.5))
        XCTAssertEqual(pad.move(x: 100, y: 100).0, 0)
    }
    func testPointerFramesRoundTripAndRejectMalformedCommands() throws {
        for frame in [PointerFrame(sequence: .max, action: .move, dx: -4096, dy: 4096),
                      PointerFrame(sequence: 0, action: .leftClick), PointerFrame(sequence: 1, action: .rightClick)] {
            XCTAssertEqual(try PointerFrame(data: frame.encode()), frame)
        }
        let valid = PointerFrame(sequence: 4, action: .leftClick).encode()
        for index in [7, 12, 15, 20, 27] {
            var bad = valid; bad[index] = 1
            XCTAssertThrowsError(try PointerFrame(data: bad))
        }
        XCTAssertThrowsError(try PointerFrame(data: PointerFrame(sequence: 0, action: .rightClick, dx: 1).encode()))
        XCTAssertThrowsError(try PointerFrame(data: PointerFrame(sequence: 0, action: .move, dx: 4097).encode()))
        var guarder = SequenceGuard()
        try guarder.accept(UInt32.max)
        try guarder.accept(0)
        XCTAssertThrowsError(try guarder.accept(0))
    }
    func testTrackpadPulseDoesNotReleaseAnAttackHeldByAnotherControl() {
        var mapper = KeyboardMapper(profile: .starter)
        var state = GamepadState(); state.rightTrigger = 255
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.mouseLeft)])
        XCTAssertEqual(mapper.pointerClick(right: false, now: 0.1), [])
        XCTAssertEqual(mapper.tick(now: 0.3), [])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.4), [.up(.mouseLeft)])
        XCTAssertEqual(mapper.pointerClick(right: true, now: 0.5), [.down(.mouseRight)])
        XCTAssertEqual(mapper.tick(now: 0.7), [.up(.mouseRight)])
        XCTAssertEqual(mapper.pointerClick(right: false, now: 1), [.down(.mouseLeft)])
        XCTAssertEqual(mapper.reset(), [.up(.mouseLeft)])
        XCTAssertEqual(mapper.tick(now: 2), [])
    }
    func testScrollBindingsPersistAndReleaseOnReset() throws {
        var profile = KeyboardProfile.starter
        profile.tapDuration = 0.5 // Wheel taps must stop before the repeat delay.
        profile[.south] = KeyBinding([.scrollUp], behavior: .tap)
        profile[.north] = KeyBinding([.scrollDown], behavior: .hold)
        let restored = try JSONDecoder().decode(KeyboardProfile.self, from: JSONEncoder().encode(profile))
        var mapper = KeyboardMapper(profile: restored)
        var state = GamepadState(); state.set(.south, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 0), [.down(.scrollUp)])
        XCTAssertEqual(mapper.receive(.neutral, now: 0.01), [])
        XCTAssertEqual(mapper.tick(now: 0.2), [.up(.scrollUp)])
        XCTAssertEqual(mapper.tick(now: 0.4), [])
        state = .neutral; state.set(.north, pressed: true)
        XCTAssertEqual(mapper.receive(state, now: 1), [.down(.scrollDown)])
        XCTAssertEqual(mapper.tick(now: 2), [])
        XCTAssertEqual(mapper.reset(), [.up(.scrollDown)])
        XCTAssertEqual(mapper.tick(now: 3), [])
    }
}
