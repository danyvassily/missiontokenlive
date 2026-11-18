import SwiftUI

/// Écran principal — « Maintenant ». Reproduit la page 02 de la maquette FigCraft.
struct NowView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Centre de contrôle",
                subtitle: "mise à jour \(store.lastRefresh.map { Self.time.string(from: $0) } ?? "—") · données locales"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kpiRow
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            if let hermes = store.orchestrator {
                                HermesCard(agent: hermes)
                            }
                            HStack(spacing: 16) {
                                ForEach(store.subAgents.prefix(3)) { agent in
                                    AgentCard(agent: agent)
                                }
                            }
                        }
                        VStack(spacing: 16) {
                            TimelineCard()
                            AlertsCard()
                        }
                        .frame(width: 420)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var kpiRow: some View {
        HStack(spacing: 16) {
            ForEach(store.snapshot.kpis.prefix(4)) { kpi in
                KpiCard(kpi: kpi)
            }
        }
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.caption(11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                if let trailing { trailing }
                HStack(spacing: 6) {
                    Circle().fill(Theme.ok).frame(width: 6, height: 6)
                    Text("Local")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.borderSoft))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }
}

/// Carte vedette d'Hermès : priorité visuelle de l'écran.
struct HermesCard: View {
    let agent: Agent
    @EnvironmentObject private var store: AppStore

    private var task: TaskItem? { store.task(for: agent) }

    var body: some View {
        Card(padding: 18, radius: Theme.radiusFeature, highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.16)).frame(width: 44, height: 44)
                        Circle().stroke(Theme.accent.opacity(0.5), lineWidth: 1).frame(width: 44, height: 44)
                        Text("H").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(agent.name).font(Theme.section(16)).foregroundStyle(Theme.textPrimary)
                            Text("Chef d'orchestre")
                                .font(Theme.micro())
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.field)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Text("Orchestrateur · \(store.subAgents.count) sous-agents")
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    StatusPill(text: agent.status.labelFR, tint: agent.status.tint, filled: true)
                }

                if let task {
                    Text(task.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        metric("Durée", durationText(Date().timeIntervalSince(task.started_at)))
                        divider
                        metric("Tokens", tokensText(task.tokens.total))
                        divider
                        metric("Coût", task.cost.display, badge: task.cost.reliability)
                    }
                    HStack(spacing: 10) {
                        Text(task.provider ?? "—").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.field).clipShape(Capsule())
                        Text(task.model ?? "—").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if task.status == .running { PulseDot() }
                    }
                } else {
                    Text("Aucune tâche en cours").font(Theme.body()).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 28).padding(.horizontal, 16)
    }

    private func metric(_ label: String, _ value: String, badge: Reliability? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(Theme.micro()).tracking(0.6).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                Text(value).font(.system(size: 15, weight: .medium)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                if let badge { ReliabilityBadge(reliability: badge) }
            }
        }
    }
}

struct AgentCard: View {
    let agent: Agent
    @EnvironmentObject private var store: AppStore
    private var task: TaskItem? { store.task(for: agent) }

    private var tint: Color {
        switch agent.color_key {
        case "signal/ok": return Theme.ok
        case "signal/warn": return Theme.warn
        case "signal/error": return Theme.error
        case "accent/violet": return Theme.violet
        default: return Theme.accent
        }
    }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(tint.opacity(0.14)).frame(width: 30, height: 30)
                        Text(String(agent.name.prefix(1))).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent.name).font(Theme.body(12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        Text(agent.model ?? "—").font(Theme.caption(10)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Circle().fill(agent.status.tint).frame(width: 6, height: 6)
                }
                Text(task?.title ?? "Aucune tâche enregistrée")
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(minHeight: 28, alignment: .topLeading)
                HStack {
                    Text(task?.cost.display ?? "—")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if let t = task { ReliabilityBadge(reliability: t.cost.reliability) }
                    Spacer()
                    Text(task.map { durationText(Date().timeIntervalSince($0.started_at)) } ?? "—")
                        .font(Theme.caption(10.5)).monospacedDigit().foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

struct TimelineCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Activité en direct").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(store.snapshot.timeline.count) événements").font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                }
                ForEach(store.snapshot.timeline.prefix(7)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(eventColor(event.kind))
                                .frame(width: 7, height: 7)
                                .padding(.top, 4)
                            Rectangle().fill(Theme.borderSoft).frame(width: 1).frame(maxHeight: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.message)
                                .font(Theme.body(11.5))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(event.agent_name).font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                                Text("·").foregroundStyle(Theme.textTertiary)
                                Text(NowView.time.string(from: event.at)).font(Theme.caption(10)).monospacedDigit().foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer(minLength: 4)
                        if event.tokens.total > 0,
                           let amount = event.cost.amount,
                           event.cost.reliability != .unavailable {
                            Text(CostValue.formatFR(amount)).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func eventColor(_ kind: EventKind) -> Color {
        switch kind {
        case .taskFailed: return Theme.error
        case .balanceWarning: return Theme.warn
        case .taskCompleted: return Theme.ok
        case .taskStarted, .taskProgress: return Theme.accent
        default: return Theme.textTertiary
        }
    }
}

struct AlertsCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Alertes").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                ForEach(store.snapshot.alerts) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(alert.level.tint).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title).font(Theme.body(12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Text(alert.detail).font(Theme.caption(10.5)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 4)
                        if let action = alert.action_label {
                            Text(action)
                                .font(Theme.caption(10.5))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.field)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(9)
                    .background(Theme.raised.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}
