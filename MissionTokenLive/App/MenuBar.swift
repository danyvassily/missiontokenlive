import SwiftUI

/// Pilule de barre de menus — équivalent macOS de la Dynamic Island de la maquette.
///
/// Quatre états : calme, actif, multi-tâches, alerte. Le contenu vient exclusivement
/// du moteur ; les montants absents restent absents.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: AppStore

    private var alerting: Bool {
        store.snapshot.alerts.contains { $0.level != .info && !$0.acknowledged }
    }

    private var text: String {
        if alerting, let alert = store.snapshot.alerts.first(where: { $0.level == .warning }) {
            // La barre de menus est étroite : on garde l'essentiel, le détail est au survol.
            return alert.title.replacingOccurrences(of: ": ", with: " : ")
        }
        let running = store.snapshot.tasks.filter { $0.status == .running }
        if running.count > 1, let first = running.first {
            return "\(first.agent_name ?? "Hermès") + \(running.count - 1) agents actifs"
        }
        if let task = running.first, let agent = task.agent_name {
            return "\(agent) · \(task.title)"
        }
        let cost = store.costTodayKpi?.value ?? "—"
        return "\(store.activeAgents.count) agents actifs · \(cost) aujourd'hui"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(alerting ? Theme.warn : (store.activeAgents.isEmpty ? Theme.textTertiary : Theme.accent))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .accessibilityLabel("MissionTokenLive : \(text)")
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MissionTokenLive").font(Theme.section(13)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(store.costTodayKpi?.value ?? "—").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                ReliabilityBadge(reliability: store.costTodayKpi?.reliability ?? .unavailable)
            }
            if let task = store.snapshot.tasks.first(where: { $0.status == .running }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(Theme.body(12, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    HStack(spacing: 8) {
                        Text(task.agent_name ?? "—").font(Theme.caption(10)).foregroundStyle(Theme.textSecondary)
                        Text(task.model ?? "—").font(Theme.caption(10)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                        Spacer()
                        Text("\(tokensText(task.tokens.total)) tok").font(Theme.caption(10)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        Text(task.cost.display).font(Theme.caption(10)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(10)
                .background(Theme.raised)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let budget = store.budgetKpi {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Budget restant").font(Theme.caption(10.5)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(budget.value).font(Theme.caption(10.5)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    }
                    ProgressBar(value: budget.progress ?? 0, tint: (budget.progress ?? 1) < 0.2 ? Theme.warn : Theme.ok)
                }
            }
            ForEach(store.snapshot.alerts.prefix(2)) { alert in
                HStack(spacing: 6) {
                    Circle().fill(alert.level.tint).frame(width: 5, height: 5)
                    Text(alert.title).font(Theme.caption(10.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Divider().overlay(Theme.borderSoft)
            Button {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Text("Ouvrir le Centre de contrôle")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.accentDeep.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.bg)
    }
}
