import Foundation
import Darwin

/// One active IPv4 interface's address and netmask, used to preset the scan range on launch.
public struct LocalIPv4Network: Sendable, Equatable {
    public let interfaceName: String
    public let address: String
    public let netmask: String
}

/// One active IPv6 interface's address and prefix length, used to preset the scan range on launch.
public struct LocalIPv6Network: Sendable, Equatable {
    public let interfaceName: String
    public let address: String
    public let prefixLength: Int
}

/// Reads the Mac's own network configuration via `getifaddrs` (a standard BSD API — no
/// entitlement, no privilege, no subprocess) so the scan range can be preset to "this machine's
/// actual subnet" on launch.
public enum LocalNetworkInfoProvider {
    /// The first active (up + running), non-loopback IPv4 interface, preferring `en0` (the
    /// typical Wi-Fi/primary interface on a Mac) when more than one qualifies.
    public static func primaryIPv4() -> LocalIPv4Network? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var candidates: [LocalIPv4Network] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addrPtr = interface.ifa_addr, addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard let maskPtr = interface.ifa_netmask else { continue }
            guard let address = dottedQuad(from: addrPtr), let netmask = dottedQuad(from: maskPtr) else { continue }

            candidates.append(LocalIPv4Network(interfaceName: String(cString: interface.ifa_name), address: address, netmask: netmask))
        }

        return candidates.first { $0.interfaceName == "en0" } ?? candidates.first
    }

    /// The best active (up + running), non-loopback IPv6 interface, preferring a global/ULA
    /// address over a link-local (`fe80::`) one (the latter needs a zone id and isn't reachable
    /// from other hosts the way a global/ULA address is), and `en0` among those.
    public static func primaryIPv6() -> LocalIPv6Network? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var candidates: [LocalIPv6Network] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addrPtr = interface.ifa_addr, addrPtr.pointee.sa_family == sa_family_t(AF_INET6) else { continue }
            guard let maskPtr = interface.ifa_netmask else { continue }
            guard let address = numericIPv6Host(from: addrPtr) else { continue }

            let prefixLength = countLeadingOneBits(of: maskPtr)
            candidates.append(LocalIPv6Network(interfaceName: String(cString: interface.ifa_name), address: address, prefixLength: prefixLength))
        }

        let globalOrULA = candidates.filter { !$0.address.lowercased().hasPrefix("fe80:") }
        let pool = globalOrULA.isEmpty ? candidates : globalOrULA
        return pool.first { $0.interfaceName == "en0" } ?? pool.first
    }

    private static func dottedQuad(from sockaddrPtr: UnsafeMutablePointer<sockaddr>) -> String? {
        sockaddrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sinPtr -> String? in
            var addr = sinPtr.pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    /// Numeric-only formatting (`NI_NUMERICHOST`, no reverse DNS) of a full `sockaddr_in6` via
    /// `getnameinfo`, rather than `inet_ntop`, specifically because `getnameinfo` honors
    /// `sin6_scope_id` and appends a "%zone" suffix for a link-local address the same way `ndp -a`
    /// does — needed for `fe80::` addresses to be independently meaningful/usable.
    private static func numericIPv6Host(from sockaddrPtr: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(sockaddrPtr.pointee.sa_len)
        let result = getnameinfo(sockaddrPtr, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A netmask's prefix length is its count of set bits (a well-formed mask is all leading 1s
    /// per byte, so counting *all* set bits equals counting *leading* ones).
    private static func countLeadingOneBits(of sockaddrPtr: UnsafeMutablePointer<sockaddr>) -> Int {
        sockaddrPtr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6Ptr -> Int in
            withUnsafeBytes(of: sin6Ptr.pointee.sin6_addr) { rawBuffer in
                rawBuffer.reduce(0) { $0 + $1.nonzeroBitCount }
            }
        }
    }
}
