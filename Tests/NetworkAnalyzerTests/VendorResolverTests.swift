import XCTest
@testable import NetworkAnalyzerCore

final class VendorResolverTests: XCTestCase {
    func testParsesStandardIEEECSV() {
        let csv = """
        Registry,Assignment,Organization Name,Organization Address
        MA-L,B827EB,Raspberry Pi Foundation,N/A
        MA-L,000C29,VMware Inc.,N/A
        """
        let map = VendorResolver.parseOUICSV(csv)
        XCTAssertEqual(map["B827EB"], "Raspberry Pi Foundation")
        XCTAssertEqual(map["000C29"], "VMware Inc.")
        XCTAssertEqual(map.count, 2)
    }

    func testParsesQuotedFieldsWithEmbeddedCommas() {
        let csv = """
        Registry,Assignment,Organization Name,Organization Address
        MA-L,AABBCC,"Acme, Inc.","123 Main St, Springfield"
        """
        let map = VendorResolver.parseOUICSV(csv)
        XCTAssertEqual(map["AABBCC"], "Acme, Inc.")
    }

    func testSkipsMalformedRows() {
        let csv = """
        Registry,Assignment,Organization Name,Organization Address
        MA-L,NOTHEX,Some Vendor,N/A
        MA-L,AABB,Too Short,N/A
        MA-L,AABBCC,Valid Vendor,N/A
        """
        let map = VendorResolver.parseOUICSV(csv)
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map["AABBCC"], "Valid Vendor")
    }

    func testEmptyCSVProducesEmptyMap() {
        XCTAssertTrue(VendorResolver.parseOUICSV("").isEmpty)
    }

    func testResolveVendorUsesBundledStarterData() async {
        let resolver = VendorResolver(appSupportDirectoryName: "NetworkAnalyzerTests-\(UUID().uuidString)")
        await resolver.loadIfNeeded()
        let vendor = await resolver.resolveVendor(mac: "b8:27:eb:11:22:33")
        XCTAssertEqual(vendor, "Raspberry Pi Foundation")
    }

    func testResolveVendorReturnsNilForUnknownOUI() async {
        let resolver = VendorResolver(appSupportDirectoryName: "NetworkAnalyzerTests-\(UUID().uuidString)")
        await resolver.loadIfNeeded()
        let vendor = await resolver.resolveVendor(mac: "ff:ff:ff:11:22:33")
        XCTAssertNil(vendor)
    }
}
