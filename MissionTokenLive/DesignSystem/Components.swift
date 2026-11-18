import SwiftUI

/// Carte standard : surface + bordure 1 px, rayon 14.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Theme.radiusCard
    var highlighted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Theme.raised : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(highlighted ? Theme.accentDeep.opacity(0.45) : Theme.borderSoft, lineWidth: 1)
            )
    }
}

/// Badge de fiabilité : Réel / Calculé / Estimé / Non disponible.
struct ReliabilityBadge: View {
    let reliability: Reliability

    var body: some View {
        Text(reliability.labelFR)
            .font(Theme.micro())
            .foregroundStyle(reliability.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(reliability.tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                    .stroke(reliability.tint.opacity(0.28), lineWidth: 0.8)
            )
            .accessibilityLabel("Fiabilité : \(reliability.labelFR)")
    }
}

struct StatusPill: View {
    let text: String
    let tint: Color
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(Theme.caption(11))
                .foregroundStyle(filled ? tint : Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(filled ? 0.16 : 0.08))
        .clipShape(Capsule())
    }
}

struct CostChip: View {
    let cost: CostValue
    var body: some View {
        HStack(spacing: 6) {
            Text(cost.display)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(cost.reliability == .unavailable ? Theme.textTertiary : Theme.textPrimary)
            ReliabilityBadge(reliability: cost.reliability)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.micro())
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct ProgressBar: View {
    var value: Double
    var tint: Color = Theme.ok
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.field)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int(value * 100)) %")
    }
}

struct KpiCard: View {
    let kpi: Kpi

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(kpi.label)
                        .font(Theme.caption(11.5))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    ReliabilityBadge(reliability: kpi.reliability)
                }
                Text(kpi.value)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let detail = kpi.detail {
                    Text(detail)
                        .font(Theme.caption(10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                if let progress = kpi.progress {
                    ProgressBar(value: progress, tint: progress < 0.2 ? Theme.warn : Theme.ok)
                }
            }
        }
    }
}

/// Pastille d'état animée pour la tâche en cours.
struct PulseDot: View {
    var tint: Color = Theme.accent
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.25)).frame(width: 14, height: 14)
                .scaleEffect(animate ? 1.3 : 0.8)
                .opacity(animate ? 0 : 0.8)
            Circle().fill(tint).frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { animate = true }
        }
        .frame(width: 14, height: 14)
    }
}

func durationText(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%02d:%02d:%02d", h, m, sec) }
    return String(format: "%02d:%02d", m, sec)
}

func tokensText(_ n: UInt64) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
