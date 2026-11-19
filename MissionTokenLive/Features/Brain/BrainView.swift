import SwiftUI

struct BrainView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab = 0
    @State private var apiAvailable: Bool?
    @State private var query = ""
    @State private var kind = ""
    @State private var entity = ""
    @State private var source = ""
    @State private var status = "active"
    @State private var sourceQuery = ""
    @State private var facts: [BrainFact] = []
    @State private var candidates: [BrainCandidate] = []
    @State private var loading = false
    @State private var loadingCandidates = false
    @State private var busyIDs: Set<Int> = []
    @State private var searchError: String?
    @State private var reviewError: String?
    @State private var notice: String?
    @State private var reloadID = 0
    private let client = BrainClient()

    private var brain: BrainStats { store.brain }
    private var sources: [BrainSource] { brain.sourceList ?? [] }
    private var pendingCount: Int { brain.pending ?? candidates.count }
    private var requestKey: String { [query, kind, entity, source, status, String(reloadID)].joined(separator: "\u{0}") }
    private let kinds = ["preference", "decision", "people", "admin", "project", "memory"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            counters
            HStack {
                Picker("", selection: $tab) {
                    Text(BrainCopy.memory).tag(0)
                    Text("\(BrainCopy.review) · \(pendingCount)").tag(1)
                    Text(BrainCopy.sources).tag(2)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)
                Spacer()
                if loading || loadingCandidates { ProgressView().controlSize(.small) }
                Button { refresh() } label: {
                    Label(BrainCopy.refresh, systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            if let notice {
                Text(notice).font(Theme.caption(12)).foregroundStyle(Theme.ok)
                    .accessibilityLabel(notice)
            }
            if tab == 0 { memoryContent }
            else if tab == 1 { reviewContent }
            else { sourcesContent }
            privacyNote
        }
        .padding(24)
        .background(Theme.bg)
        .task(id: requestKey) { await loadSearch() }
        .task { await loadCandidates(); apiAvailable = await client.apiAvailable() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(BrainCopy.title).font(Theme.title()).foregroundStyle(Theme.textPrimary)
                Text(BrainCopy.text("Retrouver, vérifier et faire évoluer ta mémoire partagée.", "Find, review and maintain your shared memory."))
                    .font(Theme.body()).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    StatusPill(text: BrainCopy.text(brain.available ? "Base accessible" : "Base indisponible", brain.available ? "Database available" : "Database unavailable"), tint: brain.available ? Theme.ok : Theme.warn, filled: true)
                    StatusPill(text: BrainCopy.text(client.available ? "Commande disponible" : "Commande absente", client.available ? "Command available" : "Command missing"), tint: client.available ? Theme.ok : Theme.warn)
                }
                if let apiAvailable {
                    Text(apiAvailable ? "API locale disponible" : "API indisponible · commandes locales disponibles")
                        .font(Theme.caption(11)).foregroundStyle(apiAvailable ? Theme.ok : Theme.warn)
                }
                Text("\(BrainCopy.text("Dernière ingestion", "Last import")) : \(brain.freshness)")
                    .font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 12) {
            metric(BrainCopy.text("Informations mémorisées", "Stored information"), value: brain.facts, tint: Theme.accent)
            metric(BrainCopy.text("Passages de contexte", "Context passages"), value: brain.chunks, tint: Theme.violet)
            metric(BrainCopy.sources, value: sources.count, tint: Theme.ok)
            Button { tab = 1 } label: {
                metric(BrainCopy.review, value: pendingCount, tint: Theme.warn)
            }
            .buttonStyle(.plain)
            .help(BrainCopy.text("Ouvrir les propositions en attente", "Open pending proposals"))
        }
    }

    private func metric(_ title: String, value: Int, tint: Color) -> some View {
        Card(padding: 15) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
                    Text(value.formatted()).font(Theme.title(25)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 2)
                Circle().fill(tint).frame(width: 7, height: 7)
            }
        }
    }

    private var memoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField(BrainCopy.search, text: $query)
                    .textFieldStyle(.plain).font(Theme.body(14))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel(BrainCopy.text("Effacer la recherche", "Clear search"))
                }
                Text(BrainCopy.text("Recherche locale", "Local search")).font(Theme.caption(11)).foregroundStyle(Theme.ok)
            }
            .padding(12).background(Theme.field).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                Picker(BrainCopy.allTypes, selection: $kind) {
                    Text(BrainCopy.allTypes).tag("")
                    ForEach(kinds, id: \.self) { Text(BrainFact.kindLabel($0)).tag($0) }
                }.labelsHidden().frame(maxWidth: 180)
                Picker(BrainCopy.allEntities, selection: $entity) {
                    Text(BrainCopy.allEntities).tag("")
                    ForEach(brain.top_entities.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { Text($0.name).tag($0.name) }
                }.labelsHidden().frame(maxWidth: 210)
                Picker(BrainCopy.allSources, selection: $source) {
                    Text(BrainCopy.allSources).tag("")
                    ForEach(sources) { Text(BrainFact.sourceName($0.path)).tag($0.path).help($0.path) }
                }.labelsHidden().frame(maxWidth: 230)
                Spacer(minLength: 0)
                Picker(BrainCopy.text("État", "State"), selection: $status) {
                    Text(BrainCopy.active).tag("active")
                    Text(BrainCopy.stale).tag("superseded")
                }.labelsHidden().frame(width: 155)
            }
            if let searchError { errorCard(searchError) { reloadID += 1 } }
            if status == "superseded" {
                Text(BrainCopy.text("Historique conservé. Ces informations ne sont plus utilisées dans les réponses des agents.", "Retained history. Agents no longer use this information in their answers."))
                    .font(Theme.caption(12)).foregroundStyle(Theme.warn)
            }
            HStack {
                Text(query.isEmpty ? BrainCopy.text("Dernières informations", "Latest information") : BrainCopy.text("Résultats", "Results"))
                    .font(Theme.section(15)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(facts.count)\(facts.count == 100 ? " · " + BrainCopy.text("affiner pour voir la suite", "refine to see more") : "")")
                    .font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if facts.isEmpty && !loading && searchError == nil {
                        emptyState(BrainCopy.empty, detail: BrainCopy.text("Essaie un autre mot ou enlève un filtre.", "Try another word or remove a filter."))
                    }
                    ForEach(facts) { fact in factRow(fact) }
                }
            }
        }
    }

    private func factRow(_ fact: BrainFact) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    badge(fact.kindLabel, tint: tint(fact.kind))
                    badge(fact.statusLabel, tint: fact.status == "superseded" ? Theme.warn : Theme.ok)
                    if let entity = fact.entity { Text(entity).font(Theme.caption(12)).foregroundStyle(Theme.textSecondary) }
                    Spacer()
                    dateLabel(fact.at)
                }
                Text(fact.text).font(Theme.body(14)).foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    sourceButton(fact.source)
                    if let section = fact.section, !section.isEmpty {
                        Text("· \(section)").lineLimit(1).font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BrainCopy.text("Ces propositions ne font pas encore partie de la mémoire active. Vérifie la preuve avant de valider chaque fait.", "These proposals are not part of active memory. Check the evidence before accepting each fact."))
                .font(Theme.body()).foregroundStyle(Theme.textSecondary)
            if let reviewError { errorCard(reviewError) { Task { await loadCandidates() } } }
            if pendingCount > candidates.count && !candidates.isEmpty {
                Text("\(candidates.count) / \(pendingCount) · \(BrainCopy.text("les suivantes apparaîtront après validation", "more will appear as you review"))")
                    .font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if candidates.isEmpty && !loadingCandidates && reviewError == nil {
                        emptyState(BrainCopy.text("Tout est à jour", "All reviewed"), detail: BrainCopy.text("Aucune proposition en attente de validation.", "No proposals are waiting for review."))
                    }
                    ForEach(candidates) { candidate in
                        Card(padding: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    badge(BrainCopy.pending, tint: Theme.warn)
                                    badge(BrainFact.kindLabel(candidate.kind), tint: tint(candidate.kind))
                                    if let entity = candidate.entity { Text(entity).font(Theme.caption(12)).foregroundStyle(Theme.textSecondary) }
                                    Spacer()
                                    dateLabel(candidate.created_at)
                                }
                                Text(candidate.text).font(Theme.body(14)).foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(BrainCopy.proof).font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
                                    Text(candidate.source?.isEmpty == false ? candidate.source! : BrainCopy.text("Preuve non conservée pour cette ancienne proposition. Vérifie sa source avant de l’accepter.", "Evidence was not retained for this older proposal. Verify its source before accepting it."))
                                        .font(Theme.body(12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                                    if let reason = candidate.reason, !reason.isEmpty {
                                        Text(reason).font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
                                    }
                                    if let origin = candidate.origin { sourceButton(origin) }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.bg.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 8))
                                HStack {
                                    Spacer()
                                    if busyIDs.contains(candidate.id) { ProgressView().controlSize(.small) }
                                    Button(BrainCopy.reject) { Task { await review(candidate, accept: false) } }
                                    Button(BrainCopy.accept) { Task { await review(candidate, accept: true) } }
                                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                                }.disabled(busyIDs.contains(candidate.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private var sourcesContent: some View {
        let visible = sources.filter { sourceQuery.isEmpty || $0.path.localizedCaseInsensitiveContains(sourceQuery) || BrainFact.kindLabel($0.kind).localizedCaseInsensitiveContains(sourceQuery) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(BrainCopy.filterSources, text: $sourceQuery).textFieldStyle(.roundedBorder).frame(maxWidth: 450)
                Spacer()
                Text("\(sources.filter(\.present).count) / \(sources.count) \(BrainCopy.text("sources disponibles", "sources available"))")
                    .font(Theme.caption(12)).foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visible) { item in
                        Card(padding: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.present ? "doc.text" : "exclamationmark.triangle")
                                    .foregroundStyle(item.present ? Theme.accent : Theme.warn).frame(width: 20)
                                VStack(alignment: .leading, spacing: 6) {
                                    sourceButton(item.path)
                                    Text(item.path).font(Theme.caption(12)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                                    if let error = item.last_error, !error.isEmpty {
                                        Text(error).font(Theme.caption(12)).foregroundStyle(Theme.warn)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text("\(item.facts) \(BrainCopy.text("faits actifs", "active facts"))").font(Theme.body(12)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                                    StatusPill(text: BrainCopy.text(item.present ? "Disponible" : "Manquante", item.present ? "Available" : "Missing"), tint: item.present ? Theme.ok : Theme.warn)
                                    dateLabel(item.ingested_at)
                                }
                            }
                        }
                    }
                    if visible.isEmpty { emptyState(BrainCopy.empty, detail: BrainCopy.text("Aucune source ne correspond au filtre.", "No source matches this filter.")) }
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "internaldrive").foregroundStyle(Theme.accent)
            Text(BrainCopy.text("Stockage local · La recherche de cet écran reste sur le Mac. Les fonctions d’enrichissement gbrain peuvent envoyer des requêtes ou extraits aux fournisseurs configurés (DeepSeek / OpenRouter).", "Local storage · Search on this screen stays on your Mac. gbrain enrichment can send queries or excerpts to configured providers (DeepSeek / OpenRouter)."))
                .font(Theme.caption(11.5)).foregroundStyle(Theme.textSecondary)
        }.padding(.top, 4)
    }

    private func sourceButton(_ path: String?) -> some View {
        let url = BrainFact.sourceURL(path)
        return Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            Label(BrainFact.sourceName(path), systemImage: "arrow.up.right.square")
                .font(Theme.caption(12)).lineLimit(1).foregroundStyle(url == nil ? Theme.textSecondary : Theme.accent)
        }
        .buttonStyle(.plain).disabled(url == nil)
        .help(path ?? BrainCopy.openSource)
        .accessibilityLabel("\(BrainCopy.openSource) : \(path ?? "")")
    }

    @ViewBuilder private func dateLabel(_ raw: String?) -> some View {
        if let date = BrainFact.date(raw) {
            Text(date, format: .dateTime.day().month().year().hour().minute())
                .font(Theme.caption(11.5)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text).font(Theme.caption(11.5)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3).background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "brain.head.profile").font(.system(size: 30)).foregroundStyle(Theme.textSecondary)
            Text(title).font(Theme.section()).foregroundStyle(Theme.textPrimary)
            Text(detail).font(Theme.body()).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    private func errorCard(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
            Text(message).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button(BrainCopy.retry, action: retry)
        }.padding(12).background(Theme.warn.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tint(_ kind: String) -> Color {
        switch kind {
        case "people": return Theme.violet
        case "preference": return Theme.cyan
        case "decision": return Theme.ok
        case "admin": return Theme.warn
        default: return Theme.accent
        }
    }

    @MainActor private func loadSearch() async {
        loading = true
        searchError = nil
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            let result = try await client.search(query: query, kind: kind, entity: entity, source: source, status: status)
            try Task.checkCancellation()
            facts = result
            loading = false
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            facts = []
            searchError = error.localizedDescription
            loading = false
        }
    }

    @MainActor private func loadCandidates() async {
        loadingCandidates = true
        defer { loadingCandidates = false }
        do {
            candidates = try await client.candidates()
            reviewError = nil
        } catch is CancellationError { }
        catch { reviewError = error.localizedDescription }
    }

    @MainActor private func review(_ candidate: BrainCandidate, accept: Bool) async {
        guard !busyIDs.contains(candidate.id) else { return }
        busyIDs.insert(candidate.id)
        defer { busyIDs.remove(candidate.id) }
        do {
            let changed = try await client.review(id: candidate.id, accept: accept)
            notice = changed > 0
                ? BrainCopy.text(accept ? "Fait validé et ajouté à la mémoire." : "Proposition rejetée.", accept ? "Fact accepted and added to memory." : "Proposal rejected.")
                : BrainCopy.text("Cette proposition a déjà été traitée.", "This proposal has already been reviewed.")
            store.refresh()
            reloadID += 1
            await loadCandidates()
        } catch { reviewError = error.localizedDescription }
    }

    @MainActor private func refresh() {
        notice = nil
        store.refresh()
        reloadID += 1
        Task { await loadCandidates(); apiAvailable = await client.apiAvailable() }
    }
}
