import Foundation

/// Resolves a MAC address's NIC vendor from the IEEE OUI registry.
///
/// A small starter dataset ships in the app bundle (see `Resources/oui.csv`) so vendor lookups
/// work offline immediately after install, but it is **not** kept current automatically — the
/// spec requires no background/startup fetching. Call `updateFromIEEE()` (wired to an explicit
/// "Update vendor data" button) to fetch the authoritative list and cache it under Application
/// Support; after that it takes priority over the bundled copy.
public actor VendorResolver {
    public static let shared = VendorResolver()

    public static let ieeeCSVURL = URL(string: "https://standards-oui.ieee.org/oui/oui.csv")!

    private let appSupportDirectoryName: String
    private var ouiMap: [String: String] = [:]
    private var loaded = false
    public private(set) var lastUpdated: Date?

    public init(appSupportDirectoryName: String = "NetworkAnalyzer") {
        self.appSupportDirectoryName = appSupportDirectoryName
    }

    private var cachedCSVURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent(appSupportDirectoryName, isDirectory: true).appendingPathComponent("oui.csv")
    }

    /// Loads the cached downloaded CSV if present, otherwise the bundled starter dataset.
    /// Safe to call repeatedly; only does work once.
    public func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true

        if let cachedURL = cachedCSVURL,
           let data = try? Data(contentsOf: cachedURL),
           let text = String(data: data, encoding: .utf8) {
            ouiMap = Self.parseOUICSV(text)
            lastUpdated = (try? FileManager.default.attributesOfItem(atPath: cachedURL.path)[.modificationDate]) as? Date
            return
        }

        if let bundledURL = Bundle.module.url(forResource: "oui", withExtension: "csv"),
           let data = try? Data(contentsOf: bundledURL),
           let text = String(data: data, encoding: .utf8) {
            ouiMap = Self.parseOUICSV(text)
        }
    }

    /// Looks up the vendor name for a MAC address's OUI (first 3 octets). Returns nil if unknown.
    public func resolveVendor(mac: String) -> String? {
        guard let key = MACAddress.ouiKey(mac) else { return nil }
        return ouiMap[key]
    }

    public enum UpdateError: Error {
        case network(Error)
        case invalidResponse
        case emptyData
        case parseProducedNoEntries
    }

    /// Fetches the current IEEE OUI registry, replaces the in-memory table, and caches it to
    /// Application Support for future launches. Only ever called from an explicit user action
    /// (a "Update vendor data" button) — never automatically.
    @discardableResult
    public func updateFromIEEE() async throws -> Date {
        await loadIfNeeded()

        let data: Data
        do {
            let (fetchedData, response) = try await URLSession.shared.data(from: Self.ieeeCSVURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw UpdateError.invalidResponse
            }
            data = fetchedData
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.network(error)
        }

        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            throw UpdateError.emptyData
        }

        let parsed = Self.parseOUICSV(text)
        guard !parsed.isEmpty else {
            throw UpdateError.parseProducedNoEntries
        }

        guard let cachedURL = cachedCSVURL else {
            throw UpdateError.invalidResponse
        }
        try FileManager.default.createDirectory(at: cachedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cachedURL, options: .atomic)

        ouiMap = parsed
        let now = Date()
        lastUpdated = now
        return now
    }

    /// Parses an IEEE OUI registry CSV (`Registry,Assignment,Organization Name,Organization Address`)
    /// into an `[OUI hex key: vendor name]` map. Pure and dependency-free for unit testing.
    static func parseOUICSV(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var isFirstLine = true
        // `.components(separatedBy: .newlines)` (not `split(separator: "\n")`): the IEEE export
        // uses CRLF line endings, and Swift's `Character` treats "\r\n" as a single grapheme
        // cluster, so splitting on the bare "\n" `Character` never matches inside it — the whole
        // file would come back as one unparseable "line". `.newlines` handles CRLF/CR/LF alike.
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if isFirstLine {
                isFirstLine = false
                if line.lowercased().hasPrefix("registry,assignment") {
                    continue
                }
            }
            let fields = parseCSVLine(line)
            guard fields.count >= 3 else { continue }
            let assignment = fields[1].trimmingCharacters(in: .whitespaces).uppercased()
            let orgName = fields[2].trimmingCharacters(in: .whitespaces)
            guard assignment.count == 6, assignment.allSatisfy({ $0.isHexDigit }), !orgName.isEmpty else { continue }
            result[assignment] = orgName
        }
        return result
    }

    /// Minimal RFC 4180 CSV field splitter: handles double-quoted fields, embedded commas, and
    /// "" as an escaped quote. Sufficient for the IEEE registry's export format.
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if inQuotes {
                if char == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            }
            i += 1
        }
        fields.append(current)
        return fields
    }
}
