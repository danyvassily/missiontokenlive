
import SwiftUI

/// Écran « Cerveau » : le corpus gbrain vu depuis l'application.
///
/// L'application ne parle jamais à l'API gbrain : elle lit la base en lecture seule,
/// via le moteur Rust. Aucune écriture, aucun appel réseau.
struct BrainView: View {
    @EnvironmentObject private var store: AppStore

    private var brain: BrainStats { store.brain }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if brain.available {
                    counters
                    coverageCard
                    HStack(alignment: .top, spacing: 16) {
                        entitiesCard.frame(maxWidth: 380)
                        recentCard
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cerveau")
                    .font(Theme.title())
                    .foregroundStyle(Theme.textPrimary)
                Text("Mémoire partagée entre Hermès, OpenCode, Antigravity et le moteur local")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            StatusPill(text: brain.available ? "synchronisé \(brain.freshness)" : "absent",
                       tint: brain.available ? Theme.ok : Theme.warn, filled: true)
        }
    }

    private var counters: some View {
        HStack(spacing: 14) {
            counter("Faits", "\(brain.facts)", "phrases atomiques", Theme.accent)
            counter("Chunks", "\(brain.chunks)", "paragraphes de contexte", Theme.violet)
            counter("Sources", "\(brain.sourceCount)", "fichiers de notes", Theme.ok)
            counter("Entités", "\(brain.entities)", "personnes et projets", Theme.warn)
        }
    }

    private func counter(_ label: String, _ value: String, _ detail: String, _ tint: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(Theme.micro())
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.caption(10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .overlay(alignment: .topTrailing) {
                Circle().fill(tint.opacity(0.75)).frame(width: 6, height: 6).padding(2)
            }
        }
    }

    private var entitiesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Entités les plus citées")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if brain.top_entities.isEmpty {
                    Text("Aucune entité détectée")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    let maxFacts = max(1, brain.top_entities.map(\.facts).max() ?? 1)
                    ForEach(brain.top_entities) { entity in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entity.name)
                                    .font(Theme.caption(11.5))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(entity.facts)")
                                    .font(Theme.micro())
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.raised)
                                    Capsule()
                                        .fill(Theme.accent.opacity(0.65))
                                        .frame(width: max(3, geo.size.width * CGFloat(entity.facts) / CGFloat(maxFacts)))
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
        }
    }

    private var recentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Derniers faits enregistrés")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(brain.path)
                        .font(Theme.micro())
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(brain.recent) { fact in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(fact.kindLabel)
                                .font(Theme.micro())
                                .foregroundStyle(tint(for: fact.kind))
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(tint(for: fact.kind).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            if let entity = fact.entity {
                                Text(entity)
                                    .font(Theme.micro())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            if let source = fact.source {
                                Text(source)
                                    .font(Theme.micro())
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Text(fact.text)
                            .font(Theme.caption(11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 5)
                    if fact.id != brain.recent.last?.id {
                        Divider().overlay(Theme.borderSoft)
                    }
                }
            }
        }
    }

    /// Ce que gbrain voit — et ce qu'il ne voit jamais. La transparence fait partie du produit.
    private var coverageCard: some View {
        let sources = brain.sourceList ?? []
        let never = brain.never ?? []
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Accès et couverture")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(sources.filter(\.present).count) / \(sources.count) sources lisibles")
                        .font(Theme.micro())
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LU")
                            .font(Theme.micro())
                            .foregroundStyle(Theme.ok.opacity(0.85))
                        ForEach(sources) { source in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(source.present ? Theme.ok : Theme.warn)
                                    .frame(width: 5, height: 5)
                                Text(source.path)
                                    .font(Theme.micro())
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(source.facts)")
                                    .font(Theme.micro())
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("JAMAIS LU")
                            .font(Theme.micro())
                            .foregroundStyle(Theme.warn.opacity(0.9))
                        ForEach(never, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("—")
                                    .font(Theme.micro())
                                    .foregroundStyle(Theme.textTertiary)
                                Text(item)
                                    .font(Theme.micro())
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aucun cerveau détecté")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Lance l'ingestion une fois pour construire le corpus :")
                    .font(Theme.caption(11.5))
                    .foregroundStyle(Theme.textSecondary)
                Text("~/gbrain/bin/gbrain ingest")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Chemin attendu : \(brain.path)")
                    .font(Theme.micro())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func tint(for kind: String) -> Color {
        switch kind {
        case "preference": return Theme.ok
        case "decision": return Theme.warn
        case "people": return Theme.violet
        case "admin": return Theme.accent
        case "project": return Theme.cyan
        default: return Theme.textSecondary
        }
    }
}
