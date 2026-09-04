import Foundation

/// Non-privileged liveness/TTL probe used by `HostDiscovery`.
///
/// The spec describes this as a "SOCK_DGRAM-based unprivileged ICMP echo, the same method as
/// MultiPingMonitor". MultiPingMonitor-macOS's actual implementation doesn't open a raw/datagram
/// ICMP socket itself — it shells out to the system `/sbin/ping`/`/sbin/ping6` binaries, which
/// macOS lets any user run without sudo. Those binaries are what perform the unprivileged
/// SOCK_DGRAM echo internally. This probe follows that same precedent (`Process` +
/// `/sbin/ping`/`/sbin/ping6`) rather than reimplementing ICMP packet construction/checksums by
/// hand: it needs no entitlement beyond network client, works unmodified under App Sandbox's
/// process-launch rules, and matches the sibling project's already-proven approach.
public enum PingProbe {
    // IPv4 replies report "ttl=NN"; IPv6 (ping6) reports "hlim=NN" (hop limit) instead.
    private static let ttlRegex = try! NSRegularExpression(pattern: #"(?:ttl|hlim)=([0-9]+)"#, options: .caseInsensitive)

    public struct Result: Sendable {
        public let isAlive: Bool
        public let ttl: Int?
    }

    /// Sends a single ICMP echo request to `host` and reports whether a reply arrived within
    /// `timeoutMs`, plus the reply's TTL/hop-limit when it did.
    public static func probe(host: String, timeoutMs: Int = 800, ipVersion: IPVersion = .v4) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()

                // "--" forces getopt-based ping/ping6 to treat `host` as positional even if it
                // happens to look like a flag (e.g. a literal IPv6 "-fe80::1" is nonsensical, but
                // some zone-suffixed forms could otherwise confuse argument parsing).
                switch ipVersion {
                case .v4:
                    process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                    let waitSeconds = max(1, Int((Double(timeoutMs) / 1000.0).rounded(.up)))
                    process.arguments = ["-c", "1", "-W", String(timeoutMs), "-t", String(waitSeconds), "--", host]
                case .v6:
                    // ping6 has no timeout flag at all, so this (like v4) is additionally bounded
                    // by the manual watchdog below.
                    process.executableURL = URL(fileURLWithPath: "/sbin/ping6")
                    process.arguments = ["-c", "1", "--", host]
                }

                let stdoutPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(isAlive: false, ttl: nil))
                    return
                }

                let killWorkItem = DispatchWorkItem {
                    if process.isRunning {
                        process.interrupt()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs + 500), execute: killWorkItem)

                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killWorkItem.cancel()

                let output = String(data: data, encoding: .utf8) ?? ""
                let isAlive = output.contains("bytes from") && (output.contains("time=") || output.contains("time<"))
                let ttl = isAlive ? extractTTL(from: output) : nil
                continuation.resume(returning: Result(isAlive: isAlive, ttl: ttl))
            }
        }
    }

    static func extractTTL(from output: String) -> Int? {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = ttlRegex.firstMatch(in: output, range: range),
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Int(output[valueRange])
    }
}
