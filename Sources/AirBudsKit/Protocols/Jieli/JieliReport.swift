// Jieli replies and updates as the brand-neutral EarbudsReport.

extension JieliSysInfo {
    public var report: EarbudsReport {
        var report = EarbudsReport()
        report.noiseMode = noiseMode
        report.eqPreset = eqPreset
        if !eqFrequencies.isEmpty {
            report.customEqGains = eqGains[CustomEq.id]?.map { Int(Int8(bitPattern: $0)) }
        }
        return report
    }
}

extension JieliAdvInfo {
    public var report: EarbudsReport {
        var report = EarbudsReport()
        report.battery = battery
        report.name = name
        report.lowLatency = lowLatency
        report.touchControls = touchControls
        return report
    }
}
