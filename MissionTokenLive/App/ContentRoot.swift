import SwiftUI

/// Racine de la fenêtre : barre latérale + écran courant.
struct ContentRoot: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: Theme.sidebarWidth)
            Rectangle().fill(Theme.borderSoft).frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            if store.settings.hideDock {
                NSApp?.setActivationPolicy(.accessory)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.selection {
        case .now: NowView()
        case .agents: FluxView()
        case .flux: FluxView()
        case .tasks: TasksView()
        case .costs: CostsView()
        case .providers: ProvidersView()
        case .software: SoftwareView()
        case .projects: ProjectsView()
        case .brain: BrainView()
        case .galaxy: GalaxyView(galaxy: store.galaxy)
        case .settings: SettingsView()
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MissionTokenLive")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Centre de contrôle local")
                    .font(Theme.caption(10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 16)

            ForEach(Screen.allCases.filter { $0 != .settings && $0 != .agents }) { screen in
                SidebarItem(screen: screen, isActive: store.selection == screen || (screen == .flux && store.selection == .agents)) {
                    store.selection = screen
                }
            }

            Spacer(minLength: 12)

            SidebarItem(screen: .settings, isActive: store.selection == .settings) {
                store.selection = .settings
            }

            LocalStatusCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .background(Theme.sidebar)
    }
}

struct SidebarItem: View {
    let screen: Screen
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(isActive ? Theme.accent : .clear)
                    .frame(width: 3, height: 16)
                    .clipShape(Capsule())
                Image(systemName: screen.icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(screen.title)
                    .font(Theme.body(13, weight: isActive ? .medium : .regular))
                Spacer()
                if screen == .flux && store.worktree.activeSessions > 0 {
                    Text("\(store.worktree.activeSessions)")
                        .font(Theme.micro())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
            .padding(.vertical, 7)
            .padding(.trailing, 12)
            .background(isActive ? Theme.raised : (hovering ? Theme.raised.opacity(0.45) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @EnvironmentObject private var store: AppStore
}

struct LocalStatusCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Theme.ok).frame(width: 7, height: 7)
                Text("Stockage local")
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("\(store.snapshot.software.count) logiciels · \(store.activeAgents.count) agents actifs")
                .font(Theme.caption(10.5))
                .foregroundStyle(Theme.textSecondary)
            Text("Traitements externes selon les fonctions utilisées")
                .font(Theme.caption(10.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.borderSoft)
            Text(store.engineVersion)
                .font(Theme.caption(9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.borderSoft))
    }
}
