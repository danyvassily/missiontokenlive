import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var keys: [ProviderKey] = []
    @State private var stored: Set<String> = []
    @State private var message: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Providers & solde",
                subtitle: "Les soldes proviennent uniquement des API officielles ; toute valeur absente reste absente"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(store.apiProviders) { provider in
                            ProviderCard(provider: provider)
                        }
                    }
                    keycard
                    Card(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Abonnements (hors API)").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                            }
                            Text("Suivi de présence uniquement — aucun compteur de tokens ni de crédits inventé.")
                                .font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                            ForEach(store.subscriptionProviders) { provider in
                                HStack(spacing: 10) {
                                    Circle().fill(Theme.textTertiary).frame(width: 6, height: 6)
                                    Text(provider.name).font(Theme.body(12)).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(provider.note ?? "Suivi de présence")
                                        .font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                                }
                                .padding(.vertical, 6)
                                Rectangle().fill(Theme.borderSoft).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        keys = EngineBridge.keyInventory()
        stored = Set(keys.map(\.envVar).filter { Keychain.has(account: $0) })
    }

    private func importKey(_ key: ProviderKey) {
        guard let value = EngineBridge.keyValue(key.envVar) else {
            message = "Lecture impossible pour \(key.provider)."
            return
        }
        if Keychain.store(value, account: key.envVar) {
            stored.insert(key.envVar)
            message = "\(key.provider) : clé placée dans le Trousseau."
        } else {
            message = "\(key.provider) : le Trousseau a refusé l'écriture."
        }
    }

    private var keycard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    Text("Clés présentes sur ce Mac").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("Trousseau macOS — jamais affichées")
                        .font(Theme.micro()).foregroundStyle(Theme.textTertiary)
                }
                Text("Lecture de ~/.hermes/.env. Aucune valeur n'est affichée, journalisée ni écrite dans la base : "
                     + "l'import copie la clé directement dans le Trousseau du système.")
                    .font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(keys) { key in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(stored.contains(key.envVar) ? Theme.ok : (key.present ? Theme.accent : Theme.textTertiary))
                            .frame(width: 6, height: 6)
                        Text(key.provider).font(Theme.body(12)).foregroundStyle(Theme.textPrimary).frame(width: 120, alignment: .leading)
                        Text(key.kind).font(Theme.micro()).foregroundStyle(Theme.textTertiary).frame(width: 54, alignment: .leading)
                        Text(key.present ? key.masked : "absente")
                            .font(Theme.micro()).monospaced()
                            .foregroundStyle(key.present ? Theme.textSecondary : Theme.textTertiary)
                        Spacer()
                        if stored.contains(key.envVar) {
                            Label("dans le Trousseau", systemImage: "checkmark.seal.fill")
                                .font(Theme.micro()).foregroundStyle(Theme.ok)
                        } else if key.present {
                            Button("Importer") { importKey(key) }
                                .buttonStyle(.plain)
                                .font(Theme.caption(10.5)).foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Theme.field).clipShape(Capsule())
                        } else {
                            Text("—").font(Theme.micro()).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    Rectangle().fill(Theme.borderSoft).frame(height: 1)
                }
                if !message.isEmpty {
                    Text(message).font(Theme.caption(10.5)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

struct ProviderCard: View {
    let provider: Provider

    private var dotColor: Color {
        switch provider.availability {
        case .available: return Theme.ok
        case .degraded: return Theme.warn
        case .unavailable: return Theme.error
        case .unknown: return Theme.textTertiary
        }
    }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                    Text(provider.name).font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    ReliabilityBadge(reliability: provider.balance.reliability)
                }
                Text(provider.active_model ?? "Aucun modèle actif")
                    .font(Theme.caption(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SOLDE API").font(Theme.micro()).tracking(0.6).foregroundStyle(Theme.textTertiary)
                        Text(provider.balance.display)
                            .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(provider.balance.reliability == .unavailable ? Theme.textTertiary : Theme.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("COÛT DU JOUR").font(Theme.micro()).tracking(0.6).foregroundStyle(Theme.textTertiary)
                        HStack(spacing: 5) {
                            Text(provider.cost_today.display)
                                .font(Theme.body(13, weight: .medium)).monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            ReliabilityBadge(reliability: provider.cost_today.reliability)
                        }
                    }
                }
                if provider.balance.reliability == .unavailable {
                    Text(provider.note ?? "Solde non disponible via API")
                        .font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                }
                if provider.balance_alert_pct > 0 {
                    HStack(spacing: 6) {
                        Text("Seuil d'alerte \(provider.balance_alert_pct) %")
                            .font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text("Gérer").font(Theme.caption(10.5)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.field).clipShape(Capsule())
                    }
                }
            }
        }
    }
}
