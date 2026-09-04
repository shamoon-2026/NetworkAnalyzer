import XCTest
@testable import NetworkAnalyzerCore

final class CSVExportTests: XCTestCase {
    func testHeaderRow() {
        let csv = CSVExport.content(for: [])
        XCTAssertEqual(csv, "ip_address,hostname,mac_address,vendor,os_guess,os_confidence,open_ports,comment\n")
    }

    func testRowWithFullData() {
        let host = HostViewModel(
            ip: "192.168.1.10",
            mac: "b8:27:eb:11:22:33",
            vendor: "Raspberry Pi Foundation",
            hostname: "raspberrypi.local",
            osGuess: OSGuess(os: .unixLike, confidence: .high),
            ports: [
                PortResult(port: 22, proto: .tcp, tcpStatus: .open),
                PortResult(port: 80, proto: .tcp, tcpStatus: .closed),
                PortResult(port: 53, proto: .udp, udpStatus: .responded)
            ],
            ttl: 64,
            isAlive: true,
            comment: "living room switch"
        )
        let csv = CSVExport.content(for: [host])
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(
            String(rows[1]),
            "192.168.1.10,raspberrypi.local,b8:27:eb:11:22:33,Raspberry Pi Foundation,unixLike,high,TCP/22 UDP/53,living room switch"
        )
    }

    func testRowWithMissingDataUsesEmptyFields() {
        let host = HostViewModel(ip: "192.168.1.20", isAlive: false)
        let csv = CSVExport.content(for: [host])
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(String(rows[1]), "192.168.1.20,,,,,,,")
    }

    func testCommentContainingCommaIsQuoted() {
        let host = HostViewModel(ip: "192.168.1.30", isAlive: true, comment: "garage, side door")
        let csv = CSVExport.content(for: [host])
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(String(rows[1]), "192.168.1.30,,,,,,,\"garage, side door\"")
    }

    func testEscapesFormulaInjectionPrefixes() {
        XCTAssertEqual(CSVExport.escape("=cmd"), "'=cmd")
        XCTAssertEqual(CSVExport.escape("+1"), "'+1")
        XCTAssertEqual(CSVExport.escape("-1"), "'-1")
        XCTAssertEqual(CSVExport.escape("@SUM"), "'@SUM")
        XCTAssertEqual(CSVExport.escape("normal"), "normal")
    }

    func testQuotesFieldsContainingCommasOrQuotes() {
        XCTAssertEqual(CSVExport.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.escape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(CSVExport.escape("a\nb"), "\"a\nb\"")
    }
}
