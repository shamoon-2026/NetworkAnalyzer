import Foundation

/// Orchestrates the full discovery pipeline (§3 of the spec) for one IP version and publishes
/// display-ready rows.
///
/// IPv4 and IPv6 are fully separate, mirroring `MonitorViewModel` in the sibling
/// MultiPingMonitor-macOS project: each gets its own `NetworkAnalyzerViewModel` instance (one per
/// tab), its own host list, and its own run state — no state is shared between them except the
/// process-wide `VendorResolver` (OUI data isn't IP-version-specific).
///
/// Every stage after `HostDiscovery.scan` is injectable so tests substitute deterministic stubs
/// instead of touching the network.
@MainActor
public final class NetworkAnalyzerViewModel: ObservableObject {
    public let ipVersion: IPVersion

    @Published public private(set) var hosts: [HostViewModel] = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var lastScanDate: Date?
    @Published public private(set) var lastErrorDescription: String?

    private let vendorResolver: VendorResolver
    private let commentStore: HostCommentStore
    private let hostDiscoveryProvider: @Sendable (IPVersion, Int, (start: String, end: String)?) async -> [HostEntry]
    private let hostnameProvider: @Sendable (String, BonjourServiceMap?, Double) async -> String?
    private let portScanProvider: @Sendable (String, [(port: Int, proto: PortProtocolKind)], Double) async -> [PortResult]
    private let bonjourBuildDuration: Double
    private let pingTimeoutMs: Int

    public init(
        ipVersion: IPVersion = .v4,
        vendorResolver: VendorResolver = .shared,
        commentStore: HostCommentStore? = nil,
        hostDiscoveryProvider: @escaping @Sendable (IPVersion, Int, (start: String, end: String)?) async -> [HostEntry] = HostDiscovery.scan,
        hostnameProvider: @escaping @Sendable (String, BonjourServiceMap?, Double) async -> String? = HostnameResolver.resolveHostname,
        portScanProvider: @escaping @Sendable (String, [(port: Int, proto: PortProtocolKind)], Double) async -> [PortResult] = PortScanner.scan,
        bonjourBuildDuration: Double = 2.5,
        pingTimeoutMs: Int = 800
    ) {
        self.ipVersion = ipVersion
        self.vendorResolver = vendorResolver
        self.commentStore = commentStore ?? HostCommentStore()
        self.hostDiscoveryProvider = hostDiscoveryProvider
        self.hostnameProvider = hostnameProvider
        self.portScanProvider = portScanProvider
        self.bonjourBuildDuration = bonjourBuildDuration
        self.pingTimeoutMs = pingTimeoutMs
    }

    /// - Parameter range: Actively sweeps this address range instead of just reading the
    ///   existing ARP/NDP cache (see `HostDiscovery.scan`). Interpreted as IPv4 or IPv6 addresses
    ///   according to this instance's own `ipVersion`.
    public func runScan(range: (start: String, end: String)? = nil) async {
        guard !isScanning else { return }
        isScanning = true
        lastErrorDescription = nil
        defer { isScanning = false }

        await vendorResolver.loadIfNeeded()

        let bonjourMap = BonjourServiceMap()
        async let bonjourBuild: Void = bonjourMap.build(duration: bonjourBuildDuration)

        let entries = await hostDiscoveryProvider(ipVersion, pingTimeoutMs, range)
        await bonjourBuild

        let vendorResolver = self.vendorResolver
        let hostnameProvider = self.hostnameProvider
        let portScanProvider = self.portScanProvider

        let results = await withTaskGroup(of: HostViewModel.self) { group in
            for entry in entries {
                group.addTask {
                    await Self.enrich(
                        entry: entry,
                        vendorResolver: vendorResolver,
                        bonjourMap: bonjourMap,
                        hostnameProvider: hostnameProvider,
                        portScanProvider: portScanProvider
                    )
                }
            }
            var collected: [HostViewModel] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Comments are user-entered state, not something a rescan discovers — carry forward
        // whatever's already stored for each IP (for this app run only; see `HostCommentStore`)
        // rather than losing it every time `hosts` is rebuilt from scratch.
        let comments = await commentStore.snapshot()
        let commented = results.map { host -> HostViewModel in
            var host = host
            host.comment = comments[IPAddressSortKey.make(for: host.ip)]
            return host
        }

        hosts = commented.sorted { lhs, rhs in
            IPAddressSortKey.make(for: lhs.ip) < IPAddressSortKey.make(for: rhs.ip)
        }
        lastScanDate = Date()
    }

    /// A CSV export of the current results. Column values are fixed, non-localized identifiers
    /// (not the UI's current display language) so the file stays meaningful independent of
    /// whatever language the app happens to be showing.
    public func csvContent() -> String {
        CSVExport.content(for: hosts)
    }

    /// Updates a host's comment: immediately in the published `hosts` (so the UI reflects the
    /// edit right away), and recorded in `commentStore` in the background so it survives a
    /// rescan for the rest of this app run — but not a relaunch; see `HostCommentStore`. An
    /// empty/whitespace-only comment clears it.
    public func setComment(_ comment: String, forIP ip: String) {
        if let index = hosts.firstIndex(where: { $0.ip == ip }) {
            let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            hosts[index].comment = trimmed.isEmpty ? nil : trimmed
        }
        let commentStore = self.commentStore
        Task {
            await commentStore.setComment(comment, forIP: ip)
        }
    }

    public func reportUpdateFailure(_ description: String) {
        lastErrorDescription = description
    }

    nonisolated static func enrich(
        entry: HostEntry,
        vendorResolver: VendorResolver,
        bonjourMap: BonjourServiceMap,
        hostnameProvider: @Sendable (String, BonjourServiceMap?, Double) async -> String?,
        portScanProvider: @Sendable (String, [(port: Int, proto: PortProtocolKind)], Double) async -> [PortResult]
    ) async -> HostViewModel {
        guard entry.isAlive else {
            return HostViewModel(ip: entry.ip, mac: entry.mac, vendor: nil, hostname: nil, osGuess: nil, ports: [], ttl: entry.ttl, isAlive: false)
        }

        async let hostnameTask = hostnameProvider(entry.ip, bonjourMap, 2.0)
        async let portsTask = portScanProvider(entry.ip, PortScanner.defaultPorts, 1.5)

        var vendor: String?
        if let mac = entry.mac {
            vendor = await vendorResolver.resolveVendor(mac: mac)
        }

        let hostname = await hostnameTask
        let ports = await portsTask
        let osGuess = OSFingerprint.guessOS(ttl: entry.ttl, openPorts: ports, mdnsResponded: hostname != nil)

        return HostViewModel(
            ip: entry.ip,
            mac: entry.mac,
            vendor: vendor,
            hostname: hostname,
            osGuess: osGuess,
            ports: ports,
            ttl: entry.ttl,
            isAlive: true
        )
    }
}
