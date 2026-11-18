
import Foundation

/// État du cerveau gbrain, lu en lecture seule par le moteur Rust.
struct BrainStats: Codable {
    let available: Bool
    let path: String
    let facts: Int
    let chunks: Int
    let sources: Int
    let entities: Int
    let last_ingest: String?
    let top_entities: [BrainEntity]
    let recent: [BrainFact]

    static let unavailable = BrainStats(
        available: false, path: "~/.gbrain/gbrain.sqlite", facts: 0, chunks: 0,
        sources: 0, entities: 0, last_ingest: nil, top_entities: [], recent: []
    )

    /// « il y a 12 min » — l'écran doit dire la fraîcheur, pas une date brute.
    var freshness: String {
        guard let raw = last_ingest, let date = ISO8601DateFormatter().date(from: raw) else {
            return "jamais"
        }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 2 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return "il y a \(hours) h" }
        return "il y a \(hours / 24) j"
    }
}

struct BrainEntity: Codable, Identifiable {
    let name: String
    let facts: Int
    var id: String { name }
}

struct BrainFact: Codable, Identifiable {
    let text: String
    let kind: String
    let entity: String?
    let source: String?
    var id: String { text }

    var kindLabel: String {
        switch kind {
        case "preference": return "Préférence"
        case "decision": return "Décision"
        case "people": return "Personne"
        case "admin": return "Admin"
        case "project": return "Projet"
        default: return "Note"
        }
    }
}
