import XCTest
@testable import NetworkAnalyzerCore

final class IPAddressSortKeyTests: XCTestCase {
    func testIPv4PadsOctetsForNumericOrder() {
        XCTAssertEqual(IPAddressSortKey.make(for: "192.168.1.9"), "192.168.001.009")
        XCTAssertEqual(IPAddressSortKey.make(for: "9.9.9.9") < IPAddressSortKey.make(for: "10.0.0.0"), true)
    }

    func testIPv4SortsNumericallyNotLexicographically() {
        let ips = ["192.168.1.10", "192.168.1.2", "192.168.1.1"]
        let sorted = ips.sorted { IPAddressSortKey.make(for: $0) < IPAddressSortKey.make(for: $1) }
        XCTAssertEqual(sorted, ["192.168.1.1", "192.168.1.2", "192.168.1.10"])
    }

    func testIPv6ExpandsDoubleColon() {
        XCTAssertEqual(IPAddressSortKey.make(for: "fe80::1"), "fe80:0000:0000:0000:0000:0000:0000:0001")
        XCTAssertEqual(IPAddressSortKey.make(for: "::1"), "0000:0000:0000:0000:0000:0000:0000:0001")
        XCTAssertEqual(IPAddressSortKey.make(for: "::"), "0000:0000:0000:0000:0000:0000:0000:0000")
    }

    func testIPv6KeepsZoneSuffixForStableGrouping() {
        XCTAssertEqual(IPAddressSortKey.make(for: "fe80::1%en0"), "fe80:0000:0000:0000:0000:0000:0000:0001%en0")
    }

    func testIPv6SortsNumericallyNotLexicographically() {
        // Lexicographically "2001:db8::2" < "2001:db8::10" is false (":10" < ":2" as strings),
        // but numerically 2 < 0x10 (16) — the padded form must get this right.
        let ips = ["2001:db8::10", "2001:db8::2", "2001:db8::1"]
        let sorted = ips.sorted { IPAddressSortKey.make(for: $0) < IPAddressSortKey.make(for: $1) }
        XCTAssertEqual(sorted, ["2001:db8::1", "2001:db8::2", "2001:db8::10"])
    }

    func testMalformedInputFallsBackToRawString() {
        XCTAssertEqual(IPAddressSortKey.make(for: "not-an-ip"), "not-an-ip")
        XCTAssertEqual(IPAddressSortKey.make(for: "fe80::1::2"), "fe80::1::2")
    }
}
