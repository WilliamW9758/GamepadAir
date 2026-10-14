import XCTest
import Darwin
import GamepadCore
@testable import MacSupport

final class CableTests: XCTestCase {
    private func pair() throws -> (StreamSocket, StreamSocket) {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw LinkError.message("socketpair failed") }
        return (StreamSocket(fd: fds[0]), StreamSocket(fd: fds[1]))
    }
    func testFragmentedAndCoalescedFrames() throws {
        let (reader, writer) = try pair()
        let data = StateFrame(sequence: 1, state: .neutral).encode() + StateFrame(sequence: 2, state: .neutral).encode()
        DispatchQueue.global().async {
            try? writer.write(data.prefix(5))
            Thread.sleep(forTimeInterval: 0.02)
            try? writer.write(data.dropFirst(5))
        }
        XCTAssertEqual(try StateFrame(data: reader.readExactly(28, timeout: 1)).sequence, 1)
        XCTAssertEqual(try StateFrame(data: reader.readExactly(28, timeout: 1)).sequence, 2)
    }
    func testPartialFrameCannotKeepDeadlineAlive() throws {
        let (reader, writer) = try pair()
        try writer.write(Data([1, 2]))
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try reader.readExactly(28, timeout: 0.05))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.3)
    }
    func testDisconnectReleasesHeldControls() throws { try verifyRelease(stall: false) }
    func testStallReleasesHeldControls() throws { try verifyRelease(stall: true) }
    func testLayoutPauseResetsPendingOutput() throws {
        let (reader, writer) = try pair()
        let reset = expectation(description: "Pause calls reset rather than submitting neutral")
        let sink = ResetRecordingOutput(reset: reset)
        let session = CableSession(connect: { reader }, output: { sink }, update: { _ in })
        session.start()
        defer { session.stop() }
        _ = try writer.readExactly(StateFrame.hello.count, timeout: 1)
        var held = GamepadState(); held.set(.east, pressed: true)
        try writer.write(StateFrame(sequence: 0, state: held).encode() + StateFrame(sequence: 1, state: .paused).encode())
        wait(for: [reset], timeout: 0.2)
    }
    private func verifyRelease(stall: Bool) throws {
        let (reader, writer) = try pair()
        let released = expectation(description: "Held controls released")
        let sink = RecordingOutput(released: released)
        let session = CableSession(connect: { reader }, output: { sink }, update: { _ in })
        session.start()
        XCTAssertEqual(try writer.readExactly(StateFrame.hello.count, timeout: 1), StateFrame.hello)
        var state = GamepadState(); state.set(.south, pressed: true); state.leftX = 1234
        try writer.write(StateFrame(sequence: 0, state: state).encode())
        if !stall { writer.interrupt() }
        wait(for: [released], timeout: 1)
        session.stop()
    }
}

private final class ResetRecordingOutput: GamepadOutput {
    let expectation: XCTestExpectation
    private var pending = false
    init(reset: XCTestExpectation) { expectation = reset }
    func submit(_ state: GamepadState) throws { if state.buttons != 0 { pending = true } }
    func reset() throws { if pending { pending = false; expectation.fulfill() } }
    func close() {}
}

private final class RecordingOutput: GamepadOutput {
    let released: XCTestExpectation
    private var sawPressed = false
    private var fulfilled = false
    init(released: XCTestExpectation) { self.released = released }
    func submit(_ state: GamepadState) throws {
        if state.buttons != 0 { sawPressed = true }
        if sawPressed && state == .neutral && !fulfilled { fulfilled = true; released.fulfill() }
    }
    func close() {}
}
