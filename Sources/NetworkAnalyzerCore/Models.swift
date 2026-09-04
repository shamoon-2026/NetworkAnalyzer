import Foundation

/// IPv4 uses `arp -a` for discovery; IPv6 uses `ndp -a` (the analogous IPv6 neighbor-discovery
/// cache). The two are fully independent throughout the app — separate tabs, separate
/// `NetworkAnalyzerViewModel`s, separate scans and CSV exports.
public enum IPVersion: String, Sendable, CaseIterable {
    case v4
    case v6
}

/// A host discovered via the local ARP/NDP table, before hostname/vendor/port enrichment.
public struct HostEntry: Sendable, Identifiable, Hashable {
    public var id: String { ip }
    public let ip: String
    public var mac: String?
    public var isAlive: Bool
    public var ttl: Int?

    public init(ip: String, mac: String?, isAlive: Bool, ttl: Int? = nil) {
        self.ip = ip
        self.mac = mac
        self.isAlive = isAlive
        self.ttl = ttl
    }
}

public enum PortProtocolKind: String, Sendable, Hashable, CaseIterable {
    case tcp
    case udp
}

public enum TCPStatus: String, Sendable, Hashable {
    case open
    case closed
    case timeout
}

public enum UDPStatus: String, Sendable, Hashable {
    case responded
    case noResponse
}

/// The result of probing a single well-known port. Exactly one of `tcpStatus`/`udpStatus`
/// is populated, matching `proto`.
public struct PortResult: Sendable, Identifiable, Hashable {
    public var id: String { "\(proto.rawValue)-\(port)" }
    public let port: Int
    public let proto: PortProtocolKind
    public let tcpStatus: TCPStatus?
    public let udpStatus: UDPStatus?

    public init(port: Int, proto: PortProtocolKind, tcpStatus: TCPStatus? = nil, udpStatus: UDPStatus? = nil) {
        self.port = port
        self.proto = proto
        self.tcpStatus = tcpStatus
        self.udpStatus = udpStatus
    }

    /// True for a TCP port that accepted a connection. UDP never reports "open" — see `UDPStatus`.
    public var isOpenOrResponded: Bool {
        tcpStatus == .open || udpStatus == .responded
    }
}

/// A coarse OS family guess. Deliberately machine-readable, not display text — the UI layer is
/// responsible for localizing this (and for always pairing it with a "guess only" disclaimer).
/// String-backed so CSV export has a stable, language-independent identifier for free.
public enum OSFamily: String, Sendable, Hashable {
    case windows
    case unixLike
    case networkDevice
    case unknown
}

public enum OSGuessConfidence: String, Sendable, Hashable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: OSGuessConfidence, rhs: OSGuessConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// OS family guess. Always advisory — never claim certainty in UI copy that surfaces this type.
public struct OSGuess: Sendable, Hashable {
    public let os: OSFamily
    public let confidence: OSGuessConfidence

    public init(os: OSFamily, confidence: OSGuessConfidence) {
        self.os = os
        self.confidence = confidence
    }
}

/// The fully merged, display-ready row for one host.
public struct HostViewModel: Sendable, Identifiable, Hashable {
    public var id: String { ip }
    public let ip: String
    public var mac: String?
    public var vendor: String?
    public var hostname: String?
    public var osGuess: OSGuess?
    public var ports: [PortResult]
    public var ttl: Int?
    public var isAlive: Bool
    /// A free-text note the user typed for this host. Not discovered — set via `HostCommentStore`
    /// and carried over across rescans (keyed by IP), unlike every other field here.
    public var comment: String?

    public init(
        ip: String,
        mac: String? = nil,
        vendor: String? = nil,
        hostname: String? = nil,
        osGuess: OSGuess? = nil,
        ports: [PortResult] = [],
        ttl: Int? = nil,
        isAlive: Bool = false,
        comment: String? = nil
    ) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.osGuess = osGuess
        self.ports = ports
        self.ttl = ttl
        self.isAlive = isAlive
        self.comment = comment
    }

    // MARK: - Sort keys

    /// A zero-padded string form of `ip` (IPv4 or IPv6) where lexicographic order matches numeric
    /// order — see `IPAddressSortKey`.
    public var ipSortValue: String { IPAddressSortKey.make(for: ip) }

    public var hostnameSortValue: String { hostname ?? "" }
    public var macSortValue: String { mac ?? "" }
    public var vendorSortValue: String { vendor ?? "" }
    public var commentSortValue: String { comment ?? "" }
    public var openPortCount: Int { ports.filter(\.isOpenOrResponded).count }

    /// Orders by OS family first, then confidence — both `OSFamily` and `OSGuessConfidence` are
    /// declaration-ordered from least to most specific/certain, matching this ranking.
    public var osSortValue: Int {
        let familyRank: Int
        switch osGuess?.os {
        case .none, .unknown: familyRank = 0
        case .networkDevice: familyRank = 1
        case .unixLike: familyRank = 2
        case .windows: familyRank = 3
        }
        let confidenceRank: Int
        switch osGuess?.confidence {
        case .none: confidenceRank = 0
        case .low: confidenceRank = 1
        case .medium: confidenceRank = 2
        case .high: confidenceRank = 3
        }
        return familyRank * 10 + confidenceRank
    }
}
