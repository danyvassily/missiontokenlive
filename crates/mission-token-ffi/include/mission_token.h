/* MissionTokenLive — pont C (Rust → SwiftUI).
 *
 * Toutes les chaînes renvoyées sont en UTF-8, allouées par Rust, et DOIVENT être
 * libérées avec mtl_free_string(). Un pointeur NULL signale une erreur.
 */
#ifndef MISSION_TOKEN_H
#define MISSION_TOKEN_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

char *mtl_version(void);
void mtl_free_string(char *ptr);

/* 0 = succès, -1 = chemin invalide, -2 = ouverture base, -3 = seed. */
int32_t mtl_seed_demo(const char *db_path);

/* Instantané complet (agents, tâches, timeline, alertes, providers, logiciels, KPI). */
char *mtl_snapshot_json(const char *db_path);

/* Tâches lues dans ~/.hermes/state.db (lecture seule). */
char *mtl_hermes_tasks_json(uint32_t limit);

/* Présence des logiciels : ouvert / fermé uniquement. */
char *mtl_desktop_activity_json(void);

/* Cycle de vie local d'un projet : "archive" | "restore" | "trash" | "purge".
 * 0 = succès, -1 = argument invalide, -2 = base, -3 = opération, -4 = action inconnue. */
int32_t mtl_project_action(const char *db_path, const char *project_id, const char *action);

/* État du cerveau gbrain (lecture seule, JSON). NULL si indisponible. */
char *mtl_brain_json(void);

/* Purge les corbeilles expirées. Renvoie le nombre purgé, ou -1. */
int32_t mtl_sweep_trash(const char *db_path);

/* Réglages en JSON : {"budget":…,"warn":…,"critical":…,"hideDock":…}. NULL si indisponible. */
char *mtl_settings_json(const char *db_path);

/* Enregistre les réglages (budget vide = aucun budget). 0 = succès. */
int32_t mtl_save_settings(const char *db_path, const char *budget, int32_t warn_pct, int32_t critical_pct, int32_t hide_dock);

/* Arborescence de travail (sessions, délégations, harnais) en JSON. NULL si indisponible. */
char *mtl_worktree_json(const char *db_path);

/* Galaxie gbrain : sources, entités et échantillon de faits (JSON, lecture seule). */
char *mtl_galaxy_json(const char *db_path);

/* Chemin par défaut de la base gbrain. */
char *mtl_galaxy_default_path(void);

/* Inventaire des clés connues de ~/.hermes/.env, masquées (JSON). NULL si indisponible. */
char *mtl_keys_json(void);

/* Valeur en clair d'une variable de la liste blanche, pour le Trousseau uniquement.
 * NULL si la variable est inconnue ou vide. Le pointeur doit être libéré par mtl_free. */
char *mtl_key_value(const char *env_var);

#ifdef __cplusplus
}
#endif

#endif /* MISSION_TOKEN_H */
