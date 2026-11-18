import SwiftUI

/// Arborescence de travail en 3D.
///
/// Projection perspective maison : chaque nœud vit dans un espace (x, y, z), subit une rotation
/// lente autour de l'axe vertical, puis est projeté sur l'écran avec un facteur `f / (f + z)`.
/// Les nœuds sont triés par profondeur avant dessin (algorithme du peintre), ce qui suffit ici
/// car les formes sont petites et espacées. Aucune donnée n'est inventée : tout vient de `WorkTree`.
struct WorkTree3DView: View {
    let tree: WorkTree

    @State private var yaw: Double = 0
    @State private var dragging: Double = 0
    @State private var showLegend = true

    /// Géométrie figée une seule fois : le graphe ne change pas pendant l'animation.
    private var layout: Graph3D { Graph3D(tree: tree) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let angle = yaw + dragging + t * 0.075
                    layout.draw(in: &context, size: size, angle: angle, time: t)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in dragging = Double(value.translation.width) / 260.0 }
                    .onEnded { _ in
                        yaw += dragging
                        dragging = 0
                    }
            )

            hud
        }
        .background(Theme.bg)
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Arborescence de travail")
                        .font(Theme.title())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Hermès · sessions · délégations · harnais")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 18) {
                    metric("\(tree.activeSessions)", "sessions actives", Theme.ok)
                    metric("\(tree.runningTasks)", "tâches en cours", Theme.accent)
                    metric("\(tree.branches.count)", "branches", Theme.textSecondary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.6)) { yaw = 0; dragging = 0 }
                } label: {
                    Label("Recentrer", systemImage: "arrow.counterclockwise")
                        .font(Theme.caption(10.5))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.field).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if tree.harnesses.contains(where: { $0.active }) {
                HStack(spacing: 8) {
                    ForEach(tree.harnesses.filter { $0.active }) { harness in
                        HStack(spacing: 5) {
                            Circle().fill(Theme.ok).frame(width: 5, height: 5)
                            Text(harness.name)
                                .font(Theme.micro())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.surface.opacity(0.7))
                        .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            if showLegend {
                legend
            }
        }
        .padding(22)
    }

    private func metric(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(Theme.micro())
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(Theme.ok, "session active")
            legendItem(Theme.accent, "outil utilisé")
            legendItem(Theme.textTertiary, "délégation")
            Spacer()
            Text("glisser pour tourner")
                .font(Theme.micro())
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(Theme.micro()).foregroundStyle(Theme.textTertiary)
        }
    }
}

/// Graphe précalculé : positions 3D et liens, indépendants du temps.
private struct Graph3D {
    struct Node {
        let id: String
        let label: String
        let detail: String
        let position: SIMD3<Double>
        let tint: Color
        let kind: Kind
        let active: Bool

        enum Kind { case root, branch, tool, delegation, harness }
    }

    struct Edge {
        let from: Int
        let to: Int
        let tint: Color
        let active: Bool
        let dashed: Bool
    }

    var nodes: [Node] = []
    var edges: [Edge] = []

