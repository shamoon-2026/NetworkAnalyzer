import Foundation

/// Builds a CSV export of scan results.
public enum CSVExport {
    /// Column values are fixed, non-localized identifiers (`OSFamily`/`OSGuessConfidence` raw
    /// values, "TCP"/"UDP") rather than the UI's current display language, so an exported file
    /// stays meaningful regardless of what language the app happens to be showing when opened.
    public static func content(for hosts: [HostViewModel]) -> String {
        var lines = ["ip_address,hostname,mac_address,vendor,os_guess,os_confidence,open_ports,comment"]
        for host in hosts {
            let ports = host.ports
                .filter(\.isOpenOrResponded)
                .map { "\($0.proto.rawValue.uppercased())/\($0.port)" }
                .joined(separator: " ")
            let fields = [
                host.ip,
                host.hostname ?? "",
                host.mac ?? "",
                host.vendor ?? "",
                host.osGuess?.os.rawValue ?? "",
                host.osGuess?.confidence.rawValue ?? "",
                ports,
                host.comment ?? ""
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC 4180 quoting for a CSV field, plus a leading `'` on values starting with `=`, `+`, `-`,
    /// or `@` so a resolved hostname/vendor string can't be interpreted as a formula if the file
    /// is opened in a spreadsheet app (CSV/formula injection) — same convention as
    /// MultiPingMonitor-macOS's `MonitorViewModel.csvContent`.
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.unicodeScalars.first, "=+-@".unicodeScalars.contains(first) {
            value = "'" + value
        }
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
