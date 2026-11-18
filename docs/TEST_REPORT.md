# Rapport de tests

Dernière exécution : 18 novembre 2026, Mac Apple Silicon (macOS 27.3), Rust 1.94.1, Swift 6.4.2.

## Résultats

| Suite | Tests | Résultat |
|---|---|---|
| `cargo test -p mission-token-core` | 18 (dont 6 alertes) | OK |
| `cargo test -p mission-token-storage` | 3 + 3 cycle de vie + 1 seed | OK |
| `cargo test -p mission-token-collectors` | 3 | OK |
| `cargo test -p mission-token-ffi` | 5 | OK |
| `swift test` | 5 | OK |
| `bash scripts/build.sh` | — | `dist/MissionTokenLive.app` produit |

## Ce que les tests protègent réellement

1. **Aucun coût inventé** : `PricingTable::empty()` → `Reliability::Unavailable`, `amount = None`,
   affichage `—` (`pricing.rs::empty_table_never_invents_a_cost`).
2. **Barème vide par défaut en production** ; le barème de démonstration est marqué `is_demo`.
3. **Adaptateur Hermès** : lit des tokens réels et refuse de fabriquer un coût quand
   `actual_cost_usd`/`estimated_cost_usd` valent 0 (`hermes_adapter_reads_tokens_and_refuses_to_invent_cost`).
4. **Présence ≠ usage** : `desktop_activity_never_reports_usage_data` vérifie qu'aucune métrique
   n'est attachée à ChatGPT/Gemini.
5. **Cycle de vie local** : archivage d'un projet vérifié de bout en bout via la FFI
   (`project_lifecycle_is_local_and_reversible`).
6. **Snapshot FFI** : aller-retour JSON complet, 6 agents / 10 tâches / KPI présents.
7. **Format français** : `12,48 $`, virgule décimale, chiffres tabulaires.
8. **Agrégat de fiabilité** : le pire niveau l'emporte (`worst_reliability_wins`).
9. **Alertes** : seuils 80/90/100 % sans doublon, solde faible uniquement avec un montant réel,
   tâche longue vs médiane de l'agent, échecs répétés, provider indisponible.
10. **Corbeille** : envoi, restauration, non-purge avant 30 jours, purge après expiration,
    et vérification que seules les données internes disparaissent.
11. **Réglages** : aller-retour complet via la FFI (budget 450,50 / 85 / 97 / Dock masqué).

## Bugs trouvés par vérification visuelle et corrigés

| Bug | Cause | Correctif |
|---|---|---|
| Badge « Non disponible » sur un montant affiché | agrégat démarrant au pire niveau | départ à `Réel`, `worst()` explicite |
| « Aucune tâche enregistrée » sur un agent qui en avait une | filtre `status == .running` | dernière tâche tous statuts |
| Base vide au premier lancement | test d'existence du fichier au lieu du contenu | vérification du snapshot |
| `0,00 $` pour un montant sous le centime | arrondi naïf | affichage `< 0,01 $` |

## Non couvert

- Tests UI automatisés (XCUITest) : absents.
- Tests de charge sur une base Hermès de 500 Mo : non mesurés.
- Notarisation / signature Developer ID : non testées (signature ad-hoc).
