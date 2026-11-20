// What Jieli reports turn on in Capabilities, and which earbuds get the Jieli
// connection.

extension Capabilities {
    /// Turn on what a Jieli report shows the earbuds support.
    public mutating func learn(from info: JieliSysInfo) {
        if !info.noiseModes.isEmpty {
            noiseControl = info.noiseModes[.anc] != nil
            transparency = info.noiseModes[.transparency] != nil
        }
        if info.eqPreset != nil && eqPresets.isEmpty {
            eqPresets = JieliCodec.eqPresets
        }
        // A table with a Custom slot means custom gains are possible.
        if info.eqGains[CustomEq.id] != nil && !info.eqFrequencies.isEmpty {
            eqBands = info.eqFrequencies
        }
    }

    public mutating func learn(from info: JieliAdvInfo) {
        if info.lowLatency != nil { lowLatency = true }
        if info.name != nil {
            rename = true
            maxNameBytes = JieliCodec.maxNameBytes
        }
        if let controls = info.touchControls, !controls.isEmpty { touchControls = true }
    }

    /// Product names that get the Jieli connection.
    public static func isJieli(deviceName name: String) -> Bool {
        name.lowercased().contains("hoco")
    }
}
