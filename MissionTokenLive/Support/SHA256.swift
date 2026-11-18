
import Foundation
import CryptoKit

enum SHA256 {
    static func hash(_ text: String) -> String {
        let digest = CryptoKit.SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