    init(tree: WorkTree) {
        nodes.append(Node(id: "__root", label: tree.rootLabel, detail: "orchestrateur",
                          position: SIMD3<Double>(0, 0, 0), tint: Theme.accent, kind: .root,
                          active: tree.runningTasks > 0 || tree.activeSessions > 0))

        let branches = Array(tree.branches.prefix(7))
        let count = max(branches.count, 1)
        for (index, branch) in branches.enumerated() {
            let angle = (Double(index) / Double(count)) * 2 * .pi
            let radius = 1.35
            let tilt = 0.32
            let base = SIMD3<Double>(cos(angle) * radius,
                                     sin(angle) * radius * tilt,
                                     sin(angle) * radius * 0.92)
            let tint = branch.isActive ? Theme.ok : Theme.textTertiary
            nodes.append(Node(id: "b-\(branch.id)", label: branch.title, detail: branch.project,
                              position: base, tint: tint, kind: .branch, active: branch.isActive))
            let branchIndex = nodes.count - 1
            edges.append(Edge(from: 0, to: branchIndex, tint: tint, active: branch.isActive, dashed: false))

            for (toolIndex, tool) in branch.tools.prefix(3).enumerated() {
                let spread = (Double(toolIndex) - 1) * 0.34
                let outward = SIMD3<Double>(cos(angle + spread) * 0.72,
                                            0.10 + Double(toolIndex) * 0.06,
                                            sin(angle + spread) * 0.72)
                let pos = base + outward
                nodes.append(Node(id: "t-\(branch.id)-\(tool.name)",
                                  label: tool.name, detail: "\(tool.count)×",
                                  position: pos, tint: Theme.accent, kind: .tool,
                                  active: branch.isActive))
                edges.append(Edge(from: branchIndex, to: nodes.count - 1, tint: Theme.accent,
                                  active: branch.isActive, dashed: false))
            }

            for (delegIndex, delegation) in branch.delegations.prefix(2).enumerated() {
                let spread = (Double(delegIndex) - 0.5) * 0.5
                let pos = base + SIMD3<Double>(cos(angle + spread) * 0.55, -0.28,
                                               sin(angle + spread) * 0.55)
                nodes.append(Node(id: "d-\(delegation.id)", label: delegation.goal,
                                  detail: delegation.state,
                                  position: pos, tint: Theme.warn, kind: .delegation,
                                  active: delegation.state != "completed"))
                edges.append(Edge(from: branchIndex, to: nodes.count - 1, tint: Theme.warn,
                                  active: delegation.state != "completed", dashed: true))
            }
        }

        // Harnais externes : anneau vertical décalé, pour lire « qui travaille en dehors d'Hermès ».
        for (index, harness) in tree.harnesses.enumerated() {
            let angle = (Double(index) / Double(max(tree.harnesses.count, 1))) * 2 * .pi
            let pos = SIMD3<Double>(cos(angle) * 2.05, sin(angle) * 1.15, sin(angle) * 0.6)
            nodes.append(Node(id: "h-\(harness.name)", label: harness.name,
                              detail: harness.active ? "actif" : "inactif",
                              position: pos,
                              tint: harness.active ? Theme.ok : Theme.textTertiary,
                              kind: .harness, active: harness.active))
            edges.append(Edge(from: 0, to: nodes.count - 1,
                              tint: harness.active ? Theme.ok : Theme.border,
                              active: harness.active, dashed: true))
        }
    }

    func draw(in context: inout GraphicsContext, size: CGSize, angle: Double, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 18)
        let scale = min(size.width, size.height) * 0.30
        let focal = 3.4

        var projected: [(point: CGPoint, depth: Double, scale: Double, index: Int)] = []
        projected.reserveCapacity(nodes.count)

        for (index, node) in nodes.enumerated() {
            let rotated = rotate(node.position, yaw: angle, pitch: 0.18)
            let depth = rotated.z + 3.2
            guard depth > 0.2 else { continue }
            let k = focal / depth
            let point = CGPoint(x: center.x + rotated.x * scale * k,
                                y: center.y - rotated.y * scale * k)
            projected.append((point, depth, k, index))
        }
        var lookup: [Int: (point: CGPoint, depth: Double, scale: Double, index: Int)] = [:]
        for item in projected { lookup[item.index] = item }

        // Liens d'abord : ils passent derrière les nœuds.
        for edge in edges {
            guard let a = lookup[edge.from], let b = lookup[edge.to] else { continue }
            var path = Path()
            path.move(to: a.point)
            let control = CGPoint(x: (a.point.x + b.point.x) / 2,
                                  y: (a.point.y + b.point.y) / 2 - 14)
            path.addQuadCurve(to: b.point, control: control)
            let alpha = edge.active ? 0.55 : 0.18
            context.stroke(path,
                           with: .color(edge.tint.opacity(alpha * min(a.scale, b.scale))),
                           style: StrokeStyle(lineWidth: edge.dashed ? 0.9 : 1.3,
                                              dash: edge.dashed ? [3, 4] : []))
            if edge.active {
                particle(&context, from: a.point, to: b.point, control: control,
                         time: time, phase: Double(edge.to) * 0.17, tint: edge.tint)
            }
        }

