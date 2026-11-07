import Foundation
import SpendingDomain

enum SourceFileStore {
    static var sourcesDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = root.appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func saveImage(data: Data, sourceDocumentId: String, fileName: String) throws -> String {
        let safeName = fileName.replacingOccurrences(of: "/", with: "_")
        let relative = "\(sourceDocumentId)-\(safeName)"
        let url = sourcesDirectory.appendingPathComponent(relative)
        try data.write(to: url, options: .atomic)
        return relative
    }

    static func url(forRelativePath path: String) -> URL {
        sourcesDirectory.appendingPathComponent(path)
    }

    static func cleanup(retentionDays: Int, sources: [SourceDocumentRecord]) {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        for source in sources {
            guard let relative = source.localRelativePath else { continue }
            let url = url(forRelativePath: relative)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
