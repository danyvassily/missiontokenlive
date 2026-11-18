import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var monthlyBudget: String = "300"
    @State private var warnPct: Double = 80
    @State private var criticalPct: Double = 95

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Réglages", subtitle: "Budget, alertes, providers et confidentialité")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        Card(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Budget").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                                labeledField("Budget mensuel (USD)", text: $monthlyBudget)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Seuil d'alerte").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        Text("\(Int(warnPct)) %").font(Theme.caption(11)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                                    }
                                    Slider(value: $warnPct, in: 50...100).tint(Theme.accent)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Seuil critique").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        Text("\(Int(criticalPct)) %").font(Theme.caption(11)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                                    }
                                    Slider(value: $criticalPct, in: 70...100).tint(Theme.warn)
                                }
                            }
                        }
                        Card(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Confidentialité").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                                HStack(spacing: 7) {
                                    Circle().fill(Theme.ok).frame(width: 7, height: 7)
                                    Text("100 % local").font(Theme.body(12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                }
                                bullet("Aucune donnée envoyée à un service tiers")
                                bullet("Aucune clé API affichée — Trousseau macOS uniquement")
                                bullet("Journalisation locale sur 30 jours")
                                bullet("ChatGPT et Gemini : présence seulement")
                            }
                        }
                    }
                    Card(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Providers & clés").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                            ForEach(store.snapshot.providers.filter { $0.kind != .subscription }) { provider in
                                HStack(spacing: 10) {
                                    Text(provider.name).font(Theme.body(12)).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(provider.keychain_ref != nil ? "clé en Keychain" : "aucune clé requise")
                                        .font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                                    Text("sk-••••••••").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textTertiary)
                                }
                                .padding(.vertical, 5)
                                Rectangle().fill(Theme.borderSoft).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Theme.body(12))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusField))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.border))
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Theme.textTertiary).frame(width: 4, height: 4).padding(.top, 5)
            Text(text).font(Theme.caption(10.5)).foregroundStyle(Theme.textSecondary)
        }
    }
}
