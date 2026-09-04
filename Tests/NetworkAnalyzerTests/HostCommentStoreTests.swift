import XCTest
@testable import NetworkAnalyzerCore

final class HostCommentStoreTests: XCTestCase {
    func testSetAndGetComment() async {
        let store = HostCommentStore()
        await store.setComment("living room switch", forIP: "192.168.1.10")
        let comment = await store.comment(forIP: "192.168.1.10")
        XCTAssertEqual(comment, "living room switch")
    }

    func testCommentTrimsWhitespace() async {
        let store = HostCommentStore()
        await store.setComment("  padded  ", forIP: "192.168.1.10")
        let comment = await store.comment(forIP: "192.168.1.10")
        XCTAssertEqual(comment, "padded")
    }

    func testEmptyCommentRemovesEntry() async {
        let store = HostCommentStore()
        await store.setComment("note", forIP: "192.168.1.10")
        await store.setComment("   ", forIP: "192.168.1.10")
        let comment = await store.comment(forIP: "192.168.1.10")
        XCTAssertNil(comment)
    }

    func testCommentLookupIsCanonicalForIPv6Compression() async {
        let store = HostCommentStore()
        await store.setComment("router", forIP: "2001:db8:0:0:0:0:0:1")
        // Same address, differently compressed — must resolve to the same stored comment.
        let comment = await store.comment(forIP: "2001:db8::1")
        XCTAssertEqual(comment, "router")
    }

    /// The whole point of this store: it holds comments only for the current app run. A fresh
    /// instance (standing in for a relaunch, which creates a brand new `HostCommentStore` inside
    /// a new `NetworkAnalyzerViewModel`) must never see another instance's comments.
    func testDoesNotShareStateAcrossInstances() async {
        let first = HostCommentStore()
        await first.setComment("should not survive a relaunch", forIP: "192.168.1.10")

        let second = HostCommentStore()
        let comment = await second.comment(forIP: "192.168.1.10")
        XCTAssertNil(comment)
    }

    func testSnapshotReturnsAllStoredComments() async {
        let store = HostCommentStore()
        await store.setComment("router", forIP: "192.168.1.1")
        await store.setComment("printer", forIP: "192.168.1.2")
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot["192.168.001.001"], "router")
        XCTAssertEqual(snapshot["192.168.001.002"], "printer")
    }
}
