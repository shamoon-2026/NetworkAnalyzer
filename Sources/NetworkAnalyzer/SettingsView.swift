import SwiftUI
import NetworkAnalyzerCore

struct SettingsView: View {
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var isUpdating = false
    @State private var resultMessage: String?
    @State private var updateSucceededLast = false
    @State private var lastUpdated: Date?

    private var l10n: L10n { L10n(lang: language) }
    private let vendorResolver = VendorResolver.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n.settingsTitle)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.vendorDataSectionTitle)
                    .font(.subheadline)
                    .bold()

                HStack {
                    Button(l10n.updateVendorDataButton) {
                        Task { await updateVendorData() }
                    }
                    .disabled(isUpdating)
                    if isUpdating {
                        ProgressView().controlSize(.small)
                    }
                }

                if let lastUpdated {
                    Text(l10n.lastUpdatedLabel(lastUpdated))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(l10n.usingBundledData)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(updateSucceededLast ? .green : .red)
                }
            }

            Divider()

            Text(l10n.osDisclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button(l10n.closeButton) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 440, height: 300)
        .task {
            await vendorResolver.loadIfNeeded()
            lastUpdated = await vendorResolver.lastUpdated
        }
    }

    private func updateVendorData() async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            let date = try await vendorResolver.updateFromIEEE()
            lastUpdated = date
            resultMessage = l10n.updateSucceeded
            updateSucceededLast = true
        } catch {
            resultMessage = l10n.updateFailed(String(describing: error))
            updateSucceededLast = false
        }
    }
}
