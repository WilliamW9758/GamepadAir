import XCTest
@testable import MacSupport

final class RecentInputLogTests: XCTestCase {
    func testFiveMinuteWindowExpiresEvenWithoutNewInput() {
        var log = RecentInputLog()
        let start = Date(timeIntervalSince1970: 1000)
        log.append("old\n", at: start)
        log.append("recent\n", at: start.addingTimeInterval(250))
        log.prune(at: start.addingTimeInterval(301))
        XCTAssertEqual(String(decoding: log.data, as: UTF8.self), "recent\n")
        log.prune(at: start.addingTimeInterval(551))
        XCTAssertTrue(log.data.isEmpty)
    }
    func testByteCapDropsOldestWholeEntries() {
        var log = RecentInputLog(byteLimit: 8)
        let now = Date()
        log.append("1234\n", at: now)
        log.append("5678\n", at: now)
        XCTAssertEqual(String(decoding: log.data, as: UTF8.self), "5678\n")
        XCTAssertLessThanOrEqual(log.byteCount, 8)
        log.append("oversized-entry\n", at: now)
        XCTAssertTrue(log.data.isEmpty)
    }
}
