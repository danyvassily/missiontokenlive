import SwiftUI

/// Galaxie de données : ce que gbrain sait, en trois couches.
///
/// Noyau (gbrain) → sources → entités → nuage de faits. Même moteur de projection que la vue
/// Flux (perspective + tri en profondeur), mais la densité est bien plus grande : les faits sont
/// réduits à des points sans libellé, et seuls le noyau, les sources et les entités sont nommés.
struct GalaxyView: View {
    let galaxy: Galaxy

    @State private var yaw: Double = 0
    @State private var dragging: Double = 0

    private var scene: GalaxyScene { GalaxyScene(galaxy: galaxy) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if galaxy.available && !galaxy.nodes.isEmpty {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        scene.draw(in: &context, size: size, angle: yaw + dragging + t * 0.055, time: t)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { dragging = Double($0.translation.width) / 300.0 }
                        .onEnded { _ in yaw += dragging; dragging = 0 }
                )
            } else {
                emptyState
            }
            hud
        }
        .background(Theme.bg)
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Galaxie de données")
                        .font(Theme.title()).foregroundStyle(Theme.textPrimary)
                    Text("Tout ce que gbrain a ingéré, sur cette machine uniquement")
                        .font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 18) {
                    metric("\(galaxy.facts)", "faits", Theme.accent)
                    metric("\(galaxy.sources)", "sources", Theme.ok)
                    metric("\(galaxy.entities)", "entités", Theme.warn)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.6)) { yaw = 0; dragging = 0 }
                } label: {
                    Label("Recentrer", systemImage: "arrow.counterclockwise")
                        .font(Theme.caption(10.5)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.field).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 16) {
                legend(Theme.accent, "noir : noyau gbrain")
                legend(Theme.ok, "sources")
                legend(Theme.warn, "entités")
                legend(Theme.textTertiary, "faits (points)")
                Spacer()
                Text("glisser pour tourner")
                    .font(Theme.micro()).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(22)
    }

    private func metric(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(c)
            Text(l).font(Theme.micro()).foregroundStyle(Theme.textTertiary)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(Theme.micro()).foregroundStyle(Theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Aucune donnée dans gbrain").font(Theme.section(14)).foregroundStyle(Theme.textPrimary)
            Text("Lance `gbrain ingest` puis `gbrain capture` pour remplir le cerveau.")
                .font(Theme.caption(11)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Géométrie de la galaxie : positions par couche, précalculées une fois.
private struct GalaxyScene {
    struct Point3 {
        let p: SIMD3<Double>
        let node: GalaxyNode
        let tint: Color
        let baseRadius: Double
    }

    var points: [Point3] = []
    var links: [(Int, Int)] = []

    init(galaxy: Galaxy) {
        var index: [Int: Int] = [:]
        var sources: [Int] = []
        var entities: [Int] = []
        var facts: [Int] = []

        // Répartition des index par type, pour placer chaque couche sur son orbite.
        for (i, node) in galaxy.nodes.enumerated() {
            switch node.kind {
            case "core": index[i] = 0; points.append(Point3(p: SIMD3<Double>(0, 0, 0), node: node,
                                                          tint: Theme.accent, baseRadius: 22))
            case "source": sources.append(i)
            case "entity": entities.append(i)
            default: facts.append(i)
            }
        }

        func place(_ list: [Int], radius: Double, tilt: Double, tint: Color, dot: Double, wobble: Double) {
            let n = max(list.count, 1)
            for (k, original) in list.enumerated() {
                let angle = (Double(k) / Double(n)) * 2 * .pi
                let jitter = wobble * sin(Double(k) * 12.9898)
                let y = sin(angle) * radius * tilt + jitter
                let p = SIMD3<Double>(cos(angle) * radius,
                                      y,
                                      sin(angle) * radius * 0.85)
                index[original] = points.count
                points.append(Point3(p: p, node: galaxy.nodes[original], tint: tint, baseRadius: dot))
            }
        }

        place(sources, radius: 1.05, tilt: 0.30, tint: Theme.ok, dot: 8, wobble: 0.05)
        place(entities, radius: 1.95, tilt: 0.42, tint: Theme.warn, dot: 5, wobble: 0.12)
        place(facts, radius: 2.75, tilt: 0.55, tint: Theme.textTertiary, dot: 1.6, wobble: 0.25)

        for edge in galaxy.edges {
            if let a = index[edge.a], let b = index[edge.b], a != b {
                links.append((a, b))
            }
        }
    }

    func draw(in context: inout GraphicsContext, size: CGSize, angle: Double, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
        let scale = min(size.width, size.height) * 0.26
        let focal = 4.2

        var projected: [(point: CGPoint, depth: Double, k: Double, id: Int)] = []
        projected.reserveCapacity(points.count)
        for (i, pt) in points.enumerated() {
            let r = rotate(pt.p, yaw: angle, pitch: 0.22)
            let depth = r.z + 4.0
            guard depth > 0.3 else { continue }
            let k = focal / depth
            projected.append((CGPoint(x: center.x + r.x * scale * k,
                                      y: center.y - r.y * scale * k), depth, k, i))
        }
        var lookup: [Int: (point: CGPoint, depth: Double, k: Double, id: Int)] = [:]
        for it in projected { lookup[it.id] = it }

        // Liens : alpha très faible, beaucoup de traits — c'est la texture de la galaxie.
        var path = Path()
        for (a, b) in links {
            guard let pa = lookup[a], let pb = lookup[b] else { continue }
            path.move(to: pa.point)
            path.addLine(to: pb.point)
        }
        context.stroke(path, with: .color(Theme.border.opacity(0.20)), lineWidth: 0.4)

        for it in projected.sorted(by: { $0.depth > $1.depth }) {
            let pt = points[it.id]
            let prox = min(max(it.k, 0.6), 1.5)
            let r = pt.baseRadius * prox
            let alpha = min(1.0, 0.35 + (prox - 0.6) * 0.7)
            switch pt.node.kind {
            case "core":
                context.fill(Path(ellipseIn: CGRect(x: it.point.x - r * 3, y: it.point.y - r * 3,
                                                    width: r * 6, height: r * 6)),
                             with: .radialGradient(Gradient(colors: [Theme.accent.opacity(0.30), .clear]),
                                                   center: it.point, startRadius: r * 0.2, endRadius: r * 3))
                context.fill(Path(ellipseIn: CGRect(x: it.point.x - r, y: it.point.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(Theme.accent))
                label(&context, "gbrain", at: CGPoint(x: it.point.x, y: it.point.y + r + 6),
                      size: 12, weight: .semibold, color: Theme.textPrimary)
            case "source":
                context.fill(Path(ellipseIn: CGRect(x: it.point.x - r, y: it.point.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(Theme.ok.opacity(alpha)))
                label(&context, pt.node.label, at: CGPoint(x: it.point.x, y: it.point.y + r + 4),
                      size: 9.5, weight: .medium, color: Theme.textSecondary.opacity(alpha))
            case "entity":
                context.fill(Path(ellipseIn: CGRect(x: it.point.x - r, y: it.point.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(Theme.warn.opacity(alpha * 0.9)))
                if prox > 0.95 {
                    label(&context, pt.node.label, at: CGPoint(x: it.point.x, y: it.point.y + r + 3),
                          size: 8.5, weight: .regular, color: Theme.textTertiary.opacity(alpha))
                }
            default:
                context.fill(Path(ellipseIn: CGRect(x: it.point.x - r, y: it.point.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(Theme.textSecondary.opacity(alpha * 0.55)))
            }
        }
    }

    private func label(_ context: inout GraphicsContext, _ text: String, at p: CGPoint,
                       size: CGFloat, weight: Font.Weight, color: Color) {
        guard !text.isEmpty else { return }
        let resolved = context.resolve(Text(text).font(.system(size: size, weight: weight))
            .foregroundStyle(color))
        let measured = resolved.measure(in: CGSize(width: 140, height: 24))
        context.draw(resolved, at: CGPoint(x: p.x - measured.width / 2, y: p.y), anchor: .topLeading)
    }

    private func rotate(_ p: SIMD3<Double>, yaw: Double, pitch: Double) -> SIMD3<Double> {
        let cy = cos(yaw), sy = sin(yaw)
        let x1 = p.x * cy + p.z * sy
        let z1 = -p.x * sy + p.z * cy
        let cp = cos(pitch), sp = sin(pitch)
        return SIMD3<Double>(x1, p.y * cp - z1 * sp, p.y * sp + z1 * cp)
    }
}
