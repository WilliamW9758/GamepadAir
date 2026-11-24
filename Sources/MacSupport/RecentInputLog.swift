import Foundation

/// A bounded rolling window; also pruned when no new input arrives.
struct RecentInputLog {
    struct Entry { let date: Date; let line: String }
    private(set) var entries: [Entry] = []
    private(set) var byteCount = 0
    let retention: TimeInterval
    let byteLimit: Int
    init(retention: TimeInterval = 300, byteLimit: Int = 512_000) {
        self.retention = retention; self.byteLimit = byteLimit
    }
    mutating func append(_ line: String, at date: Date) {
        entries.append(Entry(date: date, line: line)); byteCount += line.utf8.count
        prune(at: date)
    }
    @discardableResult mutating func prune(at now: Date) -> Bool {
        var removed = 0
        while removed < entries.count && (entries[removed].date <= now.addingTimeInterval(-retention) || byteCount > byteLimit) {
            byteCount -= entries[removed].line.utf8.count; removed += 1
        }
        if removed > 0 { entries.removeFirst(removed) }
        return removed > 0
    }
    var data: Data { Data(entries.map(\.line).joined().utf8) }
}
