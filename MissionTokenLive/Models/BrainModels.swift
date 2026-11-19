import Foundation

/// Strings for the memory workspace; the rest of the app keeps its existing localization.
enum BrainCopy {
    static func text(_ french: String, _ english: String) -> String {
        Locale.current.language.languageCode?.identifier == "en" ? english : french
    }
    static let title = text("Cerveau", "Memory")
    static let memory = text("Mémoire", "Memory")
    static let review = text("À valider", "To review")
    static let sources = text("Sources", "Sources")
    static let active = text("En mémoire", "In memory")
    static let stale = text("À actualiser", "Outdated")
    static let search = text("Rechercher dans ma mémoire", "Search my memory")
    static let refresh = text("Actualiser", "Refresh")
    static let allTypes = text("Tous les types", "All types")
    static let allEntities = text("Personnes et projets", "People and projects")
    static let allSources = text("Toutes les sources", "All sources")
    static let accept = text("Valider ce fait", "Accept this fact")
    static let reject = text("Rejeter", "Reject")
    static let openSource = text("Ouvrir la source", "Open source")
    static let proof = text("Preuve et provenance", "Evidence and origin")
    static let empty = text("Aucun résultat", "No results")
    static let retry = text("Réessayer", "Try again")
    static let filterSources = text("Filtrer les sources", "Filter sources")
    static let unavailable = text("Indisponible", "Unavailable")
    static let pending = text("Proposé", "Proposed")
}

struct BrainStats: Codable {
    let available: Bool
    let path: String
    let facts: Int
    let chunks: Int
    let sourceCount: Int
    let entities: Int
    let last_ingest: String?
    let top_entities: [BrainEntity]
    let recent: [BrainFact]
    let sourceList: [BrainSource]?
    let never: [String]?
    var pending: Int? = nil
    var superseded: Int? = nil
    var last_error: String? = nil

    static let unavailable = BrainStats(
        available: false, path: "~/.gbrain/gbrain.sqlite", facts: 0, chunks: 0,
        sourceCount: 0, entities: 0, last_ingest: nil, top_entities: [], recent: [],
        sourceList: [], never: []
    )

    var freshness: String {
        guard let date = BrainFact.date(last_ingest) else { return BrainCopy.text("jamais", "never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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
    var section: String? = nil
    var at: String? = nil
    var status: String? = nil
    var id: String { "\(source ?? "")|\(text)" }
    var kindLabel: String { Self.kindLabel(kind) }
    var statusLabel: String { status == "superseded" ? BrainCopy.stale : BrainCopy.active }

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "preference": return BrainCopy.text("Préférence", "Preference")
        case "decision": return BrainCopy.text("Décision", "Decision")
        case "people": return BrainCopy.text("Personne", "Person")
        case "admin": return BrainCopy.text("Administratif", "Administrative")
        case "project": return BrainCopy.text("Projet", "Project")
        default: return BrainCopy.text("Note", "Note")
        }
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }

    static func sourceURL(_ source: String?) -> URL? {
        guard let source, !source.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path: String
        if source.hasPrefix("pdf:") {
            let relative = String(source.dropFirst(4))
            guard !relative.split(separator: "/").contains("..") else { return nil }
            path = home.appendingPathComponent(".gbrain").appendingPathComponent(relative).path
        } else if source.hasPrefix("~/") {
            path = home.appendingPathComponent(String(source.dropFirst(2))).path
        } else if source.hasPrefix("/") {
            path = source
        } else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    static func sourceName(_ source: String?) -> String {
        guard let source else { return BrainCopy.text("Source inconnue", "Unknown source") }
        return sourceURL(source)?.lastPathComponent ?? source
    }
}

struct BrainCandidate: Decodable, Identifiable {
    let id: Int
    let text: String
    let kind: String
    let entity: String?
    let reason: String?
    let source: String?
    let created_at: String?
    var origin: String? = nil
}

struct BrainSource: Codable, Identifiable {
    let path: String
    let kind: String
    let facts: Int
    let present: Bool
    var ingested_at: String? = nil
    var last_error: String? = nil
    var id: String { path }
}
