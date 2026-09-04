import XCTest
@testable import NetworkAnalyzerCore

final class NdpTableParserTests: XCTestCase {
    func testParsesRoutableAddressUnchanged() {
        let output = """
        Neighbor                                Linklayer Address  Netif Expire    St Flgs Prbs
        240d:f:a5a:1400:edc:91ff:fea2:4db1      c:dc:91:a2:4d:b1    en10 23h56m56s S
        """
        let entries = NdpTableParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ip, "240d:f:a5a:1400:edc:91ff:fea2:4db1")
        XCTAssertEqual(entries[0].mac, "0c:dc:91:a2:4d:b1")
    }

    func testAppendsZoneIdToLinkLocalAddress() {
        let output = "fe80::1:2:3:4                           74:6:35:cd:81:88   en10 4s         R  R"
        let entries = NdpTableParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ip, "fe80::1:2:3:4%en10")
    }

    func testIncompleteEntryHasNilMAC() {
        let output = "240d:f:a5a:1400:1950:17de:2b6d:3d19    (incomplete)        en10 expired   N"
        let entries = NdpTableParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].mac)
    }

    func testSkipsHostnameLikeRowsThatArentAddresses() {
        // A row whose "Neighbor" is a resolved hostname made of hex-looking letters (e.g. "cafe",
        // "dead") must not be mistaken for an IPv6 literal just because it satisfies [0-9a-fA-F]+.
        let output = "ptah.local                              (incomplete)         lo0  permanent R"
        XCTAssertTrue(NdpTableParser.parse(output).isEmpty)
    }

    func testDeduplicatesSameAddressAcrossMultipleInterfaces() {
        let output = """
        240d:f:a5a:1400:ce9e:a2ff:fec8:181      cc:9e:a2:c8:1:81    en10 23h56m56s S
        240d:f:a5a:1400:ce9e:a2ff:fec8:181      cc:9e:a2:c8:1:81     en1 23h36m2s  S
        """
        let entries = NdpTableParser.parse(output)
        XCTAssertEqual(entries.count, 1)
    }

    func testEmptyInputProducesNoEntries() {
        XCTAssertTrue(NdpTableParser.parse("").isEmpty)
    }
}
