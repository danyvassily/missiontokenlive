# Confidentialité et limites techniques

## 1. Sources réellement accessibles

| Source | Chemin | Mode | Ce qui est lu | Écriture |
|---|---|---|---|---|
| Hermès (sessions, usage) | `~/.hermes/state.db` | `ro` | `session_model_usage`, `sessions` (compteurs, modèle, provider, dates) | jamais |
| OpenCode | `~/.local/share/opencode/opencode.db` | `ro` | nombre de sessions, compteurs | jamais |
| Présence des applications | `NSWorkspace` | — | nom, bundle id, état au premier plan | jamais |
| Base MissionTokenLive | `~/Library/Application Support/MissionTokenLive/` | `rw` | tout ce que l'app stocke | oui (seule base écrite) |
| Trousseau | `mtl.provider.*` | rw | référence de clé uniquement | oui, sur action explicite |

## 2. Ce qui n'est jamais lu
- Le **contenu** des messages, prompts, réponses et pièces jointes.
- Les **captures d'écran**, la frappe clavier, le presse-papiers, la position GPS.
- Les **conversations** ChatGPT, Gemini, Antigravity et OpenCode.
- Les fichiers des projets : l'application ne connaît qu'un chemin observé, jamais son contenu.

## 3. Ce qui n'est pas disponible — et restera absent
| Donnée | Pourquoi | Affichage |
|---|---|---|
| Coût réel par session Hermès | `estimated_cost_usd` / `actual_cost_usd` valent `0.0`, `cost_source = none` | `Non disponible` |
| Solde OpenRouter / DeepSeek | nécessite un appel API authentifié, désactivé par défaut | `Non disponible`, bouton « activer » explicit |
| Tokens ChatGPT / Gemini (abonnement) | aucune API officielle ne les expose localement | présence seulement |
| Crédits Antigravity | pas d'endpoint public | présence seulement |

## 4. Permissions macOS
| Permission | Nécessaire ? | Justification |
|---|---|---|
| Accessibilité | **non** | aucune lecture d'UI tierce, aucun événement clavier |
| Enregistrement d'écran | **non** | jamais de capture |
| Accès complet au disque | **non** | seuls les chemins listés ci-dessus |
| Notifications | oui (facultatif) | alertes locales uniquement |
| Réseau sortant | **désactivé par défaut** | uniquement si l'utilisateur active un connecteur de solde |

## 5. Limites connues
- **Pas de Dynamic Island** sur macOS : la pilule vit dans la barre de menus, avec un panneau
  flottant. L'encoche ne peut pas héberger d'application tierce.
- **Détection au premier plan** : fiable via `NSWorkspace`, mais ne dit rien de l'activité réelle
  de l'application (une fenêtre ouverte peut être inactive).
- **Sous-agents Hermès** : déduits des sessions et des délégations ; l'API interne peut évoluer
  et casser le mapping (voir `docs/KNOWN_LIMITATIONS.md`).
- **Barème tarifaire** : livré vide en production. Tant qu'aucun barème validé n'est fourni,
  les coûts restent `Non disponible` — c'est voulu.
- **Pas d'historique antérieur** à l'installation : l'application ne rejoue pas le passé.
