import Foundation

/// Normalization helpers shared by ARP parsing and OUI vendor lookup.
public enum MACAddress {
    /// Normalizes a MAC address to lowercase, colon-separated, zero-padded octets
    /// (e.g. "0:1e:c9:a:b:1" -> "00:1e:c9:0a:0b:01"). Returns nil if `raw` isn't a 6-octet
    /// hex address — macOS's `arp -a` omits leading zeros per octet, so this is needed
    /// before either display or OUI-prefix lookup.
    public static func normalize(_ raw: String) -> String? {
        let octets = raw.split(separator: ":")
        guard octets.count == 6 else { return nil }
        var normalized: [String] = []
        normalized.reserveCapacity(6)
        for octet in octets {
            guard octet.count <= 2, let value = UInt8(octet, radix: 16) else { return nil }
            normalized.append(String(format: "%02x", value))
        }
        return normalized.joined(separator: ":")
    }

    /// The first 3 octets (OUI, 24 bits) as an uppercase 6-hex-digit key, e.g. "3C5AB4",
    /// matching the `Assignment` column format of the IEEE OUI registry CSV.
    public static func ouiKey(_ mac: String) -> String? {
        guard let normalized = normalize(mac) else { return nil }
        let octets = normalized.split(separator: ":").prefix(3)
        guard octets.count == 3 else { return nil }
        return octets.joined().uppercased()
    }
}
