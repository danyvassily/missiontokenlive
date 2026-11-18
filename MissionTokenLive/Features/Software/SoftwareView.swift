import SwiftUI

struct SoftwareView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Logiciels",
                subtitle: "Détection locale (NSWorkspace + processus) · rien n'est envoyé sur le réseau"
            )
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.snapshot.software) { app in
                        Card(padding: 14) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9).fill(Theme.field).frame(width: 36, height: 36)
                                    Text(String(app.display_name.prefix(1)))
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(app.state.tint)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(app.display_name).font(Theme.body(13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                        if let v = app.version {
                                            Text(v).font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                    Text(app.note ?? (app.presence_only ? "Aucune donnée d'usage disponible" : "Données locales disponibles"))
                                        .font(Theme.caption(10.5)).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                if app.presence_only {
                                    Text("Présence uniquement")
                                        .font(Theme.micro()).foregroundStyle(Theme.textTertiary)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Theme.field).clipShape(Capsule())
                                }
                                StatusPill(text: app.state.labelFR, tint: app.state.tint, filled: app.state != .closed)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}
