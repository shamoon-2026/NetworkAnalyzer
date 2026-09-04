import Foundation

/// Pure IPv6 address/prefix arithmetic backing the user-specified scan range (start IP, end IP,
/// prefix length). Dependency-free so it's directly unit-testable. Mirrors `IPv4Range`, using a
/// hand-rolled 128-bit unsigned value (`UInt128Value`, two `UInt64` halves) for the full address —
/// the standard library's own `UInt128` exists, but its arithmetic protocol conformances are
/// gated to macOS 15+, which would force raising this app's macOS 13 deployment target just for
/// this one feature.
///
/// A subnet's *usable* range is a meaningless concept for IPv4-sized limits here: a /64 alone has
/// 2^64 addresses, astronomically past any address cap a real scan could use. `addresses(start:
/// end:limit:)` still enforces the same small cap as IPv4 — so presetting the *full* subnet range
/// from a detected prefix length (`hostRange`) is expected to produce a range the user must then
/// narrow by hand before scanning, and `rangeTooLarge` says so.
public enum IPv6Range {
    public static let maxAddressCount = IPv4Range.maxAddressCount

    /// Every address from `start` to `end` inclusive, in ascending numeric order, in RFC 5952
    /// canonical (zero-compressed) form. Neither bound may carry a "%zone" suffix — a link-local
    /// range with a scope id is rare enough not to be worth the extra complexity here.
    public static func addresses(start: String, end: String, limit: Int = maxAddressCount) throws -> [String] {
        guard let startValue = toUInt128(start) else { throw IPv6RangeError.invalidAddress(start) }
        guard let endValue = toUInt128(end) else { throw IPv6RangeError.invalidAddress(end) }
        guard startValue <= endValue else { throw IPv6RangeError.startAfterEnd }

        var result: [String] = []
        var current = startValue
        var count = 0
        while true {
            count += 1
            if count > limit {
                let span = endValue.subtracting(startValue).addingOne()
                throw IPv6RangeError.rangeTooLarge(count: span.approximateDecimalDescription, limit: limit)
            }
            result.append(fromUInt128(current))
            if current == endValue { break }
            current = current.addingOne()
        }
        return result
    }

    /// A cheap (no enumeration) address count for `start...end`, for live "N addresses in range"
    /// UI feedback as the user types — unlike `addresses(start:end:limit:)`, this never builds an
    /// array (which, for IPv6, could otherwise mean allocating up to 2^64 elements), so it's safe
    /// to call on every keystroke. The result is a decimal string, exact when it fits in 64 bits
    /// and an order-of-magnitude estimate otherwise (see `UInt128Value.approximateDecimalDescription`).
    /// Returns nil for an unparseable address or `start` after `end`.
    public static func addressCountDescription(start: String, end: String) -> String? {
        guard let startValue = toUInt128(start), let endValue = toUInt128(end), startValue <= endValue else { return nil }
        return endValue.subtracting(startValue).addingOne().approximateDecimalDescription
    }

    /// Whether `start...end` has `limit` addresses or fewer, computed without enumerating the
    /// range. Returns nil for an unparseable address or `start` after `end`.
    public static func isWithinScanLimit(start: String, end: String, limit: Int = maxAddressCount) -> Bool? {
        guard let startValue = toUInt128(start), let endValue = toUInt128(end), startValue <= endValue else { return nil }
        let span = endValue.subtracting(startValue)
        return span.high == 0 && span.low <= UInt64(limit - 1)
    }

    /// The full subnet range for an address + prefix length (network address through the
    /// all-ones host address) — unlike IPv4 there's no broadcast address to exclude, and the
    /// all-zeros host address is left in since it's a normal, usable address for IPv6.
    /// Returns nil for an unparseable address or an out-of-range prefix length (0...128).
    public static func hostRange(address: String, prefixLength: Int) -> (start: String, end: String)? {
        guard prefixLength >= 0, prefixLength <= 128, let addressValue = toUInt128(address) else { return nil }
        let mask = UInt128Value.max << (128 - prefixLength)
        let network = addressValue & mask
        let allOnesHost = network | ~mask
        return (fromUInt128(network), fromUInt128(allOnesHost))
    }

    /// Rejects any address carrying a "%zone" suffix — range arithmetic doesn't handle scope ids.
    static func toUInt128(_ ip: String) -> UInt128Value? {
        guard !ip.contains("%") else { return nil }
        guard let groups = IPv6AddressExpansion.groups(for: ip), groups.count == 8 else { return nil }

        var high: UInt64 = 0
        for group in groups[0..<4] {
            guard let part = UInt16(group, radix: 16) else { return nil }
            high = (high << 16) | UInt64(part)
        }
        var low: UInt64 = 0
        for group in groups[4..<8] {
            guard let part = UInt16(group, radix: 16) else { return nil }
            low = (low << 16) | UInt64(part)
        }
        return UInt128Value(high: high, low: low)
    }

