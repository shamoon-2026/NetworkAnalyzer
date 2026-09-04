import Foundation

/// Parses the output of `/usr/sbin/arp -a`. Pure and dependency-free so it's directly unit-testable.
public enum ArpTableParser {
    // "hostname (192.168.1.10) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]"
    // "? (192.168.1.5) at (incomplete) on en0 ifscope [ethernet]"
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^\S+\s+\(([0-9.]+)\)\s+at\s+(\S+)"#
    )

    /// Returns one entry per unique IP, in the order first observed. A MAC of "(incomplete)"
    /// (a stale ARP entry with no resolved link-layer address) yields `mac == nil`.
    ///
    /// A Mac with more than one active interface on the same subnet (e.g. Wi-Fi + Ethernet, or a
    /// bridged/virtual adapter) makes `arp -a` print the same IP once per interface, so entries
    /// are deduplicated by IP here rather than left for the caller to notice as duplicate rows.
    public static func parse(_ output: String) -> [(ip: String, mac: String?)] {
        var results: [(ip: String, mac: String?)] = []
        var seenIPs: Set<String> = []
        for line in output.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = lineRegex.firstMatch(in: line, range: range),
                  let ipRange = Range(match.range(at: 1), in: line),
                  let macRange = Range(match.range(at: 2), in: line) else {
                continue
            }
            let ip = String(line[ipRange])
            guard seenIPs.insert(ip).inserted else { continue }
            let rawMac = String(line[macRange])
            let mac = MACAddress.normalize(rawMac)
            results.append((ip: ip, mac: mac))
        }
        return results
    }
}
