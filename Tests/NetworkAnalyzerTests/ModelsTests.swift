import XCTest
@testable import NetworkAnalyzerCore

final class ModelsTests: XCTestCase {
    func testPortResultIsOpenOrRespondedForOpenTCP() {
        let result = PortResult(port: 22, proto: .tcp, tcpStatus: .open)
        XCTAssertTrue(result.isOpenOrResponded)
    }

    func testPortResultIsOpenOrRespondedForRespondedUDP() {
        let result = PortResult(port: 53, proto: .udp, udpStatus: .responded)
        XCTAssertTrue(result.isOpenOrResponded)
    }

    func testPortResultNotOpenOrRespondedForClosedOrNoResponse() {
        XCTAssertFalse(PortResult(port: 22, proto: .tcp, tcpStatus: .closed).isOpenOrResponded)
        XCTAssertFalse(PortResult(port: 22, proto: .tcp, tcpStatus: .timeout).isOpenOrResponded)
        XCTAssertFalse(PortResult(port: 53, proto: .udp, udpStatus: .noResponse).isOpenOrResponded)
    }

    func testHostViewModelIdentifiedByIP() {
        let host = HostViewModel(ip: "192.168.1.1")
        XCTAssertEqual(host.id, "192.168.1.1")
    }

    func testOSGuessConfidenceOrdering() {
        XCTAssertLessThan(OSGuessConfidence.low, .medium)
        XCTAssertLessThan(OSGuessConfidence.medium, .high)
    }
}
