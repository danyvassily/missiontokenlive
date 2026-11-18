
import Foundation

/// Coffre local des clés de l'application.
///
/// Pourquoi pas le Trousseau : l'app est signée ad hoc, donc son identité change à chaque
/// compilation ; macOS considère alors chaque version comme une application étrangère et
/// affiche une demande d'autorisation **bloquante** à la lecture — incompatible avec une
/// interrogation de soldes en arrière-plan.
///
/// Ici : un fichier `keys.json` dans Application Support, dossier 0700, fichier 0600,
/// lisible uniquement par l'utilisateur courant. Aucune valeur n'est affichée par l'interface.
enum SecretStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MissionTokenLive", isDirectory: true)
    }

    private static var fileURL: URL { directory.appendingPathComponent("keys.json") }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    static func all() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return dict
    }

    static func has(_ account: String) -> Bool {
        !(all()[account] ?? "").isEmpty
    }

    static func value(_ account: String) -> String? {
        let v = all()[account]
        return (v?.isEmpty == false) ? v : nil
    }

    @discardableResult
    static func store(_ value: String, account: String) -> Bool {
        ensureDirectory()
        var dict = all()
        dict[account] = value
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return false }
        do {
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    static func remove(_ account: String) {
        var dict = all()
        dict.removeValue(forKey: account)
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    /// Rapport d'import : comptes et empreintes, jamais les valeurs.
    static func fingerprintReport(_ accounts: [String]) -> [[String: Any]] {
        let dict = all()
        return accounts.compactMap { account in
            guard let value = dict[account] else { return nil }
            return ["account": account, "stored": true, "sha256": SHA256.hash(value)]
        }
    }
}
