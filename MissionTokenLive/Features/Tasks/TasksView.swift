import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected: TaskItem?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Tâches",
                subtitle: "\(store.filteredTasks.count) tâches · période : \(store.periodFilter.label.lowercased())"
            )
            HStack(spacing: 8) {
                ForEach(TaskPeriod.allCases) { period in
                    FilterChip(label: period.label, active: store.periodFilter == period) {
                        store.periodFilter = period
                    }
                }
                Rectangle().fill(Theme.border).frame(width: 1, height: 16)
                FilterChip(label: "Toutes", active: store.statusFilter == nil) { store.statusFilter = nil }
                FilterChip(label: "En cours", active: store.statusFilter == .running) { store.statusFilter = .running }
                FilterChip(label: "Terminées", active: store.statusFilter == .completed) { store.statusFilter = .completed }
                FilterChip(label: "Erreurs", active: store.statusFilter == .failed) { store.statusFilter = .failed }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    TextField("Rechercher une tâche", text: $store.searchText)
                        .textFieldStyle(.plain)
                        .font(Theme.body(12))
                        .frame(width: 200)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Card(padding: 0) {
                VStack(spacing: 0) {
                    TaskTableHeader()
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(store.filteredTasks) { task in
                                TaskRow(task: task, isSelected: selected?.id == task.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = task }
                                Rectangle().fill(Theme.borderSoft).frame(height: 1)
                            }
                            if store.filteredTasks.isEmpty {
                                EmptyStateView(title: "Aucune tâche",
                                               message: "Aucune tâche sur cette période avec ce filtre.")
                                    .padding(.vertical, 40)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            HStack(spacing: 14) {
                Text("\(store.filteredTasks.count) tâches").font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                Text("·").foregroundStyle(Theme.textTertiary)
                Text("\(tokensText(store.filteredTasks.reduce(0) { $0 + $1.tokens.total })) tokens")
                    .font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("Coûts étiquetés par source")
                    .font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 12)
        }
        .sheet(item: $selected) { task in
            TaskDetailView(task: task)
        }
    }
}

struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.caption(11.5))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? Theme.raised : Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Theme.border : Theme.borderSoft))
        }
        .buttonStyle(.plain)
    }
}

struct TaskTableHeader: View {
    private let widths: [CGFloat] = [0.30, 0.12, 0.12, 0.18, 0.08, 0.11, 0.09]

    var body: some View {
        HStack(spacing: 8) {
            cell("Tâche", widthRatio: widths[0])
            cell("Projet", widthRatio: widths[1])
            cell("Agent", widthRatio: widths[2])
            cell("Provider · Modèle", widthRatio: widths[3])
            cell("Durée", widthRatio: widths[4], align: .trailing)
            cell("Tokens entrée/sortie", widthRatio: widths[5], align: .trailing)
            cell("Coût", widthRatio: widths[6], align: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.raised.opacity(0.5))
    }

    private func cell(_ text: String, widthRatio: CGFloat, align: Alignment = .leading) -> some View {
        Text(text.uppercased())
            .font(Theme.micro()).tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: align)
            .layoutPriority(Double(widthRatio))
    }
}

struct TaskRow: View {
    let task: TaskItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(task.status.tint).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).font(Theme.body(12)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(task.status.labelFR).font(Theme.caption(9.5)).foregroundStyle(task.status.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.project_name ?? "—").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(task.agent_name ?? "—").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.provider ?? "—").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                Text(task.model ?? "—").font(Theme.caption(9.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(task.ended_at.map { durationText($0.timeIntervalSince(task.started_at)) } ?? "en cours")
                .font(Theme.caption(11)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(tokensText(task.tokens.input)) / \(tokensText(task.tokens.output))")
                .font(Theme.caption(11)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            HStack(spacing: 4) {
                Text(task.cost.display).font(Theme.caption(11.5)).monospacedDigit()
                    .foregroundStyle(task.cost.reliability == .unavailable ? Theme.textTertiary : Theme.textPrimary)
                ReliabilityBadge(reliability: task.cost.reliability)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.raised : .clear)
        .contentShape(Rectangle())
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(Theme.section(14)).foregroundStyle(Theme.textSecondary)
            Text(message).font(Theme.caption(11)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct TaskDetailView: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(Theme.section(16)).foregroundStyle(Theme.textPrimary)
                    Text("\(task.project_name ?? "Sans projet") · \(task.agent_name ?? "—")")
                        .font(Theme.caption(11)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                StatusPill(text: task.status.labelFR, tint: task.status.tint, filled: true)
                Button("Fermer") { dismiss() }.buttonStyle(.plain)
                    .font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
            }
            Divider().overlay(Theme.borderSoft)
            HStack(alignment: .top, spacing: 16) {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tokens").font(Theme.micro()).foregroundStyle(Theme.textTertiary)
                        tokenLine("Entrée", task.tokens.input)
                        tokenLine("Sortie", task.tokens.output)
                        if task.tokens.cache_read > 0 { tokenLine("Cache lu", task.tokens.cache_read) }
                        if task.tokens.reasoning > 0 { tokenLine("Raisonnement", task.tokens.reasoning) }
                    }
                }
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Coût").font(Theme.micro()).foregroundStyle(Theme.textTertiary)
                        HStack(spacing: 8) {
                            Text(task.cost.display).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            ReliabilityBadge(reliability: task.cost.reliability)
                        }
                        Text(task.cost.source).font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                        if let v = task.cost.pricing_version {
                            Text("barème \(v)").font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            if let error = task.error {
                Text(error).font(Theme.caption(11)).foregroundStyle(Theme.error)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.error.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 620, height: 360)
        .background(Theme.bg)
    }

    private func tokenLine(_ label: String, _ value: UInt64) -> some View {
        HStack {
            Text(label).font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(tokensText(value)).font(Theme.caption(11)).monospacedDigit().foregroundStyle(Theme.textPrimary)
        }
    }
}
