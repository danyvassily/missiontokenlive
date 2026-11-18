import SwiftUI
import Foundation
import CoreGraphics

/// Vue 3D temps réel de l'arborescence de travail Hermès.
///
/// Architecture graphique :
/// 1. **Projection perspective 3D maison** : chaque nœud possède des coordonnées `(x, y, z)` dans
///    l'espace monde. À chaque image, une rotation lacet/tangage (rotation automatique autour de Y,
///    glissement manuel et parallaxe souris) est appliquée, puis le point est projeté sur le plan 2D
///    via le facteur perspectif `focale / (distanceCamera + z)`.
/// 2. **Tri en profondeur (algorithme du peintre)** : les liens et les nœuds sont triés du plus
///    éloigné (`profondeur` maximale) au plus proche (`profondeur` minimale) afin que les éléments
///    au premier plan recouvrent naturellement ceux de l'arrière-plan, avec taille et opacité
///    modulées par la distance.
/// 3. **Délestage intelligent et anti-superposition** : les branches actives déploient leurs outils
///    et délégations, tandis que les branches au repos regroupent leurs outils en un nœud compact
///    `+N outils` pour garder la scène aérée. Les libellés gardent une taille de police fixe et un
///    solveur spatial évite toute collision.
/// 4. **Interactivité directe** : le survol met en évidence le chemin complet `Hermès → nœud`, et
///    le clic ouvre un panneau latéral présentant les données réelles de `WorkTree` (titre, projet,
///    messages, outils avec compteurs, état des délégations, processus de harnais).
struct WorkTree3DView: View {
    let tree: WorkTree

    @State private var angleManuel: Double = 0
    @State private var angleGlissement: Double = 0
    @State private var tempsOrigine: TimeInterval = Date.timeIntervalSinceReferenceDate
    @State private var angleDepartRecentrage: Double = 0
    @State private var dateRecentrage: TimeInterval = 0
    @State private var parallaxeCible: CGPoint = .zero
    @State private var positionSouris: CGPoint? = nil
    @State private var idSurvole: String? = nil
    @State private var idSelectionne: String? = nil

