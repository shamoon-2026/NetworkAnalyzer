import Foundation
import Darwin

/// Resolves a display hostname for an IP address.
public enum HostnameResolver {
    /// Races three independent lookups and takes whichever succeeds first:
    ///  1. Bonjour service map: an instant lookup against a `BonjourServiceMap` built once per
    ///     scan from hosts actively advertising a common service (`_http._tcp`, `_ssh._tcp`, ...).
    ///  2. mDNS reverse PTR: a genuine RFC 6762 multicast query (`MDNSReversePTR`, using
    ///     `kDNSServiceFlagsForceMulticast`). This is what actually answers for most home-LAN
    ///     devices — `getnameinfo()` alone does **not** reach mDNS for ordinary private ranges
    ///     (`scutil --dns` shows macOS only auto-routes reverse lookups through mDNS for
    ///     169.254.0.0/16 and IPv6 link-local), and most consumer routers don't publish real PTR
    ///     records for their DHCP leases either.
    ///  3. Unicast reverse DNS: `getnameinfo()`, for networks that *do* have a configured reverse
    ///     zone (common on enterprise networks).
    /// Returns nil ("unknown") if all three fail or time out.
    public static func resolveHostname(ip: String, bonjourMap: BonjourServiceMap?, timeoutSeconds: Double = 2.0) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await bonjourMap?.name(forIP: ip)
            }
            group.addTask {
                await MDNSReversePTR.resolve(ip: ip, timeoutSeconds: timeoutSeconds)
            }
            group.addTask {
                await withTimeout(seconds: timeoutSeconds) {
                    await reverseDNSLookup(ip: ip)
                }
            }
            var resolved: String?
            for await value in group {
                if let value, !value.isEmpty {
                    resolved = value
                    break
                }
            }
            group.cancelAll()
            return resolved
        }
    }

    private static func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func reverseDNSLookup(ip: String) async -> String? {
        await Task.detached(priority: .utility) {
            ip.contains(":") ? reverseDNSLookupIPv6(ip) : reverseDNSLookupIPv4(ip)
        }.value
    }

    private static func reverseDNSLookupIPv4(_ ip: String) -> String? {
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else { return nil }

        var sockaddrIn = sockaddr_in()
        sockaddrIn.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sockaddrIn.sin_family = sa_family_t(AF_INET)
        sockaddrIn.sin_addr = addr

        return withUnsafePointer(to: &sockaddrIn) { ptr -> String? in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                lookupName(saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    /// Handles a "%zone" suffix (required for a link-local `fe80::/10` address to be usable in a
    /// socket call) by resolving it to an interface index via `if_nametoindex` for `sin6_scope_id`.
    private static func reverseDNSLookupIPv6(_ ip: String) -> String? {
        var address = ip
        var scopeId: UInt32 = 0
        if let percentIndex = address.firstIndex(of: "%") {
            let zone = String(address[address.index(after: percentIndex)...])
            address = String(address[address.startIndex..<percentIndex])
            scopeId = if_nametoindex(zone)
        }

        var addr6 = in6_addr()
        guard inet_pton(AF_INET6, address, &addr6) == 1 else { return nil }

        var sockaddrIn6 = sockaddr_in6()
        sockaddrIn6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        sockaddrIn6.sin6_family = sa_family_t(AF_INET6)
        sockaddrIn6.sin6_addr = addr6
        sockaddrIn6.sin6_scope_id = scopeId

        return withUnsafePointer(to: &sockaddrIn6) { ptr -> String? in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                lookupName(saPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
    }

    private static func lookupName(_ sa: UnsafePointer<sockaddr>, _ len: socklen_t) -> String? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(sa, len, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NAMEREQD)
        guard result == 0 else { return nil }
        let bytes = hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
