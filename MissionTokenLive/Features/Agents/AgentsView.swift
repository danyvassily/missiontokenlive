import SwiftUI

/// Vue « Agents » : graphe radial lisible, Hermès au centre, 4 sous-agents autour.
struct AgentsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Agents",
                subtitle: "\(store.snapshot.agents.count) agents · \(store.activeAgents.count) actifs",
                trailing: AnyView(
                    Text("4 états · actif, attente, terminé, erreur")
                        .font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                )
            )
            HStack(alignment: .top, spacing: 16) {
                Card(padding: 0) {
                    GeometryReader { geo in
                        ZStack {
                            links(in: geo.size)
                            nodes(in: geo.size)
                        }
                    }
                    .frame(minHeight: 460)
                }
                VStack(spacing: 16) {
                    Card(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Outils externes").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
                            ForEach(store.snapshot.software.filter { $0.app != "hermes" }) { app in
                                HStack(spacing: 8) {
                                    Circle().fill(app.state == .closed ? Theme.textTertiary : Theme.accent)
                                        .frame(width: 6, height: 6)
                                    Text(app.display_name).font(Theme.body(12)).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(app.presence_only ? "présence" : app.state.labelFR)
                                        .font(Theme.caption(10))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            Divider().overlay(Theme.borderSoft)
                            Text("Les liens gris indiquent une détection par présence : aucune donnée d'usage n'est lue.")
                                .font(Theme.caption(9.5))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Card(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Légende").font(Theme.micro()).tracking(0.8).foregroundStyle(Theme.textTertiary)
                            legendRow("Actif", Theme.accent)
                            legendRow("En attente", Theme.warn)
                            legendRow("Terminé", Theme.ok)
                            legendRow("Erreur", Theme.error)
                        }
                    }
                }
                .frame(width: 300)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func legendRow(_ text: String, _ tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text).font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var center: CGPoint { CGPoint(x: 0, y: 0) }

    private func positions(in size: CGSize) -> [String: CGPoint] {
        let c = CGPoint(x: size.width * 0.42, y: size.height * 0.5)
        var out: [String: CGPoint] = [:]
        let subs = store.subAgents
        let radius = min(size.width, size.height) * 0.33
        for (i, agent) in subs.enumerated() {
            let angle = (Double(i) / Double(max(subs.count, 1))) * 2 * .pi - .pi / 2
            out[agent.id] = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
        }
        return out
    }

    private func links(in size: CGSize) -> some View {
        let pos = positions(in: size)
        let c = CGPoint(x: size.width * 0.42, y: size.height * 0.5)
        return Canvas { ctx, _ in
            for agent in store.subAgents {
                guard let p = pos[agent.id] else { continue }
                var path = Path()
                path.move(to: c)
                let mid = CGPoint(x: (c.x + p.x) / 2, y: (c.y + p.y) / 2)
                path.addQuadCurve(to: p, control: CGPoint(x: mid.x, y: mid.y))
                ctx.stroke(path, with: .color(agent.status.tint.opacity(0.35)), lineWidth: 1.4)
            }
        }
    }

    private func nodes(in size: CGSize) -> some View {
        let pos = positions(in: size)
        let c = CGPoint(x: size.width * 0.42, y: size.height * 0.5)
        return ZStack {
            if let hermes = store.orchestrator {
                AgentNode(agent: hermes, size: 132, isHovered: hovered == hermes.id)
                    .position(c)
                    .onHover { hovered = $0 ? hermes.id : nil }
            }
            ForEach(store.subAgents) { agent in
                if let p = pos[agent.id] {
                    AgentNode(agent: agent, size: 76, isHovered: hovered == agent.id)
                        .position(p)
                        .onHover { hovered = $0 ? agent.id : nil }
                }
            }
        }
    }
}

struct AgentNode: View {
    let agent: Agent
    var size: CGFloat
    var isHovered: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Theme.surface).frame(width: size, height: size)
                Circle().stroke(agent.status.tint.opacity(isHovered ? 0.9 : 0.5), lineWidth: isHovered ? 2 : 1.4)
                    .frame(width: size, height: size)
                if isHovered {
                    Circle().fill(agent.status.tint.opacity(0.12)).frame(width: size, height: size)
                }
                if agent.kind == .orchestrator {
                    VStack(spacing: 1) {
                        Text(agent.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Orchestrateur").font(Theme.caption(9.5)).foregroundStyle(Theme.textTertiary)
                    }
                } else {
                    Text(String(agent.name.prefix(1)))
                        .font(.system(size: size > 90 ? 20 : 15, weight: .semibold))
                        .foregroundStyle(agent.status.tint)
                }
            }
            if agent.kind != .orchestrator {
                Text(agent.name).font(Theme.caption(10.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Circle().fill(agent.status.tint).frame(width: 5, height: 5)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
