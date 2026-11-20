// What the earbuds just reported, in terms every driver shares. Each protocol
// turns its own replies and pushed updates into this (Jieli: JieliReport.swift).

/// One reply or update. nil (or empty) fields weren't in it.
public struct EarbudsReport: Equatable {
    public var battery: Battery?
    public var name: String?
    public var noiseMode: NoiseMode?
    public var eqPreset: Int?
    /// The gains stored in the earbuds' Custom EQ slot, in dB, one per band.
    public var customEqGains: [Int]?
    public var lowLatency: Bool?
    public var touchControls: [TouchControl]?

    public init() {}
}
