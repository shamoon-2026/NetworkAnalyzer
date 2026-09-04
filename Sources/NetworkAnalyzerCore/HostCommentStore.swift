import Foundation

/// Holds user-typed comments for hosts, keyed by IP address, for the lifetime of the current app
/// run only. Comments survive a rescan within a session (which otherwise replaces
/// `NetworkAnalyzerViewModel.hosts` entirely) but are deliberately **not** persisted to disk —
/// relaunching the app starts with a clean slate, by design.
///
/// One store per IP-version tab (comments aren't shared between the IPv4 and IPv6 tabs, matching
/// every other piece of per-tab state in this app) — see `NetworkAnalyzerViewModel`.
public actor HostCommentStore {
    private var comments: [String: String] = [:]

    public init() {}

    public func comment(forIP ip: String) -> String? {
        comments[IPAddressSortKey.make(for: ip)]
    }

    /// All stored comments, keyed by `IPAddressSortKey.make(for:)` rather than the raw address —
    /// the same IPv6 address can print with different "::" compression across scans, so callers
    /// merging this back onto freshly discovered hosts must look up by the same canonical key.
    public func snapshot() -> [String: String] {
        comments
    }

    /// Setting an empty (or all-whitespace) comment removes it rather than storing an empty string.
    public func setComment(_ comment: String, forIP ip: String) {
        let key = IPAddressSortKey.make(for: ip)
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            comments.removeValue(forKey: key)
        } else {
            comments[key] = trimmed
        }
    }
}
