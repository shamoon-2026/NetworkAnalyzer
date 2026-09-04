import Foundation

/// Discovers hosts on the local network without requiring administrator privileges.
public enum HostDiscovery {
    /// Maximum number of concurrent ping subprocesses during a range sweep — pinging is a real
    /// `/sbin/ping`/`/sbin/ping6` process per address, so this bounds process/file-descriptor
    /// usage regardless of how large the (already capped) requested range is.
    private static let maxConcurrentPings = 48

    /// Discovers hosts for one IP version.
    ///
    /// - `range` omitted: reads the existing `arp -a`/`ndp -a` neighbor cache and pings every
    ///   entry found there to confirm liveness. This only ever reports addresses the OS already
    ///   happens to know about (e.g. from recent traffic).
    /// - `range` given: actively pings every address in `[range.start, range.end]` (a real,
    ///   user-specified scan, not limited to what's already cached), then reads `arp -a`/`ndp -a`
    ///   once afterward to pick up MAC addresses resolved along the way. Only hosts that actually
    ///   responded are returned — a swept /24 that's mostly unused shouldn't surface hundreds of
    ///   blank "no other info" rows for addresses nothing is using.
    public static func scan(ipVersion: IPVersion = .v4, pingTimeoutMs: Int = 800, range: (start: String, end: String)? = nil) async -> [HostEntry] {
        if let range {
            return await scanRange(ipVersion: ipVersion, startIP: range.start, endIP: range.end, pingTimeoutMs: pingTimeoutMs)
        }

        let output = await runDiscoveryCommand(ipVersion: ipVersion)
        let parsed = ipVersion == .v4 ? ArpTableParser.parse(output) : NdpTableParser.parse(output)

        return await withTaskGroup(of: HostEntry.self) { group in
            for entry in parsed {
                group.addTask {
                    let result = await PingProbe.probe(host: entry.ip, timeoutMs: pingTimeoutMs, ipVersion: ipVersion)
                    return HostEntry(ip: entry.ip, mac: entry.mac, isAlive: result.isAlive, ttl: result.ttl)
                }
            }
            var entries: [HostEntry] = []
            for await entry in group {
                entries.append(entry)
            }
            return entries.sorted { lhs, rhs in
                IPAddressSortKey.make(for: lhs.ip) < IPAddressSortKey.make(for: rhs.ip)
            }
        }
    }

    private static func scanRange(ipVersion: IPVersion, startIP: String, endIP: String, pingTimeoutMs: Int) async -> [HostEntry] {
        let addresses: [String]?
        switch ipVersion {
        case .v4: addresses = try? IPv4Range.addresses(start: startIP, end: endIP)
        case .v6: addresses = try? IPv6Range.addresses(start: startIP, end: endIP)
        }
        guard let addresses else { return [] }

        var pingResults: [String: PingProbe.Result] = [:]
        pingResults.reserveCapacity(addresses.count)

        await withTaskGroup(of: (String, PingProbe.Result).self) { group in
            var iterator = addresses.makeIterator()

            func addNext() {
                guard let ip = iterator.next() else { return }
                group.addTask {
                    let result = await PingProbe.probe(host: ip, timeoutMs: pingTimeoutMs, ipVersion: ipVersion)
                    return (ip, result)
                }
            }

            for _ in 0..<min(maxConcurrentPings, addresses.count) {
                addNext()
            }
            while let (ip, result) = await group.next() {
                pingResults[ip] = result
                addNext()
            }
        }

        let cacheOutput = await runDiscoveryCommand(ipVersion: ipVersion)
        let cacheEntries = ipVersion == .v4 ? ArpTableParser.parse(cacheOutput) : NdpTableParser.parse(cacheOutput)
        // Keyed by canonical sort form, not the raw string: the cache and the swept range can
        // print the same IPv6 address with different "::" compression, which would otherwise
        // never match as dictionary keys.
        let macByIP = Dictionary(cacheEntries.map { (IPAddressSortKey.make(for: $0.ip), $0.mac) }, uniquingKeysWith: { first, _ in first })

        return addresses.compactMap { ip -> HostEntry? in
            guard let result = pingResults[ip], result.isAlive else { return nil }
            let mac = macByIP[IPAddressSortKey.make(for: ip)] ?? nil
            return HostEntry(ip: ip, mac: mac, isAlive: true, ttl: result.ttl)
        }.sorted { lhs, rhs in
            IPAddressSortKey.make(for: lhs.ip) < IPAddressSortKey.make(for: rhs.ip)
        }
    }

    private static func runDiscoveryCommand(ipVersion: IPVersion) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                switch ipVersion {
                case .v4:
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
                case .v6:
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/ndp")
                }
                // "-n": numeric only, skip hostname resolution for each cache entry. Without it,
                // `ndp -a` was measured taking 30+ seconds on a real network (vs. ~0.01s with it)
                // — the command itself does a reverse-DNS lookup per entry and blocks on each one
                // for entries with no PTR record, which is most of them. We only parse the
                // address/MAC columns (ArpTableParser/NdpTableParser) and never use the resolved
                // hostname column, so this is a pure win.
                process.arguments = ["-an"]

                let stdoutPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }

                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
