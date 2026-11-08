import Foundation
import SpendingDomain

struct SourceFileStore {
    let directory: URL

    init(directory: URL = Self.sourcesDirectory) { self.directory = directory }

    static var sourcesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sources", isDirectory: true)
    }

    func save(data: Data, sourceId: String, fileName: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = URL(fileURLWithPath: fileName).pathExtension
        let safeExt = ext.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } ? String(ext.prefix(10)) : "image"
        let relative = "\(StableHash.make([sourceId]))-\(UUID().uuidString).\(safeExt)"
        try data.write(to: url(relative), options: [.atomic, .completeFileProtection])
        return relative
    }

    func url(_ relative: String) throws -> URL {
        guard !relative.isEmpty, relative == (relative as NSString).lastPathComponent else { throw ImportFailure.missingImage }
        return directory.appendingPathComponent(relative)
    }

    func read(_ relative: String) throws -> Data { try Data(contentsOf: url(relative)) }
    func remove(_ relative: String) throws { try FileManager.default.removeItem(at: url(relative)) }

    static func url(forRelativePath path: String) -> URL { sourcesDirectory.appendingPathComponent((path as NSString).lastPathComponent) }

    static func cleanup(retentionDays: Int, sources: [SourceDocumentRecord]) {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        for source in sources {
            guard let relative = source.localRelativePath else { continue }
            let url = url(forRelativePath: relative)
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
