// Paired earbuds as the panel lists them.

/// A paired pair of supported earbuds, as the panel lists them.
struct PairedEarbuds: Equatable, Identifiable {
    var id: String { address }
    let name: String
    let address: String
    /// Connected for audio (classic Bluetooth).
    let connected: Bool
}
