import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private let appGroupId = "group.com.spendingassistant.shared"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await ingest() }
    }

    private func ingest() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        let inbox = container?.appendingPathComponent("Inbox", isDirectory: true)
        if let inbox {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    await save(provider: provider, type: UTType.image.identifier, inbox: inbox, ext: "jpg")
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    await save(provider: provider, type: UTType.plainText.identifier, inbox: inbox, ext: "txt")
                } else if provider.hasItemConformingToTypeIdentifier(UTType.json.identifier) {
                    await save(provider: provider, type: UTType.json.identifier, inbox: inbox, ext: "json")
                }
            }
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func save(provider: NSItemProvider, type: String, inbox: URL?, ext: String) async {
        guard let inbox else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                defer { continuation.resume() }
                let name = "share-\(UUID().uuidString).\(ext)"
                let url = inbox.appendingPathComponent(name)
                if let data = item as? Data {
                    try? data.write(to: url)
                } else if let text = item as? String {
                    try? text.data(using: .utf8)?.write(to: url)
                } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                    try? data.write(to: url)
                } else if let fileURL = item as? URL, let data = try? Data(contentsOf: fileURL) {
                    try? data.write(to: url)
                }
            }
        }
    }
}
