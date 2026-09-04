import XCTest
@testable import NetworkAnalyzerCore

final class ArpTableParserTests: XCTestCase {
    func testParsesEntryWithMAC() {
        let output = "? (192.168.1.1) at ac:1f:6b:1:22:33 on en0 ifscope [ethernet]\n"
        let entries = ArpTableParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ip, "192.168.1.1")
        XCTAssertEqual(entries[0].mac, "ac:1f:6b:01:22:33")
    }

    func testIncompleteEntryHasNilMAC() {
        let output = "? (192.168.1.5) at (incomplete) on en0 ifscope [ethernet]\n"
        let entries = ArpTableParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ip, "192.168.1.5")
        XCTAssertNil(entries[0].mac)
    }

    func testParsesMultipleLinesAndNamedHost() {
        let output = """
        myhost.lan (192.168.1.10) at aa:bb:cc:dd:ee:ff on en0 ifscope permanent [ethernet]
        ? (192.168.1.11) at 0:1e:c9:a:b:1 on en0 ifscope [ethernet]
        """
        let entries = ArpTableParser.parse(output)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].ip, "192.168.1.10")
        XCTAssertEqual(entries[0].mac, "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(entries[1].ip, "192.168.1.11")
        XCTAssertEqual(entries[1].mac, "00:1e:c9:0a:0b:01")
    }

    func testIgnoresUnparsableLines() {
        let output = "garbage line that does not match\n? (192.168.1.1) at 1:2:3:4:5:6 on en0\n"
        let entries = ArpTableParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ip, "192.168.1.1")
    }

    func testEmptyInputProducesNoEntries() {
        XCTAssertTrue(ArpTableParser.parse("").isEmpty)
    }

    func testDeduplicatesSameIPAcrossMultipleInterfaces() {
        // A Mac with two active interfaces on the same subnet (Wi-Fi + Ethernet, a bridged
        // adapter, ...) makes `arp -a` print each IP once per interface.
        let output = """
        ? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]
        ? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en1 ifscope [ethernet]
        ? (192.168.1.2) at 11:22:33:44:55:66 on en1 ifscope [ethernet]
        """
        let entries = ArpTableParser.parse(output)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.ip), ["192.168.1.1", "192.168.1.2"])
    }
}
