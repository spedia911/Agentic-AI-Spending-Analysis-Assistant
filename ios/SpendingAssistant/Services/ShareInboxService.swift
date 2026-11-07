import Foundation
import SpendingDomain

enum ShareInboxService {
    static let appGroupId = "group.com.spendingassistant.shared"

    static var inboxDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    @MainActor
    static func drain(into service: ImportPipelineService) async -> Int {
        guard let inbox = inboxDirectory else { return 0 }
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        var count = 0
        for file in files {
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                if file.pathExtension.lowercased() == "txt" || file.pathExtension.lowercased() == "json" {
                    let text = try String(contentsOf: file, encoding: .utf8)
                    _ = try await service.importAIJSON(text: text, fileName: file.lastPathComponent)
                } else {
                    let data = try Data(contentsOf: file)
                    _ = try await service.importImage(
                        data: data,
                        fileName: file.lastPathComponent,
                        mimeType: "image/jpeg",
                        sourceType: .share
                    )
                }
                count += 1
            } catch {
                // Leave a breadcrumb file for debugging without retaining sensitive payload.
                continue
            }
        }
        return count
    }
}
