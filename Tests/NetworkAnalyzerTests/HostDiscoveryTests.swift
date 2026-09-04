import XCTest
@testable import NetworkAnalyzerCore

final class HostDiscoveryTests: XCTestCase {
    func testHostEntriesSortNumericallyByIP() {
        let ips = ["192.168.1.10", "192.168.1.2", "192.168.1.1"]
        let sorted = ips.sorted { IPAddressSortKey.make(for: $0) < IPAddressSortKey.make(for: $1) }
        XCTAssertEqual(sorted, ["192.168.1.1", "192.168.1.2", "192.168.1.10"])
    }
}
