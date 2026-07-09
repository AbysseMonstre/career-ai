"""Background maintenance: data retention purge + periodic job refresh.

Uses a stdlib daemon thread (no external scheduler dependency).
"""
import threading
import time

from .database import get_conn
from . import config


def purge_expired():
    """RGPD data minimisation: drop stale scraped jobs and old contact requests."""
    with get_conn() as conn:
        conn.execute(
            "DELETE FROM jobs WHERE recruiter_id IS NULL "
            "AND fetched_at < datetime('now', ?)",
            (f"-{config.JOB_RETENTION_DAYS} days",),
        )
        conn.execute(
            "DELETE FROM contact_requests WHERE created_at < datetime('now', ?)",
            (f"-{config.CONTACT_RETENTION_DAYS} days",),
        )


# Popular queries kept warm so the DB stays full and diverse across sectors
# (tech, but also restauration, commerce, aéronautique, BTP, industrie, santé…).
WARM_QUERIES = [
    # tech / bureau
    "développeur", "data", "design", "marketing", "devops", "comptable",
    "ressources humaines", "assistant administratif", "chef de projet",
    # restauration / hôtellerie
    "serveur", "cuisinier", "restauration", "commis de cuisine", "réceptionniste",
    "employé polyvalent", "boulanger",
    # commerce / vente
    "commercial", "vendeur", "conseiller de vente", "téléconseiller", "caissier",
    # aéronautique / industrie
    "aéronautique", "mécanicien", "technicien de maintenance", "opérateur de production",
    "soudeur", "usineur",
    # BTP
    "maçon", "électricien", "plombier", "chef de chantier", "peintre",
    # transport / logistique
    "chauffeur", "cariste", "préparateur de commandes", "livreur",
    # santé / services
    "aide-soignant", "infirmier", "auxiliaire de vie", "agent de sécurité",
    "agent d'entretien", "coiffeur",
    # alternance (tous secteurs)
    "alternance", "apprentissage", "alternance commerce", "alternance restauration",
]


def _refresh_jobs():
    from .scrapers import scrape_all
    for q in WARM_QUERIES:
        try:
            scrape_all(q, "")
        except Exception as e:  # never crash the worker
            print(f"[maintenance] refresh '{q}' a échoué: {e}")


def _send_alerts():
    """Email a digest of top matching offers to seekers who opted in (once/day)."""
    import json
    from datetime import datetime, timezone
    from . import notifications, matching
    from .database import get_conn
    if not (notifications.SMTP_HOST and notifications.SMTP_USER and notifications.SMTP_PASSWORD):
        return  # email not configured -> skip silently
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with get_conn() as conn:
        users = conn.execute(
            "SELECT u.id, u.email, u.name, p.title, p.location, p.skills "
            "FROM users u JOIN profiles p ON p.user_id=u.id "
            "WHERE u.alerts_enabled=1 AND p.skills != '[]' "
            "AND (u.alerts_sent_at IS NULL OR u.alerts_sent_at < ?)", (today,)).fetchall()
        jobs = [dict(r) for r in conn.execute(
            "SELECT * FROM jobs ORDER BY fetched_at DESC LIMIT 400").fetchall()]
    for j in jobs:
        j["tags"] = json.loads(j.get("tags") or "[]")
    for u in users:
        prof = {"title": u["title"], "location": u["location"],
                "cv_text": "", "skills": json.loads(u["skills"] or "[]")}
        scored = []
        for j in jobs:
            m = matching.score(prof, j)
            if m["score"] >= 40:
                jj = dict(j); jj["match"] = m; scored.append(jj)
        scored.sort(key=lambda x: x["match"]["score"], reverse=True)
        top = scored[:5]
        if not top:
            continue
        notifications.send_job_alert(to_email=u["email"], name=u["name"], jobs=top)
        with get_conn() as conn:
            conn.execute("UPDATE users SET alerts_sent_at=? WHERE id=?", (today, u["id"]))


def backfill_search_text(batch: int = 400):
    """Fill search_text for existing jobs that predate the column (one pass)."""
    import json
    from .database import get_conn
    from .scrapers.aggregator import unaccent
    done = 0
    while True:
        with get_conn() as conn:
            rows = conn.execute(
                "SELECT id, title, company, tags FROM jobs WHERE search_text='' LIMIT ?",
                (batch,)).fetchall()
            if not rows:
                break
            for r in rows:
                tags = " ".join(str(t) for t in json.loads(r["tags"] or "[]"))
                st = unaccent(f"{r['title']} {r['company']} {tags}")
                conn.execute("UPDATE jobs SET search_text=? WHERE id=?", (st, r["id"]))
        done += len(rows)
    if done:
        print(f"[maintenance] backfill search_text: {done} offres mises à jour")


def start_backfill():
    t = threading.Thread(target=lambda: _safe(backfill_search_text), daemon=True)
    t.start()
    return t


def _safe(fn):
    try:
        fn()
    except Exception as e:
        print(f"[maintenance] {fn.__name__} échoué: {e}")


def _worker(refresh_every_sec: int):
    while True:
        try:
            purge_expired()
            _refresh_jobs()
            _send_alerts()
        except Exception as e:
            print(f"[maintenance] cycle échoué: {e}")
        time.sleep(refresh_every_sec)


def start(refresh_every_sec: int = 6 * 3600):
    """Launch the maintenance loop in a daemon thread."""
    t = threading.Thread(target=_worker, args=(refresh_every_sec,), daemon=True)
    t.start()
    print(f"[maintenance] purge + refresh planifiés toutes les {refresh_every_sec // 3600} h")
    return t


def _keepalive_worker(url: str, every_sec: int):
    import requests
    ping = url.rstrip("/") + "/"
    # small initial delay so we don't ping during boot
    time.sleep(min(every_sec, 60))
    while True:
        try:
            requests.get(ping, timeout=20)
        except Exception as e:
            print(f"[keepalive] ping échoué: {e}")
        time.sleep(every_sec)


def start_keepalive(url: str, every_sec: int = 600):
    """Self-ping the public URL periodically so a free host never idles to sleep."""
    t = threading.Thread(target=_keepalive_worker, args=(url, every_sec), daemon=True)
    t.start()
    print(f"[keepalive] auto-ping de {url} toutes les {every_sec // 60} min")
    return t
    return t
