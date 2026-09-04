import XCTest
@testable import NetworkAnalyzerCore

final class MDNSReversePTRTests: XCTestCase {
    func testIPv4ReverseName() {
        XCTAssertEqual(MDNSReversePTR.reverseARPAName(forIPv4: "192.168.1.10"), "10.1.168.192.in-addr.arpa.")
    }

    func testIPv4ReverseNameRejectsInvalidAddress() {
        XCTAssertNil(MDNSReversePTR.reverseARPAName(forIPv4: "192.168.1"))
        XCTAssertNil(MDNSReversePTR.reverseARPAName(forIPv4: "not.an.ip.address"))
    }

    func testIPv6ReverseNameForFullyExpandedAddress() {
        // 2001:0db8:0000:0000:0000:0000:0000:0001 reversed nibble-by-nibble.
        let name = MDNSReversePTR.reverseARPAName(forIPv6: "2001:db8::1")
        XCTAssertEqual(
            name,
            "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa."
        )
    }

    func testIPv6ReverseNameDropsZoneId() {
        let withZone = MDNSReversePTR.reverseARPAName(forIPv6: "fe80::1%en0")
        let withoutZone = MDNSReversePTR.reverseARPAName(forIPv6: "fe80::1")
        XCTAssertEqual(withZone, withoutZone)
    }

    func testIPv6ReverseNameRejectsMalformedAddress() {
        XCTAssertNil(MDNSReversePTR.reverseARPAName(forIPv6: "fe80::1::2"))
    }

    func testDecodeDomainNameParsesLengthPrefixedLabels() {
        // "raspberrypi" (11) + "local" (5) + terminator, matching DNS wire format.
        var bytes: [UInt8] = [11]
        bytes.append(contentsOf: Array("raspberrypi".utf8))
        bytes.append(5)
        bytes.append(contentsOf: Array("local".utf8))
        bytes.append(0)

        let name = bytes.withUnsafeBytes { rawBuffer in
            MDNSReversePTR.decodeDomainName(rdata: rawBuffer.baseAddress!, length: bytes.count)
        }
        XCTAssertEqual(name, "raspberrypi.local")
    }

    func testDecodeDomainNameReturnsNilForCompressionPointer() {
        // 0xC0 in the top two bits marks a DNS compression pointer, which can't be resolved from
        // RDATA alone.
        let bytes: [UInt8] = [0xC0, 0x0C]
        let name = bytes.withUnsafeBytes { rawBuffer in
            MDNSReversePTR.decodeDomainName(rdata: rawBuffer.baseAddress!, length: bytes.count)
        }
        XCTAssertNil(name)
    }

    func testDecodeDomainNameReturnsNilForEmptyData() {
        let bytes: [UInt8] = [0]
        let name = bytes.withUnsafeBytes { rawBuffer in
            MDNSReversePTR.decodeDomainName(rdata: rawBuffer.baseAddress!, length: bytes.count)
        }
        XCTAssertNil(name)
    }
}
