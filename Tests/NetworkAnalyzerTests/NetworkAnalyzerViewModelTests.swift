import XCTest
@testable import NetworkAnalyzerCore

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@MainActor
final class NetworkAnalyzerViewModelTests: XCTestCase {
    func testRunScanMergesDiscoveryVendorHostnameAndPorts() async {
        let entries = [
            HostEntry(ip: "192.168.1.10", mac: "b8:27:eb:11:22:33", isAlive: true, ttl: 64),
            HostEntry(ip: "192.168.1.20", mac: nil, isAlive: false, ttl: nil)
        ]
        let vendorResolver = VendorResolver(appSupportDirectoryName: "NetworkAnalyzerViewModelTests-\(UUID().uuidString)")

        let vm = NetworkAnalyzerViewModel(
            vendorResolver: vendorResolver,
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { ip, _, _ in ip == "192.168.1.10" ? "raspberrypi.local" : nil },
            portScanProvider: { ip, _, _ in
                ip == "192.168.1.10" ? [PortResult(port: 22, proto: .tcp, tcpStatus: .open)] : []
            },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )

        await vm.runScan()

        XCTAssertEqual(vm.hosts.count, 2)

        let alive = vm.hosts.first { $0.ip == "192.168.1.10" }
        XCTAssertEqual(alive?.isAlive, true)
        XCTAssertEqual(alive?.vendor, "Raspberry Pi Foundation")
        XCTAssertEqual(alive?.hostname, "raspberrypi.local")
        XCTAssertEqual(alive?.ports.count, 1)
        XCTAssertEqual(alive?.osGuess?.os, .unixLike)

        let dead = vm.hosts.first { $0.ip == "192.168.1.20" }
        XCTAssertEqual(dead?.isAlive, false)
        XCTAssertNil(dead?.hostname)
        XCTAssertEqual(dead?.ports.isEmpty, true)
        XCTAssertNotNil(vm.lastScanDate)
    }

