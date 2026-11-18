# Cahier des charges — MissionTokenLive

## 1. Objet
Cockpit **local-first** macOS qui montre, en temps réel, le travail des agents IA de Dany :
qui travaille, sur quelle tâche, avec quel provider et quel modèle, pour combien de tokens,
pour quel coût — et avec quelle **fiabilité** pour chaque chiffre.

## 2. Utilisateur et contexte d'usage
Dany ouvre la barre de menus dix fois par jour pour savoir « qu'est-ce qui tourne, combien ça
coûte, est-ce que quelque chose bloque ». L'application n'est pas un tableau de bord
analytique : c'est un **poste de contrôle**, consulté en 2 secondes.

## 3. Périmètre fonctionnel (v0.1)
| Domaine | Attendu |
|---|---|
| Maintenant | Hermès en vedette, agents actifs, tâche/durée/provider/modèle/tokens/coût, timeline, alertes |
| Agents | Graphe radial Hermès → sous-agents → outils externes, 4 états |
| Tâches | Liste filtrable (tâche, projet, agent, provider, modèle, durée, tokens, coût, statut) + détail |
| Coûts & usage | Jour / semaine / mois / budget restant, évolution quotidienne, répartitions |
| Providers & solde | Cartes API + solde réel ou « Solde non disponible via API », abonnements séparés |
| Logiciels | Hermès, OpenCode, ChatGPT, Gemini, Antigravity : ouvert / premier plan / arrière-plan / fermé |
| Projets | Actifs, archivés, corbeille 30 jours, recherche, actions locales réversibles |
| Réglages | Budget, seuils, providers, confidentialité, widget de barre de menus |
| Barre de menus | Pilule 4 états + panneau au survol + ouverture de la fenêtre au clic |

## 4. Règle non négociable : la fiabilité
Quatre étiquettes, affichées **à côté de chaque chiffre** :
- **Réel** — montant retourné tel quel par une API officielle (facturation, solde).
- **Calculé** — tokens mesurés × grille tarifaire versionnée et documentée.
- **Estimé** — approximation explicite (moyenne observée, tarif incomplet).
- **Non disponible** — aucune source fiable : on affiche `—`, jamais `0,00 $`.

Un total qui mélange des sources prend l'étiquette la plus faible.

## 5. Ce que l'application ne fait pas
- Elle ne lit pas les conversations, prompts, captures d'écran ni frappes clavier.
- Elle n'invente aucun solde, coût ou compteur de tokens pour ChatGPT et Gemini.
- Elle ne modifie ni Hermès, ni OpenCode, ni un dépôt, ni un fichier projet.
- Elle ne supprime rien en dehors de sa propre base.

## 6. Architecture
```
SwiftUI (MissionTokenLive/)  ──FFI C──>  mission-token-ffi
                                            ├── mission-token-core     (domaine, fiabilité, coût)
                                            ├── mission-token-storage  (SQLite, migrations, repos)
                                            └── mission-token-collectors (Hermès, OpenCode, présence)
```
Un seul chemin de données : le moteur produit un **instantané JSON** (`mtl_snapshot_json`),
l'interface l'affiche. Aucun calcul de coût côté Swift.

## 7. Confidentialité
Local uniquement. Aucune télémétrie, aucun backend. Clés API : Trousseau macOS, jamais
affichées en clair, jamais loggées. Les collecteurs ouvrent les bases en `mode=ro`.

## 8. Critères d'acceptation v0.1
1. L'application se lance en double-clic sur un Mac Apple Silicon (macOS 14+).
2. Elle affiche des données réelles d'Hermès (tokens) et n'affiche un coût que s'il est calculable.
3. Aucun écran ne peut être vide sans explication.
4. `cargo test` et `swift test` passent.
5. Aucun secret dans le dépôt (job CI dédié).
