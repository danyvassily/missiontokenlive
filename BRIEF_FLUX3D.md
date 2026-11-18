# Mission : écrire une vue SwiftUI 3D premium de l'arborescence de travail

Fichier à écrire (et SEUL fichier à modifier) :
`MissionTokenLive/Features/Flux/WorkTree3D.swift`

Interdit : modifier Theme.swift, AppStore.swift, EngineBridge.swift, les modèles. Ne pas lancer de tâche d'arrière-plan. Ne pas toucher au reste du dépôt.

## Contexte produit
Application macOS native (SwiftUI, macOS 14, Apple Silicon) qui observe le travail des agents IA.
Écran « Flux » : on veut **ressentir une synergie de travail** entre Hermès, les sessions qu'il ouvre,
les sous-agents qu'il délègue, les outils qu'il utilise (terminal, execute_code, vision…) et les harnais
externes (OpenCode, Gemini CLI, Antigravity, Codex) avec leur état réel.

## Données disponibles (déjà décodées, NE PAS redéfinir)
```swift
struct WorkTree { let available: Bool; let rootLabel: String; let runningTasks: Int
                  let activeSessions: Int; let branches: [WorkBranch]; let harnesses: [WorkHarness] }
struct WorkBranch { let id, title, project, state: String; let messages: Int
                    let tools: [WorkTool]; let delegations: [WorkDelegation] }  // state == "active" | "idle"
struct WorkTool { let name: String; let count: Int }
struct WorkDelegation { let id, goal, state: String }
struct WorkHarness { let name, detail: String; let active: Bool }
```
Signature attendue : `struct WorkTree3DView: View { let tree: WorkTree; var body: some View }`

## Palette et typo (API existante, à utiliser telle quelle)
`Theme.bg` (fond très sombre), `Theme.surface`, `Theme.border`, `Theme.borderSoft`,
`Theme.accent` (#4C8DFF), `Theme.ok` (#34C88A), `Theme.warn`, `Theme.error`,
`Theme.textPrimary`, `Theme.textSecondary`, `Theme.textTertiary`.
Polices : `Theme.title()`, `Theme.section(14)`, `Theme.body(12)`, `Theme.body(12, weight: .medium)`,
`Theme.caption(10.5)`, `Theme.micro()`.

## Direction artistique (impératif)
- **Vraie 3D perçue** : projection perspective maison (pas SceneKit), rotation lente autour de l'axe Y,
  tri en profondeur (peintre), taille et opacité modulées par la distance, parallaxe légère à la souris.
- **Premium** : halos radiaux, traînées lumineuses, particules qui circulent le long des liens,
  lignes en dégradé, nœuds avec anneau + cœur lumineux, léger bloom simulé par dégradés superposés.
- **Lisibilité** : libellés courts, jamais superposés ; les nœuds du fond sont atténués ; le texte reste
  en surimpression nette (taille fixe, pas de mise à l'échelle perspective pour les libellés).
- **Français**, aucun emoji, aucun texte anglais.
- Animations fluides 60 fps : `TimelineView(.animation(minimumInterval: 1.0/60.0))` + un seul `Canvas`.
  Aucune allocation lourde par frame (pas de `NumberFormatter`, pas de tri de milliers d'éléments).

## Structure de l'arborescence
1. **Racine** : Hermès, sphère lumineuse au centre, respiration lente, affiche `runningTasks` en cours.
2. **Branches (niveau 1)** : une par session (`tree.branches`, max 7), réparties sur un anneau incliné
   en 3D (rayon ~1.0), couleur `Theme.ok` si `state == "active"`, `Theme.textTertiary` sinon.
3. **Niveau 2** : pour chaque branche, ses `tools` (max 3) en éventail vers l'extérieur, et ses
   `delegations` (max 2) en nœuds plus petits, avec un lien en pointillés animé.
4. **Harnais (niveau latéral)** : `tree.harnesses` sur un anneau vertical décalé, halo vert si actif,
   gris si inactif ; libellé = nom, sous-libellé = état (« actif » / « inactif »).
5. **Particules** : 2 à 3 points par lien actif, progression continue, opacité en sinus.
6. **HUD** (en surimpression, pas dans la scène) : en haut à gauche « Arborescence de travail » +
   compteurs (`activeSessions` sessions actives, `runningTasks` tâches en cours, `branches.count` branches),
   en bas à droite une légende discrète. Un bouton « Recentrer » (icône `arrow.counterclockwise`) remet
   l'angle à zéro avec animation.

## Contraintes techniques
- Un seul fichier, import SwiftUI uniquement (+ Foundation, CoreGraphics si besoin).
- Pas de dépendance externe, pas de `NSViewRepresentable`, pas de SceneKit, pas de Metal.
- Doit compiler sans warning avec `swift build`.
- Gérer `tree.available == false` et `tree.branches.isEmpty` par un état vide propre et centré.
- Aucune donnée inventée : si une valeur manque, afficher un tiret.

## Livrable
Écrire le fichier complet, prêt à compiler, avec des commentaires courts en français expliquant
la projection 3D, le tri en profondeur et la boucle d'animation.