    func testDeadHostSkipsHostnameAndPortLookups() async {
        let hostnameLookupCounter = Counter()
        let portScanCounter = Counter()
        let entries = [HostEntry(ip: "192.168.1.99", mac: nil, isAlive: false, ttl: nil)]
        let vendorResolver = VendorResolver(appSupportDirectoryName: "NetworkAnalyzerViewModelTests-\(UUID().uuidString)")

        let vm = NetworkAnalyzerViewModel(
            vendorResolver: vendorResolver,
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { _, _, _ in await hostnameLookupCounter.increment(); return nil },
            portScanProvider: { _, _, _ in await portScanCounter.increment(); return [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )

        await vm.runScan()

        let hostnameLookupCount = await hostnameLookupCounter.value
        let portScanCount = await portScanCounter.value
        XCTAssertEqual(hostnameLookupCount, 0)
        XCTAssertEqual(portScanCount, 0)
    }

    func testPassesItsOwnIPVersionToTheDiscoveryProvider() async {
        let vendorResolver = VendorResolver(appSupportDirectoryName: "NetworkAnalyzerViewModelTests-\(UUID().uuidString)")
        let requestedVersionBox = RequestedVersionBox()

        let vm = NetworkAnalyzerViewModel(
            ipVersion: .v6,
            vendorResolver: vendorResolver,
            hostDiscoveryProvider: { ipVersion, _, _ in
                await requestedVersionBox.set(ipVersion)
                return []
            },
            hostnameProvider: { _, _, _ in nil },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )

        await vm.runScan()

        let requestedVersion = await requestedVersionBox.value
        XCTAssertEqual(requestedVersion, .v6)
        XCTAssertEqual(vm.ipVersion, .v6)
    }

    func testCsvContentReflectsCurrentResults() async {
        let entries = [HostEntry(ip: "192.168.1.10", mac: nil, isAlive: true, ttl: nil)]
        let vendorResolver = VendorResolver(appSupportDirectoryName: "NetworkAnalyzerViewModelTests-\(UUID().uuidString)")

        let vm = NetworkAnalyzerViewModel(
            vendorResolver: vendorResolver,
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { _, _, _ in "example.local" },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )

        await vm.runScan()

        let csv = vm.csvContent()
        XCTAssertTrue(csv.contains("192.168.1.10,example.local"))
    }

    func testRunScanForwardsTheGivenIPv4Range() async {
        let vendorResolver = VendorResolver(appSupportDirectoryName: "NetworkAnalyzerViewModelTests-\(UUID().uuidString)")
        let requestedRangeBox = RequestedRangeBox()

        let vm = NetworkAnalyzerViewModel(
            vendorResolver: vendorResolver,
            hostDiscoveryProvider: { _, _, range in
                await requestedRangeBox.set(range)
                return []
            },
            hostnameProvider: { _, _, _ in nil },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )

        await vm.runScan(range: (start: "192.168.1.1", end: "192.168.1.10"))

        let requestedRange = await requestedRangeBox.value
        XCTAssertEqual(requestedRange?.start, "192.168.1.1")
        XCTAssertEqual(requestedRange?.end, "192.168.1.10")
    }

    func testSetCommentUpdatesHostsImmediately() async {
        let entries = [HostEntry(ip: "192.168.1.10", mac: nil, isAlive: true, ttl: nil)]
        let commentStore = HostCommentStore()
        let vm = NetworkAnalyzerViewModel(
            commentStore: commentStore,
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { _, _, _ in nil },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )
        await vm.runScan()

        vm.setComment("living room switch", forIP: "192.168.1.10")

        XCTAssertEqual(vm.hosts.first?.comment, "living room switch")
    }

    func testCommentSurvivesARescan() async {
        let entries = [HostEntry(ip: "192.168.1.10", mac: nil, isAlive: true, ttl: nil)]
        let commentStore = HostCommentStore()
        // Populate the store directly (awaited) rather than via `vm.setComment`, whose
        // persistence is a fire-and-forget background `Task` — going through it here would race
        // against `runScan`'s later read of the store.
        await commentStore.setComment("living room switch", forIP: "192.168.1.10")

        let vm = NetworkAnalyzerViewModel(
            commentStore: commentStore,
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { _, _, _ in nil },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )

        // A fresh scan builds `hosts` from scratch — the comment must be merged in from the
        // store rather than being something only `setComment`'s in-memory path knows.
        await vm.runScan()

        XCTAssertEqual(vm.hosts.first?.comment, "living room switch")
    }

    /// Comments are session-only by design (see `HostCommentStore`) — a relaunch, modeled here as
    /// a brand new `NetworkAnalyzerViewModel` with its own default `HostCommentStore`, must not
    /// see a comment set on a previous instance.
    func testCommentDoesNotSurviveANewViewModelInstance() async {
        let entries = [HostEntry(ip: "192.168.1.10", mac: nil, isAlive: true, ttl: nil)]

        let firstRun = NetworkAnalyzerViewModel(
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { _, _, _ in nil },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )
        await firstRun.runScan()
        firstRun.setComment("living room switch", forIP: "192.168.1.10")
        XCTAssertEqual(firstRun.hosts.first?.comment, "living room switch")

        let secondRun = NetworkAnalyzerViewModel(
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { _, _, _ in nil },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )
        await secondRun.runScan()

        XCTAssertNil(secondRun.hosts.first?.comment)
    }

    func testEmptyCommentClearsIt() async {
        let entries = [HostEntry(ip: "192.168.1.10", mac: nil, isAlive: true, ttl: nil)]
        let commentStore = HostCommentStore()
        let vm = NetworkAnalyzerViewModel(
            commentStore: commentStore,
            hostDiscoveryProvider: { _, _, _ in entries },
            hostnameProvider: { _, _, _ in nil },
            portScanProvider: { _, _, _ in [] },
            bonjourBuildDuration: 0,
            pingTimeoutMs: 0
        )
        await vm.runScan()
        vm.setComment("note", forIP: "192.168.1.10")
        vm.setComment("   ", forIP: "192.168.1.10")

        XCTAssertNil(vm.hosts.first?.comment)
    }
}

private actor RequestedVersionBox {
    private(set) var value: IPVersion?
    func set(_ newValue: IPVersion?) { value = newValue }
}

private actor RequestedRangeBox {
    private(set) var value: (start: String, end: String)?
    func set(_ newValue: (start: String, end: String)?) { value = newValue }
}
