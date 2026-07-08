"""Database layer.

Default: SQLite (stdlib only, runs anywhere — local dev, tests).
Optional: PostgreSQL when ``CAREER_AI_DATABASE_URL`` (or ``DATABASE_URL``) is set
— gives real persistence on hosts with an ephemeral filesystem (e.g. Render free).

The rest of the app speaks one dialect: ``?`` placeholders, ``sqlite3.Row``-style
rows accessed by column name, ``cur.lastrowid`` after inserts, ``ON CONFLICT`` upserts.
A thin shim (`_PgConn`) translates that to psycopg for the Postgres path, so no
query in the app code needs to change.
"""
import sqlite3
import os
import re
from contextlib import contextmanager

DATABASE_URL = os.environ.get("CAREER_AI_DATABASE_URL") or os.environ.get("DATABASE_URL")
IS_PG = bool(DATABASE_URL) and DATABASE_URL.startswith(("postgres://", "postgresql://"))

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

-- Liked / favorite offers (seeker).
CREATE TABLE IF NOT EXISTS favorites (
    user_id    INTEGER NOT NULL REFERENCES users(id),
    job_id     INTEGER NOT NULL REFERENCES jobs(id),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, job_id)
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

# ---------------------------------------------------------------------------
# Postgres compatibility shim
# ---------------------------------------------------------------------------

# Tables whose primary key is a serial ``id`` — only these get ``RETURNING id``
# appended so that ``cur.lastrowid`` keeps working on the Postgres path.
_ID_TABLES = {"users", "jobs", "applications", "contact_requests",
              "interviews", "training_sessions", "placement_requests"}

_DT_NOW = re.compile(r"datetime\('now',\s*\?\)")          # -> now() + interval
_INSERT_TBL = re.compile(r"^\s*INSERT\s+INTO\s+(\w+)", re.I)


def _translate_sql(sql: str):
    """Rewrite a SQLite query for psycopg. Returns (query, fetch_returning?)."""
    s = sql
    need_nothing = False
    if re.search(r"INSERT\s+OR\s+IGNORE", s, re.I):
        s = re.sub(r"INSERT\s+OR\s+IGNORE", "INSERT", s, flags=re.I)
        need_nothing = True
    # timestamp columns are TEXT, so compare against a TEXT value (Postgres won't
    # compare text < timestamptz). ISO text compares chronologically.
    s = _DT_NOW.sub("(now() + (?)::interval)::text", s)
    # timestamp columns are TEXT here, so keep CURRENT_TIMESTAMP producing text
    # (Postgres won't assign a timestamptz to a text column without a cast).
    s = re.sub(r"CURRENT_TIMESTAMP", "now()::text", s, flags=re.I)
    # Escape literal % (e.g. LIKE '%remote%') *before* turning ? into %s.
    s = s.replace("%", "%%").replace("?", "%s")

    add_returning = False
    m = _INSERT_TBL.match(s)
    if m:
        tbl = m.group(1).lower()
        has_conflict = "ON CONFLICT" in s.upper()
        if need_nothing and not has_conflict:
            s = s.rstrip().rstrip(";") + " ON CONFLICT DO NOTHING"
            has_conflict = True
        if tbl in _ID_TABLES and not has_conflict and "RETURNING" not in s.upper():
            s = s.rstrip().rstrip(";") + " RETURNING id"
            add_returning = True
    return s, add_returning


def _translate_ddl(ddl: str) -> str:
    ddl = re.sub(r"INTEGER\s+PRIMARY\s+KEY\s+AUTOINCREMENT",
                 "SERIAL PRIMARY KEY", ddl, flags=re.I)
    # Drop inline FOREIGN KEY references: they impose a create order (favorites
    # references jobs) that SQLite ignores but Postgres enforces. The app manages
    # relationships in code and SQLite never enforced these at runtime anyway.
    ddl = re.sub(r"\s+REFERENCES\s+\w+\s*\([^)]*\)", "", ddl, flags=re.I)
    # TEXT timestamp columns: cast the default so Postgres accepts it.
    ddl = re.sub(r"DEFAULT\s+CURRENT_TIMESTAMP", "DEFAULT now()::text", ddl, flags=re.I)
    return ddl


class _Cur:
    """Minimal cursor facade exposing the bits the app relies on."""
    def __init__(self, cur, lastrowid=None):
        self._cur = cur
        self.lastrowid = lastrowid

    def fetchone(self):
        return self._cur.fetchone()

    def fetchall(self):
        return self._cur.fetchall()


class _PgConn:
    """Wraps a psycopg connection to mimic the sqlite3 connection API used here."""
    def __init__(self, raw, dict_row):
        self._raw = raw
        self._dict_row = dict_row

    def execute(self, sql, params=()):
        q, add_returning = _translate_sql(sql)
        cur = self._raw.cursor(row_factory=self._dict_row)
        cur.execute(q, tuple(params))
        last = None
        if add_returning:
            row = cur.fetchone()
            last = row["id"] if row else None
        return _Cur(cur, last)

    def commit(self):
        self._raw.commit()

    def close(self):
        self._raw.close()


def init_db():
    with get_conn() as conn:
        if IS_PG:
            for stmt in SCHEMA.split(";"):
                if stmt.strip():
                    conn.execute(_translate_ddl(stmt))
            for table, column, ddl in _MIGRATIONS:
                exists = conn.execute(
                    "SELECT 1 FROM information_schema.columns "
                    "WHERE table_name=? AND column_name=?",
                    (table, column)).fetchone()
                if not exists:
                    conn.execute(ddl)  # ALTER TABLE ... ADD COLUMN (valid in PG)
        else:
            conn.executescript(SCHEMA)
            for table, column, ddl in _MIGRATIONS:
                cols = [r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]
                if column not in cols:
                    conn.execute(ddl)


@contextmanager
def get_conn():
    if IS_PG:
        import psycopg
        from psycopg.rows import dict_row
        # autocommit: each statement is independent, so a caught duplicate-insert
        # error (e.g. in auto-apply) never poisons later statements in the block.
        raw = psycopg.connect(DATABASE_URL, autocommit=True)
        conn = _PgConn(raw, dict_row)
        try:
            yield conn
        finally:
            conn.close()
    else:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()
