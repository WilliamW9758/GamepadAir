import XCTest
import Network
import GamepadCore
@testable import MacSupport

final class WirelessTests: XCTestCase {
    func testFragmentedBLEPacketsAndCoalescedFramesKeepExactOrder() throws {
        let inbox = LinkInbox()
        let a = StateFrame(sequence: 0, state: .neutral).encode()
        let b = PointerFrame(sequence: 1, action: .leftClick).encode()
        let combined = a + b
        for start in stride(from: 0, to: combined.count, by: 20) { inbox.append(Data(combined[start..<min(start + 20, combined.count)])) }
        XCTAssertEqual(try inbox.read(28, timeout: 0.1), a)
        XCTAssertEqual(try inbox.read(28, timeout: 0.1), b)
    }
    func testInputDeadlineOverflowAndDisconnectDoNotDeliverStaleBytes() {
        let inbox = LinkInbox(); inbox.append(Data([1]))
        let began = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try inbox.read(28, timeout: 0.03))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 0.2)
        inbox.fail("Disconnected"); inbox.append(Data(repeating: 0, count: 28))
        XCTAssertThrowsError(try inbox.read(28, timeout: 1))
        let flooded = LinkInbox(); flooded.append(Data(repeating: 0, count: 8193))
        XCTAssertThrowsError(try flooded.read(1, timeout: 0.1))
    }
    func testEncryptedWiFiRoundTripAndWrongPairingCodeRejected() throws {
        let code = "012345"
        let listener = try NWListener(using: WirelessSettings.parameters(code: code), on: .any)
        let queue = DispatchQueue(label: "test.wifi")
        let listening = expectation(description: "TLS listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { listening.fulfill() } }
        var connections: [NWConnection] = []
        listener.newConnectionHandler = { connection in
            connections.append(connection)
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.receive(minimumIncompleteLength: 7, maximumLength: 7) { data, _, _, _ in
                        if data == StateFrame.hello {
                            connection.send(content: StateFrame(sequence: 0, state: .neutral).encode(), completion: .contentProcessed { _ in })
                        }
                    }
                }
            }
            connection.start(queue: queue)
        }
        listener.start(queue: queue)
        wait(for: [listening], timeout: 3)
        defer { listener.cancel(); queue.sync { connections.forEach { $0.cancel() } } }
        let port = try XCTUnwrap(listener.port?.rawValue)
        let client = WiFiLink(host: "127.0.0.1", code: code, port: port)
        defer { client.interrupt() }
        try client.prepare(timeout: 3)
        try client.write(StateFrame.hello)
        XCTAssertEqual(try client.readExactly(28, timeout: 1), StateFrame(sequence: 0, state: .neutral).encode())
        let wrong = WiFiLink(host: "127.0.0.1", code: "654321", port: port)
        defer { wrong.interrupt() }
        XCTAssertThrowsError(try wrong.prepare(timeout: 2))
    }
}

extension WirelessTests {
    func testNetworkErrorsAreNotMisreportedAsBadCodes() {
        XCTAssertTrue(WiFiLink.failureMessage(.posix(.EHOSTDOWN), localNetworkDenied: false).contains("unreachable"))
        XCTAssertTrue(WiFiLink.failureMessage(.posix(.ENETDOWN), localNetworkDenied: false).contains("unreachable"))
        XCTAssertTrue(WiFiLink.failureMessage(.posix(.EHOSTDOWN), localNetworkDenied: true).contains("Local Network access is blocked"))
        XCTAssertTrue(WiFiLink.failureMessage(.tls(-9858), localNetworkDenied: false).contains("Pairing failed"))
    }
}
