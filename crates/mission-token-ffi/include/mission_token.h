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

#ifdef __cplusplus
}
#endif

#endif /* MISSION_TOKEN_H */
