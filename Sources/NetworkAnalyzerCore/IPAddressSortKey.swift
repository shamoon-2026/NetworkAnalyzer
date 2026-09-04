import Foundation

/// Produces a string form of an IPv4 or IPv6 address where plain lexicographic (`<`) comparison
/// matches numeric address order — so it can back a `KeyPathComparator` for a sortable SwiftUI
/// `Table` column without needing a custom `SortComparator`.
public enum IPAddressSortKey {
    public static func make(for ip: String) -> String {
        ip.contains(":") ? ipv6(ip) : ipv4(ip)
    }

    /// "192.168.1.9" -> "192.168.001.009" (each octet zero-padded to 3 digits).
    static func ipv4(_ ip: String) -> String {
        let octets = ip.split(separator: ".")
        guard octets.count == 4 else { return ip }
        let padded = octets.map { octet -> String? in
            guard let value = UInt8(octet) else { return nil }
            return String(format: "%03d", value)
        }
        guard padded.allSatisfy({ $0 != nil }) else { return ip }
        return padded.compactMap { $0 }.joined(separator: ".")
    }

    /// Expands an abbreviated IPv6 address to 8 zero-padded 4-hex-digit groups so it sorts
    /// numerically, e.g. "fe80::1%en0" -> "fe80:0000:0000:0000:0000:0000:0000:0001%en0".
    /// A zone id (link-local scope, e.g. "%en0") is kept as a suffix so same-address entries with
    /// different zones still sort next to each other; malformed input is returned unchanged so
    /// sorting stays merely unhelpful rather than lossy.
    static func ipv6(_ ip: String) -> String {
        var zoneSuffix = ""
        if let percentIndex = ip.firstIndex(of: "%") {
            zoneSuffix = String(ip[percentIndex...])
        }
        guard let groups = IPv6AddressExpansion.groups(for: ip) else { return ip }
        return groups.joined(separator: ":") + zoneSuffix
    }
}