    static func fromUInt128(_ value: UInt128Value) -> String {
        func groups16(of word: UInt64) -> [UInt16] {
            var remaining = word
            var parts: [UInt16] = []
            for _ in 0..<4 {
                parts.insert(UInt16(truncatingIfNeeded: remaining & 0xFFFF), at: 0)
                remaining >>= 16
            }
            return parts
        }
        return compress(groups16(of: value.high) + groups16(of: value.low))
    }

    /// RFC 5952 §4.2 zero-compression: replaces the longest run of 2+ consecutive zero groups
    /// with "::" (the leftmost run wins a tie), leaving the address unabbreviated if no such run
    /// exists.
    private static func compress(_ groups: [UInt16]) -> String {
        var bestStart = -1
        var bestLength = 0
        var currentStart = -1
        var currentLength = 0

        for (index, group) in groups.enumerated() {
            if group == 0 {
                if currentStart == -1 { currentStart = index }
                currentLength += 1
                if currentLength > bestLength {
                    bestLength = currentLength
                    bestStart = currentStart
                }
            } else {
                currentStart = -1
                currentLength = 0
            }
        }

        guard bestLength >= 2 else {
            return groups.map { String($0, radix: 16) }.joined(separator: ":")
        }

        let before = groups[0..<bestStart].map { String($0, radix: 16) }
        let after = groups[(bestStart + bestLength)...].map { String($0, radix: 16) }
        switch (before.isEmpty, after.isEmpty) {
        case (true, true): return "::"
        case (true, false): return "::" + after.joined(separator: ":")
        case (false, true): return before.joined(separator: ":") + "::"
        case (false, false): return before.joined(separator: ":") + "::" + after.joined(separator: ":")
        }
    }
}

public enum IPv6RangeError: Error, Equatable, Sendable {
    case invalidAddress(String)
    case startAfterEnd
    /// `count` is a plain decimal string, not `Int` — a full subnet's address count (e.g. 2^64
    /// for a /64) can vastly exceed `Int.max`.
    case rangeTooLarge(count: String, limit: Int)
}

/// A minimal 128-bit unsigned value covering exactly what IPv6 range arithmetic needs
/// (comparison, +1, subtraction, AND/OR/NOT, and a left shift for building a prefix mask) —
/// see the availability note on `IPv6Range` for why this isn't the standard library's `UInt128`.
struct UInt128Value: Equatable, Comparable {
    var high: UInt64
    var low: UInt64

    static let max = UInt128Value(high: .max, low: .max)

    static func < (lhs: UInt128Value, rhs: UInt128Value) -> Bool {
        lhs.high != rhs.high ? lhs.high < rhs.high : lhs.low < rhs.low
    }

    static func & (lhs: UInt128Value, rhs: UInt128Value) -> UInt128Value {
        UInt128Value(high: lhs.high & rhs.high, low: lhs.low & rhs.low)
    }

    static func | (lhs: UInt128Value, rhs: UInt128Value) -> UInt128Value {
        UInt128Value(high: lhs.high | rhs.high, low: lhs.low | rhs.low)
    }

    static prefix func ~ (value: UInt128Value) -> UInt128Value {
        UInt128Value(high: ~value.high, low: ~value.low)
    }

    /// Left shift by 0...128 bits (used to build a prefix-length mask from `hostBits`).
    static func << (lhs: UInt128Value, shift: Int) -> UInt128Value {
        guard shift > 0 else { return lhs }
        guard shift < 128 else { return UInt128Value(high: 0, low: 0) }
        if shift >= 64 {
            return UInt128Value(high: lhs.low << (shift - 64), low: 0)
        }
        let high = (lhs.high << shift) | (lhs.low >> (64 - shift))
        let low = lhs.low << shift
        return UInt128Value(high: high, low: low)
    }

    func addingOne() -> UInt128Value {
        let (newLow, overflow) = low.addingReportingOverflow(1)
        return UInt128Value(high: overflow ? high &+ 1 : high, low: newLow)
    }

    /// `self - other`. Only ever called with `self >= other` (unchecked) by `IPv6Range`.
    func subtracting(_ other: UInt128Value) -> UInt128Value {
        let (lowResult, borrow) = low.subtractingReportingOverflow(other.low)
        let highResult = borrow ? high &- other.high &- 1 : high &- other.high
        return UInt128Value(high: highResult, low: lowResult)
    }

    /// Exact when the value fits in 64 bits (as any realistic "too large by a manageable amount"
    /// range does); otherwise a `~1.23e19`-style order-of-magnitude estimate. This only ever backs
    /// a "range is too large" error message, where precision past "obviously huge" doesn't matter.
    var approximateDecimalDescription: String {
        guard high != 0 else { return "\(low)" }
        let asDouble = Double(high) * 18_446_744_073_709_551_616.0 + Double(low)
        return String(format: "~%.3e", asDouble)
    }
}
