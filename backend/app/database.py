"""Thin SQLite layer — no ORM, stdlib only, so the backend runs anywhere."""
import sqlite3
import os
from contextlib import contextmanager

DB_PATH = os.environ.get(
    "CAREER_AI_DB", os.path.join(os.path.dirname(__file__), "..", "career_ai.db"))

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    email         TEXT UNIQUE NOT NULL,
    password      TEXT NOT NULL,
    role          TEXT NOT NULL,          -- 'seeker' | 'recruiter'
    name          TEXT NOT NULL,
    talent_access TEXT DEFAULT 'none',    -- recruiter: none | pending | granted
    consent_at    TEXT,                   -- RGPD: when data-processing consent was given
    created_at    TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS contact_requests (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    company     TEXT DEFAULT '',
    phone       TEXT DEFAULT '',
    message     TEXT DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'pending',  -- pending | granted | rejected
    created_at  TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Interview a recruiter schedules with a chosen candidate (Teams link).
CREATE TABLE IF NOT EXISTS interviews (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    recruiter_id  INTEGER NOT NULL REFERENCES users(id),
    candidate_id  INTEGER NOT NULL REFERENCES users(id),
    company       TEXT DEFAULT '',
    scheduled_at  TEXT DEFAULT '',          -- ISO datetime chosen by the recruiter
    teams_link    TEXT DEFAULT '',
    message       TEXT DEFAULT '',
    status        TEXT NOT NULL DEFAULT 'proposed',  -- proposed | accepted | declined
    created_at    TEXT DEFAULT CURRENT_TIMESTAMP
);

-- One saved interview-training session (aggregate of its answers).
CREATE TABLE IF NOT EXISTS training_sessions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    score       INTEGER DEFAULT 0,
    axes        TEXT DEFAULT '{}',       -- JSON {axis: 0-100}
    answers     INTEGER DEFAULT 0,
    created_at  TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Duolingo-style daily activity log (one row per user per day).
CREATE TABLE IF NOT EXISTS activity (
    user_id     INTEGER NOT NULL REFERENCES users(id),
    day         TEXT NOT NULL,            -- 'YYYY-MM-DD'
    count       INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, day)
);

-- A company asks to be connected with a specific freelance. The platform
-- arranges the connection and bills the freelance (commission).
CREATE TABLE IF NOT EXISTS placement_requests (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    recruiter_id  INTEGER NOT NULL REFERENCES users(id),
    candidate_id  INTEGER NOT NULL REFERENCES users(id),
    company       TEXT DEFAULT '',
    message       TEXT DEFAULT '',
    match_score   INTEGER DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'requested', -- requested|arranged|billed|closed
    created_at    TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS profiles (
    user_id     INTEGER PRIMARY KEY REFERENCES users(id),
    title       TEXT DEFAULT '',
    location    TEXT DEFAULT '',
    cv_text     TEXT DEFAULT '',
    skills      TEXT DEFAULT '[]',        -- JSON array
    updated_at  TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS jobs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    source      TEXT NOT NULL,
    ext_id      TEXT NOT NULL,
    title       TEXT NOT NULL,
    company     TEXT DEFAULT '',
    location    TEXT DEFAULT '',
    url         TEXT DEFAULT '',
    description TEXT DEFAULT '',
    tags        TEXT DEFAULT '[]',        -- JSON array
    salary      TEXT DEFAULT '',
    posted_at   TEXT DEFAULT '',
    fetched_at  TEXT DEFAULT CURRENT_TIMESTAMP,
    recruiter_id INTEGER,                 -- set when posted by a recruiter
    UNIQUE(source, ext_id)
);

CREATE TABLE IF NOT EXISTS applications (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    job_id      INTEGER NOT NULL REFERENCES jobs(id),
    status      TEXT NOT NULL DEFAULT 'auto_pending', -- auto_pending|validated|rejected|applied
    match_score INTEGER DEFAULT 0,
    cover_letter TEXT DEFAULT '',
    created_at  TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, job_id)
);
"""


# columns added after initial release -> (table, column, ddl)
_MIGRATIONS = [
    ("users", "talent_access", "ALTER TABLE users ADD COLUMN talent_access TEXT DEFAULT 'none'"),
    ("users", "consent_at", "ALTER TABLE users ADD COLUMN consent_at TEXT"),
    ("applications", "cover_letter", "ALTER TABLE applications ADD COLUMN cover_letter TEXT DEFAULT ''"),
]


def init_db():
    with get_conn() as conn:
        conn.executescript(SCHEMA)
        for table, column, ddl in _MIGRATIONS:
            cols = [r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]
            if column not in cols:
                conn.execute(ddl)


@contextmanager
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()
