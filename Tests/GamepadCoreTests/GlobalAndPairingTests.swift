import XCTest
@testable import GamepadCore

final class GlobalAndPairingTests: XCTestCase {
    func testGlobalAcceptsAppChangesButScopedTargetDoesNot() {
        XCTAssertTrue(InputTargetPolicy.accepts(global: true, selectedPID: nil, frontmostPID: 100))
        XCTAssertTrue(InputTargetPolicy.accepts(global: true, selectedPID: nil, frontmostPID: 200))
        XCTAssertFalse(InputTargetPolicy.accepts(global: false, selectedPID: nil, frontmostPID: nil))
        XCTAssertTrue(InputTargetPolicy.accepts(global: false, selectedPID: 100, frontmostPID: 100))
        XCTAssertFalse(InputTargetPolicy.accepts(global: false, selectedPID: 100, frontmostPID: 200))
    }
    func testGlobalStillRequiresPermissionFreshnessAndUnpausedInput() {
        var gate = KeyboardInputGate()
        XCTAssertEqual(gate.evaluate(state: .neutral, lastInput: 1, now: 1, authorized: true, focused: true), .active)
        XCTAssertEqual(gate.evaluate(state: .neutral, lastInput: 1, now: 1.1, authorized: false, focused: true), .permission)
        XCTAssertEqual(gate.evaluate(state: .neutral, lastInput: 1, now: 2, authorized: true, focused: true), .stale)
        XCTAssertEqual(gate.evaluate(state: .paused, lastInput: 2, now: 2, authorized: true, focused: true), .editing)
    }
    func testPairingCodeIsSixDigitsIncludingLeadingZeros() {
        for _ in 0..<100 {
            let code = WirelessSettings.newCode()
            XCTAssertTrue(WirelessSettings.validCode(code)); XCTAssertEqual(code.count, 6)
        }
        XCTAssertTrue(WirelessSettings.validCode("000001"))
        XCTAssertEqual(WirelessSettings.formattedCode("000001"), "000001")
        XCTAssertFalse(WirelessSettings.validCode("12345"))
        XCTAssertFalse(WirelessSettings.validCode("1234567"))
        XCTAssertFalse(WirelessSettings.validCode("ABCDEF"))
        XCTAssertFalse(WirelessSettings.validCode("123 456"))
    }
    func testPairingAttemptsAreLimitedAndRecoverAfterCooldown() {
        var limiter = PairingAttemptLimiter()
        for n in 0..<5 { XCTAssertTrue(limiter.accept(now: Double(n))) }
        XCTAssertFalse(limiter.accept(now: 5))
        XCTAssertFalse(limiter.accept(now: 59))
        XCTAssertTrue(limiter.accept(now: 60))
        XCTAssertFalse(limiter.accept(now: 60.5))
        limiter.succeeded()
        XCTAssertTrue(limiter.accept(now: 61))
    }
}
