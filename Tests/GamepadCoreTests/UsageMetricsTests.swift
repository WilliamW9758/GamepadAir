import XCTest
@testable import GamepadCore

final class UsageMetricsTests: XCTestCase {
    func testConsentAndWithdrawalNeverBackfill() {
        var buffer = UsageMetricBuffer()
        buffer.record(.connectionAttempt, transport: "usb")
        XCTAssertTrue(buffer.drain().isEmpty)
        buffer.setEnabled(true)
        buffer.record(.connectionAttempt, transport: "usb")
        buffer.record(.connectionAttempt, transport: "usb")
        XCTAssertEqual(buffer.drain().first?.count, 2)
        buffer.record(.connectionFailed, transport: "usb")
        buffer.setEnabled(false)
        buffer.setEnabled(true)
        XCTAssertTrue(buffer.drain().isEmpty)
    }
    func testTimingsAreBucketedAndBounded() throws {
        var buffer = UsageMetricBuffer(); buffer.setEnabled(true)
        buffer.record(.connectTime, transport: "wifi", milliseconds: 50)
        buffer.record(.connectTime, transport: "wifi", milliseconds: .nan)
        buffer.record(.connectTime, transport: "wifi", milliseconds: -1)
        buffer.record(.connectionAttempt, transport: "personal-device-name")
        let records = buffer.drain()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.bucket, 2)
        let json = String(decoding: try JSONEncoder().encode(records), as: UTF8.self)
        XCTAssertFalse(json.contains("timestamp"))
        XCTAssertFalse(json.contains("device"))
        for _ in 0..<10001 { buffer.record(.connectionAttempt) }
        XCTAssertEqual(buffer.drain().first?.count, 10000)
    }
}
