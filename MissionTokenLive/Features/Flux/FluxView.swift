
import SwiftUI

/// Écran « Flux » : la carte animée du travail en cours.
///
/// Chaque pulsation représente une session qui travaille ; elle part d'Hermès, traverse
/// le logiciel concerné et arrive chez le provider. Aucune donnée n'est inventée : les
/// nœuds viennent du snapshot, les pulsations de l'état `running`.
struct FluxView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                GeometryReader { geo in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let map = FlowMap(size: geo.size, snapshot: store.snapshot, activeAgents: store.activeAgents)
                    Canvas { context, _ in
                        map.draw(in: &context, time: t)
                    }
                    .background(
                        LinearGradient(colors: [Theme.bg, Theme.surface.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            footer
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Flux")
                    .font(Theme.title())
                    .foregroundStyle(Theme.textPrimary)
                Text("Travail en direct : Hermès → logiciels → providers")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            StatusPill(text: "\(store.activeAgents.count) agents actifs",
                       tint: store.activeAgents.isEmpty ? Theme.textTertiary : Theme.ok,
                       filled: !store.activeAgents.isEmpty)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            legend(Theme.ok, "session en cours")
            legend(Theme.accent, "provider actif")
            legend(Theme.warn, "alerte")
            Spacer()
            Text("les pulsations suivent l'état réel des sessions")
                .font(Theme.micro())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(Theme.micro()).foregroundStyle(Theme.textTertiary)
        }
    }
}

/// Géométrie et rendu du graphe animé, isolés pour rester testables et lisibles.
private struct FlowMap {
    struct Node {
        let label: String
        let detail: String
        let point: CGPoint
        let tint: Color
        let running: Bool
        let isHub: Bool
    }

    let size: CGSize
    let snapshot: Snapshot
    let activeAgents: [Agent]

    private var hub: CGPoint { CGPoint(x: size.width * 0.26, y: size.height * 0.52) }

    private var providers: [Node] {
        let list = snapshot.providers.isEmpty
            ? [("Provider", "aucun observé", Theme.textTertiary)] as [(String, String, Color)]
            : snapshot.providers.prefix(4).map { p in
                (p.name, p.balance.reliability == .unavailable ? "solde non disponible" : p.balance.display,
                 p.availability == .available ? Theme.accent : Theme.warn)
            }
        let step = size.height * 0.62 / CGFloat(max(1, list.count))
        return list.enumerated().map { idx, item in
            Node(label: item.0,
                 detail: item.1,
                 point: CGPoint(x: size.width * 0.80, y: size.height * 0.20 + step * CGFloat(idx) + step / 2),
                 tint: item.2, running: true, isHub: false)
        }
    }

    private var agents: [Node] {
        let list = activeAgents.isEmpty ? Array(snapshot.agents.prefix(3)) : Array(activeAgents.prefix(5))
        let count = max(1, list.count)
        // Colonne verticale entre Hermès et les providers : lisible même à cinq agents,
        // et les liens ne se croisent jamais.
        let columnX = size.width * 0.52
        let top = size.height * 0.24
        let bottom = size.height * 0.82
        let step = count > 1 ? (bottom - top) / CGFloat(count - 1) : 0
        return list.enumerated().map { idx, agent in
            let y = count == 1 ? (top + bottom) / 2 : top + step * CGFloat(idx)
            let running = agent.status == .active
            return Node(label: agent.name,
                        detail: running ? "en cours" : agent.status.labelFR,
                        point: CGPoint(x: columnX, y: y),
                        tint: running ? Theme.ok : (agent.status == .error ? Theme.warn : Theme.textTertiary),
                        running: running, isHub: false)
        }
    }

