import XCTest
@testable import NetworkAnalyzerCore

final class MACAddressTests: XCTestCase {
    func testNormalizePadsShortOctets() {
        XCTAssertEqual(MACAddress.normalize("0:1e:c9:a:b:1"), "00:1e:c9:0a:0b:01")
    }

    func testNormalizeLowercases() {
        XCTAssertEqual(MACAddress.normalize("AC:1F:6B:11:22:33"), "ac:1f:6b:11:22:33")
    }

    func testNormalizeRejectsWrongOctetCount() {
        XCTAssertNil(MACAddress.normalize("ac:1f:6b:11:22"))
    }

    func testNormalizeRejectsNonHex() {
        XCTAssertNil(MACAddress.normalize("zz:1f:6b:11:22:33"))
    }

    func testOUIKeyExtractsFirstThreeOctets() {
        XCTAssertEqual(MACAddress.ouiKey("b8:27:eb:11:22:33"), "B827EB")
    }

    func testOUIKeyNormalizesShortOctetsFirst() {
        XCTAssertEqual(MACAddress.ouiKey("8:0:27:11:22:33"), "080027")
    }
}
