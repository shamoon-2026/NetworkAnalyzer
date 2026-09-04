import Foundation
import Network

/// A one-time, network-wide Bonjour browse that maps IP addresses to advertised service names.
///
/// This is the "mDNS: NWBrowser/Bonjour" leg of hostname resolution from the spec. Browsing is
/// LAN-wide, not per-host, so it's built once per scan (not once per host) and then consulted as
/// an instant lookup by `HostnameResolver`. It only finds a name for hosts that are actively
/// advertising one of the probed service types — a best-effort supplement to reverse DNS, not a
/// general mDNS resolver.
public actor BonjourServiceMap {
    private var ipToName: [String: String] = [:]
    private var built = false

    private static let serviceTypes = [
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_smb._tcp", "_afpovertcp._tcp",
        "_airplay._tcp", "_raop._tcp", "_ipp._tcp", "_ipps._tcp", "_printer._tcp",
        "_device-info._tcp", "_googlecast._tcp", "_homekit._tcp", "_workstation._tcp",
        "_spotify-connect._tcp"
    ]

    public init() {}

    public func name(forIP ip: String) -> String? {
        ipToName[ip]
    }

    /// Browses all curated service types concurrently for `duration` seconds and resolves each
    /// discovered instance to an IP. Safe to call repeatedly; only does work once.
    public func build(duration: TimeInterval = 2.5) async {
        guard !built else { return }
        built = true

        await withTaskGroup(of: Void.self) { group in
            for type in Self.serviceTypes {
                group.addTask { [weak self] in
                    await self?.browseAndResolve(serviceType: type, duration: duration)
                }
            }
        }
    }

    private func browseAndResolve(serviceType: String, duration: TimeInterval) async {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        let discoveredBox = LockedBox<[NWBrowser.Result]>([])

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = OneShotContinuation<Void>(continuation)
            let finish: @Sendable () -> Void = {
                browser.cancel()
                box.resume(with: ())
            }
            browser.browseResultsChangedHandler = { results, _ in
                discoveredBox.set(Array(results))
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { finish() }
            }
            browser.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + duration) { finish() }
        }

        // Resolved concurrently, not one at a time: a busy network can have dozens of instances
        // advertising a single service type (e.g. many devices exposing `_http._tcp`), and each
        // resolve is bounded by its own 1-second timeout — sequentially, that's dozens of seconds
        // for one service type alone, even though all 15 service types already run concurrently
        // with each other via `build`'s outer task group.
        let resolved = await withTaskGroup(of: (ip: String, name: String)?.self) { group in
            for result in discoveredBox.get() {
                group.addTask { await Self.resolve(result: result) }
            }
            var collected: [(ip: String, name: String)] = []
            for await case let .some(entry) in group {
                collected.append(entry)
            }
            return collected
        }
        for (ip, name) in resolved {
            ipToName[ip] = name
        }
    }

    private static func resolve(result: NWBrowser.Result) async -> (ip: String, name: String)? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        let endpoint = result.endpoint

        return await withCheckedContinuation { (continuation: CheckedContinuation<(ip: String, name: String)?, Never>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let box = OneShotContinuation<(ip: String, name: String)?>(continuation)
            let finish: @Sendable ((ip: String, name: String)?) -> Void = { value in
                connection.cancel()
                box.resume(with: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let remote = connection.currentPath?.remoteEndpoint, case let .hostPort(host, _) = remote {
                        finish((ip: ipString(from: host), name: name))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { finish(nil) }
        }
    }

    private static func ipString(from host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let addr): return addr.debugDescription
        case .ipv6(let addr): return addr.debugDescription
        case .name(let n, _): return n
        @unknown default: return ""
        }
    }
}