    func draw(in context: inout GraphicsContext, time: TimeInterval) {
        let agentsNodes = agents
        let providerNodes = providers

        // Liens Hermès → agents
        for node in agentsNodes {
            stroke(&context, from: hub, to: node.point, color: Theme.border, width: 1.2)
            if node.running {
                pulse(&context, from: hub, to: node.point, time: time, phase: 0.0,
                      color: Theme.ok, speed: 1.6)
            }
        }
        // Liens agents → providers (un par agent actif, distribué)
        for (i, node) in agentsNodes.enumerated() where node.running {
            guard let target = providerNodes.isEmpty ? nil : providerNodes[i % providerNodes.count] else { continue }
            stroke(&context, from: node.point, to: target.point, color: Theme.borderSoft, width: 1.0)
            pulse(&context, from: node.point, to: target.point, time: time,
                  phase: Double(i) * 0.33, color: Theme.accent, speed: 1.1)
        }

        // Providers : halo doux quand actifs
        for (i, node) in providerNodes.enumerated() {
            let breath = 0.5 + 0.5 * sin(time * 1.4 + Double(i))
            context.fill(Path(ellipseIn: CGRect(x: node.point.x - 26, y: node.point.y - 26, width: 52, height: 52)),
                         with: .color(node.tint.opacity(0.05 + 0.05 * breath)))
            circle(&context, at: node.point, radius: 7, fill: node.tint, ring: true)
            label(&context, node.label, at: CGPoint(x: node.point.x + 14, y: node.point.y - 4),
                  font: .system(size: 11.5, weight: .medium), color: Theme.textPrimary)
            label(&context, node.detail, at: CGPoint(x: node.point.x + 14, y: node.point.y + 9),
                  font: .system(size: 9.5), color: Theme.textTertiary)
        }

        // Agents
        for node in agentsNodes {
            circle(&context, at: node.point, radius: 5.5, fill: node.tint, ring: false)
            label(&context, node.label, at: CGPoint(x: node.point.x, y: node.point.y - 16),
                  font: .system(size: 11, weight: .medium), color: Theme.textSecondary, centered: true)
        }

        // Hermès : nœud central qui respire
        let breath = sin(time * 1.8) * 2.0
        for ring in 0..<3 {
            let r = 46 + Double(ring) * 12 + breath
            context.stroke(Path(ellipseIn: CGRect(x: hub.x - r, y: hub.y - r, width: r * 2, height: r * 2)),
                           with: .color(Theme.accent.opacity(0.10 - Double(ring) * 0.028)), lineWidth: 1)
        }
        context.fill(Path(ellipseIn: CGRect(x: hub.x - 30, y: hub.y - 30, width: 60, height: 60)),
                     with: .radialGradient(Gradient(colors: [Theme.accent.opacity(0.35), .clear]),
                                           center: hub, startRadius: 6, endRadius: 34))
        circle(&context, at: hub, radius: 15, fill: Theme.accent, ring: true)
        label(&context, "Hermès", at: CGPoint(x: hub.x, y: hub.y + 26),
              font: .system(size: 12, weight: .semibold), color: Theme.textPrimary, centered: true)
        let running = snapshot.tasks.filter { $0.status == .running }.count
        label(&context, running == 0 ? "au repos" : "\(running) en cours",
              at: CGPoint(x: hub.x, y: hub.y + 40), font: .system(size: 9.5),
              color: running == 0 ? Theme.textTertiary : Theme.ok, centered: true)
    }

    private func stroke(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                        color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: a)
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        path.addQuadCurve(to: b, control: CGPoint(x: mid.x, y: mid.y - abs(b.x - a.x) * 0.06))
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    /// Petit point qui parcourt le lien : la seule animation, mais elle dit « ça travaille ».
    private func pulse(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                       time: TimeInterval, phase: Double, color: Color, speed: Double) {
        let progress = ((time * speed + phase).truncatingRemainder(dividingBy: 1.0))
        let e = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        let x = a.x + (b.x - a.x) * e
        let y = a.y + (b.y - a.y) * e - sin(e * .pi) * abs(b.x - a.x) * 0.06
        let alpha = sin(progress * .pi)
        context.fill(Path(ellipseIn: CGRect(x: x - 7, y: y - 7, width: 14, height: 14)),
                     with: .color(color.opacity(0.16 * alpha)))
        context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                     with: .color(color.opacity(0.9 * alpha)))
        context.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6)),
                     with: .color(.white.opacity(alpha)))
    }

    private func circle(_ context: inout GraphicsContext, at p: CGPoint, radius: CGFloat,
                        fill: Color, ring: Bool) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .color(fill))
        if ring {
            context.stroke(Path(ellipseIn: CGRect(x: p.x - radius - 4, y: p.y - radius - 4,
                                                  width: (radius + 4) * 2, height: (radius + 4) * 2)),
                           with: .color(fill.opacity(0.25)), lineWidth: 1)
        }
    }

    private func label(_ context: inout GraphicsContext, _ text: String, at point: CGPoint,
                       font: Font, color: Color, centered: Bool = false) {
        let resolved = context.resolve(Text(text).font(font).foregroundStyle(color))
        let measured = resolved.measure(in: CGSize(width: 220, height: 40))
        let origin = centered
            ? CGPoint(x: point.x - measured.width / 2, y: point.y - measured.height / 2)
            : point
        context.draw(resolved, at: origin, anchor: .topLeading)
    }
}
