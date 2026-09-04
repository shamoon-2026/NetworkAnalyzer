import XCTest
@testable import NetworkAnalyzerCore

final class IPv4RangeTests: XCTestCase {
    func testAddressesEnumeratesInclusiveRange() throws {
        let addresses = try IPv4Range.addresses(start: "192.168.1.253", end: "192.168.2.1")
        XCTAssertEqual(addresses, ["192.168.1.253", "192.168.1.254", "192.168.1.255", "192.168.2.0", "192.168.2.1"])
    }

    func testAddressesRejectsInvalidStart() {
        XCTAssertThrowsError(try IPv4Range.addresses(start: "not-an-ip", end: "192.168.1.10")) { error in
            XCTAssertEqual(error as? IPv4RangeError, .invalidAddress("not-an-ip"))
        }
    }

    func testAddressesRejectsInvalidEnd() {
        XCTAssertThrowsError(try IPv4Range.addresses(start: "192.168.1.10", end: "192.168.1.999")) { error in
            XCTAssertEqual(error as? IPv4RangeError, .invalidAddress("192.168.1.999"))
        }
    }

    func testAddressesRejectsStartAfterEnd() {
        XCTAssertThrowsError(try IPv4Range.addresses(start: "192.168.1.10", end: "192.168.1.1")) { error in
            XCTAssertEqual(error as? IPv4RangeError, .startAfterEnd)
        }
    }

    func testAddressesRejectsRangeExceedingLimit() {
        XCTAssertThrowsError(try IPv4Range.addresses(start: "10.0.0.0", end: "10.0.0.10", limit: 5)) { error in
            XCTAssertEqual(error as? IPv4RangeError, .rangeTooLarge(count: 11, limit: 5))
        }
    }

    func testAddressesAllowsASingleAddressRange() throws {
        let addresses = try IPv4Range.addresses(start: "192.168.1.1", end: "192.168.1.1")
        XCTAssertEqual(addresses, ["192.168.1.1"])
    }

    func testHostRangeExcludesNetworkAndBroadcastAddresses() {
        let range = IPv4Range.hostRange(address: "192.168.1.42", netmask: "255.255.255.0")
        XCTAssertEqual(range?.start, "192.168.1.1")
        XCTAssertEqual(range?.end, "192.168.1.254")
    }

    func testHostRangeHandlesNonByteAlignedNetmask() {
        // 192.168.1.42/26 -> network 192.168.1.0, broadcast 192.168.1.63
        let range = IPv4Range.hostRange(address: "192.168.1.42", netmask: "255.255.255.192")
        XCTAssertEqual(range?.start, "192.168.1.1")
        XCTAssertEqual(range?.end, "192.168.1.62")
    }

    func testHostRangeHandlesPointToPointSlash31() {
        let range = IPv4Range.hostRange(address: "192.168.1.5", netmask: "255.255.255.254")
        XCTAssertEqual(range?.start, "192.168.1.4")
        XCTAssertEqual(range?.end, "192.168.1.5")
    }

    func testHostRangeHandlesSingleHostSlash32() {
        let range = IPv4Range.hostRange(address: "192.168.1.5", netmask: "255.255.255.255")
        XCTAssertEqual(range?.start, "192.168.1.5")
        XCTAssertEqual(range?.end, "192.168.1.5")
    }

    func testHostRangeRejectsMalformedInput() {
        XCTAssertNil(IPv4Range.hostRange(address: "not-an-ip", netmask: "255.255.255.0"))
        XCTAssertNil(IPv4Range.hostRange(address: "192.168.1.1", netmask: "not-a-mask"))
    }

    func testAddressCountIsCheapAndExactWithoutEnumerating() {
        // Well past the scan cap — must not attempt to allocate an array of this size.
        XCTAssertEqual(IPv4Range.addressCount(start: "0.0.0.0", end: "255.255.255.255"), 4_294_967_296)
        XCTAssertEqual(IPv4Range.addressCount(start: "192.168.1.1", end: "192.168.1.1"), 1)
    }

    func testAddressCountRejectsInvalidOrReversedRange() {
        XCTAssertNil(IPv4Range.addressCount(start: "not-an-ip", end: "192.168.1.1"))
        XCTAssertNil(IPv4Range.addressCount(start: "192.168.1.10", end: "192.168.1.1"))
    }
}
