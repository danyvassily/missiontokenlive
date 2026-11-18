-- MissionTokenLive — schéma local (SQLite).
-- Aucune donnée personnelle externe : uniquement ce que l'application observe localement.

CREATE TABLE IF NOT EXISTS schema_migrations (
    version     INTEGER PRIMARY KEY,
    applied_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS agents (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    kind            TEXT NOT NULL,
    status          TEXT NOT NULL,
    parent_id       TEXT REFERENCES agents(id),
    provider        TEXT,
    model           TEXT,
    current_task_id TEXT,
    color_key       TEXT NOT NULL DEFAULT 'accent/blue',
    started_at      TEXT
);

CREATE TABLE IF NOT EXISTS projects (
    id               TEXT PRIMARY KEY,
    name             TEXT NOT NULL,
    path             TEXT,
    status           TEXT NOT NULL DEFAULT 'active',
    budget_usd       REAL,
    created_at       TEXT NOT NULL,
    archived_at      TEXT,
    purge_after      TEXT,
    last_activity_at TEXT
);

CREATE TABLE IF NOT EXISTS providers (
    id                    TEXT PRIMARY KEY,
    name                  TEXT NOT NULL,
    kind                  TEXT NOT NULL,
    availability          TEXT NOT NULL,
    active_model          TEXT,
    cost_today_amount     REAL,
    cost_today_reliability TEXT NOT NULL DEFAULT 'unavailable',
    cost_today_source     TEXT NOT NULL DEFAULT '',
    balance_amount        REAL,
    balance_reliability   TEXT NOT NULL DEFAULT 'unavailable',
    balance_source        TEXT NOT NULL DEFAULT '',
    balance_alert_pct     INTEGER NOT NULL DEFAULT 20,
    keychain_ref          TEXT,
    note                  TEXT
);

CREATE TABLE IF NOT EXISTS tasks (
    id                    TEXT PRIMARY KEY,
    title                 TEXT NOT NULL,
    project_id            TEXT REFERENCES projects(id),
    agent_id              TEXT REFERENCES agents(id),
    provider              TEXT,
    model                 TEXT,
    status                TEXT NOT NULL,
    started_at            TEXT NOT NULL,
    ended_at              TEXT,
    tokens_input          INTEGER NOT NULL DEFAULT 0,
    tokens_output         INTEGER NOT NULL DEFAULT 0,
    tokens_cache_read     INTEGER NOT NULL DEFAULT 0,
    tokens_cache_write    INTEGER NOT NULL DEFAULT 0,
    tokens_reasoning      INTEGER NOT NULL DEFAULT 0,
    cost_amount           REAL,
    cost_reliability      TEXT NOT NULL DEFAULT 'unavailable',
    cost_source           TEXT NOT NULL DEFAULT '',
    cost_pricing_version  TEXT,
    error                 TEXT
);
CREATE INDEX IF NOT EXISTS idx_tasks_started ON tasks(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);

CREATE TABLE IF NOT EXISTS events (
    id                    TEXT PRIMARY KEY,
    at                    TEXT NOT NULL,
    agent_name            TEXT NOT NULL,
    kind                  TEXT NOT NULL,
    message               TEXT NOT NULL,
    tokens_input          INTEGER NOT NULL DEFAULT 0,
    tokens_output         INTEGER NOT NULL DEFAULT 0,
    tokens_cache_read     INTEGER NOT NULL DEFAULT 0,
    tokens_cache_write    INTEGER NOT NULL DEFAULT 0,
    tokens_reasoning      INTEGER NOT NULL DEFAULT 0,
    cost_amount           REAL,
    cost_reliability      TEXT NOT NULL DEFAULT 'unavailable',
    cost_source           TEXT NOT NULL DEFAULT '',
    cost_pricing_version  TEXT,
    task_id               TEXT,
    running               INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_events_at ON events(at DESC);

CREATE TABLE IF NOT EXISTS alerts (
    id            TEXT PRIMARY KEY,
    level         TEXT NOT NULL,
    title         TEXT NOT NULL,
    detail        TEXT NOT NULL,
    created_at    TEXT NOT NULL,
    acknowledged  INTEGER NOT NULL DEFAULT 0,
    action_label  TEXT
);
CREATE INDEX IF NOT EXISTS idx_alerts_created ON alerts(created_at DESC);

CREATE TABLE IF NOT EXISTS software (
    id              TEXT PRIMARY KEY,
    app             TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    version         TEXT,
    state           TEXT NOT NULL,
    since_seconds   INTEGER NOT NULL DEFAULT 0,
    presence_only   INTEGER NOT NULL DEFAULT 1,
    note            TEXT
);

CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Corbeille locale : on ne supprime jamais le projet source, seulement la fiche.
CREATE TABLE IF NOT EXISTS trash (
    project_id   TEXT PRIMARY KEY,
    trashed_at   TEXT NOT NULL,
    purge_after  TEXT NOT NULL,
    payload_json TEXT NOT NULL
);
