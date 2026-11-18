# Feuille de route

## v0.1 — socle (fait)
- Domaine Rust, fiabilité, moteur de coût, SQLite, migrations, repos.
- Collecteurs Hermès/OpenCode/présence en lecture seule.
- Pont C + snapshot JSON, 8 écrans SwiftUI, pilule de barre de menus.
- Tests Rust + Swift, CI.

## v0.2 — données réelles
- Agent A : snapshot Hermès réel (tokens), mode démo derrière `MTL_DEMO=1`.
- Connecteurs de solde OpenRouter/DeepSeek, désactivés par défaut, activation explicite.
- Détection de présence via `NSWorkspace`.

## v0.3 — projets et alertes
- Agent B : moteur d'alertes (budget 80/90/100 %, solde, tâche longue, échecs répétés, provider indisponible).
- Corbeille 30 jours + purge automatique, persistance des réglages.

## v0.4 — finition visuelle
- Agent C : fidélité à la maquette FigCraft, états vides/chargement/erreur, accessibilité, survol du widget.

## v0.5 — avant diffusion
- Barème tarifaire validé par l'utilisateur (source officielle, versionnée).
- Notifications locales, lancement au démarrage, signature Developer ID + notarisation.
- Export CSV des coûts, mode « semaine » et « mois » sur tous les écrans.

## Idées non planifiées
- Intégration OpenCode en profondeur (coût par session).
- Vue « projets » avec graphe de dépendances.
- Widgets bureau (WidgetKit).
