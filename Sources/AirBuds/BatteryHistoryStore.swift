// Records battery readings for each pair of earbuds and keeps them in
// ~/Library/Application Support/AirBuds/battery-history.json (last 7 days),
// so the Battery page and time-left estimate survive a relaunch. The rules
// for what to keep and how to estimate live in AirBudsKit's BatteryHistory.

import Combine
import Foundation
import AirBudsKit

final class BatteryHistoryStore: ObservableObject {
    private static let saveDelay: TimeInterval = 30

    /// History of the connected (or last connected) earbuds.
    @Published private(set) var history = BatteryHistory()

    private var byAddress: [String: BatteryHistory] = [:]
    private var address: String?
    private let saveTimer = Delayed()
    private var cancellables = Set<AnyCancellable>()

    private static let fileURL: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("AirBuds/battery-history.json")

    /// `live: false` neither records nor touches the disk (for snapshots).
    init(controller: EarbudsController, live: Bool = true) {
        guard live else { return }
        load()
        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.record(state) }
            .store(in: &cancellables)
    }

    /// Time until `part` runs out, or nil when there's no estimate yet.
    func timeRemaining(_ part: BatteryPart, now: Date = Date()) -> TimeInterval? {
        history.timeRemaining(part, now: now)
    }

    /// The bud that runs out first, and when.
    func soonestEmpty(now: Date = Date()) -> TimeInterval? {
        [BatteryPart.left, .right].compactMap { timeRemaining($0, now: now) }.min()
    }

    func saveNow() {
        saveTimer.cancel()
        guard let url = Self.fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(byAddress).write(to: url, options: .atomic)
        } catch {
            Log.info("Could not save battery history: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    func setSample(_ sample: BatteryHistory) { history = sample }
    #endif

    private func record(_ state: DeviceState) {
        guard state.connected, let address = state.address, !address.isEmpty else { return }
        if address != self.address {
            self.address = address
            history = byAddress[address] ?? BatteryHistory()
        }
        var updated = history
        guard updated.record(state.battery, at: Date()) else { return }
        history = updated
        byAddress[address] = updated
        saveTimer.schedule(Self.saveDelay) { [weak self] in self?.saveNow() }
    }

    private func load() {
        guard let url = Self.fileURL, let data = try? Data(contentsOf: url) else { return }
        do {
            byAddress = try JSONDecoder().decode([String: BatteryHistory].self, from: data)
        } catch {
            Log.info("Ignoring unreadable battery history: \(error.localizedDescription)")
        }
    }
}

/// "3h 10m", "45m".
enum Duration {
    private static let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    static func short(_ interval: TimeInterval) -> String {
        let rounded: TimeInterval = (interval / 60).rounded() * 60
        return formatter.string(from: max(rounded, 60)) ?? ""
    }

    /// The time-left line, e.g. "About 3h 10m left".
    static func left(_ interval: TimeInterval) -> String {
        interval < 5 * 60 ? "Almost empty" : "About \(short(interval)) left"
    }
}
