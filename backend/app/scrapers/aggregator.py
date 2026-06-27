"""Fan out across every source in parallel, normalize, dedupe, persist."""
import json
from concurrent.futures import ThreadPoolExecutor, as_completed

from .sources import ALL_SCRAPERS
from ..database import get_conn

# Training providers / schools that advertise "formations" instead of real jobs.
_FORMATION_COMPANY = [
    "cfa", "centre de formation", "ecole", "école", "campus", "openclassrooms",
    "studi", "iscod", "ifocop", "skill and you", "academie", "académie", "academy",
    "afpa", "greta", "organisme de formation", "icademie", "ynov", "digital school",
    "digital campus", "walter learning", "doranco", "ipac", "my digital school",
    "alternance.com", "diplomeo", "nextformation", "formaposte",
]
# Title/description phrases that signal a training advert (not an employer offer).
_FORMATION_PHRASE = [
    "préparez un", "préparez votre", "obtenez un diplôme", "obtenez votre diplôme",
    "formation diplômante", "intègre notre formation", "rejoignez notre formation",
    "titre rncp", "formation en alternance", "alternance - formation",
    "formation gratuite", "rémunérée et diplômante", "préparation au",
]


def _is_formation_ad(r: dict) -> bool:
    """True if the offer is a school/training advert rather than a real job."""
    company = (r.get("company") or "").lower()
    if any(k in company for k in _FORMATION_COMPANY):
        return True
    blob = (r.get("title", "") + " " + r.get("description", "")).lower()
    return any(p in blob for p in _FORMATION_PHRASE)


def scrape_all(query: str = "", location: str = "") -> dict:
    """Fetch from all sources concurrently and upsert into the jobs table.

    Returns a per-source count summary.
    """
    summary = {}
    jobs = []
    with ThreadPoolExecutor(max_workers=len(ALL_SCRAPERS)) as ex:
        futures = {ex.submit(s.fetch, query, location): s.name for s in ALL_SCRAPERS}
        for fut in as_completed(futures):
            name = futures[fut]
            try:
                rows = fut.result()
            except Exception:
                rows = []
            # client-side filtering: keep rows containing every query word (>=3 chars),
            # not the exact phrase, so "python developer" still matches "Python Back-End Developer".
            if query:
                words = [w for w in query.lower().split() if len(w) >= 3]
                if words:
                    def _match(r):
                        blob = (r["title"] + " " + r["description"] + " "
                                + " ".join(str(t) for t in (r["tags"] or []))).lower()
                        return all(w in blob for w in words)
                    rows = [r for r in rows if _match(r)]
            # drop school/training adverts (they are not real job offers)
            rows = [r for r in rows if not _is_formation_ad(r)]
            summary[name] = len(rows)
            jobs.extend(rows)

    _upsert(jobs)
    summary["total_upserted"] = len(jobs)
    return summary


def _upsert(jobs: list):
    if not jobs:
        return
    with get_conn() as conn:
        for j in jobs:
            conn.execute(
                """INSERT INTO jobs (source, ext_id, title, company, location, url,
                       description, tags, salary, posted_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(source, ext_id) DO UPDATE SET
                       title=excluded.title, description=excluded.description,
                       tags=excluded.tags, fetched_at=CURRENT_TIMESTAMP""",
                (j["source"], j["ext_id"], j["title"], j["company"], j["location"],
                 j["url"], j["description"], json.dumps(j["tags"]), j["salary"],
                 j["posted_at"]),
            )
