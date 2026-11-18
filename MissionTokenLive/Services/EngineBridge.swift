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

    struct Settings: Codable {
        let budget: Double?
        let warn: Int
        let critical: Int
        let hideDock: Bool

        static let fallback = Settings(budget: nil, warn: 80, critical: 95, hideDock: false)
    }

    static func keyInventory() -> [ProviderKey] {
        guard let raw = mtl_keys_json() else { return [] }
        defer { mtl_free_string(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        return (try? JSONDecoder().decode([ProviderKey].self, from: data)) ?? []
    }

    /// Valeur en clair : seul `ProvidersView.importKey` l'appelle, puis la copie
    /// dans le Trousseau. Aucun affichage, aucun log.
    static func keyValue(_ envVar: String) -> String? {
        guard let ptr = mtl_key_value(envVar) else { return nil }
        defer { mtl_free_string(ptr) }
        return String(cString: ptr)
    }

    static func brainStats() -> BrainStats {
        guard let c = mtl_brain_json() else { return .unavailable }
        defer { mtl_free_string(c) }
        let json = String(cString: c)
        return (try? JSONDecoder().decode(BrainStats.self, from: Data(json.utf8))) ?? .unavailable
    }

    static func settings() -> Settings {
        let path = databaseURL().path
        guard let c = path.withCString({ mtl_settings_json($0) }) else { return .fallback }
        defer { mtl_free_string(c) }
        let json = String(cString: c)
        return (try? JSONDecoder().decode(Settings.self, from: Data(json.utf8))) ?? .fallback
    }

    @discardableResult
    static func saveSettings(budget: String, warn: Double, critical: Double, hideDock: Bool) -> Bool {
        let path = databaseURL().path
        let code = path.withCString { db in
            budget.withCString { b in
                mtl_save_settings(db, b, Int32(warn), Int32(critical), hideDock ? 1 : 0)
            }
        }
        return code == 0
    }

    /// Purge les fiches dont la corbeille a expiré. Appelé au démarrage.
    @discardableResult
    static func sweepTrash() -> Int {
        let path = databaseURL().path
        let n = path.withCString { mtl_sweep_trash($0) }
        return Int(n)
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
