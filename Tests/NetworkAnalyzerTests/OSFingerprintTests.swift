import XCTest
@testable import NetworkAnalyzerCore

final class OSFingerprintTests: XCTestCase {
    func testEstimateInitialTTLRoundsUpToNearestCommonValue() {
        XCTAssertEqual(OSFingerprint.estimateInitialTTL(fromObserved: 64), 64)
        XCTAssertEqual(OSFingerprint.estimateInitialTTL(fromObserved: 60), 64)
        XCTAssertEqual(OSFingerprint.estimateInitialTTL(fromObserved: 118), 128)
        XCTAssertEqual(OSFingerprint.estimateInitialTTL(fromObserved: 200), 255)
    }

    func testEstimateInitialTTLRejectsOutOfRangeValues() {
        XCTAssertNil(OSFingerprint.estimateInitialTTL(fromObserved: 0))
        XCTAssertNil(OSFingerprint.estimateInitialTTL(fromObserved: 300))
    }

    func testGuessOSFavorsWindowsWhenSMBPortsOpen() {
        let ports = [
            PortResult(port: 445, proto: .tcp, tcpStatus: .open),
            PortResult(port: 139, proto: .tcp, tcpStatus: .open)
        ]
        let guess = OSFingerprint.guessOS(ttl: 128, openPorts: ports)
        XCTAssertEqual(guess.os, .windows)
        XCTAssertEqual(guess.confidence, .high)
    }

    func testGuessOSFavorsUnixLikeWithMDNSAndOnlySSH() {
        let ports = [PortResult(port: 22, proto: .tcp, tcpStatus: .open)]
        let guess = OSFingerprint.guessOS(ttl: 64, openPorts: ports, mdnsResponded: true)
        XCTAssertEqual(guess.os, .unixLike)
        XCTAssertEqual(guess.confidence, .high)
    }

    func testGuessOSNetworkDeviceFromHighTTL() {
        let guess = OSFingerprint.guessOS(ttl: 250, openPorts: [])
        XCTAssertEqual(guess.os, .networkDevice)
    }

    func testGuessOSUnknownWhenNoEvidence() {
        let guess = OSFingerprint.guessOS(ttl: nil, openPorts: [])
        XCTAssertEqual(guess.os, .unknown)
        XCTAssertEqual(guess.confidence, .low)
    }

    func testGuessOSLowConfidenceOnTie() {
        // TTL says Windows (128), an open port 22 says unix-like: 1 vs 1, a tie -> low confidence.
        let ports = [PortResult(port: 22, proto: .tcp, tcpStatus: .open)]
        let guess = OSFingerprint.guessOS(ttl: 128, openPorts: ports)
        XCTAssertEqual(guess.confidence, .low)
    }
}
