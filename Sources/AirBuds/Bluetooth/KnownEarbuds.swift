// Earbuds remembered by address, so they're still recognised after a rename.

import Foundation

/// Addresses of earbuds that passed the handshake, so they're recognised after a rename.
enum KnownEarbuds {
    private static let key = "knownEarbuds"

    static var addresses: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func remember(_ address: String) {
        let lowered = address.lowercased()
        guard !addresses.contains(lowered) else { return }
        UserDefaults.standard.set(Array(addresses) + [lowered], forKey: key)
    }
}
