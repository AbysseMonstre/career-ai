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


# popular queries kept warm so the feed is never empty
WARM_QUERIES = ["python", "javascript", "data", "design", "marketing", "devops"]


def _refresh_jobs():
    from .scrapers import scrape_all
    for q in WARM_QUERIES:
        try:
            scrape_all(q, "")
        except Exception as e:  # never crash the worker
            print(f"[maintenance] refresh '{q}' a échoué: {e}")


def _worker(refresh_every_sec: int):
    while True:
        try:
            purge_expired()
            _refresh_jobs()
        except Exception as e:
            print(f"[maintenance] cycle échoué: {e}")
        time.sleep(refresh_every_sec)


def start(refresh_every_sec: int = 6 * 3600):
    """Launch the maintenance loop in a daemon thread."""
    t = threading.Thread(target=_worker, args=(refresh_every_sec,), daemon=True)
    t.start()
    print(f"[maintenance] purge + refresh planifiés toutes les {refresh_every_sec // 3600} h")
    return t
