// Battery page: this session's levels as a chart, and time left for each part.

import AirBudsKit
import SwiftUI

struct BatteryView: View {
    @EnvironmentObject var device: EarbudsController
    @EnvironmentObject var store: BatteryHistoryStore

    var body: some View {
        let battery = device.state.battery
        VStack(spacing: 8) {
            SubpageHeader(title: "Battery")
            BatteryChart(session: store.history.session(), now: Date())
                .padding(.horizontal, 14)
            VStack(spacing: 0) {
                Divider().padding(.bottom, 4)
                PartRow(part: .left, info: battery.left)
                PartRow(part: .right, info: battery.right)
                if let info = battery.case {
                    PartRow(part: .case, info: info)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

private struct PartRow: View {
    let part: BatteryPart
    let info: BatteryLevel?
    @EnvironmentObject var store: BatteryHistoryStore

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(SeriesColor.color(part)).frame(width: 8, height: 8)
                .opacity(part == .case ? 0 : 1)
            Text(SeriesColor.name(part)).font(.system(size: 12))
            Spacer()
            Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(info.map { "\($0.level)%" } ?? "—")
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var status: String {
        guard let info else { return "Not available" }
        if info.charging { return "Charging" }
        if part != .case, let left = store.timeRemaining(part) { return Duration.left(left) }
        return ""
    }
}

/// Fixed series colors: dataviz categorical slots 1 and 2, stepped per mode.
enum SeriesColor {
    static func color(_ part: BatteryPart) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch (part, dark) {
            case (.right, false): return NSColor(hex: 0xEB6834)
            case (.right, true): return NSColor(hex: 0xD95926)
            case (_, false): return NSColor(hex: 0x2A78D6)
            case (_, true): return NSColor(hex: 0x3987E5)
            }
        })
    }

    static func name(_ part: BatteryPart) -> String {
        switch part {
        case .left: return "Left"
        case .right: return "Right"
        case .case: return "Case"
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Chart

/// Left and right levels over the session as step lines (levels hold until the
/// next reading), 0–100% on one axis, with a hover crosshair.
struct BatteryChart: View {
    static let plotHeight: CGFloat = 96
    private static let axisWidth: CGFloat = 34
    private static let minimumSpan: TimeInterval = 2 * 60

    let session: [BatterySample]
    let now: Date
    @StateObject private var hover = Local<CGFloat?>(nil)

    var body: some View {
        if let start = session.first?.time, now.timeIntervalSince(start) >= Self.minimumSpan {
            chart(start: start)
        } else {
            Text("The chart fills in as you listen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: Self.plotHeight)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
    }

    private func chart(start: Date) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                axis
                GeometryReader { geo in
                    let size = geo.size
                    ZStack(alignment: .topLeading) {
                        grid(size)
                        line(.left, start: start, size: size)
                        line(.right, start: start, size: size)
                        crosshair(start: start, size: size)
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): hover.value = point.x
                        case .ended: hover.value = nil
                        }
                    }
                }
                .frame(height: Self.plotHeight)
            }
            HStack {
                Text(start.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text("Now")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .padding(.leading, Self.axisWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery this session, from \(start.formatted(date: .omitted, time: .shortened)) to now")
    }

    private var axis: some View {
        VStack(alignment: .trailing) {
            Text("100%")
            Spacer()
            Text("50%")
            Spacer()
            Text("0%")
        }
        .font(.system(size: 9).monospacedDigit())
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.secondary)
        // Taller than the plot by one line of text, so each label centres on its grid line.
        .frame(width: Self.axisWidth - 4, height: Self.plotHeight + 11, alignment: .trailing)
        .padding(.trailing, 4)
    }

    private func grid(_ size: CGSize) -> some View {
        Path { path in
            for fraction: CGFloat in [0, 0.5, 1] {
                let y: CGFloat = fraction * size.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
    }

    private func x(_ time: Date, start: Date, width: CGFloat) -> CGFloat {
        let span: TimeInterval = max(now.timeIntervalSince(start), 1)
        let fraction = CGFloat(time.timeIntervalSince(start) / span)
        return min(max(fraction, 0), 1) * width
    }

    private func y(_ level: Int, height: CGFloat) -> CGFloat {
        let fraction = CGFloat(min(max(level, 0), 100)) / 100
        return (1 - fraction) * height
    }

    /// A step line; it breaks where the part wasn't reported (e.g. back in the case).
    private func line(_ part: BatteryPart, start: Date, size: CGSize) -> some View {
        Path { path in
            var last: CGPoint?
            for sample in session {
                let px: CGFloat = x(sample.time, start: start, width: size.width)
                guard let info = sample.battery[part] else {
                    if let last { path.addLine(to: CGPoint(x: px, y: last.y)) }
                    last = nil
                    continue
                }
                let point = CGPoint(x: px, y: y(info.level, height: size.height))
                if let last {
                    path.addLine(to: CGPoint(x: point.x, y: last.y))
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                }
                last = point
            }
            if let last { path.addLine(to: CGPoint(x: size.width, y: last.y)) } // holds until now
        }
        .stroke(SeriesColor.color(part), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private func crosshair(start: Date, size: CGSize) -> some View {
        if let hx = hover.value, size.width > 0 {
            let span: TimeInterval = now.timeIntervalSince(start)
            let time = start.addingTimeInterval(span * Double(hx / size.width))
            let sample = session.last { $0.time <= time } ?? session[0]
            let tip = tooltip(time: time, battery: sample.battery)
            Path { path in
                path.move(to: CGPoint(x: hx, y: 0))
                path.addLine(to: CGPoint(x: hx, y: size.height))
            }
            .stroke(Color.primary.opacity(0.35), lineWidth: 1)
            Text(tip)
                .font(.system(size: 10).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
                .fixedSize()
                .alignmentGuide(.leading) { d in
                    // Keep the tooltip inside the plot.
                    let left: CGFloat = min(max(hx - d.width / 2, 0), size.width - d.width)
                    return -left
                }
                .offset(y: 2)
        }
    }

    private func tooltip(time: Date, battery: Battery) -> String {
        let clock = time.formatted(date: .omitted, time: .shortened)
        let left = battery.left.map { "L \($0.level)%" } ?? "L —"
        let right = battery.right.map { "R \($0.level)%" } ?? "R —"
        return "\(clock)  \(left)  \(right)"
    }
}
