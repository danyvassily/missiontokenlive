import SwiftUI
import Charts

/// Vue « Coûts & usage ».
struct CostsView: View {
    @EnvironmentObject private var store: AppStore

    private struct DayPoint: Identifiable {
        let id = UUID()
        let day: Date
        let amount: Double
        let reliability: Reliability
    }

    private var dailyPoints: [DayPoint] {
        let cal = Calendar.current
        var buckets: [Date: (Double, Reliability)] = [:]
        for task in store.snapshot.tasks {
            guard let amount = task.cost.amount, task.cost.reliability != .unavailable else { continue }
            let day = cal.startOfDay(for: task.started_at)
            let prev = buckets[day] ?? (0, task.cost.reliability)
            buckets[day] = (prev.0 + amount, task.cost.reliability)
        }
        return buckets
            .map { DayPoint(day: $0.key, amount: $0.value.0, reliability: $0.value.1) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Coûts & usage",
                subtitle: "Chaque montant porte sa source : Réel, Calculé, Estimé ou Non disponible"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        ForEach(store.snapshot.kpis.prefix(4)) { KpiCard(kpi: $0) }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Card(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Évolution quotidienne").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    ReliabilityBadge(reliability: dailyPoints.last?.reliability ?? .unavailable)
                                }
                                if dailyPoints.isEmpty {
                                    EmptyStateView(title: "Aucune donnée de coût", message: "Aucun montant exploitable sur la période.")
                                        .frame(height: 200)
                                } else {
                                    Chart(dailyPoints) { point in
                                        BarMark(
                                            x: .value("Jour", point.day, unit: .day),
                                            y: .value("Coût", point.amount)
                                        )
                                        .foregroundStyle(Theme.accentGradient)
                                        .cornerRadius(3)
                                    }
                                    .chartYAxis {
                                        AxisMarks(position: .leading) { _ in
                                            AxisGridLine().foregroundStyle(Theme.borderSoft)
                                            AxisValueLabel().foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                    .chartXAxis {
                                        AxisMarks { _ in
                                            AxisValueLabel(format: .dateTime.day().month(), centered: true)
                                                .foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                    .frame(height: 210)
                                }
                                Text("Coûts calculés à partir des tokens mesurés et d'un barème documenté ; jamais de montant inventé.")
                                    .font(Theme.caption(9.5)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Card(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Par agent").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                                let rows = store.costByAgent
                                if rows.isEmpty {
                                    Text("Aucun coût attribuable").font(Theme.caption(11)).foregroundStyle(Theme.textTertiary)
                                } else {
                                    ForEach(rows, id: \.name) { row in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(row.name).font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                                                Spacer()
                                                Text(CostValue.formatFR(row.amount))
                                                    .font(Theme.caption(11)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                                                ReliabilityBadge(reliability: row.reliability)
                                            }
                                            ProgressBar(value: row.amount / max(rows.first?.amount ?? 1, 0.01),
                                                        tint: Theme.accent, height: 3)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 340)
                    }
                    ReliabilityLegend()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

struct ReliabilityLegend: View {
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lisibilité des données").font(Theme.micro()).tracking(0.8).foregroundStyle(Theme.textTertiary)
                HStack(spacing: 10) {
                    legend(.real, "mesuré par l'API")
                    legend(.calculated, "tokens × tarif documenté")
                    legend(.estimated, "moyenne observée")
                    legend(.unavailable, "aucune API")
                }
            }
        }
    }

    private func legend(_ r: Reliability, _ detail: String) -> some View {
        HStack(spacing: 6) {
            ReliabilityBadge(reliability: r)
            Text(detail).font(Theme.caption(10)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Theme.raised.opacity(0.6))
        .clipShape(Capsule())
    }
}
