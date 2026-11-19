// Battery readings over time, and how long each bud has left.
//
// A sample is stored whenever the battery changes, plus a heartbeat every few
// minutes while connected, so a long gap between samples means the earbuds were
// away. The newest run of samples without such a gap is the current session.
//
// Time left comes from the drain rate between the first and last level drop in
// the current discharge (no charging, level never rising). Timing from drop to
// drop, rather than from when we first saw a level, keeps coarse levels (some
// buds report in 10% steps) from skewing the rate.

import Foundation

public struct BatterySample: Equatable, Codable {
    public var time: Date
    public var battery: Battery

    public init(time: Date, battery: Battery) {
        self.time = time
        self.battery = battery
    }
}

public struct BatteryHistory: Equatable, Codable {
    /// Store a sample at least this often while connected, even if nothing changed.
    public static let heartbeat: TimeInterval = 5 * 60
    /// A longer gap between samples ends a session.
    public static let sessionGap: TimeInterval = 15 * 60
    /// Older samples are dropped.
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    /// Drops must span at least this long before there's an estimate.
    public static let minimumSpan: TimeInterval = 5 * 60

    public private(set) var samples: [BatterySample]

    public init(samples: [BatterySample] = []) {
        self.samples = samples
    }

    /// Adds a reading if it's new or the last one is due a heartbeat. Returns true if stored.
    @discardableResult
    public mutating func record(_ battery: Battery, at time: Date) -> Bool {
        guard battery.left != nil || battery.right != nil || battery.case != nil else { return false }
        if let last = samples.last, last.battery == battery,
           time.timeIntervalSince(last.time) < Self.heartbeat {
            return false
        }
        samples.append(BatterySample(time: time, battery: battery))
        let cutoff = time.addingTimeInterval(-Self.retention)
        if let first = samples.first, first.time < cutoff {
            samples.removeAll { $0.time < cutoff }
        }
        return true
    }

    /// The newest samples with no gap longer than `sessionGap` between them.
    public func session() -> [BatterySample] {
        guard var start = samples.indices.last else { return [] }
        while start > 0 {
            let gap: TimeInterval = samples[start].time.timeIntervalSince(samples[start - 1].time)
            if gap > Self.sessionGap { break }
            start -= 1
        }
        return Array(samples[start...])
    }

    /// Time until `part` runs out at its current drain rate, or nil while
    /// charging, without enough drops yet, or when the session is over.
    public func timeRemaining(_ part: BatteryPart, now: Date) -> TimeInterval? {
        let session = session()
        guard let newest = session.last, now.timeIntervalSince(newest.time) <= Self.sessionGap else { return nil }

        // The trailing discharge: walking back, stop at charging, a missing reading or a rise.
        var run: [(time: Date, level: Int)] = []
        for sample in session.reversed() {
            guard let info = sample.battery[part], !info.charging else { break }
            if let later = run.last, info.level < later.level { break }
            run.append((sample.time, info.level))
        }
        run.reverse()

        // Moments the level dropped.
        var drops: [(time: Date, level: Int)] = []
        for i in run.indices.dropFirst() where run[i].level < run[i - 1].level {
            drops.append(run[i])
        }
        guard drops.count >= 2, let first = drops.first, let last = drops.last else { return nil }

        let span: TimeInterval = last.time.timeIntervalSince(first.time)
        let fallen = Double(first.level - last.level)
        guard span >= Self.minimumSpan, fallen > 0 else { return nil }

        // If the next drop is overdue, the buds are draining slower than measured.
        let stepTime: TimeInterval = span / Double(drops.count - 1)
        let sinceDrop: TimeInterval = max(0, now.timeIntervalSince(last.time))
        let measured: TimeInterval = max(span, span + sinceDrop - stepTime)
        let perSecond: Double = fallen / measured
        let remaining: TimeInterval = Double(last.level) / perSecond - min(sinceDrop, stepTime)
        return max(0, remaining)
    }
}

extension Battery {
    public subscript(part: BatteryPart) -> BatteryLevel? {
        switch part {
        case .left: return left
        case .right: return right
        case .case: return self.case
        }
    }
}
