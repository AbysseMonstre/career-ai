"""One-off: create the Career AI schema on Neon and report what landed.

Reads the connection string from /tmp/.neon_uri so the secret never appears in
a shell command line or in process listings.
"""
import os
import time

os.environ["CAREER_AI_DATABASE_URL"] = open("/tmp/.neon_uri").read().strip()

from app.database import init_db, get_conn, IS_PG  # noqa: E402  (after env setup)

print("mode Postgres:", IS_PG)
t0 = time.time()
init_db()
print(f"init_db + migrations OK en {time.time() - t0:.1f}s")

with get_conn() as c:
    rows = c.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema='public' ORDER BY table_name"
    ).fetchall()
    print("tables:", ", ".join(r["table_name"] for r in rows))
    cols = c.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_name='profiles' ORDER BY column_name"
    ).fetchall()
    print("colonnes profiles:", ", ".join(r["column_name"] for r in cols))
    t1 = time.time()
    c.execute("SELECT 1").fetchone()
    print(f"latence aller-retour: {(time.time() - t1) * 1000:.0f} ms")
