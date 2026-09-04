import Foundation
import NetworkAnalyzerCore

/// The app's display language. Independent of the system locale — starts in English and only
/// switches when the user explicitly picks a different language in the UI.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ja

    var id: String { rawValue }

    var label: String {
        switch self {
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}

/// All user-facing strings, keyed off the current `AppLanguage`. Kept in the app target (not
/// `NetworkAnalyzerCore`) so the discovery/scanning logic stays language-agnostic — Core only
/// exposes plain enums (`OSFamily`, `TCPStatus`, ...) which this type turns into copy.
struct L10n {
    let lang: AppLanguage

    private func t(_ en: String, _ ja: String) -> String {
        lang == .en ? en : ja
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var appTitle: String { t("Network Analyzer", "ネットワークアナライザ") }
    var scanButton: String { t("Scan", "スキャン") }
    var scanningLabel: String { t("Scanning…", "スキャン中…") }
    var settingsButton: String { t("Settings", "設定") }
    var closeButton: String { t("Close", "閉じる") }
    var unknownValue: String { t("Unknown", "不明") }
    var noOpenPorts: String { t("None", "なし") }
    var exportCsvButton: String { t("Export CSV", "CSVに出力") }

    func csvSaved(_ path: String) -> String { t("Saved CSV to: \(path)", "CSVを保存しました: \(path)") }
    func csvFailed(_ error: String) -> String { t("Failed to export CSV: \(error)", "CSV出力に失敗しました: \(error)") }

    var columnIP: String { t("IP Address", "IPアドレス") }
    var columnHostname: String { t("Hostname", "ホスト名") }
    var columnMAC: String { t("MAC Address", "MACアドレス") }
    var columnVendor: String { t("Vendor", "ベンダー名") }
    var columnOS: String { t("OS (estimated)", "OS種別(推定)") }
    var columnPorts: String { t("Open Ports", "開いているポート") }
    var columnComment: String { t("Comment", "コメント") }
    var commentPlaceholder: String { t("Add a note…", "メモを追加…") }

    var osGuessSuffix: String { t(" (estimated)", "(推定)") }

    func osFamilyLabel(_ family: OSFamily) -> String {
        switch family {
        case .windows: return t("Windows", "Windows系")
        case .unixLike: return t("macOS/Linux", "macOS/Linux系")
        case .networkDevice: return t("Network device", "ネットワーク機器")
        case .unknown: return t("Unknown", "不明")
        }
    }

    func confidenceLabel(_ confidence: OSGuessConfidence) -> String {
        switch confidence {
        case .high: return t("Confidence: high", "確度: 高")
        case .medium: return t("Confidence: medium", "確度: 中")
        case .low: return t("Confidence: low", "確度: 低")
        }
    }

    /// Required disclaimer (spec §2.4): must always accompany the OS-guess column.
    var osDisclaimer: String {
        t(
            "OS type is estimated from TTL values and open-port patterns, and accuracy is not guaranteed.",
            "OS種別はTTL値と開いているポートの傾向から推定したものであり、正確性を保証するものではありません。"
        )
    }

    func lastScanLabel(_ date: Date) -> String {
        t("Last scan: \(Self.dateFormatter.string(from: date))", "最終スキャン: \(Self.dateFormatter.string(from: date))")
    }

    var settingsTitle: String { t("Settings", "設定") }
    var vendorDataSectionTitle: String { t("Vendor Data", "ベンダーデータ") }
    var updateVendorDataButton: String { t("Update Vendor Data", "ベンダーデータを更新") }
    var usingBundledData: String { t("Using the bundled starter dataset.", "同梱の初期データを使用しています。") }

    func lastUpdatedLabel(_ date: Date) -> String {
        t("Last updated: \(Self.dateFormatter.string(from: date))", "最終更新日時: \(Self.dateFormatter.string(from: date))")
    }

    var updateSucceeded: String { t("Vendor data updated successfully.", "ベンダーデータの更新に成功しました。") }
    func updateFailed(_ reason: String) -> String {
        t("Update failed: \(reason)", "更新に失敗しました: \(reason)")
    }

    var rangeStartLabel: String { t("Start IP", "開始IP") }
    var rangeEndLabel: String { t("End IP", "終了IP") }
    var rangeNetmaskLabel: String { t("Netmask", "ネットマスク") }
    var rangePrefixLengthLabel: String { t("Prefix length", "プレフィックス長") }
    var resetToLocalNetworkButton: String { t("Reset to this Mac's network", "このMacのネットワークにリセット") }

    func rangeErrorMessage(_ error: IPv4RangeError) -> String {
        switch error {
        case .invalidAddress(let ip):
            return t("Invalid IP address: \(ip)", "無効なIPアドレスです: \(ip)")
        case .startAfterEnd:
            return t("Start IP must not come after End IP.", "開始IPが終了IPより後になっています。")
        case .rangeTooLarge(let count, let limit):
            return t(
                "Range is too large (\(count) addresses; max \(limit)). Narrow the range.",
                "範囲が広すぎます(\(count)件、上限\(limit)件)。範囲を狭めてください。"
            )
        }
    }

    func rangeErrorMessage(_ error: IPv6RangeError) -> String {
        switch error {
        case .invalidAddress(let ip):
            return t("Invalid IP address: \(ip)", "無効なIPアドレスです: \(ip)")
        case .startAfterEnd:
            return t("Start IP must not come after End IP.", "開始IPが終了IPより後になっています。")
        case .rangeTooLarge(let count, let limit):
            return t(
                "Range is too large (\(count) addresses; max \(limit)). A full subnet is normally far too large to scan — narrow the range.",
                "範囲が広すぎます(\(count)件、上限\(limit)件)。サブネット全体は通常スキャンするには広すぎます。範囲を狭めてください。"
            )
        }
    }

    /// Live "how many addresses does this cover" feedback shown under the range fields as the
    /// user types, before they ever press Scan.
    func rangeAddressCount(_ count: Int, limit: Int) -> String {
        t(
            "\(count) address\(count == 1 ? "" : "es") in range (max \(limit))",
            "範囲内のアドレス数: \(count)件(上限\(limit)件)"
        )
    }

    func rangeAddressCountDescription(_ description: String, limit: Int) -> String {
        t(
            "\(description) addresses in range (max \(limit))",
            "範囲内のアドレス数: \(description)件(上限\(limit)件)"
        )
    }

    /// Explains what range size is actually appropriate for IPv6, shown as a persistent caption
    /// under the range fields on that tab — not just after the user hits the too-large error.
    var ipv6RangeGuidance: String {
        t(
            """
            IPv6 addresses aren't assigned sequentially the way IPv4 addresses typically are, so \
            there's no single subnet-wide range worth sweeping. Narrow Start/End IP to at most \
            \(IPv6Range.maxAddressCount) addresses that plausibly cover real hosts — typically by \
            varying only the last group (e.g. "2001:db8:1234:5678::1" through \
            "2001:db8:1234:5678::1000"), around an address you already know, or a small block your \
            network assigns manually. Scanning the full preset /64 will always report the range as \
            too large.
            """,
            """
            IPv6アドレスはIPv4のように連番で割り当てられるとは限らないため、サブネット全体を \
            スキャンする意味のある「適切な範囲」というものは存在しません。開始IP・終了IPは、実在する \
            可能性のあるホストをカバーできる程度、最大\(IPv6Range.maxAddressCount)件程度に狭めてください。 \
            多くの場合、最後のグループだけを変える(例: "2001:db8:1234:5678::1" 〜 \
            "2001:db8:1234:5678::1000")か、既に分かっているアドレスの周辺、または手動でIPv6アドレスを \
            割り当てているネットワークの小さなブロックを指定するのが現実的です。プリセットされた/64全体を \
            そのままスキャンしようとすると、常に「範囲が広すぎます」という結果になります。
            """
        )
    }
}
