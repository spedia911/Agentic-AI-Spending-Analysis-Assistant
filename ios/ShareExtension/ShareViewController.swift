import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupId = "group.com.spendingassistant.shared"
    private var started = false
    private var ingesting = false
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "Saving shared items…"
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { await ingest() }
    }

    private func ingest() async {
        guard !ingesting else { return }
        ingesting = true; defer { ingesting = false }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var saved = 0
        do {
            guard !providers.isEmpty else { throw HandoffError.noAttachments }
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { throw HandoffError.noContainer }
            let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            var failures = 0
            for provider in providers {
                do { try await save(provider, in: inbox); saved += 1 }
                catch { failures += 1 }
            }
            if failures > 0 { throw HandoffError.unsaved }
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            // Never display provider errors containing attachment paths or financial text.
            statusLabel.text = "Saved \(saved) of \(providers.count) items."
            let alert = UIAlertController(title: "Some items were not saved", message: "\(statusLabel.text ?? "") Open the app to process saved items. Retry to save the remaining attachments; repeated items will be recognized by the app.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in Task { await self?.ingest() } })
            alert.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self] _ in self?.extensionContext?.completeRequest(returningItems: nil) })
            present(alert, animated: true)
        }
    }

    private func save(_ provider: NSItemProvider, in inbox: URL) async throws {
        let identifier: String
        if let imageType = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            identifier = imageType
        } else if provider.hasItemConformingToTypeIdentifier(UTType.json.identifier) {
            identifier = UTType.json.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            identifier = UTType.plainText.identifier
        } else { throw HandoffError.unsupported }
        let ext = UTType(identifier)?.preferredFilenameExtension ?? "txt"
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else { continuation.resume(throwing: HandoffError.unsaved) }
            }
        }
        // The final file becomes visible to the host only after a complete write.
        let url = inbox.appendingPathComponent("share-\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private enum HandoffError: Error { case noAttachments, noContainer, unsupported, unsaved }
}
