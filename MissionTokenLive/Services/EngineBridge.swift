import Foundation
import CMissionTokenFFI

/// Pont Swift → moteur Rust.
///
/// Le moteur expose un instantané JSON unique (`mtl_snapshot_json`) : l'interface ne
/// fabrique aucune donnée, elle affiche ce que le moteur a collecté, avec son étiquette
/// de fiabilité.
enum EngineBridge {
    static var version: String {
        guard let c = mtl_version() else { return "moteur indisponible" }
        defer { mtl_free_string(c) }
        return String(cString: c)
    }

    /// Base locale de l'application (jamais celle d'Hermès).
    static func databaseURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("MissionTokenLive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("missiontokenlive.sqlite")
    }

    /// Remplit la base avec les fixtures si elle est vide.
    ///
    /// On teste le contenu et non l'existence du fichier : une base créée par une
    /// version antérieure (donc vide) doit être réamorcée, sinon l'interface reste
    /// muette — c'est exactement le bug observé au premier lancement.
    static func seedDemoIfNeeded() {
        let path = databaseURL().path
        if let snap = snapshot(), !snap.agents.isEmpty { return }
        _ = mtl_seed_demo(path)
    }

    static func snapshot() -> Snapshot? {
        let path = databaseURL().path
        guard let c = path.withCString({ mtl_snapshot_json($0) }) else { return nil }
        defer { mtl_free_string(c) }
        let json = String(cString: c)
        return try? JSONDecoder.mtl.decode(Snapshot.self, from: Data(json.utf8))
    }

    static func hermesTasks(limit: UInt32 = 50) -> [TaskItem] {
        guard let c = mtl_hermes_tasks_json(limit) else { return [] }
        defer { mtl_free_string(c) }
        let json = String(cString: c)
        return (try? JSONDecoder.mtl.decode([TaskItem].self, from: Data(json.utf8))) ?? []
    }

    /// Actions de gestion des projets (locales, réversibles sauf purge).
    @discardableResult
    static func projectAction(id: String, action: String) -> Bool {
        let path = databaseURL().path
        let code = path.withCString { db in
            id.withCString { pid in
                action.withCString { act in
                    mtl_project_action(db, pid, act)
                }
            }
        }
        return code == 0
    }

    static func desktopActivity() -> [DesktopAppActivity] {
        guard let c = mtl_desktop_activity_json() else { return [] }
        defer { mtl_free_string(c) }
        let json = String(cString: c)
        return (try? JSONDecoder.mtl.decode([DesktopAppActivity].self, from: Data(json.utf8))) ?? []
    }
}

extension JSONDecoder {
    /// Les dates du moteur sont en RFC 3339 avec fraction de seconde.
    static var mtl: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "date invalide: \(s)"))
        }
        return d
    }
}
