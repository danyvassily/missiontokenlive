import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject private var store: AppStore

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
