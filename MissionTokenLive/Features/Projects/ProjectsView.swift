import SwiftUI

/// Gestion des projets : archiver, restaurer, envoyer en corbeille locale (30 jours).
///
/// Ces actions ne touchent QUE la base interne de MissionTokenLive. Aucun dépôt, dossier
/// ou tâche Hermès n'est modifié.
struct ProjectsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var scope: ProjectStatus = .active
    @State private var confirmTrash: Project?
    @State private var purging: Project?

    private var projects: [Project] {
        store.snapshot.projects.filter { $0.status == scope }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Projets",
                subtitle: "La suppression locale ne touche jamais le projet source"
            )
            HStack(spacing: 8) {
                FilterChip(label: "Actifs", active: scope == .active) { scope = .active }
                FilterChip(label: "Archivés", active: scope == .archived) { scope = .archived }
                FilterChip(label: "Corbeille", active: scope == .trashed) { scope = .trashed }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(projects) { project in
                        Card(padding: 14) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Theme.field).frame(width: 34, height: 34)
                                    Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name).font(Theme.body(13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                    Text(project.path ?? "Aucun chemin observé")
                                        .font(Theme.caption(10)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                }
                                Spacer()
                                if project.status == .trashed, let purge = project.purge_after {
                                    let days = Calendar.current.dateComponents([.day], from: Date(), to: purge).day ?? 0
                                    Text("purge dans \(max(0, days)) j")
                                        .font(Theme.caption(10)).foregroundStyle(Theme.warn)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Theme.warn.opacity(0.1)).clipShape(Capsule())
                                }
                                if let budget = project.budget {
                                    Text(CostValue.formatFR(budget)).font(Theme.caption(11)).monospacedDigit()
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Menu {
                                    if project.status == .active {
                                        Button("Archiver") { act(project, "archive") }
                                        Button("Envoyer dans la corbeille", role: .destructive) { confirmTrash = project }
                                    } else if project.status == .archived {
                                        Button("Restaurer") { act(project, "restore") }
                                    } else {
                                        Button("Restaurer") { act(project, "restore") }
                                        Button("Purger définitivement", role: .destructive) { purging = project }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 24)
                            }
                        }
                    }
                    if projects.isEmpty {
                        EmptyStateView(title: "Aucun projet", message: "Aucun projet dans cette catégorie.")
                    }
                    Text("Une suppression place la fiche dans une corbeille locale récupérable pendant 30 jours. Le dossier, le dépôt GitHub et les tâches Hermès ne sont jamais modifiés.")
                        .font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .alert("Envoyer « \(confirmTrash?.name ?? "") » dans la corbeille ?", isPresented: .constant(confirmTrash != nil)) {
            Button("Annuler", role: .cancel) { confirmTrash = nil }
            Button("Envoyer", role: .destructive) {
                if let p = confirmTrash { act(p, "trash") }
                confirmTrash = nil
                scope = .trashed
            }
        } message: {
            Text("La fiche sera conservée 30 jours. Aucun fichier externe ne sera supprimé.")
        }
        .alert("Purger définitivement « \(purging?.name ?? "") » ?", isPresented: .constant(purging != nil)) {
            Button("Annuler", role: .cancel) { purging = nil }
            Button("Purger", role: .destructive) {
                if let p = purging { act(p, "purge") }
                purging = nil
            }
        } message: {
            Text("Cette action supprime uniquement les données internes de MissionTokenLive.")
        }
    }

    private func act(_ project: Project, _ action: String) {
        EngineBridge.projectAction(id: project.id, action: action)
        store.refresh()
    }
}
