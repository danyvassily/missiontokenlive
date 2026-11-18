
import Foundation

/// Interrogation des soldes réels des providers, à la demande.
///
/// Règles tenues ici :
/// - la clé est lue dans le Trousseau juste avant l'appel, jamais stockée en propriété ;
/// - seules des requêtes **gratuites et en lecture** sont faites (aucune inférence) ;
/// - un échec ne produit pas de zéro : il produit « indisponible » avec la raison.
struct ProviderBalance: Identifiable {
    let provider: String
    let amount: Double?
    let currency: String
    let detail: String
    let fetchedAt: Date
    var id: String { provider }

    var display: String {
        guard let amount else { return "Non disponible" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f %@", amount, currency)
    }
}

enum Balances {
    struct Target {
        let provider: String
        let account: String
        let url: String
    }

    static let targets: [Target] = [
        .init(provider: "OpenRouter", account: "OPENROUTER_API_KEY",
              url: "https://openrouter.ai/api/v1/credits"),
        .init(provider: "DeepSeek", account: "DEEPSEEK_API_KEY",
              url: "https://api.deepseek.com/user/balance"),
        .init(provider: "Abliteration", account: "ABLITERATION_API_KEY",
              url: "https://api.abliteration.ai/v1/models"),
    ]

    static func fetchAll() async -> [ProviderBalance] {
        await withTaskGroup(of: ProviderBalance.self) { group in
            for target in targets {
                group.addTask { await fetch(target) }
            }
            var out: [ProviderBalance] = []
            for await item in group { out.append(item) }
            return out.sorted { $0.provider < $1.provider }
        }
    }

    private static func fetch(_ target: Target) async -> ProviderBalance {
        let now = Date()
        guard let key = SecretStore.value(target.account), !key.isEmpty else {
            return .init(provider: target.provider, amount: nil, currency: "USD",
                         detail: "aucune clé dans le Trousseau", fetchedAt: now)
        }
        guard let url = URL(string: target.url) else {
            return .init(provider: target.provider, amount: nil, currency: "USD",
                         detail: "URL invalide", fetchedAt: now)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                return .init(provider: target.provider, amount: nil, currency: "USD",
                             detail: "HTTP \(code)", fetchedAt: Date())
            }
            return parse(target, data: data)
        } catch {
            return .init(provider: target.provider, amount: nil, currency: "USD",
                         detail: "réseau : \(error.localizedDescription)", fetchedAt: Date())
        }
    }

    /// Chaque provider a sa forme de réponse ; on ne devine pas, on lit les champs documentés.
    private static func parse(_ target: Target, data: Data) -> ProviderBalance {
        let now = Date()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch target.provider {
        case "OpenRouter":
            if let d = json["data"] as? [String: Any],
               let total = d["total_credits"] as? Double,
               let used = d["total_usage"] as? Double {
                return .init(provider: "OpenRouter", amount: total - used, currency: "USD",
                             detail: String(format: "crédit %.2f − usage %.2f", total, used), fetchedAt: now)
            }
        case "DeepSeek":
            if let infos = json["balance_infos"] as? [[String: Any]], let first = infos.first,
               let raw = first["total_balance"] as? String, let amount = Double(raw) {
                return .init(provider: "DeepSeek", amount: amount,
                             currency: (first["currency"] as? String) ?? "USD",
                             detail: (json["is_available"] as? Bool) == true ? "compte actif" : "compte indisponible",
                             fetchedAt: now)
            }
        case "Abliteration":
            // Pas d'endpoint de solde connu : /models sert seulement à prouver que la clé est acceptée.
            if let list = json["data"] as? [Any] {
                return .init(provider: "Abliteration", amount: nil, currency: "USD",
                             detail: "clé valide · \(list.count) modèles · solde non exposé", fetchedAt: now)
            }
        default:
            break
        }
        return .init(provider: target.provider, amount: nil, currency: "USD",
                     detail: "réponse inattendue", fetchedAt: now)
    }
}
