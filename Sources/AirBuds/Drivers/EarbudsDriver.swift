// One earbud protocol (a brand or chip family) behind the interface the rest of
// the app uses. EarbudsController only talks to this; each driver lives in its
// own Drivers/<name>/ folder, with its codecs in AirBudsKit/Protocols/<name>/.
//
// A driver finds its earbuds, opens and authenticates the control link, sends
// reads and settings, and reports what comes back as EarbudsReport. Callbacks
// run on the main thread.

import AirBudsKit

protocol EarbudsDriver: AnyObject {
    /// The control link is up and ready for commands.
    var onConnected: ((_ name: String, _ address: String, _ firmware: String?) -> Void)? { get set }
    /// A reply or pushed update, with everything learned about the earbuds so far.
    var onReport: ((_ report: EarbudsReport, _ capabilities: Capabilities) -> Void)? { get set }
    var onDisconnected: (() -> Void)? { get set }
    /// The paired earbuds this driver supports changed (connected for audio or not).
    var onPairedChanged: (([PairedEarbuds]) -> Void)? { get set }

    func start()
    func stop()
    /// Closes the control link only; audio stays connected.
    func dropLink()

    // Reads: the answer arrives through onReport.
    func readAll()
    func readBattery()
    func readNoiseMode()
    func readEq()
    func readLowLatency()
    func readName()
    func readTouchControls()

    // Settings: the earbuds confirm them through onReport.
    func setNoiseMode(_ mode: NoiseMode)
    func setEqPreset(_ id: Int)
    func setLowLatency(_ on: Bool)
    func setTouchControl(_ control: TouchControl)
    func setCustomEq(gains: [Int])
    func setName(_ name: String)
}
