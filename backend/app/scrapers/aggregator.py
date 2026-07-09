"""Fan out across every source in parallel, normalize, dedupe, persist."""
import json
import unicodedata
from concurrent.futures import ThreadPoolExecutor, as_completed

from .sources import ALL_SCRAPERS
from ..database import get_conn


def unaccent(s: str) -> str:
    """Lowercase + strip accents (for accent-insensitive search)."""
    return "".join(c for c in unicodedata.normalize("NFD", (s or "").lower())
                   if unicodedata.category(c) != "Mn")


def search_text_for(row: dict) -> str:
    """Small, accent-stripped blob used for fast SQL search (title+company+tags)."""
    tags = " ".join(str(t) for t in (row.get("tags") or []))
    return unaccent(f"{row.get('title','')} {row.get('company','')} {tags}")

# Training providers / schools that advertise "formations" instead of real jobs.
_FORMATION_COMPANY = [
    "cfa", "centre de formation", "ecole", "école", "school", "campus",
    "openclassrooms", "studi", "iscod", "ifocop", "skill and you", "academie",
    "académie", "academy", "afpa", "greta", "organisme de formation", "icademie",
    "ynov", "digital school", "digital campus", "walter learning", "doranco",
    "ipac", "my digital school", "alternance.com", "diplomeo", "nextformation",
    "formaposte", "cnam", "institut de formation", "college de paris", "collège de paris",
    "pigier", "iscom", "isefac", "iscpa", "esg", "cesi", "esaip", "supdeweb",
    "3w academy", "the bridge", "wall street english", "eni ecole", "efab", "ipi",
    "digital college", "formasup", "aftec", "isifa", "igs", "iesa", "esupcom",
    "sup de", "esiee", "esarc", "win sport school", "sport management school",
    "e-learning", "mastere ", "mastère ", "bachelor factory", "école de", "ecole de",
    "cci formation", "faculté des métiers", "centre de formation", "institut de formation",
]
# Phrases that only a school selling its own formation uses (an employer
# describing an alternance may say "vous préparez un diplôme", so generic
# wording like that is intentionally NOT here — it would drop real offers).
_FORMATION_PHRASE = [
    "obtenez un diplôme", "obtenez votre diplôme", "formation diplômante",
    "intègre notre formation", "intègre notre école", "rejoignez notre formation",
    "rejoins notre formation", "rejoins notre école", "formation gratuite",
    "rémunérée et diplômante", "notre organisme de formation",
    "notre centre de formation", "frais de formation", "financé par le cpf",
    "éligible cpf", "eligible cpf", "prise en charge à 100",
    "postule à notre formation", "candidature à notre formation",
    "nos formations", "cursus diplômant", "intègre notre cursus",
    "notre école recrute pour", "rejoindre notre formation", "intégrer notre formation",
]


def _is_formation_ad(r: dict) -> bool:
    """True if the offer is a school/training advert rather than a real job.

    Alternance listings are especially polluted by CFA/écoles selling a
    "formation" dressed up as a job, so this filter is applied at scrape time
    *and* at serve time for work-study results.
    """
    company = (r.get("company") or "").lower()
    if any(k in company for k in _FORMATION_COMPANY):
        return True
    blob = (r.get("title", "") + " " + r.get("description", "")).lower()
    return any(p in blob for p in _FORMATION_PHRASE)


# Malformed / placeholder rows that must never reach the feed.
_JUNK_TITLES = {
    "job title", "title", "learn more", "read more", "untitled", "n/a", "na",
    "none", "test", "example", "i am looking for guide", "apply now",
}


def _is_junk(r: dict) -> bool:
    """Drop rows with empty/placeholder/numeric titles (parsing artefacts)."""
    t = (r.get("title") or "").strip().lower()
    if len(t) < 3:
        return True
    if t in _JUNK_TITLES:
        return True
    if t.replace(" ", "").isdigit():       # e.g. "1419", "2035"
        return True
    if not r.get("url"):                    # no link to apply -> unusable
        return True
    return False


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
            # drop school/training adverts and malformed/placeholder rows
            rows = [r for r in rows if not _is_formation_ad(r) and not _is_junk(r)]
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
                       description, tags, salary, posted_at, search_text)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(source, ext_id) DO UPDATE SET
                       title=excluded.title, description=excluded.description,
                       tags=excluded.tags, search_text=excluded.search_text,
                       fetched_at=CURRENT_TIMESTAMP""",
                (j["source"], j["ext_id"], j["title"], j["company"], j["location"],
                 j["url"], j["description"], json.dumps(j["tags"]), j["salary"],
                 j["posted_at"], search_text_for(j)),
            )
