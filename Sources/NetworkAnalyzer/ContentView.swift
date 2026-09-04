import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NetworkAnalyzerCore

struct ContentView: View {
    @AppStorage("appLanguage") private var language: AppLanguage = .en
    @State private var showSettings = false

    private var l10n: L10n { L10n(lang: language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                NetworkAnalyzerPanelView(ipVersion: .v4, language: language)
                    .tabItem { Label("IPv4", systemImage: "4.circle") }
                NetworkAnalyzerPanelView(ipVersion: .v6, language: language)
                    .tabItem { Label("IPv6", systemImage: "6.circle") }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showSettings) {
            SettingsView(language: language)
        }
    }

    private var header: some View {
        HStack {
            Text(l10n.appTitle).font(.headline)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Label(l10n.settingsButton, systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            Picker("", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        }
        .padding()
    }
}

/// A fully self-contained scan panel for one IP version: its own `NetworkAnalyzerViewModel`, sort
/// state, and CSV export — the IPv4 and IPv6 tabs never share scan results.
struct NetworkAnalyzerPanelView: View {
    let ipVersion: IPVersion
    let language: AppLanguage

    @StateObject private var viewModel: NetworkAnalyzerViewModel
    @State private var sortOrder = [KeyPathComparator(\HostViewModel.ipSortValue, order: .forward)]
    @State private var uiMessage: String?

    // The user-specified scan target (a range + netmask/prefix length, the latter used only for
    // the "reset to local network" computation), preset from this Mac's own network
    // configuration on first appearance.
    @State private var startIPText = ""
    @State private var endIPText = ""
    @State private var netmaskOrPrefixText = ""
    @State private var rangeError: String?

    private var l10n: L10n { L10n(lang: language) }

    init(ipVersion: IPVersion, language: AppLanguage) {
        self.ipVersion = ipVersion
        self.language = language
        _viewModel = StateObject(wrappedValue: NetworkAnalyzerViewModel(ipVersion: ipVersion))
    }

    private var sortedHosts: [HostViewModel] {
        viewModel.hosts.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            rangeInputRow
            toolbar
            if let uiMessage {
                Text(uiMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
            Divider()
            table
            Divider()
            footer
        }
        .task {
            presetRangeFromLocalNetwork()
        }
    }

    private var rangeInputRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.rangeStartLabel)
                TextField("", text: $startIPText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: ipVersion == .v4 ? 130 : 260)
                Text(l10n.rangeEndLabel)
                TextField("", text: $endIPText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: ipVersion == .v4 ? 130 : 260)
                Text(ipVersion == .v4 ? l10n.rangeNetmaskLabel : l10n.rangePrefixLengthLabel)
                TextField("", text: $netmaskOrPrefixText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: ipVersion == .v4 ? 130 : 50)
                Button {
                    presetRangeFromLocalNetwork()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(l10n.resetToLocalNetworkButton)
                .accessibilityLabel(l10n.resetToLocalNetworkButton)
                Spacer()
            }
            if let rangeSummary {
                Text(rangeSummary.text)
                    .font(.caption)
                    .foregroundStyle(rangeSummary.isTooLarge ? .red : .secondary)
            }
            if ipVersion == .v6 {
                Text(l10n.ipv6RangeGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rangeError {
                Text(rangeError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    /// Live "how many addresses does this cover, and is that scannable" feedback computed
    /// cheaply from the current Start/End IP text as the user types — not just surfaced as an
    /// error after they press Scan.
    private var rangeSummary: (text: String, isTooLarge: Bool)? {
        switch ipVersion {
        case .v4:
            guard let count = IPv4Range.addressCount(start: startIPText, end: endIPText) else { return nil }
            return (l10n.rangeAddressCount(count, limit: IPv4Range.maxAddressCount), count > IPv4Range.maxAddressCount)
        case .v6:
            guard let description = IPv6Range.addressCountDescription(start: startIPText, end: endIPText) else { return nil }
            let within = IPv6Range.isWithinScanLimit(start: startIPText, end: endIPText) ?? false
            return (l10n.rangeAddressCountDescription(description, limit: IPv6Range.maxAddressCount), !within)
        }
    }

    private var toolbar: some View {
        HStack {
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text(l10n.scanningLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(l10n.exportCsvButton) {
                exportCsv()
            }
            .disabled(viewModel.hosts.isEmpty || viewModel.isScanning)
            Button(l10n.scanButton) {
                startScan()
            }
            .disabled(viewModel.isScanning)
        }
        .padding()
    }

    private func presetRangeFromLocalNetwork() {
        switch ipVersion {
        case .v4:
            guard let info = LocalNetworkInfoProvider.primaryIPv4(),
                  let range = IPv4Range.hostRange(address: info.address, netmask: info.netmask) else {
                return
            }
            startIPText = range.start
            endIPText = range.end
            netmaskOrPrefixText = info.netmask
        case .v6:
            guard let info = LocalNetworkInfoProvider.primaryIPv6(),
                  let range = IPv6Range.hostRange(address: info.address, prefixLength: info.prefixLength) else {
                return
            }
            startIPText = range.start
            endIPText = range.end
            netmaskOrPrefixText = String(info.prefixLength)
        }
        rangeError = nil
    }

    private func startScan() {
        uiMessage = nil
        do {
            switch ipVersion {
            case .v4:
                _ = try IPv4Range.addresses(start: startIPText, end: endIPText)
            case .v6:
                _ = try IPv6Range.addresses(start: startIPText, end: endIPText)
            }
            rangeError = nil
            let range = (start: startIPText, end: endIPText)
            Task { await viewModel.runScan(range: range) }
        } catch let error as IPv4RangeError {
            rangeError = l10n.rangeErrorMessage(error)
        } catch let error as IPv6RangeError {
            rangeError = l10n.rangeErrorMessage(error)
        } catch {
            rangeError = error.localizedDescription
        }
    }

    private var table: some View {
        Table(sortedHosts, sortOrder: $sortOrder) {
            TableColumn(l10n.columnIP, value: \.ipSortValue) { host in Text(host.ip) }
                .width(min: 110, ideal: 160)
            TableColumn(l10n.columnHostname, value: \.hostnameSortValue) { host in Text(host.hostname ?? l10n.unknownValue) }
                .width(min: 120, ideal: 160)
            TableColumn(l10n.columnMAC, value: \.macSortValue) { host in Text(host.mac ?? l10n.unknownValue).monospaced() }
                .width(min: 140, ideal: 150)
            TableColumn(l10n.columnVendor, value: \.vendorSortValue) { host in Text(host.vendor ?? l10n.unknownValue) }
                .width(min: 120, ideal: 160)
            TableColumn(l10n.columnOS, value: \.osSortValue) { host in osCell(host) }
                .width(min: 140, ideal: 160)
            TableColumn(l10n.columnPorts, value: \.openPortCount) { host in portsCell(host) }
                .width(min: 200, ideal: 280)
            TableColumn(l10n.columnComment, value: \.commentSortValue) { host in commentCell(host) }
                .width(min: 140, ideal: 220)
        }
    }

    private func commentCell(_ host: HostViewModel) -> some View {
        TextField(l10n.commentPlaceholder, text: Binding(
            get: { host.comment ?? "" },
            set: { viewModel.setComment($0, forIP: host.ip) }
        ))
        .textFieldStyle(.plain)
    }

    private var footer: some View {
        HStack(alignment: .top) {
            Text(l10n.osDisclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let date = viewModel.lastScanDate {
                Text(l10n.lastScanLabel(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func osCell(_ host: HostViewModel) -> some View {
        if let guess = host.osGuess {
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.osFamilyLabel(guess.os) + l10n.osGuessSuffix)
                Text(l10n.confidenceLabel(guess.confidence))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(l10n.unknownValue)
        }
    }

    @ViewBuilder
    private func portsCell(_ host: HostViewModel) -> some View {
        let interesting = host.ports.filter(\.isOpenOrResponded)
        if interesting.isEmpty {
            Text(l10n.noOpenPorts)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(interesting) { port in
                    PortBadge(port: port)
                }
            }
        }
    }

    private func exportCsv() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        panel.nameFieldStringValue = "network-analyzer-\(ipVersion.rawValue)-\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try viewModel.csvContent().write(to: url, atomically: true, encoding: .utf8)
                uiMessage = l10n.csvSaved(url.path)
            } catch {
                uiMessage = l10n.csvFailed(error.localizedDescription)
            }
        }
    }
}

private struct PortBadge: View {
    let port: PortResult

    var body: some View {
        Text("\(port.proto == .tcp ? "TCP" : "UDP") \(port.port)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private var tint: Color {
        port.proto == .tcp ? .blue : .orange
    }
}
