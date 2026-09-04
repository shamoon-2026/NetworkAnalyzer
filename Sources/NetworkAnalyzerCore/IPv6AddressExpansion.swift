import Foundation

/// Expands an abbreviated IPv6 address (an optional "%zone" suffix is stripped first) into its 8
/// full 4-hex-digit groups. Shared by `IPAddressSortKey` (numeric sort) and `MDNSReversePTR`
/// (constructing an `ip6.arpa` reverse-DNS name) so the "::" expansion logic exists exactly once.
enum IPv6AddressExpansion {
    static func groups(for ip: String) -> [String]? {
        var address = ip
        if let percentIndex = address.firstIndex(of: "%") {
            address = String(address[address.startIndex..<percentIndex])
        }

        let parts: [Substring]
        let halves = address.components(separatedBy: "::")
        switch halves.count {
        case 1:
            parts = address.split(separator: ":")
        case 2:
            let head = halves[0].isEmpty ? [] : halves[0].split(separator: ":")
            let tail = halves[1].isEmpty ? [] : halves[1].split(separator: ":")
            let missing = 8 - head.count - tail.count
            guard missing >= 0 else { return nil }
            parts = head + Array(repeating: Substring("0"), count: missing) + tail
        default:
            return nil
        }

        guard parts.count == 8 else { return nil }
        var groups: [String] = []
        groups.reserveCapacity(8)
        for part in parts {
            guard let value = UInt16(part, radix: 16) else { return nil }
            groups.append(String(format: "%04x", value))
        }
        return groups
    }
}
