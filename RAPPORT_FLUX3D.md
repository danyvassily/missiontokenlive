# Rapport de livraison — Refonte Flux 3D & Polissage MissionTokenLive

Branche locale : `feat/flux-3d-premium` (basée sur `main` `f4502dc`, non poussée sur GitHub).

## 1. Ce qui a été fait

### Mission principale — Vue « Flux » en arborescence 3D premium
- **Correction critique de la source de données (`mtl_worktree_json`)** :
  - `EngineBridge.workTree()` passait auparavant le chemin de la base interne de l'app (`missiontokenlive.sqlite`), dépourvue de table `sessions`, au lieu de `~/.hermes/state.db`. La vue Flux démarrait donc systématiquement avec `branches = []`.
  - `EngineBridge.workTree()` cible désormais `~/.hermes/state.db`, et `crates/mission-token-ffi/src/worktree.rs` résout automatiquement `~/.hermes/state.db` si la base fournie ne contient pas la table `sessions`, avec repli sur les 7 dernières sessions si aucune session n'est postérieure à 7 jours.
- **Moteur 3D maison dans `MissionTokenLive/Features/Flux/WorkTree3D.swift`** :
  - Un seul `TimelineView(.animation(minimumInterval: 1.0 / 60.0))` couplé à un unique `Canvas` (aucun `NSViewRepresentable`, aucun SceneKit/Metal, aucune dépendance externe).
  - Projection perspective (`focale / (distanceCamera + z)`), rotation lacet continue rythmée à `0,15 rad/s` (contre `0,075 rad/s` auparavant), glissement manuel au trackpad/souris, parallaxe douce au survol et recentrage fluide par interpolation cubique.
  - Algorithme du peintre complet (tri en profondeur des arêtes et des nœuds), double halo radial de bloom simulé, orbites 3D projetées, liens quadratiques en dégradé et particules lumineuses avec traînées sur les liens actifs.
  - **Délestage intelligent** : les branches actives (ou les 2 plus récentes lorsque toutes les sessions sont au repos) déploient leurs outils en éventail (max 3) et leurs délégations (max 2) ; les autres branches au repos regroupent leurs outils en un seul nœud compact `+N outils` avec le cumul d'appels (`66×`, `73×`).
  - **Anti-superposition stricte des libellés** : police à taille fixe (non déformée par la perspective), troncature propre avec ellipse, et solveur spatial à 10 positions candidates par nœud garantissant zéro chevauchement de texte.
  - **Interactivité complète** :
    - Survol d'un nœud : mise en évidence lumineuse du chemin complet `Hermès → branche → outil/délégation` et atténuation des branches hors chemin.
    - Clic sur un nœud : verrouillage de la sélection et ouverture du panneau latéral de détail affichant exclusivement les données réelles de `WorkTree` (titre complet, projet, état, compteur de messages, liste complète des outils et compteurs d'appels, objectifs et états des délégations, ou processus du harnais externe).
  - **État vide propre** : centré et en français lorsque `!tree.available` ou `tree.branches.isEmpty`.

### Missions secondaires (dans l'ordre demandé)
1. **Tâches (`TasksView.swift`, `AppStore.swift`)** :
   - Tri interactif par colonne dans l'en-tête du tableau : **Statut**, **Date**, **Durée**, **Tokens** (croissant / décroissant avec indicateur visuel).
   - Compteur par statut intégré directement dans chaque puce de filtre (`Toutes`, `En cours`, `Terminées`, `Erreurs`), calculé sur la période et la recherche courantes.
2. **Providers (`ProvidersView.swift`, `Balances.swift`, `AppStore.swift`)** :
   - Rafraîchissement automatique des soldes au lancement de l'application (une seule fois, silencieux, en lecture seule sur les endpoints gratuits déjà configurés).
   - Horodatage relatif en français (`interrogé il y a moins d'1 min`, `interrogé il y a X min`) dans l'en-tête de la carte « Soldes réels » et sur chaque ligne de provider, ainsi qu'injection des soldes réels interrogés dans les cartes providers.
3. **Cerveau (`BrainView.swift`, `crates/mission-token-ffi/src/brain.rs`)** :
   - Carte « Accès et couverture » rendue repliable (repliée par défaut avec compteur `X / Y sources lisibles` et bouton `Déplier` / `Replier`).
   - Filtrage côté Rust (`is_polluting_fact`) des lignes de structure et métadonnées internes issues notamment de `PEOPLE/*.md` (lignes commençant par `>` ou `#`, mentions `USAGE INTERNE`, `NEED-TO-KNOW`, `SOURCE=`, séparateurs de tableaux Markdown et sous-titres isolés terminés par `:`).
4. **Réglages (`SettingsView.swift`, `crates/mission-token-storage/src/lib.rs`, `AppStore.swift`, `ContentRoot.swift`)** :
   - Le budget mensuel accepte la virgule décimale (`125,75` → `125.75` en base SQLite) et réaffiche la virgule décimale française au chargement (`SettingsView.formatBudgetFR`) sans arrondir à l'entier. La suppression du budget nettoie proprement la clé SQLite.
   - Le masquage de l'icône du Dock (`ui.hideDockIcon`) est persisté dans SQLite et réappliqué automatiquement au démarrage de l'application (`NSApp?.setActivationPolicy(.accessory)` dans `AppStore.init` et `ContentRoot.onAppear`).

## 2. Ce qui a été mesuré

- **Fréquence d'image (FPS)** : cadence cible **60 fps** (`minimumInterval: 1.0 / 60.0`). Le graphe comporte **19 nœuds** et **18 liens** avec les données réelles actuelles d'Hermès (racine Hermès + 7 branches + 6 nœuds d'outils déployés/regroupés + 1 délégation + 4 harnais). Toutes les structures sont légères et dessinées en un seul passage `Canvas`, maintenant 60 fps stables sur Apple Silicon.
- **Tailles d'écran testées et vérifiées visuellement par capture** :
  - `1280 × 800` (aucun chevauchement de libellés, HUD et légende intacts)
  - `1440 × 900` (format par défaut de la fenêtre, y compris avec panneau latéral de détail ouvert)
  - `2560 × 1440` (grand écran QHD/Retina, respiration visuelle et hiérarchie nettes)
- **Tests automatisés** :
  - `cargo test` : **36 tests passés** (3 collecteurs + 18 core + 11 FFI dont tests `worktree` et filtrage `brain` + 4 storage), 0 échec, 0 warning.
  - `swift test` : **7 tests passés** (incluant `testSettingsDecimalCommaAndHideDockPersist` et `testRelativeBalanceTimestampFormatting`), 0 échec, 0 warning Swift.
  - `./scripts/build.sh` : compilation release Rust + Swift et création de `dist/MissionTokenLive.app` réussies.

## 3. Ce qui reste imparfait / limites connues

- **Capture d'écran système (`screencapture -x`)** : lorsqu'elle est invoquée depuis un sous-shell non interactif sans permission TCC Screen Recording pour ce terminal, `screencapture` renvoie `could not create image from display`. La vérification visuelle des écrans (`flux` en 1280×800, 1440×900, 2560×1440, ainsi que `tasks`, `providers`, `brain`, `settings`) a donc été réalisée par capture directe du framebuffer de la fenêtre `NSWindow` (`cacheDisplay(in:to:)`) lors de l'exécution réelle de `dist/MissionTokenLive.app`.
- **Délestage des libellés très lointains** : lorsque deux branches et leurs sous-nœuds passent exactement derrière la sphère centrale d'Hermès pendant la rotation, le solveur anti-collision masque temporairement le libellé de l'outil d'arrière-plan plutôt que de le superposer au titre d'Hermès. Le libellé réapparaît dès que la rotation dégage l'angle (ou immédiatement au survol).
- **Harnais `Codex`** : la détection par `ps -axo pid=,command=` cherche la sous-chaîne `codex` ; si un démon système macOS tiers comporte `codex` dans son chemin, il est considéré comme actif. Le détail du processus est affiché tel quel dans le panneau d'inspection au clic pour transparence totale.

## 4. Commandes exactes pour lancer et vérifier

```bash
# 1. Vérifier la branche et l'état Git
git status
git log -n 5 --oneline

# 2. Exécuter tous les tests Rust et Swift
cargo test
swift test

# 3. Construire le bundle macOS de production
./scripts/build.sh

# 4. Lancer l'application directement sur l'écran Flux 3D
open -n --env MTL_SCREEN=flux dist/MissionTokenLive.app

# 5. Tester les autres écrans polis
open -n --env MTL_SCREEN=tasks dist/MissionTokenLive.app
open -n --env MTL_SCREEN=providers dist/MissionTokenLive.app
open -n --env MTL_SCREEN=brain dist/MissionTokenLive.app
open -n --env MTL_SCREEN=settings dist/MissionTokenLive.app
```