        // Nœuds du plus lointain au plus proche.
        for item in projected.sorted(by: { $0.depth > $1.depth }) {
            let node = nodes[item.index]
            let proximity = min(max(item.scale, 0.55), 1.45)
            let radius: CGFloat
            switch node.kind {
            case .root: radius = 26
            case .branch: radius = 11
            case .tool: radius = 6.5
            case .delegation: radius = 5.5
            case .harness: radius = 8
            }
            let r = radius * proximity
            let alpha = min(1.0, 0.45 + (proximity - 0.55) * 0.8)

            if node.active || node.kind == .root {
                let halo = CGRect(x: item.point.x - r * 3, y: item.point.y - r * 3,
                                  width: r * 6, height: r * 6)
                context.fill(Path(ellipseIn: halo),
                             with: .radialGradient(Gradient(colors: [node.tint.opacity(0.22 * alpha), .clear]),
                                                   center: item.point, startRadius: r * 0.2,
                                                   endRadius: r * 2.6))
            }
            context.fill(Path(ellipseIn: CGRect(x: item.point.x - r, y: item.point.y - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(node.tint.opacity(alpha)))
            if node.kind == .root || node.kind == .branch {
                context.stroke(Path(ellipseIn: CGRect(x: item.point.x - r - 5, y: item.point.y - r - 5,
                                                      width: (r + 5) * 2, height: (r + 5) * 2)),
                               with: .color(node.tint.opacity(0.22 * alpha)), lineWidth: 1)
            }
            if node.kind == .root {
                context.fill(Path(ellipseIn: CGRect(x: item.point.x - r * 0.34,
                                                    y: item.point.y - r * 0.34,
                                                    width: r * 0.68, height: r * 0.68)),
                             with: .color(.white.opacity(0.9 * alpha)))
            }

            // Libellés : taille fixe, jamais mise à l'échelle, pour rester nets.
            if node.kind == .root || node.kind == .branch || (node.kind == .harness && node.active) {
                drawLabel(&context, node.label,
                          at: CGPoint(x: item.point.x, y: item.point.y + r + 7),
                          font: .system(size: node.kind == .root ? 13 : 10.5,
                                        weight: node.kind == .root ? .semibold : .medium),
                          color: node.kind == .root ? Theme.textPrimary : Theme.textSecondary.opacity(alpha),
                          centered: true, maxWidth: node.kind == .root ? 160 : 120)
            }
            if node.kind == .root {
                drawLabel(&context, node.detail, at: CGPoint(x: item.point.x, y: item.point.y - r - 18),
                          font: .system(size: 9.5), color: Theme.textTertiary, centered: true, maxWidth: 120)
            }
        }
    }

    private func particle(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                          control: CGPoint, time: TimeInterval, phase: Double, tint: Color) {
        for step in 0..<2 {
            let raw = (time * 0.55 + phase + Double(step) * 0.5).truncatingRemainder(dividingBy: 1.0)
            let p = bezierPoint(a, control, b, raw)
            let alpha = sin(raw * .pi) * 0.9
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.6, y: p.y - 2.6, width: 5.2, height: 5.2)),
                         with: .color(tint.opacity(0.18 * alpha)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)),
                         with: .color(tint.opacity(alpha)))
        }
    }

    private func bezierPoint(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let mt = 1 - t
        let x = mt * mt * a.x + 2 * mt * t * c.x + t * t * b.x
        let y = mt * mt * a.y + 2 * mt * t * c.y + t * t * b.y
        return CGPoint(x: x, y: y)
    }

    private func drawLabel(_ context: inout GraphicsContext, _ text: String, at point: CGPoint,
                           font: Font, color: Color, centered: Bool, maxWidth: CGFloat) {
        guard !text.isEmpty else { return }
        let resolved = context.resolve(Text(text).font(font).foregroundStyle(color))
        let measured = resolved.measure(in: CGSize(width: maxWidth, height: 30))
        let origin = centered ? CGPoint(x: point.x - measured.width / 2, y: point.y) : point
        context.draw(resolved, at: origin, anchor: .topLeading)
    }

    private func rotate(_ p: SIMD3<Double>, yaw: Double, pitch: Double) -> SIMD3<Double> {
        let cosY = cos(yaw), sinY = sin(yaw)
        let x1 = p.x * cosY + p.z * sinY
        let z1 = -p.x * sinY + p.z * cosY
        let cosP = cos(pitch), sinP = sin(pitch)
        let y2 = p.y * cosP - z1 * sinP
        let z2 = p.y * sinP + z1 * cosP
        return SIMD3<Double>(x1, y2, z2)
    }
}