    /// Topologie 3D précalculée à partir des données décodées de `WorkTree`.
    private var scene: SceneArborescence3D {
        SceneArborescence3D(tree: tree)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            fondAtmospherique

            if !tree.available || tree.branches.isEmpty {
                etatVideCentre
            } else {
                canvasTridimensionnel
            }

            hudSuperpose
        }
        .background(Theme.bg)
    }

    // MARK: - Scène 3D animée (60 fps)

    private var canvasTridimensionnel: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { geo in
                let maintenant = timeline.date.timeIntervalSinceReferenceDate
                let angleCourant = calculerAngleRotation(maintenant: maintenant)
                let tangageCourant = 0.23 + Double(parallaxeCible.y) * 0.11
                let cheminMisEnEvidence = scene.cheminDepuisRacine(
                    vers: idSurvole ?? idSelectionne
                )

                Canvas { context, size in
                    scene.dessiner(
                        dans: &context,
                        taille: size,
                        lacet: angleCourant,
                        tangage: tangageCourant,
                        parallaxe: parallaxeCible,
                        temps: maintenant,
                        idSurvole: idSurvole,
                        idSelectionne: idSelectionne,
                        cheminActif: cheminMisEnEvidence
                    )
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            let hit = scene.noeudSousPoint(
                                event.location,
                                taille: geo.size,
                                lacet: angleCourant,
                                tangage: tangageCourant,
                                parallaxe: parallaxeCible,
                                temps: maintenant
                            )
                            withAnimation(.easeInOut(duration: 0.22)) {
                                if let hit {
                                    idSelectionne = (idSelectionne == hit.identifiant) ? nil : hit.identifiant
                                } else {
                                    idSelectionne = nil
                                }
                            }
                        }
                        .exclusively(
                            before: DragGesture(minimumDistance: 3)
                                .onChanged { valeur in
                                    angleGlissement = Double(valeur.translation.width) / 220.0
                                }
                                .onEnded { _ in
                                    angleManuel += angleGlissement
                                    angleGlissement = 0
                                }
                        )
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let position):
                        positionSouris = position
                        let largeur = max(geo.size.width, 1)
                        let hauteur = max(geo.size.height, 1)
                        let nx = max(-1.0, min(1.0, (position.x / largeur - 0.5) * 2.0))
                        let ny = max(-1.0, min(1.0, (position.y / hauteur - 0.5) * 2.0))
                        parallaxeCible = CGPoint(x: nx, y: ny)

                        let hit = scene.noeudSousPoint(
                            position,
                            taille: geo.size,
                            lacet: angleCourant,
                            tangage: tangageCourant,
                            parallaxe: parallaxeCible,
                            temps: maintenant
                        )
                        if idSurvole != hit?.identifiant {
                            idSurvole = hit?.identifiant
                        }
                    case .ended:
                        positionSouris = nil
                        idSurvole = nil
                        withAnimation(.easeOut(duration: 0.45)) {
                            parallaxeCible = .zero
                        }
                    }
                }
            }
        }
    }

    /// Calcule l'angle de rotation Y en combinant rotation rythmée continue (0,15 rad/s),
    /// parallaxe souris et interpolation cubique fluide lors d'un appui sur « Recentrer ».
    private func calculerAngleRotation(maintenant: TimeInterval) -> Double {
        let vitesseRotation = 0.15
        let rotationAuto = (maintenant - tempsOrigine) * vitesseRotation
        let parallaxeLacet = Double(parallaxeCible.x) * 0.16

        let dureeRecentrage = 0.55
        let ecouleRecentrage = maintenant - dateRecentrage
        var amortissementRecentrage = 0.0
        if dateRecentrage > 0 && ecouleRecentrage < dureeRecentrage {
            let t = max(0.0, min(1.0, ecouleRecentrage / dureeRecentrage))
            let easeOut = 1.0 - pow(1.0 - t, 3.0)
            amortissementRecentrage = angleDepartRecentrage * (1.0 - easeOut)
        }

        return angleManuel + angleGlissement + rotationAuto + parallaxeLacet + amortissementRecentrage
    }

    private func recentrerScene() {
        let maintenant = Date.timeIntervalSinceReferenceDate
        let angleActuel = calculerAngleRotation(maintenant: maintenant)
        let deuxPi = Double.pi * 2.0
        var residu = angleActuel.truncatingRemainder(dividingBy: deuxPi)
        if residu > Double.pi { residu -= deuxPi }
        if residu < -Double.pi { residu += deuxPi }

        angleDepartRecentrage = residu
        dateRecentrage = maintenant
        tempsOrigine = maintenant
        angleManuel = 0
        angleGlissement = 0
        withAnimation(.easeOut(duration: 0.45)) {
            parallaxeCible = .zero
        }
    }

    // MARK: - Fond et État vide

    private var fondAtmospherique: some View {
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [
                    Theme.accent.opacity(0.09),
                    Theme.surface.opacity(0.38),
                    Theme.bg
                ],
                center: .center,
                startRadius: 24,
                endRadius: 540
            )
        }
        .ignoresSafeArea()
    }

    private var etatVideCentre: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.accent.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 44
                        )
                    )
                    .frame(width: 88, height: 88)

                Circle()
                    .stroke(Theme.border, lineWidth: 1)
                    .frame(width: 48, height: 48)

                Circle()
                    .fill(tree.available ? Theme.accent : Theme.textTertiary)
                    .frame(width: 14, height: 14)
            }

            Text(tree.available ? "Aucune session récente dans l'arborescence" : "Arborescence de travail indisponible")
                .font(Theme.section(14))
                .foregroundStyle(Theme.textPrimary)

            Text(
                tree.available
                    ? "Hermès est en veille. Ouvrez une session ou lancez une tâche pour observer les flux en trois dimensions."
                    : "La base locale d'Hermès n'est pas joignable pour le moment."
            )
            .font(Theme.body(12))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 390)

            HStack(spacing: 16) {
                pastilleEtatVide(titre: "Racine", valeur: textePropre(tree.rootLabel))
                pastilleEtatVide(titre: "Harnais actifs", valeur: "\(tree.harnesses.filter { $0.active }.count)")
            }
            .padding(.top, 4)
        }
        .padding(28)
        .background(Theme.surface.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.borderSoft, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func pastilleEtatVide(titre: String, valeur: String) -> some View {
        HStack(spacing: 6) {
            Text(titre)
                .font(Theme.micro())
                .foregroundStyle(Theme.textTertiary)
            Text(valeur)
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.bg.opacity(0.65))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.borderSoft, lineWidth: 1))
    }

    // MARK: - HUD en surimpression + panneau latéral de détail

    private var hudSuperpose: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Arborescence de travail")
                            .font(Theme.title())
                            .foregroundStyle(Theme.textPrimary)
                        Text("Synergie temps réel : \(textePropre(tree.rootLabel)) · sessions · outils · délégations · harnais")
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    HStack(spacing: 14) {
                        compteurHUD(
                            valeur: "\(tree.activeSessions)",
                            libelle: "sessions actives",
                            teinte: tree.activeSessions > 0 ? Theme.ok : Theme.textTertiary
                        )
                        separateurVerticalHUD
                        compteurHUD(
                            valeur: "\(tree.runningTasks)",
                            libelle: "tâches en cours",
                            teinte: tree.runningTasks > 0 ? Theme.accent : Theme.textTertiary
                        )
                        separateurVerticalHUD
                        compteurHUD(
                            valeur: "\(tree.branches.count)",
                            libelle: "branches",
                            teinte: Theme.textSecondary
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.borderSoft, lineWidth: 1)
                    )

                    if tree.harnesses.contains(where: { $0.active }) {
                        HStack(spacing: 8) {
                            ForEach(tree.harnesses.filter { $0.active }) { harness in
                                HStack(spacing: 5) {
                                    Circle().fill(Theme.ok).frame(width: 5, height: 5)
                                    Text(harness.name)
                                        .font(Theme.micro())
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Theme.surface.opacity(0.82))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Theme.borderSoft, lineWidth: 1))
                            }
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    Button(action: recentrerScene) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Recentrer")
                                .font(Theme.caption(10.5))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.surface.opacity(0.88))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recentrer l'arborescence 3D")

                    if let noeud = scene.noeudParIdentifiant(idSelectionne ?? idSurvole) {
                        panneauDetail(pour: noeud, estVerrouille: idSelectionne != nil)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }

            Spacer()

            HStack(alignment: .bottom) {
                Text("Glisser pour orienter · Survoler ou cliquer un nœud pour inspecter")
                    .font(Theme.micro())
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.72))
                    .clipShape(Capsule())
                Spacer()
                legendeDiscrete
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private func panneauDetail(pour noeud: SceneArborescence3D.Noeud3D, estVerrouille: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(noeud.teinte)
                    .frame(width: 8, height: 8)
                Text(noeud.categorie.titreFR.uppercased())
                    .font(Theme.micro())
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if estVerrouille {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { idSelectionne = nil }
                    } label: {
                        Text("Fermer")
                            .font(Theme.micro())
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.field)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(noeud.titreComplet)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            switch noeud.cibleDetail {
            case .racine:
                ligneDetail("Rôle", "Orchestrateur local")
                ligneDetail("Sessions actives", "\(tree.activeSessions)")
                ligneDetail("Tâches en cours", "\(tree.runningTasks)")
                ligneDetail("Branches observées", "\(tree.branches.count)")
                ligneDetail("Harnais actifs", "\(tree.harnesses.filter { $0.active }.count) / \(tree.harnesses.count)")

            case .branche(let b), .resumeOutils(let b):
                ligneDetail("Projet", textePropre(b.project))
                ligneDetail("État", b.isActive ? "Active" : "Au repos")
                ligneDetail("Messages", "\(b.messages)")
                if !b.tools.isEmpty {
                    Divider().overlay(Theme.borderSoft)
                    Text("OUTILS UTILISÉS")
                        .font(Theme.micro())
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(b.tools) { tool in
                        HStack {
                            Text(tool.name)
                                .font(Theme.caption(11))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(tool.count)×")
                                .font(Theme.caption(11))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                if !b.delegations.isEmpty {
                    Divider().overlay(Theme.borderSoft)
                    Text("DÉLÉGATIONS")
                        .font(Theme.micro())
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(b.delegations) { del in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(del.goal)
                                .font(Theme.caption(11))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                            Text(traduireEtatFR(del.state))
                                .font(Theme.micro())
                                .foregroundStyle(estEtatActif(del.state) ? Theme.warn : Theme.textTertiary)
                        }
                    }
                }

            case .outil(let tool, let b):
                ligneDetail("Session", texteCourt(b.title, maxCaracteres: 28))
                ligneDetail("Projet", textePropre(b.project))
                ligneDetail("Appels mesurés", "\(tool.count)×")
                ligneDetail("État session", b.isActive ? "Active" : "Au repos")

            case .delegation(let del, let b):
                ligneDetail("Session parente", texteCourt(b.title, maxCaracteres: 28))
                ligneDetail("Projet", textePropre(b.project))
                ligneDetail("Statut", traduireEtatFR(del.state))

            case .harnais(let h):
                ligneDetail("Statut", h.active ? "Actif sur ce Mac" : "Aucun processus actif")
                ligneDetail("Détail", texteCourt(h.detail, maxCaracteres: 44))
            }
        }
        .padding(14)
        .frame(width: 288, alignment: .leading)
        .background(Theme.surface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(estVerrouille ? Theme.accent.opacity(0.55) : Theme.border, lineWidth: 1)
        )
    }

    private func ligneDetail(_ cle: String, _ valeur: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(cle)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(valeur)
                .font(Theme.caption(11))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var separateurVerticalHUD: some View {
        Rectangle()
            .fill(Theme.borderSoft)
            .frame(width: 1, height: 24)
    }

    private func compteurHUD(valeur: String, libelle: String, teinte: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(valeur)
                .font(Theme.section(14))
                .monospacedDigit()
                .foregroundStyle(teinte)
            Text(libelle)
                .font(Theme.micro())
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var legendeDiscrete: some View {
        HStack(spacing: 14) {
            elementLegende(couleur: Theme.accent, texte: "Hermès et outils", pointille: false)
            elementLegende(couleur: Theme.ok, texte: "Session ou harnais actif", pointille: false)
            elementLegende(couleur: Theme.warn, texte: "Délégation", pointille: true)
            elementLegende(couleur: Theme.textTertiary, texte: "Repos ou inactif", pointille: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.82))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Theme.borderSoft, lineWidth: 1)
        )
    }

    private func elementLegende(couleur: Color, texte: String, pointille: Bool) -> some View {
        HStack(spacing: 6) {
            if pointille {
                Circle()
                    .strokeBorder(couleur, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .fill(couleur)
                    .frame(width: 6, height: 6)
            }
            Text(texte)
                .font(Theme.micro())
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Moteur géométrique et rendu 3D

private struct SceneArborescence3D {
    enum CategorieNoeud: Int {
        case racine = 0
        case branche = 1
        case harnais = 2
        case outil = 3
        case delegation = 4

        var titreFR: String {
            switch self {
            case .racine: return "Orchestrateur"
            case .branche: return "Session Hermès"
            case .harnais: return "Harnais externe"
            case .outil: return "Outil utilisé"
            case .delegation: return "Sous-agent délégué"
            }
        }
    }

    enum CibleDetail {
        case racine
        case branche(WorkBranch)
        case outil(WorkTool, WorkBranch)
        case resumeOutils(WorkBranch)
        case delegation(WorkDelegation, WorkBranch)
        case harnais(WorkHarness)
    }

    struct Noeud3D {
        let identifiant: String
        let parentIndice: Int?
        let libelle: String
        let sousLibelle: String
        let titreComplet: String
        let position: SIMD3<Double>
        let teinte: Color
        let categorie: CategorieNoeud
        let actif: Bool
        let cibleDetail: CibleDetail
    }

    struct Lien3D {
        let source: Int
        let cible: Int
        let pointControle: SIMD3<Double>
        let teinteSource: Color
        let teinteCible: Color
        let actif: Bool
        let pointille: Bool
        let nombreParticules: Int
        let vitesseFlux: Double
    }

    private struct PointProjete {
        let ecran: CGPoint
        let profondeur: Double
        let echelle: Double
        let indice: Int
    }

    var noeuds: [Noeud3D] = []
    var liens: [Lien3D] = []
    var anneauBranches: [SIMD3<Double>] = []
    var anneauHarnais: [SIMD3<Double>] = []

    private let rayonAnneauBranches: Double = 1.04
    private let inclinaisonAnneauBranches: Double = 0.34
    private let rayonAnneauHarnais: Double = 1.56
    private let decalageXHarnais: Double = -0.18

    init(tree: WorkTree) {
        let nomRacine = textePropre(tree.rootLabel)
        let sousLibelleRacine = tree.runningTasks > 0
            ? "\(tree.runningTasks) en cours"
            : "\(tree.activeSessions) active\(tree.activeSessions > 1 ? "s" : "")"
        let racineActive = tree.runningTasks > 0 || tree.activeSessions > 0

        // 1. Racine : Hermès au centre (0, 0, 0)
        noeuds.append(
            Noeud3D(
                identifiant: "racine",
                parentIndice: nil,
                libelle: nomRacine,
                sousLibelle: sousLibelleRacine,
                titreComplet: nomRacine,
                position: SIMD3<Double>(0, 0, 0),
                teinte: Theme.accent,
                categorie: .racine,
                actif: racineActive,
                cibleDetail: .racine
            )
        )

        let segmentsOrbite = 48
        anneauBranches.reserveCapacity(segmentsOrbite)
        for i in 0..<segmentsOrbite {
            let theta = (Double(i) / Double(segmentsOrbite)) * 2.0 * Double.pi
            anneauBranches.append(positionSurAnneauBranches(angle: theta, rayon: rayonAnneauBranches))
        }

        // 2. Branches (niveau 1) : max 7 sessions sur un anneau incliné en 3D
        let branchesRetenues = Array(tree.branches.prefix(7))
        let totalBranches = max(branchesRetenues.count, 1)
        let aucuneBrancheActive = !branchesRetenues.contains(where: { $0.isActive })

        for (idxBranche, branche) in branchesRetenues.enumerated() {
            let angleBranche = (Double(idxBranche) / Double(totalBranches)) * 2.0 * Double.pi
            let posBranche = positionSurAnneauBranches(angle: angleBranche, rayon: rayonAnneauBranches)
            let estActive = branche.isActive
            let teinteBranche = estActive ? Theme.ok : Theme.textTertiary

            let titreBranche = texteCourt(branche.title, maxCaracteres: 22)
            let projetBranche = texteCourt(branche.project, maxCaracteres: 16)

            noeuds.append(
                Noeud3D(
                    identifiant: "branche-\(branche.id)-\(idxBranche)",
                    parentIndice: 0,
                    libelle: titreBranche,
                    sousLibelle: "\(projetBranche) · \(branche.messages) msg",
                    titreComplet: textePropre(branche.title),
                    position: posBranche,
                    teinte: teinteBranche,
                    categorie: .branche,
                    actif: estActive,
                    cibleDetail: .branche(branche)
                )
            )
            let indiceBranche = noeuds.count - 1

            let controleRacineBranche = SIMD3<Double>(
                posBranche.x * 0.5,
                posBranche.y * 0.5 + 0.16,
                posBranche.z * 0.5
            )
            liens.append(
                Lien3D(
                    source: 0,
                    cible: indiceBranche,
                    pointControle: controleRacineBranche,
                    teinteSource: Theme.accent,
                    teinteCible: teinteBranche,
                    actif: estActive,
                    pointille: false,
                    nombreParticules: 3,
                    vitesseFlux: 0.58
                )
            )

            // 3a. Délestage intelligent des outils :
            // - branche active (ou les 2 premières si toutes au repos) : éventail jusqu'à 3 outils
            // - branche au repos avec outils : 1 seul nœud regroupé "+N outils" (ou le seul outil)
            let deployerOutils = estActive || (aucuneBrancheActive && idxBranche < 2)
            if deployerOutils {
                let outilsRetenus = Array(branche.tools.prefix(3))
                let nbOutils = outilsRetenus.count
                for (idxOutil, outil) in outilsRetenus.enumerated() {
                    let centrage = Double(idxOutil) - Double(nbOutils - 1) * 0.5
                    let angleOutil = angleBranche + centrage * 0.24
                    let rayonOutil = rayonAnneauBranches + 0.50
                    let baseExterieure = positionSurAnneauBranches(angle: angleOutil, rayon: rayonOutil)
                    let elevationOutil = 0.12 + Double(idxOutil) * 0.05
                    let posOutil = SIMD3<Double>(
                        baseExterieure.x,
                        baseExterieure.y + elevationOutil,
                        baseExterieure.z
                    )

                    let teinteOutil = estActive ? Theme.accent : Theme.textTertiary
                    let detailOutil = outil.count > 0 ? "\(outil.count)×" : "—"

                    noeuds.append(
                        Noeud3D(
                            identifiant: "outil-\(branche.id)-\(idxOutil)",
                            parentIndice: indiceBranche,
                            libelle: texteCourt(outil.name, maxCaracteres: 16),
                            sousLibelle: detailOutil,
                            titreComplet: "\(outil.name) (\(detailOutil))",
                            position: posOutil,
                            teinte: teinteOutil,
                            categorie: .outil,
                            actif: estActive,
                            cibleDetail: .outil(outil, branche)
                        )
                    )
                    let indiceOutil = noeuds.count - 1
                    let controleOutil = (posBranche + posOutil) * 0.5 + SIMD3<Double>(0, 0.08, 0)

                    liens.append(
                        Lien3D(
                            source: indiceBranche,
                            cible: indiceOutil,
                            pointControle: controleOutil,
                            teinteSource: teinteBranche,
                            teinteCible: teinteOutil,
                            actif: estActive,
                            pointille: false,
                            nombreParticules: 2,
                            vitesseFlux: 0.72
                        )
                    )
                }
            } else if !branche.tools.isEmpty {
                let nbTotal = branche.tools.count
                let totalAppels = branche.tools.reduce(0) { $0 + $1.count }
                let libelleCompact = nbTotal == 1
                    ? texteCourt(branche.tools[0].name, maxCaracteres: 15)
                    : "+\(nbTotal) outils"
                let baseExterieure = positionSurAnneauBranches(angle: angleBranche, rayon: rayonAnneauBranches + 0.42)
                let posCompact = SIMD3<Double>(baseExterieure.x, baseExterieure.y + 0.09, baseExterieure.z)

                noeuds.append(
                    Noeud3D(
                        identifiant: "outils-groupe-\(branche.id)",
                        parentIndice: indiceBranche,
                        libelle: libelleCompact,
                        sousLibelle: "\(totalAppels)×",
                        titreComplet: "Outils de \(texteCourt(branche.title, maxCaracteres: 26))",
                        position: posCompact,
                        teinte: Theme.textTertiary,
                        categorie: .outil,
                        actif: false,
                        cibleDetail: .resumeOutils(branche)
                    )
                )
                let indiceCompact = noeuds.count - 1
                liens.append(
                    Lien3D(
                        source: indiceBranche,
                        cible: indiceCompact,
                        pointControle: (posBranche + posCompact) * 0.5 + SIMD3<Double>(0, 0.05, 0),
                        teinteSource: teinteBranche,
                        teinteCible: Theme.textTertiary,
                        actif: false,
                        pointille: false,
                        nombreParticules: 0,
                        vitesseFlux: 0.5
                    )
                )
            }

            // 3b. Niveau 2 — Délégations (max 2) en nœuds plus petits avec lien pointillé animé
            let delegationsRetenues = Array(branche.delegations.prefix(2))
            let nbDelegations = delegationsRetenues.count
            for (idxDel, delegation) in delegationsRetenues.enumerated() {
                let centrage = Double(idxDel) - Double(nbDelegations - 1) * 0.5
                let angleDel = angleBranche + centrage * 0.28 + 0.10
                let rayonDel = rayonAnneauBranches + 0.40
                let baseDel = positionSurAnneauBranches(angle: angleDel, rayon: rayonDel)
                let posDel = SIMD3<Double>(
                    baseDel.x,
                    baseDel.y - 0.24 - Double(idxDel) * 0.05,
                    baseDel.z
                )

                let delActive = estActive || estEtatActif(delegation.state)
                let teinteDel = delActive ? Theme.warn : Theme.textTertiary

                noeuds.append(
                    Noeud3D(
                        identifiant: "del-\(branche.id)-\(delegation.id)-\(idxDel)",
                        parentIndice: indiceBranche,
                        libelle: texteCourt(delegation.goal, maxCaracteres: 18),
                        sousLibelle: traduireEtatFR(delegation.state),
                        titreComplet: textePropre(delegation.goal),
                        position: posDel,
                        teinte: teinteDel,
                        categorie: .delegation,
                        actif: delActive,
                        cibleDetail: .delegation(delegation, branche)
                    )
                )
                let indiceDel = noeuds.count - 1
                let controleDel = (posBranche + posDel) * 0.5 + SIMD3<Double>(0, -0.09, 0)

                liens.append(
                    Lien3D(
                        source: indiceBranche,
                        cible: indiceDel,
                        pointControle: controleDel,
                        teinteSource: teinteBranche,
                        teinteCible: teinteDel,
                        actif: delActive,
                        pointille: true,
                        nombreParticules: 2,
                        vitesseFlux: 0.50
                    )
                )
            }
        }

        // 4. Harnais (niveau latéral) : anneau vertical décalé
        anneauHarnais.reserveCapacity(segmentsOrbite)
        for i in 0..<segmentsOrbite {
            let phi = (Double(i) / Double(segmentsOrbite)) * 2.0 * Double.pi
            anneauHarnais.append(positionSurAnneauHarnais(angle: phi))
        }

        let totalHarnais = max(tree.harnesses.count, 1)
        for (idxHarnais, harnais) in tree.harnesses.enumerated() {
            let angleHarnais = (Double(idxHarnais) / Double(totalHarnais)) * 2.0 * Double.pi + 0.35
            let posHarnais = positionSurAnneauHarnais(angle: angleHarnais)
            let teinteHarnais = harnais.active ? Theme.ok : Theme.textTertiary

            noeuds.append(
                Noeud3D(
                    identifiant: "harnais-\(harnais.name)-\(idxHarnais)",
                    parentIndice: 0,
                    libelle: texteCourt(harnais.name, maxCaracteres: 18),
                    sousLibelle: harnais.active ? "actif" : "inactif",
                    titreComplet: harnais.name,
                    position: posHarnais,
                    teinte: teinteHarnais,
                    categorie: .harnais,
                    actif: harnais.active,
                    cibleDetail: .harnais(harnais)
                )
            )
            let indiceHarnais = noeuds.count - 1
            let controleHarnais = posHarnais * 0.52 + SIMD3<Double>(0, 0.14, 0)

            liens.append(
                Lien3D(
                    source: 0,
                    cible: indiceHarnais,
                    pointControle: controleHarnais,
                    teinteSource: Theme.accent,
                    teinteCible: teinteHarnais,
                    actif: harnais.active,
                    pointille: !harnais.active,
                    nombreParticules: 2,
                    vitesseFlux: 0.48
                )
            )
        }
    }

    // MARK: - Recherche d'interaction (survol, clic, chemin Hermès → nœud)

    func noeudParIdentifiant(_ id: String?) -> Noeud3D? {
        guard let id else { return nil }
        return noeuds.first { $0.identifiant == id }
    }

    /// Renvoie l'ensemble des indices de nœuds composant le chemin entre Hermès (0) et le nœud cible.
    func cheminDepuisRacine(vers idCible: String?) -> Set<Int> {
        guard let idCible, let idx = noeuds.firstIndex(where: { $0.identifiant == idCible }) else {
            return []
        }
        var chemin: Set<Int> = [idx]
        var courant = idx
        while let parent = noeuds[courant].parentIndice {
            chemin.insert(parent)
            courant = parent
        }
        // Si on survole une branche, inclure aussi ses enfants directs pour montrer sa grappe
        if noeuds[idx].categorie == .branche {
            for (i, n) in noeuds.enumerated() where n.parentIndice == idx {
                chemin.insert(i)
            }
        }
        return chemin
    }

    func noeudSousPoint(
        _ point: CGPoint,
        taille: CGSize,
        lacet: Double,
        tangage: Double,
        parallaxe: CGPoint,
        temps: TimeInterval
    ) -> Noeud3D? {
        let centreEcran = CGPoint(
            x: taille.width * 0.5 + parallaxe.x * 10.0,
            y: taille.height * 0.52 + parallaxe.y * 8.0
        )
        let echelleMonde = min(taille.width, taille.height) * 0.27
        let focale = 3.5
        let distanceCamera = 3.35

        var candidats: [(noeud: Noeud3D, distance: CGFloat, profondeur: Double)] = []
        for (indice, noeud) in noeuds.enumerated() {
            let oscillation = indice == 0 ? 0.0 : sin(temps * 1.45 + Double(indice) * 0.9) * 0.018
            let pos = SIMD3<Double>(noeud.position.x, noeud.position.y + oscillation, noeud.position.z)
            guard let proj = projeter(
                pos,
                indice: indice,
                centre: centreEcran,
                echelle: echelleMonde,
                focale: focale,
                distanceCamera: distanceCamera,
                lacet: lacet,
                tangage: tangage
            ) else { continue }

            let r = max(14.0, rayonPourNoeud(noeud, echelle: proj.echelle) + 8.0)
            let dx = point.x - proj.ecran.x
            let dy = point.y - proj.ecran.y
            let dist = hypot(dx, dy)
            if dist <= r {
                candidats.append((noeud, dist, proj.profondeur))
            }
        }
        return candidats.sorted { a, b in
            if abs(a.distance - b.distance) < 6 {
                return a.profondeur < b.profondeur
            }
            return a.distance < b.distance
        }.first?.noeud
    }

    private func positionSurAnneauBranches(angle: Double, rayon: Double) -> SIMD3<Double> {
        let x = cos(angle) * rayon
        let y = sin(angle) * rayon * sin(inclinaisonAnneauBranches)
        let z = sin(angle) * rayon * cos(inclinaisonAnneauBranches)
        return SIMD3<Double>(x, y, z)
    }

    private func positionSurAnneauHarnais(angle: Double) -> SIMD3<Double> {
        let x = decalageXHarnais + cos(angle) * (rayonAnneauHarnais * 0.55)
        let y = sin(angle) * (rayonAnneauHarnais * 0.78)
        let z = cos(angle + 0.65) * (rayonAnneauHarnais * 0.88)
        return SIMD3<Double>(x, y, z)
    }

    // MARK: - Pipeline de rendu Canvas

    func dessiner(
        dans context: inout GraphicsContext,
        taille: CGSize,
        lacet: Double,
        tangage: Double,
        parallaxe: CGPoint,
        temps: TimeInterval,
        idSurvole: String?,
        idSelectionne: String?,
        cheminActif: Set<Int>
    ) {
        let centreEcran = CGPoint(
            x: taille.width * 0.5 + parallaxe.x * 10.0,
            y: taille.height * 0.52 + parallaxe.y * 8.0
        )
        let echelleMonde = min(taille.width, taille.height) * 0.27
        let focale = 3.5
        let distanceCamera = 3.35

        dessinerFondSpatial(&context, taille: taille, parallaxe: parallaxe, temps: temps)

        dessinerOrbite3D(
            &context,
            points3D: anneauBranches,
            centre: centreEcran,
            echelle: echelleMonde,
            focale: focale,
            distanceCamera: distanceCamera,
            lacet: lacet,
            tangage: tangage,
            couleur: Theme.accent.opacity(0.12),
            pointille: false
        )
        if !anneauHarnais.isEmpty {
            dessinerOrbite3D(
                &context,
                points3D: anneauHarnais,
                centre: centreEcran,
                echelle: echelleMonde,
                focale: focale,
                distanceCamera: distanceCamera,
                lacet: lacet,
                tangage: tangage,
                couleur: Theme.border.opacity(0.32),
                pointille: true
            )
        }

        // Projection perspective de tous les nœuds
        var projetes: [PointProjete] = []
        projetes.reserveCapacity(noeuds.count)

        for (indice, noeud) in noeuds.enumerated() {
            let oscillation = indice == 0
                ? 0.0
                : sin(temps * 1.45 + Double(indice) * 0.9) * 0.018
            let posAnimee = SIMD3<Double>(
                noeud.position.x,
                noeud.position.y + oscillation,
                noeud.position.z
            )
            if let p = projeter(
                posAnimee,
                indice: indice,
                centre: centreEcran,
                echelle: echelleMonde,
                focale: focale,
                distanceCamera: distanceCamera,
                lacet: lacet,
                tangage: tangage
            ) {
                projetes.append(p)
            }
        }

        // Tri des liens en profondeur
        let liensTries = liens.sorted { lienA, lienB in
            let profA = (projetes[safe: lienA.source]?.profondeur ?? 0) + (projetes[safe: lienA.cible]?.profondeur ?? 0)
            let profB = (projetes[safe: lienB.source]?.profondeur ?? 0) + (projetes[safe: lienB.cible]?.profondeur ?? 0)
            return profA > profB
        }

        for (idxLien, lien) in liensTries.enumerated() {
            guard
                let ptSource = projetes[safe: lien.source],
                let ptCible = projetes[safe: lien.cible],
                let ptControle = projeter(
                    lien.pointControle,
                    indice: -1,
                    centre: centreEcran,
                    echelle: echelleMonde,
                    focale: focale,
                    distanceCamera: distanceCamera,
                    lacet: lacet,
                    tangage: tangage
                )
            else { continue }

            let estDansChemin = !cheminActif.isEmpty
                && cheminActif.contains(lien.source)
                && cheminActif.contains(lien.cible)

            dessinerLien(
                &context,
                lien: lien,
                indice: idxLien,
                source: ptSource,
                controle: ptControle.ecran,
                cible: ptCible,
                temps: temps,
                surbrillanceChemin: estDansChemin,
                attenuerHorsChemin: !cheminActif.isEmpty && !estDansChemin
            )
        }

        // Tri en profondeur des nœuds (algorithme du peintre : du plus lointain au plus proche)
        let noeudsDuFondAuPremierPlan = projetes.sorted { $0.profondeur > $1.profondeur }

        for item in noeudsDuFondAuPremierPlan {
            let noeud = noeuds[item.indice]
            let estCible = (noeud.identifiant == idSurvole) || (noeud.identifiant == idSelectionne)
            let estDansChemin = cheminActif.contains(item.indice)
            dessinerNoeud(
                &context,
                noeud: noeud,
                projete: item,
                temps: temps,
                estCible: estCible,
                estDansChemin: estDansChemin,
                attenuerHorsChemin: !cheminActif.isEmpty && !estDansChemin
            )
        }

        // Placement des libellés en surimpression nette sans superposition
        var zonesOccupees: [CGRect] = []
        zonesOccupees.reserveCapacity(noeuds.count * 2)

        for item in noeudsDuFondAuPremierPlan.reversed() {
            let noeud = noeuds[item.indice]
            if noeud.categorie == .racine || noeud.categorie == .branche {
                let r = rayonPourNoeud(noeud, echelle: item.echelle)
                zonesOccupees.append(
                    CGRect(
                        x: item.ecran.x - r - 4,
                        y: item.ecran.y - r - 4,
                        width: (r + 4) * 2,
                        height: (r + 4) * 2
                    )
                )
            }
        }

        let ordrePrioriteLibelles = projetes.sorted { a, b in
            let na = noeuds[a.indice]
            let nb = noeuds[b.indice]
            let aCible = (na.identifiant == idSurvole || na.identifiant == idSelectionne)
            let bCible = (nb.identifiant == idSurvole || nb.identifiant == idSelectionne)
            if aCible != bCible { return aCible }
            if na.categorie == .racine { return true }
            if nb.categorie == .racine { return false }
            if na.categorie.rawValue != nb.categorie.rawValue {
                return na.categorie.rawValue < nb.categorie.rawValue
            }
            return a.profondeur < b.profondeur
        }

        for item in ordrePrioriteLibelles {
            let noeud = noeuds[item.indice]
            let estCible = (noeud.identifiant == idSurvole) || (noeud.identifiant == idSelectionne)
            let estDansChemin = cheminActif.contains(item.indice)
            dessinerLibelleSansCollision(
                &context,
                noeud: noeud,
                projete: item,
                tailleCanvas: taille,
                estCible: estCible,
                estDansChemin: estDansChemin,
                zonesOccupees: &zonesOccupees
            )
        }
    }

    // MARK: - Projection perspective 3D

    private func projeter(
        _ point: SIMD3<Double>,
        indice: Int,
        centre: CGPoint,
        echelle: CGFloat,
        focale: Double,
        distanceCamera: Double,
        lacet: Double,
        tangage: Double
    ) -> PointProjete? {
        let cosY = cos(lacet), sinY = sin(lacet)
        let x1 = point.x * cosY + point.z * sinY
        let z1 = -point.x * sinY + point.z * cosY

        let cosP = cos(tangage), sinP = sin(tangage)
        let y2 = point.y * cosP - z1 * sinP
        let z2 = point.y * sinP + z1 * cosP

        let profondeur = distanceCamera + z2
        guard profondeur > 0.35 else { return nil }

        let facteur = focale / profondeur
        let xEcran = centre.x + CGFloat(x1 * facteur) * echelle
        let yEcran = centre.y - CGFloat(y2 * facteur) * echelle

        return PointProjete(
            ecran: CGPoint(x: xEcran, y: yEcran),
            profondeur: profondeur,
            echelle: facteur,
            indice: indice
        )
    }

    // MARK: - Dessin des liens et particules

    private func dessinerLien(
        _ context: inout GraphicsContext,
        lien: Lien3D,
        indice: Int,
        source: PointProjete,
        controle: CGPoint,
        cible: PointProjete,
        temps: TimeInterval,
        surbrillanceChemin: Bool,
        attenuerHorsChemin: Bool
    ) {
        var courbe = Path()
        courbe.move(to: source.ecran)
        courbe.addQuadCurve(to: cible.ecran, control: controle)

        let facteurProfondeur = max(0.30, min(1.18, (source.echelle + cible.echelle) * 0.48))
        var opaciteBase = (lien.actif || surbrillanceChemin ? 0.74 : 0.24) * facteurProfondeur
        if attenuerHorsChemin { opaciteBase *= 0.45 }
        if surbrillanceChemin { opaciteBase = min(1.0, opaciteBase * 1.35) }

        if lien.actif || surbrillanceChemin {
            let haloGradient = Gradient(colors: [
                lien.teinteSource.opacity(opaciteBase * (surbrillanceChemin ? 0.45 : 0.30)),
                lien.teinteCible.opacity(opaciteBase * (surbrillanceChemin ? 0.45 : 0.30))
            ])
            context.stroke(
                courbe,
                with: .linearGradient(
                    haloGradient,
                    startPoint: source.ecran,
                    endPoint: cible.ecran
                ),
                style: StrokeStyle(
                    lineWidth: (surbrillanceChemin ? 5.6 : 4.2) * CGFloat(facteurProfondeur),
                    lineCap: .round
                )
            )
        }

        let degradeLigne = Gradient(colors: [
            lien.teinteSource.opacity(opaciteBase),
            lien.teinteCible.opacity(opaciteBase)
        ])

        let epaisseurBase: CGFloat = surbrillanceChemin ? 2.1 : (lien.pointille ? 1.15 : 1.55)
        let epaisseur: CGFloat = epaisseurBase * CGFloat(facteurProfondeur)
        let styleTrait: StrokeStyle
        if lien.pointille && !surbrillanceChemin {
            let phaseAnimee = lien.actif ? -CGFloat(temps * 22.0) : 0
            styleTrait = StrokeStyle(
                lineWidth: epaisseur,
                lineCap: .round,
                dash: [4.5, 4.5],
                dashPhase: phaseAnimee
            )
        } else {
            styleTrait = StrokeStyle(lineWidth: epaisseur, lineCap: .round)
        }

        context.stroke(
            courbe,
            with: .linearGradient(
                degradeLigne,
                startPoint: source.ecran,
                endPoint: cible.ecran
            ),
            style: styleTrait
        )

        if lien.actif || surbrillanceChemin {
            let totalParticules = max(2, min(3, lien.nombreParticules))
            for idxParticule in 0..<totalParticules {
                let decalage = Double(idxParticule) / Double(totalParticules)
                let phase = Double(indice) * 0.23 + decalage
                let vitesse = surbrillanceChemin ? max(0.75, lien.vitesseFlux * 1.25) : lien.vitesseFlux
                let progression = (temps * vitesse + phase).truncatingRemainder(dividingBy: 1.0)
                let opaciteSinus = sin(progression * Double.pi) * facteurProfondeur

                for etapeTrainee in 1...4 {
                    let tTrainee = max(0.0, progression - Double(etapeTrainee) * 0.024)
                    let ptTrainee = pointBezierQuadratique(
                        a: source.ecran,
                        c: controle,
                        b: cible.ecran,
                        t: tTrainee
                    )
                    let facteurTrainee = Double(5 - etapeTrainee) / 5.0
                    let rayonTrainee = CGFloat(2.5 * facteurTrainee * facteurProfondeur)
                    let rectTrainee = CGRect(
                        x: ptTrainee.x - rayonTrainee,
                        y: ptTrainee.y - rayonTrainee,
                        width: rayonTrainee * 2,
                        height: rayonTrainee * 2
                    )
                    context.fill(
                        Path(ellipseIn: rectTrainee),
                        with: .color(lien.teinteCible.opacity(0.34 * opaciteSinus * facteurTrainee))
                    )
                }

                let ptParticule = pointBezierQuadratique(
                    a: source.ecran,
                    c: controle,
                    b: cible.ecran,
                    t: progression
                )
                let rayonHalo = CGFloat(7.8 * facteurProfondeur)
                let rectHalo = CGRect(
                    x: ptParticule.x - rayonHalo,
                    y: ptParticule.y - rayonHalo,
                    width: rayonHalo * 2,
                    height: rayonHalo * 2
                )
                context.fill(
                    Path(ellipseIn: rectHalo),
                    with: .radialGradient(
                        Gradient(colors: [
                            lien.teinteCible.opacity(0.58 * opaciteSinus),
                            .clear
                        ]),
                        center: ptParticule,
                        startRadius: 0.5,
                        endRadius: rayonHalo
                    )
                )

                let rayonCoeur = CGFloat(2.4 * facteurProfondeur)
                let rectCoeur = CGRect(
                    x: ptParticule.x - rayonCoeur,
                    y: ptParticule.y - rayonCoeur,
                    width: rayonCoeur * 2,
                    height: rayonCoeur * 2
                )
                context.fill(
                    Path(ellipseIn: rectCoeur),
                    with: .color(Color.white.opacity(0.95 * opaciteSinus))
                )
            }
        }
    }

    // MARK: - Dessin des nœuds 3D (halos, anneaux et cœur lumineux)

    private func rayonPourNoeud(_ noeud: Noeud3D, echelle: Double) -> CGFloat {
        let facteur = CGFloat(max(0.52, min(1.48, echelle)))
        let base: CGFloat
        switch noeud.categorie {
        case .racine: base = 24.0
        case .branche: base = 11.5
        case .harnais: base = 9.0
        case .outil: base = 6.8
        case .delegation: base = 5.6
        }
        return base * facteur
    }

    private func dessinerNoeud(
        _ context: inout GraphicsContext,
        noeud: Noeud3D,
        projete: PointProjete,
        temps: TimeInterval,
        estCible: Bool,
        estDansChemin: Bool,
        attenuerHorsChemin: Bool
    ) {
        let proximite = max(0.50, min(1.48, projete.echelle))
        var opaciteProfondeur = max(0.28, min(1.0, (proximite - 0.42) * 1.05))
        if attenuerHorsChemin { opaciteProfondeur *= 0.48 }
        if estDansChemin || estCible { opaciteProfondeur = min(1.0, opaciteProfondeur * 1.25) }

        let respiration: Double
        if noeud.categorie == .racine {
            respiration = 1.0 + 0.08 * sin(temps * 2.1)
        } else if noeud.actif || estCible {
            respiration = 1.0 + 0.075 * sin(temps * 2.8 + Double(projete.indice))
        } else {
            respiration = 1.0
        }

        let multiplicateurCible: CGFloat = estCible ? 1.18 : (estDansChemin ? 1.07 : 1.0)
        let r = rayonPourNoeud(noeud, echelle: projete.echelle) * CGFloat(respiration) * multiplicateurCible
        let centre = projete.ecran

        if noeud.categorie == .racine || noeud.actif || estDansChemin || estCible {
            let rayonBloomExterne = r * (noeud.categorie == .racine ? 3.8 : 3.2)
            let rectBloomExterne = CGRect(
                x: centre.x - rayonBloomExterne,
                y: centre.y - rayonBloomExterne,
                width: rayonBloomExterne * 2,
                height: rayonBloomExterne * 2
            )
            context.fill(
                Path(ellipseIn: rectBloomExterne),
                with: .radialGradient(
                    Gradient(colors: [
                        noeud.teinte.opacity((estCible ? 0.34 : 0.24) * opaciteProfondeur),
                        noeud.teinte.opacity(0.07 * opaciteProfondeur),
                        .clear
                    ]),
                    center: centre,
                    startRadius: r * 0.2,
                    endRadius: rayonBloomExterne
                )
            )

            let rayonBloomInterne = r * 1.95
            let rectBloomInterne = CGRect(
                x: centre.x - rayonBloomInterne,
                y: centre.y - rayonBloomInterne,
                width: rayonBloomInterne * 2,
                height: rayonBloomInterne * 2
            )
            context.fill(
                Path(ellipseIn: rectBloomInterne),
                with: .radialGradient(
                    Gradient(colors: [
                        noeud.teinte.opacity((estCible ? 0.50 : 0.38) * opaciteProfondeur),
                        .clear
                    ]),
                    center: centre,
                    startRadius: r * 0.1,
                    endRadius: rayonBloomInterne
                )
            )
        }

        if noeud.categorie == .racine {
            for idxAnneau in 0..<2 {
                let onde = sin(temps * 1.9 + Double(idxAnneau) * 1.2) * 2.8
                let rayonAnneau = r + CGFloat(8.0 + Double(idxAnneau) * 7.5 + onde)
                let rectAnneau = CGRect(
                    x: centre.x - rayonAnneau,
                    y: centre.y - rayonAnneau,
                    width: rayonAnneau * 2,
                    height: rayonAnneau * 2
                )
                context.stroke(
                    Path(ellipseIn: rectAnneau),
                    with: .color(Theme.accent.opacity((0.30 - Double(idxAnneau) * 0.10) * opaciteProfondeur)),
                    lineWidth: 1.15
                )
            }
        }

        let ecartAnneau: CGFloat = noeud.categorie == .racine ? 4.5 : (estCible ? 4.4 : 3.2)
        let rayonAnneauNoeud = r + ecartAnneau
        let rectAnneauNoeud = CGRect(
            x: centre.x - rayonAnneauNoeud,
            y: centre.y - rayonAnneauNoeud,
            width: rayonAnneauNoeud * 2,
            height: rayonAnneauNoeud * 2
        )
        context.stroke(
            Path(ellipseIn: rectAnneauNoeud),
            with: .color((estCible ? Color.white : noeud.teinte).opacity((estCible ? 0.75 : (noeud.actif ? 0.45 : 0.20)) * opaciteProfondeur)),
            style: StrokeStyle(
                lineWidth: estCible ? 1.6 : (noeud.categorie == .racine ? 1.4 : 1.0),
                dash: (noeud.categorie == .delegation && !estCible) ? [2.5, 2.5] : []
            )
        )

        let rectCorps = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
        let foyerLumiere = CGPoint(x: centre.x - r * 0.28, y: centre.y - r * 0.28)
        context.fill(
            Path(ellipseIn: rectCorps),
            with: .radialGradient(
                Gradient(colors: [
                    noeud.teinte.opacity(0.98 * opaciteProfondeur),
                    noeud.teinte.opacity(0.62 * opaciteProfondeur)
                ]),
                center: foyerLumiere,
                startRadius: r * 0.08,
                endRadius: r * 1.15
            )
        )

        let rayonCoeur = r * (noeud.categorie == .racine ? 0.42 : 0.36)
        let rectCoeur = CGRect(
            x: centre.x - rayonCoeur,
            y: centre.y - rayonCoeur,
            width: rayonCoeur * 2,
            height: rayonCoeur * 2
        )
        context.fill(
            Path(ellipseIn: rectCoeur),
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity((noeud.actif || noeud.categorie == .racine || estCible ? 0.96 : 0.55) * opaciteProfondeur),
                    noeud.teinte.opacity(0.1 * opaciteProfondeur)
                ]),
                center: centre,
                startRadius: 0,
                endRadius: rayonCoeur
            )
        )
    }

    // MARK: - Libellés nets en surimpression (anti-superposition)

    private func dessinerLibelleSansCollision(
        _ context: inout GraphicsContext,
        noeud: Noeud3D,
        projete: PointProjete,
        tailleCanvas: CGSize,
        estCible: Bool,
        estDansChemin: Bool,
        zonesOccupees: inout [CGRect]
    ) {
        let proximite = max(0.50, min(1.48, projete.echelle))
        let opaciteProfondeur = max(0.34, min(1.0, (proximite - 0.42) * 1.08))

        if !estCible && !estDansChemin {
            if (noeud.categorie == .outil || noeud.categorie == .delegation) && opaciteProfondeur < 0.52 {
                return
            }
        }

        let r = rayonPourNoeud(noeud, echelle: projete.echelle)

        let policePrincipale: Font
        let couleurPrincipale: Color
        switch noeud.categorie {
        case .racine:
            policePrincipale = Theme.section(14)
            couleurPrincipale = Theme.textPrimary
        case .branche, .harnais:
            policePrincipale = Theme.body(12, weight: .medium)
            couleurPrincipale = Theme.textPrimary.opacity(estCible ? 1.0 : opaciteProfondeur)
        case .outil, .delegation:
            policePrincipale = Theme.caption(10.5)
            couleurPrincipale = (estCible ? Theme.textPrimary : Theme.textSecondary).opacity(estCible ? 1.0 : opaciteProfondeur)
        }

        let textePrincipal = context.resolve(
            Text(noeud.libelle)
                .font(policePrincipale)
                .foregroundStyle(couleurPrincipale)
        )
        let taillePrincipale = textePrincipal.measure(in: CGSize(width: 185, height: 24))

        let afficherSousLibelle = !noeud.sousLibelle.isEmpty && (
            estCible ||
            noeud.categorie == .racine ||
            noeud.categorie == .harnais ||
            noeud.categorie == .branche ||
            opaciteProfondeur > 0.62
        )

        var texteSecondaireResolu: GraphicsContext.ResolvedText?
        var tailleSecondaire: CGSize = .zero
        if afficherSousLibelle {
            let couleurSousLibelle: Color
            if noeud.categorie == .racine {
                couleurSousLibelle = noeud.actif ? Theme.ok : Theme.textSecondary
            } else if noeud.categorie == .harnais {
                couleurSousLibelle = noeud.actif
                    ? Theme.ok.opacity(opaciteProfondeur)
                    : Theme.textTertiary.opacity(opaciteProfondeur)
            } else {
                couleurSousLibelle = Theme.textTertiary.opacity(opaciteProfondeur)
            }

            let resolu = context.resolve(
                Text(noeud.sousLibelle)
                    .font(Theme.micro())
                    .foregroundStyle(couleurSousLibelle)
            )
            tailleSecondaire = resolu.measure(in: CGSize(width: 170, height: 18))
            texteSecondaireResolu = resolu
        }

        let largeurBloc = max(taillePrincipale.width, tailleSecondaire.width)
        let hauteurBloc = taillePrincipale.height + (afficherSousLibelle ? tailleSecondaire.height + 1 : 0)

        let espacement: CGFloat = r + 7
        let candidats: [CGPoint] = [
            CGPoint(x: projete.ecran.x - largeurBloc * 0.5, y: projete.ecran.y + espacement),
            CGPoint(x: projete.ecran.x - largeurBloc * 0.5, y: projete.ecran.y - espacement - hauteurBloc),
            CGPoint(x: projete.ecran.x + espacement, y: projete.ecran.y - hauteurBloc * 0.5),
            CGPoint(x: projete.ecran.x - espacement - largeurBloc, y: projete.ecran.y - hauteurBloc * 0.5),
            CGPoint(x: projete.ecran.x + espacement * 0.85, y: projete.ecran.y + espacement * 0.85),
            CGPoint(x: projete.ecran.x - espacement * 0.85 - largeurBloc, y: projete.ecran.y + espacement * 0.85)
        ]

        let margeSecurite: CGFloat = 5
        var origineRetenue: CGPoint?

        for candidat in candidats {
            let rectCandidat = CGRect(
                x: candidat.x - margeSecurite,
                y: candidat.y - margeSecurite,
                width: largeurBloc + margeSecurite * 2,
                height: hauteurBloc + margeSecurite * 2
            )
            let dansBornes = rectCandidat.minX >= 16 &&
                rectCandidat.maxX <= tailleCanvas.width - 16 &&
                rectCandidat.minY >= 104 &&
                rectCandidat.maxY <= tailleCanvas.height - 54
            guard dansBornes || noeud.categorie == .racine else { continue }

            let enCollision = zonesOccupees.contains { $0.intersects(rectCandidat) }
            if !enCollision {
                origineRetenue = candidat
                zonesOccupees.append(rectCandidat)
                break
            }
        }

        guard let origine = origineRetenue else { return }

        let xPrincipal = origine.x + (largeurBloc - taillePrincipale.width) * 0.5
        context.draw(textePrincipal, at: CGPoint(x: xPrincipal, y: origine.y), anchor: .topLeading)

        if let secondaire = texteSecondaireResolu {
            let xSecondaire = origine.x + (largeurBloc - tailleSecondaire.width) * 0.5
            let ySecondaire = origine.y + taillePrincipale.height + 1
            context.draw(secondaire, at: CGPoint(x: xSecondaire, y: ySecondaire), anchor: .topLeading)
        }
    }

    // MARK: - Orbites guides et fond spatial

    private func dessinerOrbite3D(
        _ context: inout GraphicsContext,
        points3D: [SIMD3<Double>],
        centre: CGPoint,
        echelle: CGFloat,
        focale: Double,
        distanceCamera: Double,
        lacet: Double,
        tangage: Double,
        couleur: Color,
        pointille: Bool
    ) {
        guard points3D.count > 2 else { return }
        var chemin = Path()
        var premierPoint: CGPoint?

        for pt3D in points3D {
            guard let proj = projeter(
                pt3D,
                indice: -1,
                centre: centre,
                echelle: echelle,
                focale: focale,
                distanceCamera: distanceCamera,
                lacet: lacet,
                tangage: tangage
            ) else { continue }

            if premierPoint == nil {
                premierPoint = proj.ecran
                chemin.move(to: proj.ecran)
            } else {
                chemin.addLine(to: proj.ecran)
            }
        }
        if let debut = premierPoint {
            chemin.addLine(to: debut)
        }

        context.stroke(
            chemin,
            with: .color(couleur),
            style: StrokeStyle(
                lineWidth: 0.9,
                dash: pointille ? [3, 5] : []
            )
        )
    }

    private func dessinerFondSpatial(
        _ context: inout GraphicsContext,
        taille: CGSize,
        parallaxe: CGPoint,
        temps: TimeInterval
    ) {
        let nbParticulesFond = 18
        for i in 0..<nbParticulesFond {
            let graineX = Double((i * 73 + 19) % 100) / 100.0
            let graineY = Double((i * 41 + 53) % 100) / 100.0
            let couche = Double(i % 3 + 1)
            let x = CGFloat(graineX) * taille.width - parallaxe.x * CGFloat(6.0 * couche)
            let y = CGFloat(graineY) * taille.height - parallaxe.y * CGFloat(5.0 * couche)
            let scintillement = 0.35 + 0.35 * sin(temps * 0.9 + Double(i) * 1.4)
            let rayon: CGFloat = CGFloat(0.7 + 0.35 * couche)
            let rect = CGRect(x: x - rayon, y: y - rayon, width: rayon * 2, height: rayon * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Theme.textTertiary.opacity(0.18 * scintillement))
            )
        }
    }

    private func pointBezierQuadratique(a: CGPoint, c: CGPoint, b: CGPoint, t: Double) -> CGPoint {
        let u = 1.0 - t
        let x = u * u * Double(a.x) + 2.0 * u * t * Double(c.x) + t * t * Double(b.x)
        let y = u * u * Double(a.y) + 2.0 * u * t * Double(c.y) + t * t * Double(b.y)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Fonctions utilitaires pures (formatage français sans allocation lourde)

private func textePropre(_ valeur: String) -> String {
    let nettoye = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    return nettoye.isEmpty ? "—" : nettoye
}

private func texteCourt(_ valeur: String, maxCaracteres: Int) -> String {
    let propre = textePropre(valeur)
    guard propre != "—", propre.count > maxCaracteres else { return propre }
    return String(propre.prefix(maxCaracteres - 1)) + "…"
}

private func estEtatActif(_ etat: String) -> Bool {
    let normalise = etat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalise == "active" || normalise == "running" || normalise == "en_cours" || normalise == "in_progress"
}

private func traduireEtatFR(_ etat: String) -> String {
    let normalise = etat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalise.isEmpty else { return "—" }
    switch normalise {
    case "active", "running", "in_progress", "working":
        return "en cours"
    case "idle", "waiting", "pending", "queued":
        return "en attente"
    case "completed", "done", "success", "finished":
        return "terminée"
    case "failed", "error":
        return "erreur"
    default:
        return normalise
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
