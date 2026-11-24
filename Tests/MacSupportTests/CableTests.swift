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
    func testSetupReturnChannelTracksStagesWhileInputContinues() throws {
        let (reader, writer) = try pair()
        let session = CableSession(connect: { reader }, output: { MonitorOutput() }, update: { _ in })
        session.setSetupStage(.pairing)
        session.start()
        defer { session.stop() }
        XCTAssertEqual(try writer.readExactly(StateFrame.hello.count, timeout: 1), StateFrame.hello)
        XCTAssertEqual(try SetupStage(data: writer.readExactly(4, timeout: 1)), .pairing)
        for (index, stage) in [SetupStage.practice, .controls, .play].enumerated() {
            session.setSetupStage(stage)
            try writer.write(StateFrame(sequence: UInt32(index), state: .paused).encode())
            XCTAssertEqual(try SetupStage(data: writer.readExactly(4, timeout: 1)), stage)
        }
    }

    func testPlayWaitsForControllerTrafficBeforeReportingConnection() throws {
        let (reader, writer) = try pair()
        let connected = expectation(description: "Confirmed connection")
        let session = CableSession(connect: { reader }, output: { MonitorOutput() }, update: { event in
            if event.connected && event.frames == 1 { connected.fulfill() }
        })
        session.setSetupStage(.play)
        session.start()
        defer { session.stop() }
        XCTAssertEqual(try writer.readExactly(StateFrame.hello.count, timeout: 1), StateFrame.hello)
        XCTAssertThrowsError(try writer.readExactly(4, timeout: 0.05))
        try writer.write(StateFrame(sequence: 0, state: .paused).encode())
        XCTAssertEqual(try SetupStage(data: writer.readExactly(4, timeout: 1)), .play)
        wait(for: [connected], timeout: 1)
    }

    func testEditorPauseKeepsHeartbeatAliveAndResumesSameConnection() throws {
        let (reader, writer) = try pair()
        let resumed = expectation(description: "Input resumes on the existing link")
        let sink = EditorPauseOutput(resumed: resumed)
        let session = CableSession(connect: { reader }, output: { sink }, update: { _ in })
        session.setOutputPaused(true)
        session.start()
        defer { session.stop() }
        XCTAssertEqual(try writer.readExactly(StateFrame.hello.count, timeout: 1), StateFrame.hello)
        var held = GamepadState(); held.set(.south, pressed: true)
        // Longer than the heartbeat timeout: healthy traffic must keep editing connected.
        for sequence in UInt32(0)..<20 {
            try writer.write(StateFrame(sequence: sequence, state: held).encode())
            Thread.sleep(forTimeInterval: 0.025)
        }
        session.setOutputPaused(false)
        try writer.write(StateFrame(sequence: 20, state: .neutral).encode())
        wait(for: [resumed], timeout: 1)
    }

    func testPhoneLayoutTelemetryInterleavesWithState() throws {
        let snapshot = ControllerSnapshot(layout: SavedLayout(name: "Phone layout", style: .xbox), modeIndex: 1)
        let chunks = try LayoutTelemetry.chunks(snapshot)
        var receiver = LayoutTelemetryReceiver()
        var result: ControllerSnapshot?
        for chunk in chunks { if let value = try receiver.accept(chunk) { result = value } }
        XCTAssertEqual(result, snapshot)
        XCTAssertThrowsError(try receiver.accept(Data(repeating: 0, count: 28)))

        let (reader, writer) = try pair()
        let received = expectation(description: "Phone layout is published with live input")
        let session = CableSession(connect: { reader }, output: { MonitorOutput() }, update: { event in
            if event.layout == snapshot { received.fulfill() }
        })
        session.start()
        defer { session.stop() }
        _ = try writer.readExactly(StateFrame.hello.count, timeout: 1)
        var sequence: UInt32 = 0
        for var chunk in chunks {
            try writer.write(StateFrame(sequence: sequence, state: .neutral).encode()); sequence &+= 1
            for i in 0..<4 { chunk[8 + i] = UInt8(truncatingIfNeeded: sequence >> (8 * i)) }
            try writer.write(chunk); sequence &+= 1
        }
        try writer.write(StateFrame(sequence: sequence, state: .neutral).encode())
        wait(for: [received], timeout: 2)
    }

    func testLayoutCommandsRoundTripAndRejectMalformedFrames() throws {
        var layout = SavedLayout(name: "Custom 中文", style: .xbox)
        layout.isPreset = false
        let commands = [
            LayoutCommand(action: .select, layoutID: layout.id),
            LayoutCommand(action: .create, layout: layout),
            LayoutCommand(action: .save, layout: layout, base: layout)
        ]
        for command in commands {
            let bytes = try command.encode()
            var receiver = LayoutCommandReceiver()
            var decoded: LayoutCommand?
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                if let value = try receiver.accept(bytes.subdata(in: offset..<(offset + 4))) { decoded = value }
            }
            XCTAssertEqual(decoded, command)
        }
        var receiver = LayoutCommandReceiver()
        XCTAssertThrowsError(try receiver.accept(Data([0x49, 0x50, 2, 65])))
        XCTAssertThrowsError(try receiver.accept(Data([0, 0, 0, 0])))
    }

    func testScreenGeometryAndLibraryTelemetry() throws {
        let layout = SavedLayout(name: "Phone layout", style: .xbox)
        var snapshot = ControllerSnapshot(layout: layout, modeIndex: 0)
        snapshot.screen = PhoneScreen(model: "iPhone", width: 852, height: 393)
        snapshot.layouts = [LayoutSummary(layout)]
        snapshot.commandID = "confirmed"
        var receiver = LayoutTelemetryReceiver()
        var decoded: ControllerSnapshot?
        for chunk in try LayoutTelemetry.chunks(snapshot) {
            if let value = try receiver.accept(chunk) { decoded = value }
        }
        XCTAssertEqual(decoded, snapshot)
        snapshot.screen?.height = 0
        XCTAssertThrowsError(try LayoutTelemetry.chunks(snapshot).forEach { _ = try receiver.accept($0) })
    }

    func testSetupCommandRejectsUnknownVersionAndStage() throws {
        XCTAssertThrowsError(try SetupStage(data: Data([0x49, 0x50, 2, 1])))
        XCTAssertThrowsError(try SetupStage(data: Data([0x49, 0x50, 1, 4])))
        XCTAssertThrowsError(try SetupStage(data: Data([0x49, 0x50, 1])))
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
    func testPausedPracticeReachesMonitorWithoutSubmittingOutput() throws {
        let (reader, writer) = try pair()
        let observed = expectation(description: "Practice state arrives")
        let reset = expectation(description: "Output is reset")
        let sink = PracticeRecordingOutput(reset: reset)
        var practice = GamepadState.paused
        practice.leftX = 16000; practice.set(.south, pressed: true)
        let expected = practice
        let session = CableSession(connect: { reader }, output: { sink }, update: { event in
            if event.frames == 1 { XCTAssertEqual(event.state, expected); observed.fulfill() }
        })
        session.start()
        defer { session.stop() }
        _ = try writer.readExactly(StateFrame.hello.count, timeout: 1)
        try writer.write(StateFrame(sequence: 0, state: practice).encode())
        wait(for: [observed, reset], timeout: 0.2)
    }
    func testPointerTrafficCannotKeepHeldControllerStateAlive() throws {
        let (reader, writer) = try pair()
        let released = expectation(description: "State heartbeat expires despite pointer traffic")
        let finished = expectation(description: "Pointer sender finishes")
        let sink = RecordingOutput(released: released)
        let session = CableSession(connect: { reader }, output: { sink }, update: { _ in })
        session.start()
        defer { session.stop() }
        _ = try writer.readExactly(StateFrame.hello.count, timeout: 1)
        var state = GamepadState(); state.set(.south, pressed: true)
        try writer.write(StateFrame(sequence: 0, state: state).encode())
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            for sequence in UInt32(1)...40 {
                do { try writer.write(PointerFrame(sequence: sequence, action: .move, dx: 1).encode()) }
                catch { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        wait(for: [released], timeout: 0.6)
        wait(for: [finished], timeout: 1)
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

private final class PracticeRecordingOutput: GamepadOutput {
    let resetExpectation: XCTestExpectation
    private var resetSeen = false
    init(reset: XCTestExpectation) { resetExpectation = reset }
    func submit(_ state: GamepadState) throws { XCTFail("Paused practice must never reach game output") }
    func reset() throws {
        if !resetSeen { resetSeen = true; resetExpectation.fulfill() }
    }
    func close() {}
}


private final class EditorPauseOutput: GamepadOutput {
    let resumed: XCTestExpectation
    init(resumed: XCTestExpectation) { self.resumed = resumed }
    func submit(_ state: GamepadState) throws {
        XCTAssertEqual(state, .neutral, "Editor input must not reach the game")
        if state == .neutral { resumed.fulfill() }
    }
    func reset() throws {}
    func close() {}
}
