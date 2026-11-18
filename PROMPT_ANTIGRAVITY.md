# Prompt à donner à Antigravity (Gemini) — MissionTokenLive

Copie tout le bloc ci-dessous dans Antigravity, en ouvrant le dossier `/Users/danyvassily/missiontokenlive`.

---

Tu es ingénieur macOS senior (SwiftUI, Rust, SQLite) et designer d'interfaces. Tu travailles sur **MissionTokenLive**, une application macOS native de contrôle local du travail des agents IA. Le dépôt est à jour sur `main` (dernier commit `86712b5`), les tests passent, l'app se construit. Ta mission : **refondre la vue « Flux » en une arborescence 3D premium**, puis **polir les écrans** sans jamais casser l'existant.

## 1. Contexte produit

L'app observe, en local uniquement, ce que font les agents IA sur cette machine : sessions Hermès, tâches, sous-agents délégués, outils utilisés, providers et leurs soldes réels, et un « cerveau » partagé (gbrain) qui indexe les notes de Dany.

Règles absolues, non négociables :

1. **Aucune donnée inventée.** Un token, un coût, un solde non disponible doit afficher « Non disponible » avec son étiquette (`Réel`, `Calculé`, `Estimé`, `Non disponible`). Jamais de zéro de complaisance, jamais de chiffre décoratif.
2. **Aucun secret affiché, journalisé, exporté ou commité.** Pas de clé API, pas de jeton, pas de contenu de conversation.
3. **Interface intégralement en français**, sans emoji, ton sobre et professionnel.
4. **Local-first.** Aucun appel réseau sauf les endpoints de solde déjà branchés (dans `Balances.swift`), et seulement sur action de l'utilisateur.
5. **Ne casse rien.** `cargo test`, `swift test` et `./scripts/build.sh` doivent rester verts à la fin.

## 2. Stack et commandes

- `crates/mission-token-core` : domaine pur (fiabilité, argent, prix, alertes).
- `crates/mission-token-storage` : SQLite, migrations, corbeille 30 jours, réglages.
- `crates/mission-token-collectors` : lecture de `~/.hermes/state.db` en lecture seule.
- `crates/mission-token-ffi` : pont C (`mtl_*`), expose snapshot, réglages, cerveau, arborescence, clés.
- `MissionTokenLive/` : app SwiftUI (SPM), cible macOS 14+, Apple Silicon.
- Build : `./scripts/build.sh` → `dist/MissionTokenLive.app`
- DMG : `./scripts/make_dmg.sh` → `dist/MissionTokenLive-0.1.0.dmg`
- Tests : `cargo test` (29 tests) et `swift test` (5 tests)
- Capturer un écran précis : `open -n --env MTL_SCREEN=flux dist/MissionTokenLive.app` (valeurs : `now, agents, flux, tasks, costs, providers, software, projects, brain, settings`)

## 3. Mission principale : la vue « Flux » en 3D

Fichier à refondre : `MissionTokenLive/Features/Flux/WorkTree3D.swift` (et `FluxView.swift` si nécessaire).

L'objectif de Dany, mot pour mot : « je veux vraiment ressentir une synergie de travail entre Hermès, les agents qu'il crée, ce que OpenCode ou Gemini fait, sur quelle tâche il travaille — une arborescence de travail avec une magnifique animation 3D premium ».

### Données déjà disponibles (ne les invente pas, utilise-les)

`AppStore.worktree` de type `WorkTree` (défini dans `Models/WorkTreeModels.swift`, produit par `mtl_worktree_json`) :

```swift
WorkTree { available: Bool, rootLabel: String, runningTasks: Int, activeSessions: Int,
           branches: [WorkBranch], harnesses: [WorkHarness] }
WorkBranch { id, title, project, state ("active" | "idle"), messages: Int,
             tools: [WorkTool], delegations: [WorkDelegation] }
WorkTool { name: String, count: Int }              // outils réellement utilisés, avec compteurs
WorkDelegation { id, goal, state }                 // sous-agents délégués par Hermès
WorkHarness { name, detail, active: Bool }         // OpenCode, Gemini CLI, Antigravity, Codex
```

Si tu as besoin de plus de données (par exemple le modèle utilisé par branche, ou la durée), **étends le schéma côté Rust** (`crates/mission-token-ffi/src/worktree.rs`) et le modèle Swift en gardant la cohérence des noms (serde `rename_all = "camelCase"`), puis vérifie avec `cargo test`.

