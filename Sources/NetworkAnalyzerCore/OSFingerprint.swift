import Foundation

/// Guesses a host's OS family from its ICMP TTL and open-port profile. Heuristic only — never
/// surface this without a disclaimer; see `os_fingerprint_disclaimer` in `Localization.swift`.
public enum OSFingerprint {
    /// A TTL only ever decreases by one per hop, so a live-captured TTL is always `initialTTL -
    /// hopCount` for some small non-negative hop count. The smallest of the common initial values
    /// (64 / 128 / 255) that is still >= the observed value is the best guess of what the sender
    /// started with. Returns nil for an out-of-range value (> 255, or <= 0).
    public static func estimateInitialTTL(fromObserved ttl: Int) -> Int? {
        guard ttl > 0, ttl <= 255 else { return nil }
        return [64, 128, 255].first { $0 >= ttl }
    }

    /// Combines the TTL-derived guess with well-known-port evidence into a single best-effort
    /// OS family guess plus a confidence label ("高"/"中"/"低").
    ///
    /// - Parameters:
    ///   - ttl: The observed (received) TTL from a ping reply, if any.
    ///   - openPorts: Port scan results for the host.
    ///   - mdnsResponded: Whether the host answered to mDNS/Bonjour-based hostname resolution
    ///     (used for the "mDNS response + port 22 only -> macOS/Linux" heuristic).
    public static func guessOS(ttl: Int?, openPorts: [PortResult], mdnsResponded: Bool = false) -> OSGuess {
        var windowsScore = 0
        var unixScore = 0
        var networkDeviceScore = 0

        if let ttl, let initialTTL = estimateInitialTTL(fromObserved: ttl) {
            switch initialTTL {
            case 64: unixScore += 1
            case 128: windowsScore += 1
            case 255: networkDeviceScore += 1
            default: break
            }
        }

        let openTCPPorts = Set(openPorts.filter { $0.proto == .tcp && $0.tcpStatus == .open }.map(\.port))

        if openTCPPorts.contains(139) || openTCPPorts.contains(445) {
            windowsScore += 2
        }
        if mdnsResponded && openTCPPorts == [22] {
            unixScore += 2
        } else if openTCPPorts.contains(22) {
            unixScore += 1
        }

        let scores: [(os: OSFamily, score: Int)] = [
            (.windows, windowsScore),
            (.unixLike, unixScore),
            (.networkDevice, networkDeviceScore)
        ]
        let sorted = scores.sorted { $0.score > $1.score }
        guard let best = sorted.first, best.score > 0 else {
            return OSGuess(os: .unknown, confidence: .low)
        }
        let runnerUpScore = sorted.count > 1 ? sorted[1].score : 0
        let margin = best.score - runnerUpScore
        let confidence: OSGuessConfidence = margin >= 2 ? .high : (margin == 1 ? .medium : .low)
        return OSGuess(os: best.os, confidence: confidence)
    }
}
