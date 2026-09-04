import XCTest
@testable import NetworkAnalyzerCore

final class IPv6RangeTests: XCTestCase {
    func testAddressesEnumeratesInclusiveRange() throws {
        let addresses = try IPv6Range.addresses(start: "2001:db8::1", end: "2001:db8::4")
        XCTAssertEqual(addresses, ["2001:db8::1", "2001:db8::2", "2001:db8::3", "2001:db8::4"])
    }

    func testAddressesCarriesAcrossAGroupBoundary() throws {
        // ...:ffff -> ...:1:0, the 16-bit-group equivalent of "999" -> "1000" carrying a digit.
        let addresses = try IPv6Range.addresses(start: "2001:db8::ffff", end: "2001:db8::1:1")
        XCTAssertEqual(addresses, ["2001:db8::ffff", "2001:db8::1:0", "2001:db8::1:1"])
    }

    func testAddressesRejectsInvalidStart() {
        XCTAssertThrowsError(try IPv6Range.addresses(start: "not-an-ip", end: "2001:db8::1")) { error in
            XCTAssertEqual(error as? IPv6RangeError, .invalidAddress("not-an-ip"))
        }
    }

    func testAddressesRejectsZoneSuffix() {
        XCTAssertThrowsError(try IPv6Range.addresses(start: "fe80::1%en0", end: "fe80::2%en0")) { error in
            XCTAssertEqual(error as? IPv6RangeError, .invalidAddress("fe80::1%en0"))
        }
    }

    func testAddressesRejectsStartAfterEnd() {
        XCTAssertThrowsError(try IPv6Range.addresses(start: "2001:db8::2", end: "2001:db8::1")) { error in
            XCTAssertEqual(error as? IPv6RangeError, .startAfterEnd)
        }
    }

    func testAddressesRejectsRangeExceedingLimit() {
        XCTAssertThrowsError(try IPv6Range.addresses(start: "2001:db8::0", end: "2001:db8::a", limit: 5)) { error in
            guard case let .rangeTooLarge(count, limit) = error as? IPv6RangeError else {
                return XCTFail("expected .rangeTooLarge, got \(error)")
            }
            XCTAssertEqual(count, "11")
            XCTAssertEqual(limit, 5)
        }
    }

    func testAddressesReportsAnApproximateCountForAnAstronomicallyLargeRange() {
        // A full /64 has 2^64 addresses — far beyond a plain Int, let alone the scan cap.
        XCTAssertThrowsError(try IPv6Range.addresses(start: "2001:db8::", end: "2001:db8:0:1::", limit: 4096)) { error in
            guard case let .rangeTooLarge(count, _) = error as? IPv6RangeError else {
                return XCTFail("expected .rangeTooLarge, got \(error)")
            }
            XCTAssertTrue(count.contains("e"), "expected an order-of-magnitude estimate like '~1.845e19', got \(count)")
        }
    }

    func testAddressesAllowsASingleAddressRange() throws {
        XCTAssertEqual(try IPv6Range.addresses(start: "::1", end: "::1"), ["::1"])
    }

    func testHostRangeForATypicalSlash64() {
        let range = IPv6Range.hostRange(address: "2001:db8:1234:5678:aaaa:bbbb:cccc:dddd", prefixLength: 64)
        XCTAssertEqual(range?.start, "2001:db8:1234:5678::")
        XCTAssertEqual(range?.end, "2001:db8:1234:5678:ffff:ffff:ffff:ffff")
    }

    func testHostRangeForSlash128IsASingleAddress() {
        let range = IPv6Range.hostRange(address: "2001:db8::1", prefixLength: 128)
        XCTAssertEqual(range?.start, "2001:db8::1")
        XCTAssertEqual(range?.end, "2001:db8::1")
    }

    func testHostRangeForSlashZeroSpansEverything() {
        let range = IPv6Range.hostRange(address: "2001:db8::1", prefixLength: 0)
        XCTAssertEqual(range?.start, "::")
        XCTAssertEqual(range?.end, "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
    }

    func testHostRangeRejectsOutOfRangePrefixLength() {
        XCTAssertNil(IPv6Range.hostRange(address: "2001:db8::1", prefixLength: -1))
        XCTAssertNil(IPv6Range.hostRange(address: "2001:db8::1", prefixLength: 129))
    }

    func testHostRangeRejectsMalformedAddress() {
        XCTAssertNil(IPv6Range.hostRange(address: "not-an-ip", prefixLength: 64))
    }

    func testCanonicalCompressionUsesTheSingleLongestRun() {
        XCTAssertEqual(IPv6Range.fromUInt128(IPv6Range.toUInt128("2001:0:0:0:0:0:0:1")!), "2001::1")
    }

    func testCanonicalCompressionPicksLeftmostRunOnATie() {
        // Two equal-length (2-group) zero runs at indices 1-2 and 4-5; RFC 5952 breaks the tie by
        // compressing the leftmost one.
        XCTAssertEqual(IPv6Range.fromUInt128(IPv6Range.toUInt128("1:0:0:2:0:0:3:4")!), "1::2:0:0:3:4")
    }

    func testCanonicalCompressionRequiresAtLeastTwoZeroGroups() {
        // A single lone zero group is not compressed (RFC 5952 requires 2+).
        XCTAssertEqual(IPv6Range.fromUInt128(IPv6Range.toUInt128("2001:db8:0:1:2:3:4:5")!), "2001:db8:0:1:2:3:4:5")
    }

    func testAddressCountDescriptionIsExactWhenItFitsIn64Bits() {
        XCTAssertEqual(IPv6Range.addressCountDescription(start: "2001:db8::1", end: "2001:db8::4"), "4")
    }

    func testAddressCountDescriptionIsAnEstimateForAnAstronomicallyLargeRange() {
        // A full /64: 2^64 addresses — must not attempt to enumerate this to count it.
        let description = IPv6Range.addressCountDescription(start: "2001:db8::", end: "2001:db8:0:1::")
        XCTAssertEqual(description, "~1.845e+19")
    }

    func testAddressCountDescriptionRejectsInvalidOrReversedRange() {
        XCTAssertNil(IPv6Range.addressCountDescription(start: "not-an-ip", end: "2001:db8::1"))
        XCTAssertNil(IPv6Range.addressCountDescription(start: "2001:db8::2", end: "2001:db8::1"))
    }

    func testIsWithinScanLimit() {
        XCTAssertEqual(IPv6Range.isWithinScanLimit(start: "2001:db8::1", end: "2001:db8::4", limit: 5), true)
        XCTAssertEqual(IPv6Range.isWithinScanLimit(start: "2001:db8::1", end: "2001:db8::a", limit: 5), false)
        XCTAssertEqual(IPv6Range.isWithinScanLimit(start: "2001:db8::", end: "2001:db8:0:1::", limit: 4096), false)
    }

    func testIsWithinScanLimitRejectsInvalidOrReversedRange() {
        XCTAssertNil(IPv6Range.isWithinScanLimit(start: "not-an-ip", end: "2001:db8::1"))
        XCTAssertNil(IPv6Range.isWithinScanLimit(start: "2001:db8::2", end: "2001:db8::1"))
    }
}
