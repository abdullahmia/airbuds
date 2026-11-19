// Touch Controls page: what single, double and triple tap do on each bud.

import AirBudsKit
import SwiftUI

struct TouchControlsView: View {
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let state = device.state
        VStack(spacing: 0) {
            SubpageHeader(title: "Touch Controls")
            ForEach(Bud.allCases, id: \.self) { bud in
                let controls = state.touchControls.filter { $0.bud == bud }.sorted { $0.gesture < $1.gesture }
                if !controls.isEmpty {
                    SectionTitle("\(bud.label) Earbud")
                    ForEach(controls, id: \.self) { control in
                        GestureRow(control: control)
                    }
                }
            }
            Text("Changes are saved on the earbuds and work with any phone or computer.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 6)
        }
    }
}

private struct GestureRow: View {
    let control: TouchControl
    @EnvironmentObject var device: EarbudsController

    var body: some View {
        let state = device.state
        // Switching noise modes only makes sense on earbuds with noise control.
        var options: [Int] = TouchFunction.allCases
            .filter { $0 != .noiseControl || state.capabilities.noiseControl }
            .map(\.rawValue)
        if !options.contains(control.function) { options.append(control.function) }
        let selection = Binding<Int>(
            get: { control.function },
            set: { device.setTouchControl(bud: control.bud, gesture: control.gesture, function: $0) }
        )
        return HStack(spacing: 8) {
            Text(TouchControl.gestureLabel(control.gesture)).font(.system(size: 13))
            Spacer(minLength: 4)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { raw in
                    Text(TouchFunction.label(for: raw)).tag(raw)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(state.touchPending)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
