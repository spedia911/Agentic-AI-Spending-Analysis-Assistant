import Foundation
import SpendingDomain

struct ShareInboxItem: Identifiable {
    var id: URL { url }
    var url: URL
    var error: String?
    var failureURL: URL { url.appendingPathExtension("failure") }
}

enum ShareInboxService {
    static let appGroupId = "group.com.spendingassistant.shared"
    static var inboxDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    static func items(in inbox: URL) throws -> [ShareInboxItem] {
        guard FileManager.default.fileExists(atPath: inbox.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter {
                guard $0.pathExtension != "failure" else { return false }
                return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let failure = url.appendingPathExtension("failure")
                let error: String?
                if FileManager.default.fileExists(atPath: failure.path) {
                    // An unreadable failure marker must not cause an automatic retry loop.
                    error = (try? String(contentsOf: failure, encoding: .utf8)) ?? "Previous import failed. Retry or delete this item."
                } else { error = nil }
                return ShareInboxItem(url: url, error: error)
            }
    }

    static func markFailed(_ item: ShareInboxItem, message: String) throws {
        try Data(PrivacyRedactor.maskSensitiveText(message).utf8).write(to: item.failureURL, options: [.atomic, .completeFileProtection])
    }

    static func delete(_ item: ShareInboxItem) throws {
        if FileManager.default.fileExists(atPath: item.url.path) { try FileManager.default.removeItem(at: item.url) }
        if FileManager.default.fileExists(atPath: item.failureURL.path) { try FileManager.default.removeItem(at: item.failureURL) }
    }
}
