import Foundation
import CryptoKit

public enum StableHash {
    public static func make(_ parts: [Any?]) -> String {
        let joined = parts.map { part -> String in
            if let part { return String(describing: part) }
            return ""
        }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