### Direction artistique attendue

- **Vraie 3D perçue** : projection perspective, caméra qui tourne lentement, parallaxe, profondeur visible (les nœuds lointains plus petits et plus sombres).
- **Premium** : halos lumineux, bloom simulé, liens en dégradé, particules qui circulent le long des arêtes, nœuds avec anneau et cœur brillant. Palette existante : fond `#0A0C0F`, accent `#4C8DFF`, vert `#34C88A`, via `Theme.*`.
- **Lisibilité avant spectaculaire** : les libellés ne doivent jamais se superposer ; taille de police fixe (pas de mise à l'échelle perspective) ; troncature propre avec ellipse.
- **Hiérarchie lisible en un regard** : Hermès → sessions → (outils + délégations) → harnais externes.
- 60 fps : `TimelineView(.animation(minimumInterval: 1.0/60.0))` et **un seul** `Canvas`. Pas d'allocation lourde par image, pas de `NSViewRepresentable`, pas de SceneKit, pas de Metal, pas de dépendance externe.

### Défauts connus du rendu actuel (à corriger)

1. Les libellés de branches se chevauchent quand deux branches passent au même endroit à l'écran.
2. Trop de nœuds pour la fenêtre : 7 branches × 3 outils + délégations + 5 harnais. Prévois un délestage intelligent (par exemple : n'afficher les outils que des branches actives, ou regrouper en un nœud « +3 »).
3. Rotation trop lente (0,075 rad/s) : on ne « sent » pas le travail. Donne du rythme, avec une respiration sur les nœuds actifs.
4. Aucune interaction : ajoute au minimum le survol (mise en évidence du chemin Hermès → nœud) et le clic (panneau latéral avec détail réel : titre, projet, outils, compteurs, état des délégations).

### Critères d'acceptation

- L'écran Flux affiche l'arborescence réelle au lancement, sans état vide alors que des sessions existent.
- Aucun texte ne se chevauche à 1280×800 comme à 2560×1440.
- L'animation reste fluide (aucune saccade visible) et tourne sans intervention.
- `tree.available == false` ou `branches.isEmpty` → état vide propre, centré, en français.
- Aucune valeur affichée qui ne vienne de `WorkTree`.

## 4. Missions secondaires (dans cet ordre)

1. **Tâches** : la page défile désormais et propose Aujourd'hui / 7 jours / 30 jours / Tout. Ajoute le tri par colonne (date, durée, tokens, statut) et un compteur par statut dans les puces de filtre.
2. **Providers** : ajoute un rafraîchissement automatique des soldes au lancement (une seule fois, silencieux) et l'horodatage « interrogé il y a X min ».
3. **Cerveau** : rends la carte « Accès et couverture » repliable, et filtre les lignes de structure de `PEOPLE/*.md` qui polluent aujourd'hui la recherche gbrain (lignes commençant par `>`, titres, mentions « USAGE INTERNE »).
4. **Réglages** : vérifie que le budget accepte la virgule décimale et que le masquage du Dock survit à un redémarrage de l'app.

## 5. Méthode de travail imposée

- Travaille **sur une branche** `feat/flux-3d-premium`, jamais directement sur `main`, et fais des commits atomiques en français.
- **Ne crée pas de worktree git** et **ne lance aucune tâche d'arrière-plan** : l'agent Antigravity s'est déjà bloqué deux fois sur ce projet à cause de tâches d'arrière-plan restées en suspens.
- Après chaque étape : `cargo test`, `swift test`, `./scripts/build.sh`. Si le build casse, corrige avant de continuer.
- Capture d'écran de vérification obligatoire : `MTL_SCREEN=flux` puis `screencapture`, et vérifie visuellement le résultat avant de déclarer terminé.
- Ne modifie pas : `Theme.swift` (sauf ajout de couleur), `Balances.swift` (sauf mission 2), les migrations SQL existantes, ni `scripts/build.sh` / `scripts/make_dmg.sh`.
- Ne touche à aucun fichier en dehors du dépôt. Ne pousse rien sur GitHub : laisse la branche locale prête.

## 6. Livrable final

Un court `RAPPORT_FLUX3D.md` à la racine contenant : ce qui a été fait, ce qui a été mesuré (fps approximatif, nombre de nœuds, tailles d'écran testées), ce qui reste imparfait, et les commandes exactes pour lancer et vérifier. Sois honnête : si une partie n'est pas terminée, écris-le.
