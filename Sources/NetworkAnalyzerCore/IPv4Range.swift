import Foundation

/// Pure IPv4 address/netmask arithmetic backing the user-specified scan range (start IP, end IP,
/// netmask). Dependency-free so it's directly unit-testable.
public enum IPv4Range {
    /// Upper bound on how many addresses a single scan will actively probe — pinging is done by
    /// spawning a real `/sbin/ping` process per address, so an unbounded range (e.g. a typo'd
    /// /8) would spawn an unreasonable number of processes.
    public static let maxAddressCount = 4096

    /// Every dotted-quad address from `start` to `end` inclusive, in ascending numeric order.
    public static func addresses(start: String, end: String, limit: Int = maxAddressCount) throws -> [String] {
        guard let startValue = toUInt32(start) else { throw IPv4RangeError.invalidAddress(start) }
        guard let endValue = toUInt32(end) else { throw IPv4RangeError.invalidAddress(end) }
        guard startValue <= endValue else { throw IPv4RangeError.startAfterEnd }
        let count = Int(endValue - startValue) + 1
        guard count <= limit else { throw IPv4RangeError.rangeTooLarge(count: count, limit: limit) }
        return (startValue...endValue).map(fromUInt32)
    }

    /// A cheap (no enumeration) address count for `start...end`, for live "N addresses in range"
    /// UI feedback as the user types — unlike `addresses(start:end:limit:)`, this never allocates
    /// an array, so it's safe to call on every keystroke even for a range far past the scan cap.
    /// Returns nil for an unparseable address or `start` after `end`.
    public static func addressCount(start: String, end: String) -> Int? {
        guard let startValue = toUInt32(start), let endValue = toUInt32(end), startValue <= endValue else { return nil }
        return Int(endValue - startValue) + 1
    }

    /// The usable host range for a network address + netmask, excluding the network and
    /// broadcast addresses (e.g. "192.168.1.42" + "255.255.255.0" -> "192.168.1.1"..."192.168.1.254").
    /// /31 and /32 netmasks have no distinct network/broadcast address to exclude, so both bounds
    /// are returned as-is for those. Returns nil for an unparseable address/netmask.
    public static func hostRange(address: String, netmask: String) -> (start: String, end: String)? {
        guard let addressValue = toUInt32(address), let maskValue = toUInt32(netmask) else { return nil }
        let network = addressValue & maskValue
        let broadcast = network | ~maskValue

        if maskValue == 0xFFFF_FFFF {
            return (fromUInt32(addressValue), fromUInt32(addressValue))
        }
        if maskValue == 0xFFFF_FFFE {
            return (fromUInt32(network), fromUInt32(broadcast))
        }
        guard broadcast > network + 1 else { return nil }
        return (fromUInt32(network + 1), fromUInt32(broadcast - 1))
    }

    static func toUInt32(_ ip: String) -> UInt32? {
        let octets = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for octet in octets {
            guard let byte = UInt8(octet) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    static func fromUInt32(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}

public enum IPv4RangeError: Error, Equatable, Sendable {
    case invalidAddress(String)
    case startAfterEnd
    case rangeTooLarge(count: Int, limit: Int)
}
