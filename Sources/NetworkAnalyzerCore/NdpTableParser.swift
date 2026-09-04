import Foundation

/// Parses the output of `/usr/sbin/ndp -a` — the IPv6 analogue of `arp -a` (the neighbor
/// discovery cache). Pure and dependency-free so it's directly unit-testable.
public enum NdpTableParser {
    // "240d:f:a5a:1400:edc:91ff:fea2:4db1     c:dc:91:a2:4d:b1    en10 23h56m56s S      "
    // "240d:f:a5a:1400:1950:17de:2b6d:3d19    (incomplete)        en10 expired   N      "
    // "ptah.local                             (incomplete)        lo0  permanent R      "  (not an address; skipped)
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^([0-9a-fA-F:]+)\s+(\S+)\s+(\S+)\s"#
    )

    /// Returns one entry per unique address, in the order first observed. A link-layer address of
    /// "(incomplete)" yields `mac == nil`. Link-local addresses (`fe80::/10`) are not usable for
    /// socket operations without a zone id, so the reporting interface (`ndp`'s `Netif` column)
    /// is appended as a `%zone` suffix, e.g. "fe80::1%en0" — routable addresses are left as-is.
    public static func parse(_ output: String) -> [(ip: String, mac: String?)] {
        var results: [(ip: String, mac: String?)] = []
        var seenIPs: Set<String> = []
        for line in output.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = lineRegex.firstMatch(in: line, range: range),
                  let addressRange = Range(match.range(at: 1), in: line),
                  let macRange = Range(match.range(at: 2), in: line),
                  let netifRange = Range(match.range(at: 3), in: line) else {
                continue
            }
            var address = String(line[addressRange])
            // A resolved hostname made entirely of hex letters (e.g. "cafe", "dead", "face")
            // would otherwise satisfy the address character class; every real IPv6 literal
            // contains at least one ":", so require one to reject that false match.
            guard address.contains(":") else { continue }
            let netif = String(line[netifRange])
            if address.lowercased().hasPrefix("fe80:"), !address.contains("%") {
                address += "%\(netif)"
            }
            guard seenIPs.insert(address).inserted else { continue }
            let rawMac = String(line[macRange])
            let mac = MACAddress.normalize(rawMac)
            results.append((ip: address, mac: mac))
        }
        return results
    }
}
