# Limitations connues

## Données
1. **Aucun coût réel dans Hermès.** `session_model_usage.estimated_cost_usd` et `actual_cost_usd`
   valent `0.0`, avec `cost_status ∈ {unknown, estimated}` et `cost_source = none`. Toute valeur
   monétaire est donc `Calculé` (barème) ou `Non disponible`.
2. **Le barème livré est un barème de démonstration** (`demo-2026.11`, `is_demo = true`). Il ne doit
   pas être présenté comme un tarif officiel ; l'interface l'indique via `pricing_version`.
3. **Soldes providers non interrogés.** Les adaptateurs existent mais restent inactifs : aucun appel
   réseau, aucune clé lue, donc `Non disponible`.
4. **ChatGPT et Gemini** (abonnements) n'exposent aucun compteur local : présence uniquement.
5. **Sous-agents** : le mapping repose sur `sessions`/`async_delegations`. Un changement de schéma
   d'Hermès casse silencieusement la hiérarchie (les agents apparaissent alors à plat).

## Technique
6. **Pas de Dynamic Island** : `NSStatusItem` + panneau flottant, l'encoche n'accepte pas d'app tierce.
7. **Détection au premier plan** dépend de `NSWorkspace`, pas de l'activité réelle.
8. **Pont FFI** : les chaînes renvoyées par Rust doivent être libérées par `mtl_free_string` —
   tout oubli fuit. Aucune exception ne traverse la frontière (les panics sont rattrapés).
9. **Base locale non chiffrée** : elle ne contient pas de secret, mais reste lisible par l'utilisateur
   et par tout processus du même compte.
10. **Pas de signature Developer ID** : l'application est signée ad-hoc (`codesign -s -`), Gatekeeper
    demandera une confirmation au premier lancement.
11. **SwiftUI `MenuBarExtra`** ne permet pas de dessiner complètement la pilule ; le rendu exact de la
    maquette (halo, ombre) est approximé par le libellé système.

## Produit
12. **Historique limité** : l'application ne rejoue pas les données antérieures à sa première collecte.
13. **Pas d'export** ni de synchronisation multi-Mac.
14. **Aucune suppression externe** : la corbeille ne concerne que la fiche locale, jamais un dépôt.
