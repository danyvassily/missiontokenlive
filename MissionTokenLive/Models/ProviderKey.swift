
import Foundation

/// Une clé telle que l'application la connaît : un nom, un état, jamais la valeur.
struct ProviderKey: Codable, Identifiable {
    let provider: String
    let envVar: String
    let kind: String
    let present: Bool
    let masked: String

    var id: String { envVar }
}
