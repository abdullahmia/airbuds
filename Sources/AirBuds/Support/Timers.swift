// Small one-shot timer helpers on the main queue.

import Foundation

/// A cancellable, reschedulable one-shot timer on the main queue.
final class Delayed {
    private var work: DispatchWorkItem?

    func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: block)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        work?.cancel()
        work = nil
    }
}

/// A group of one-shot timers that can all be cancelled at once (e.g. on disconnect).
final class TimerBag {
    private var items: [DispatchWorkItem] = []

    func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        items.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancelAll() {
        items.forEach { $0.cancel() }
        items.removeAll()
    }
}
