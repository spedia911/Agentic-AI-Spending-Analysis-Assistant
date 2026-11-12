import SwiftUI
import SwiftData
import SpendingDomain

struct ExportDataView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var transactions: [SDTransaction]
    @Query private var balances: [SDAssetSnapshot]
    @Query private var reviews: [SDReviewItem]
    @State private var share: ExportFile?
    @State private var exporting = false
    @State private var message: String?

    private enum Format {
        case desktop, csv
    }

    var body: some View {
        let tx = transactions.map { $0.toRecord() }
        let assets = balances.map { $0.toRecord() }
        let issues = reviews.map { $0.toRecord() }
        let eligibleTransactions = tx.count { Eligibility.transaction($0, reviews: issues).desktop }
        let eligibleBalances = assets.count { Eligibility.asset($0, reviews: issues, peers: assets).desktop }
        let withheld = tx.count + assets.count - eligibleTransactions - eligibleBalances

        Form {
            Section("Asset Management Assistant") {
                Button("Share desktop export", systemImage: "square.and.arrow.up") { export(.desktop) }
                    .accessibilityIdentifier("exportDesktop")
                Text("Share transactions and balances with your Mac. The export includes a complete snapshot of your records so new imports, corrections, and deletions carry through when you import the latest file.")
                LabeledContent("Ready for desktop", value: "\(eligibleTransactions) transactions · \(eligibleBalances) balances")
                if withheld > 0 {
                    Text("Desktop will withhold \(withheld) records. Common reasons include pending reviews, missing accounts, and a billed currency that differs from the account currency.")
                    Text("Use the CSV below to analyze account-free transactions in a spreadsheet.").font(.caption)
                }
                Text("The JSON includes extracted records and evidence. Original images and PDFs are left out.")
            }
            Section("Spreadsheet") {
                Button("Share transaction CSV", systemImage: "tablecells") { export(.csv) }
                    .accessibilityIdentifier("exportCSV")
                Text("Open in Excel or Numbers. The CSV includes all transactions, billed currencies, and desktop exclusion reasons.")
            }
            if let message { Text(message).foregroundStyle(.secondary) }
        }
        .navigationTitle("Export data")
        .disabled(imports.isBusy || exporting)
        .sheet(item: $share, onDismiss: { ExportFile.cleanup() }) { file in ExportShareSheet(url: file.url) }
    }

    private func export(_ format: Format) {
        message = nil
        exporting = true
        Task {
            defer { exporting = false }
            do {
                share = try await imports.exclusive {
                    let store = imports.service.store
                    switch format {
                    case .desktop:
                        let backup = BackupService(store: store, files: imports.service.files)
                        return try ExportFile(data: backup.export(includeOriginals: false), name: "spending-desktop", extension: "json")
                    case .csv:
                        let csv = try BackupExporter.transactionsCSV(store.allTransactions(), reviews: store.allReviews())
                        return try ExportFile(data: Data(csv.utf8), name: "spending-transactions", extension: "csv")
                    }
                }
            } catch { message = PrivacyRedactor.safeErrorDetail(error) }
        }
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("ProtectedExports") }
    init(data: Data, name: String, extension ext: String) throws {
        let folder = Self.directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateSeparator(.dash).timeSeparator(.omitted))
        url = folder.appendingPathComponent("\(name)-\(stamp).\(ext)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    static func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

struct ExportShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in ExportFile.cleanup() }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
