"""Career AI backend — FastAPI.

Endpoints
  Auth        POST /auth/register, POST /auth/login, GET /me
  CV          POST /cv/upload, GET /cv
  Jobs        GET /jobs, POST /jobs/refresh, POST /jobs/post (recruiter)
  Apply       POST /applications/auto, POST /applications/{id}/validate,
              POST /applications/{id}/reject, GET /applications
  Recruiter   GET /talents, GET /dashboard/recruiter
  Seeker      GET /dashboard/seeker
"""
import json
from typing import Optional, List
from datetime import datetime, timezone, date, timedelta

import re as _re
from fastapi import (FastAPI, Depends, HTTPException, Header, UploadFile, File, Form,
                     BackgroundTasks, Request)
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import Response
from pydantic import BaseModel

from .database import get_conn, init_db
from . import security, cv_parser, matching, notifications, config, cover_letter, expansion
from .scrapers import scrape_all
from .scrapers.aggregator import _is_junk, _is_formation_ad

app = FastAPI(title="Career AI", version="1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["*"],
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    resp: Response = await call_next(request)
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "no-referrer"
    if config.IS_PROD:
        resp.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return resp


_EMAIL_RE = _re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

import unicodedata


def _unaccent(s: str) -> str:
    """Strip accents so search is accent-insensitive (développeur == developpeur)."""
    return "".join(c for c in unicodedata.normalize("NFD", s or "")
                   if unicodedata.category(c) != "Mn")


def _client_key(request: Request, suffix: str) -> str:
    ip = request.client.host if request.client else "?"
    return f"{ip}:{suffix}"


import logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("careerai")


@app.on_event("startup")
def _startup():
    config.validate_startup()
    init_db()
    log.info("Career AI démarré (env=%s, sources=%d)", config.ENV, 7)
    from . import maintenance
    maintenance.purge_expired()  # cheap, no network
    # In the cloud (public URL known) or when explicitly enabled: keep offers
    # fresh in the background and self-ping so the free instance never sleeps.
    if config.SCHEDULER_ENABLED or config.PUBLIC_URL:
        maintenance.start(config.REFRESH_EVERY_SEC)
    if config.PUBLIC_URL:
        maintenance.start_keepalive(config.PUBLIC_URL, config.KEEPALIVE_EVERY_SEC)


# ---------- auth dependency ----------
def current_user(authorization: Optional[str] = Header(None)) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing bearer token")
    payload = security.decode_token(authorization[7:])
    if not payload:
        raise HTTPException(401, "Invalid or expired token")
    with get_conn() as conn:
        row = conn.execute("SELECT id, email, role, name FROM users WHERE id=?",
                           (payload["uid"],)).fetchone()
    if not row:
        raise HTTPException(401, "User not found")
    return dict(row)


def require_role(role: str):
    def dep(user: dict = Depends(current_user)):
        if user["role"] != role:
            raise HTTPException(403, f"Requires {role} role")
        return user
    return dep


# ---------- schemas ----------
class RegisterIn(BaseModel):
    email: str
    password: str
    name: str
    role: str  # 'seeker' | 'recruiter'
    consent: bool = False  # RGPD: explicit consent to data processing


class LoginIn(BaseModel):
    email: str
    password: str


class JobPostIn(BaseModel):
    title: str
    company: str
    location: str = ""
    description: str = ""
    tags: List[str] = []
    salary: str = ""


class AutoApplyIn(BaseModel):
    job_ids: List[int]


class ApplyOneIn(BaseModel):
    job_id: int


class ContactRequestIn(BaseModel):
    company: str
    phone: str = ""
    message: str = ""


class PlacementRequestIn(BaseModel):
    message: str = ""


# ---------- helpers ----------
def _profile(conn, uid):
    row = conn.execute("SELECT * FROM profiles WHERE user_id=?", (uid,)).fetchone()
    if not row:
        return {"user_id": uid, "title": "", "location": "", "cv_text": "", "skills": []}
    d = dict(row)
    d["skills"] = json.loads(d.get("skills") or "[]")
    return d


# --- alternance (work-study) detection + contact-email extraction ---
_ALT_TERMS = ("alternance", "alternant", "apprentissage", "apprenti",
              "contrat de professionnalisation", "contrat pro", "contrat d'apprentissage",
              "work-study", "work study", "apprenticeship")
# Popular domains scraped alongside "alternance" to maximise work-study coverage.
_ALT_DOMAINS = ["informatique", "développeur", "marketing", "commerce", "vente",
                "communication", "ressources humaines", "finance", "comptabilité",
                "logistique", "design", "data"]
_DESC_EMAIL_RE = _re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
# emails that are never a real recruiter contact
_EMAIL_SKIP = ("noreply", "no-reply", "no_reply", "example.com", "example.org",
               "sentry", "wixpress", "domain.com", "email.com", "mailer", "notification")


def _extract_contact_email(text: str):
    """First plausible recruiter email found in an offer's text, else None."""
    for m in _DESC_EMAIL_RE.findall(text or ""):
        ml = m.lower()
        if not any(s in ml for s in _EMAIL_SKIP):
            return m
    return None


def _is_alternance(job: dict) -> bool:
    blob = (job.get("title", "") + " " + job.get("description", "") + " "
            + " ".join(str(t) for t in (job.get("tags") or []))).lower()
    return any(t in blob for t in _ALT_TERMS)


def _job_row_to_dict(row):
    d = dict(row)
    d["tags"] = json.loads(d.get("tags") or "[]")
    d["is_alternance"] = _is_alternance(d)
    # surface a recruiter contact email when the advert itself includes one
    d["contact_email"] = _extract_contact_email(
        (d.get("description", "") or "") + " " + (d.get("company", "") or ""))
    return d


# ---------- auth ----------
@app.post("/auth/register")
def register(body: RegisterIn, request: Request):
    if security.rate_limited(_client_key(request, "register"), limit=5, window_sec=3600):
        raise HTTPException(429, "Trop de tentatives. Réessayez plus tard.")
    if body.role not in ("seeker", "recruiter"):
        raise HTTPException(400, "role must be 'seeker' or 'recruiter'")
    if not _EMAIL_RE.match(body.email):
        raise HTTPException(400, "Adresse email invalide")
    if len(body.password) < config.MIN_PASSWORD_LEN:
        raise HTTPException(400, f"Mot de passe trop court (min {config.MIN_PASSWORD_LEN} caractères)")
    if not body.consent:
        raise HTTPException(400, "Le consentement au traitement des données est requis")
    with get_conn() as conn:
        exists = conn.execute("SELECT 1 FROM users WHERE email=?", (body.email,)).fetchone()
        if exists:
            raise HTTPException(409, "Email already registered")
        cur = conn.execute(
            """INSERT INTO users (email, password, role, name, consent_at)
               VALUES (?,?,?,?,CURRENT_TIMESTAMP)""",
            (body.email, security.hash_password(body.password), body.role, body.name),
        )
        uid = cur.lastrowid
        if body.role == "seeker":
            conn.execute("INSERT INTO profiles (user_id) VALUES (?)", (uid,))
    token = security.create_token(uid, body.role)
    return {"token": token, "user": {"id": uid, "email": body.email,
                                     "name": body.name, "role": body.role}}


@app.post("/auth/login")
def login(body: LoginIn, request: Request):
    if security.rate_limited(_client_key(request, "login"), limit=10, window_sec=300):
        raise HTTPException(429, "Trop de tentatives de connexion. Réessayez dans quelques minutes.")
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM users WHERE email=?", (body.email,)).fetchone()
    if not row or not security.verify_password(body.password, row["password"]):
        raise HTTPException(401, "Invalid credentials")
    token = security.create_token(row["id"], row["role"])
    return {"token": token, "user": {"id": row["id"], "email": row["email"],
                                     "name": row["name"], "role": row["role"]}}


@app.get("/me")
def me(user: dict = Depends(current_user)):
    return user


# ---------- RGPD: portability, erasure, transparency ----------
@app.get("/me/export")
def export_my_data(user: dict = Depends(current_user)):
    """Right to data portability (RGPD art. 20): return everything we hold."""
    with get_conn() as conn:
        u = dict(conn.execute(
            "SELECT id, email, name, role, talent_access, consent_at, created_at "
            "FROM users WHERE id=?", (user["id"],)).fetchone())
        profile = conn.execute("SELECT * FROM profiles WHERE user_id=?", (user["id"],)).fetchone()
        apps = conn.execute(
            "SELECT id, job_id, status, match_score, created_at FROM applications WHERE user_id=?",
            (user["id"],)).fetchall()
        contacts = conn.execute(
            "SELECT company, phone, message, status, created_at FROM contact_requests WHERE user_id=?",
            (user["id"],)).fetchall()
    return {
        "user": u,
        "profile": _row_with_skills(profile) if profile else None,
        "applications": [dict(a) for a in apps],
        "contact_requests": [dict(c) for c in contacts],
    }


def _row_with_skills(row):
    d = dict(row)
    d["skills"] = json.loads(d.get("skills") or "[]")
    return d


@app.delete("/me")
def delete_my_account(user: dict = Depends(current_user)):
    """Right to erasure (RGPD art. 17): hard-delete all personal data."""
    with get_conn() as conn:
        uid = user["id"]
        conn.execute("DELETE FROM applications WHERE user_id=?", (uid,))
        conn.execute("DELETE FROM profiles WHERE user_id=?", (uid,))
        conn.execute("DELETE FROM contact_requests WHERE user_id=?", (uid,))
        conn.execute("DELETE FROM jobs WHERE recruiter_id=?", (uid,))
        conn.execute("DELETE FROM users WHERE id=?", (uid,))
    return {"deleted": True, "message": "Compte et données personnelles supprimés."}


@app.get("/legal/privacy")
def privacy_policy():
    return {
        "controller": "Career AI",
        "contact": notifications.ADMIN_EMAIL,
        "data_collected": ["email", "nom", "CV et compétences (chercheurs)",
                           "demandes de contact (recruteurs)", "candidatures"],
        "purpose": "Mise en relation chercheurs d'emploi / recruteurs et matching.",
        "legal_basis": "Consentement (art. 6.1.a RGPD), recueilli à l'inscription.",
        "retention": {
            "offres_scrapees_jours": config.JOB_RETENTION_DAYS,
            "demandes_contact_jours": config.CONTACT_RETENTION_DAYS,
            "compte": "jusqu'à suppression par l'utilisateur",
        },
        "rights": "Accès/portabilité (GET /me/export), effacement (DELETE /me), retrait du consentement.",
    }


# ---------- CV ----------
@app.post("/cv/upload")
async def upload_cv(
    file: UploadFile = File(None),
    text: Optional[str] = Form(None),
    title: Optional[str] = Form(None),
    location: Optional[str] = Form(None),
    user: dict = Depends(require_role("seeker")),
):
    if file is not None:
        content = await file.read()
        raw = cv_parser.extract_text(file.filename, content)
    elif text:
        raw = text
    else:
        raise HTTPException(400, "Provide a file or text")

    skills = cv_parser.extract_skills(raw)
    guessed_title = title or cv_parser.guess_title(raw)
    with get_conn() as conn:
        conn.execute(
            """UPDATE profiles SET cv_text=?, skills=?, title=?, location=?,
                   updated_at=CURRENT_TIMESTAMP WHERE user_id=?""",
            (raw[:20000], json.dumps(skills), guessed_title or "",
             location or "", user["id"]),
        )
    return {"skills": skills, "title": guessed_title, "location": location or "",
            "chars": len(raw)}


@app.get("/cv")
def get_cv(user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        return _profile(conn, user["id"])


# ---------- jobs ----------
@app.post("/jobs/refresh")
def refresh_jobs(query: str = "", location: str = "", user: dict = Depends(current_user)):
    return {"sources": scrape_all(query, location)}


# contract type -> synonyms detected in a job's text
_CONTRACT_SYNONYMS = {
    "cdi": ["cdi", "permanent", "full-time", "full time", "temps plein"],
    "cdd": ["cdd", "fixed-term", "fixed term", "temporary", "contrat à durée"],
    "freelance": ["freelance", "contract", "contractor", "indépendant", "self-employed", "mission"],
    "stage": ["stage", "internship", "intern", "stagiaire"],
    "alternance": ["alternance", "apprenticeship", "apprenti", "work-study"],
}


def _job_age_days(job: dict):
    """Age of the offer in days, from posted_at (ISO or unix ts) else fetched_at.
    Returns None if no date can be determined."""
    def parse(raw):
        raw = (raw or "").strip()
        if not raw:
            return None
        try:
            if raw.isdigit():
                return datetime.fromtimestamp(int(raw), tz=timezone.utc)
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00").replace(" ", "T"))
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except Exception:
            return None

    dt = parse(job.get("posted_at")) or parse(job.get("fetched_at"))
    if dt is None:
        return None
    return (datetime.now(timezone.utc) - dt).days


def _passes_filters(job: dict, contract: str, remote: bool) -> bool:
    blob = (job.get("title", "") + " " + job.get("description", "") + " "
            + " ".join(str(t) for t in (job.get("tags") or []))).lower()
    loc = (job.get("location", "") or "").lower()
    if remote and not any(w in loc or w in blob for w in ("remote", "télétravail", "anywhere", "worldwide")):
        return False
    if contract:
        syns = _CONTRACT_SYNONYMS.get(contract.lower(), [contract.lower()])
        if not any(s in blob for s in syns):
            return False
    return True


@app.get("/jobs")
def list_jobs(query: str = "", location: str = "", limit: int = 50, sync: bool = False,
              sync_profile: bool = False, favorites_only: bool = False,
              contract: str = "", remote: bool = False, sort: str = "match",
              max_age_days: int = 0, alternance: bool = False,
              user: dict = Depends(current_user)):
    """List jobs, ranked by CV match for seekers.

    The query is expanded (FR<->EN + synonyms) to surface more, more varied offers
    from the same sources. Filters: location, contract, remote, favorites_only.
    """
    if max_age_days <= 0:
        max_age_days = config.JOB_RETENTION_DAYS
    is_seeker = user["role"] == "seeker"
    variants = expansion.expand_query(query) if query else [""]

    if sync_profile and is_seeker:
        with get_conn() as conn:
            prof = _profile(conn, user["id"])
        queries = [q for q in [prof.get("title", "")] if q] + (prof.get("skills") or [])[:6]
        seen = set()
        for q in queries:
            for v in expansion.expand_query(q.strip()):
                if v and v.lower() not in seen:
                    seen.add(v.lower())
                    scrape_all(v, location)
    elif sync:
        for v in variants:
            scrape_all(v, location)

    # Alternance mode: aggressively scrape work-study offers across popular
    # domains (on an explicit sync/refresh) so the feed is packed with them.
    if alternance and sync:
        base = query.strip()
        alt_queries = ([base] if base else []) + ["alternance"] \
            + [f"alternance {d}" for d in _ALT_DOMAINS]
        for q in alt_queries[:9]:
            scrape_all(q, location)

    # Query matching is done in Python so it is ACCENT-INSENSITIVE (e.g. searching
    # "developpeur" matches "développeur"). Location stays in SQL.
    def build():
        sql = "SELECT * FROM jobs WHERE 1=1"
        args = []
        if location:
            sql += (" AND (LOWER(location) LIKE ? OR LOWER(location) LIKE '%remote%'"
                    " OR LOWER(location) LIKE '%anywhere%' OR LOWER(location) LIKE '%worldwide%'"
                    " OR LOWER(location) LIKE '%télétravail%')")
            args.append(f"%{location.lower()}%")
        sql += " ORDER BY fetched_at DESC"
        return sql, args

    _qterms = []
    if query:
        for v in variants:
            ws = [_unaccent(w) for w in v.lower().split() if len(w) >= 3]
            if ws:
                _qterms.append(ws)

    def _apply_query(rows):
        if not _qterms:
            return rows
        def _m(j):
            blob = _unaccent((j.get("title", "") + " " + j.get("description", "") + " "
                              + " ".join(str(t) for t in (j.get("tags") or []))).lower())
            return any(all(w in blob for w in ws) for ws in _qterms)
        return [j for j in rows if _m(j)]

    with get_conn() as conn:
        profile = _profile(conn, user["id"]) if is_seeker else None
        favs = {r["job_id"] for r in conn.execute(
            "SELECT job_id FROM favorites WHERE user_id=?", (user["id"],)).fetchall()}
        sql, args = build()
        rows = _apply_query([_job_row_to_dict(r) for r in conn.execute(sql, args).fetchall()])
        # self-populate when empty (e.g. fresh/ephemeral DB) — even with no query,
        # scrape a default set so the feed is never empty on first load.
        if not rows and not favorites_only:
            if alternance:
                base = query.strip()
                populate = ([base] if base else []) + ["alternance"] \
                    + [f"alternance {d}" for d in _ALT_DOMAINS[:5]]
            elif query:
                populate = variants
            elif profile is not None and (profile.get("title") or profile.get("skills")):
                # no search + a CV on file: fetch offers for the candidate's own
                # profile so the feed stays relevant (never a generic dump).
                seeds = [profile.get("title", "")] + (profile.get("skills") or [])[:4]
                populate = [s for s in seeds if s][:5]
            else:
                populate = ["", "developer", "alternance"]
            for v in populate:
                scrape_all(v, location)
            sql, args = build()
            rows = _apply_query([_job_row_to_dict(r) for r in conn.execute(sql, args).fetchall()])

    def _recent(j):
        age = _job_age_days(j)
        return age is None or age <= max_age_days
    # drop stale offers, malformed rows, and school/training adverts (never real
    # jobs — especially rife in alternance). Applied at serve time too, so old
    # rows scraped before the filter tightened can never reach the feed.
    rows = [j for j in rows if _recent(j) and not _is_junk(j) and not _is_formation_ad(j)]
    if alternance:
        rows = [j for j in rows if j["is_alternance"]]
    if contract or remote:
        rows = [j for j in rows if _passes_filters(j, contract, remote)]
    for j in rows:
        j["liked"] = j["id"] in favs
    if favorites_only:
        rows = [j for j in rows if j["liked"]]

    if profile is not None:
        for j in rows:
            j["match"] = matching.score(profile, j)

    # Relevance is mandatory: the feed must relate to the user's search, or —
    # when there is no search — to their CV profile. With a text query the SQL
    # already constrained results; here we enforce the no-query case so the feed
    # is never a generic dump of unrelated offers.
    if is_seeker and not query and profile is not None:
        terms = [w for w in (profile.get("title", "") or "").lower().split() if len(w) >= 4]
        terms += [s.lower() for s in (profile.get("skills") or []) if len(s) >= 3]
        if terms:
            def _related(j):
                blob = (j.get("title", "") + " " + j.get("description", "") + " "
                        + " ".join(str(t) for t in (j.get("tags") or []))).lower()
                return any(t in blob for t in terms) or (j.get("match", {}).get("score", 0) >= 20)
            related = [j for j in rows if _related(j)]
            # keep relevance; only fall back to best matches if it emptied the feed
            rows = related if related else sorted(
                rows, key=lambda x: x.get("match", {}).get("score", 0), reverse=True)[:limit]

    if sort == "recent":
        rows.sort(key=lambda x: x.get("fetched_at", ""), reverse=True)
    elif profile is not None:
        rows.sort(key=lambda x: x["match"]["score"], reverse=True)
    return {"count": len(rows[:limit]), "jobs": rows[:limit]}


# ---------- interview / pitch training (persuasiv-inspired, keyless) ----------
class TrainingScoreIn(BaseModel):
    question: str
    answer: str
    type: str = ""
    job_id: int = 0


@app.get("/training/questions")
def training_questions(job_id: int = 0, user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        prof = _profile(conn, user["id"])
        job = conn.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone() if job_id else None

    # ---- targeted training for a specific offer ----
    if job:
        jd = _job_row_to_dict(job)
        job_skills = sorted(matching._job_skills(jd))
        cv = {s.lower() for s in (prof.get("skills") or [])}
        have = [s for s in job_skills if s.lower() in cv][:5]
        missing = [s for s in job_skills if s.lower() not in cv][:4]
        title = jd["title"] or "ce poste"
        company = jd["company"] or "l'entreprise"
        qs = [
            {"type": "pitch", "q": f"Présentez-vous pour le poste de {title} chez {company}."},
            {"type": "motivation", "q": f"Pourquoi voulez-vous précisément ce poste de {title} chez {company} ?"},
            {"type": "persuasion", "q": f"En 30 secondes, convainquez {company} que vous êtes le bon profil pour {title}."},
        ]
        for s in have:
            qs.append({"type": "technique",
                       "q": f"L'offre exige « {s} » — décrivez un projet concret où vous l'avez utilisé, avec le résultat."})
        for s in missing:
            qs.append({"type": "weakness",
                       "q": f"L'offre demande « {s} », qui n'apparaît pas dans votre CV — comment comptez-vous compenser ?"})
        qs.append({"type": "behavioral",
                   "q": f"Décrivez une réalisation passée qui prouve que vous réussirez dans ce poste de {title}."})
        return {"questions": qs, "job_title": title, "targeted": True}

    # ---- generic CV-based training ----
    title = prof.get("title") or "ce poste"
    skills = (prof.get("skills") or [])[:5]
    qs = [
        {"type": "pitch", "q": "Présentez-vous en 2 minutes (pitch elevator)."},
        {"type": "motivation", "q": f"Pourquoi voulez-vous ce poste de {title} ?"},
        {"type": "persuasion", "q": "En 30 secondes, convainquez le recruteur que vous êtes le meilleur candidat."},
        {"type": "behavioral", "q": "Décrivez un échec professionnel et ce que vous en avez appris."},
        {"type": "behavioral", "q": "Racontez une situation de conflit en équipe et comment vous l'avez gérée."},
        {"type": "weakness", "q": "Quel est votre principal point faible, et comment le compensez-vous ?"},
        {"type": "negotiation", "q": "Quelles sont vos prétentions salariales, et comment les justifiez-vous ?"},
    ]
    for s in skills:
        qs.append({"type": "technique",
                   "q": f"Décrivez un projet concret où vous avez utilisé {s}, et le résultat obtenu."})
    return {"questions": qs, "targeted": False}


_ACTION_VERBS = ["dirigé", "géré", "gérer", "créé", "conçu", "développé", "lancé",
                 "optimisé", "amélioré", "augmenté", "réduit", "mis en place", "piloté",
                 "coordonné", "livré", "négocié", "formé", "construit", "automatisé", "déployé"]
_IMPACT_WORDS = ["résultat", "impact", "%", "augment", "réduit", "économis", "croissance",
                 "chiffre d'affaires", "roi", "gain", "performance", "doublé", "x2"]


def _score_answer(answer: str, profile_skills: list) -> dict:
    """Return an 8-axis breakdown (0-100 each), overall score and tips."""
    a = answer.strip()
    low = a.lower()
    n = len(a.split())
    tips = []

    star = sum(k in low for k in ["situation", "contexte", "tâche", "objectif", "mission",
                                  "action", "j'ai", "mis en place", "résultat", "impact", "abouti"])
    structure = round(min(star / 4, 1.0) * 100)
    if star < 2:
        tips.append("Structure en méthode STAR : Situation, Tâche, Action, Résultat.")

    resultats = 100 if _re.search(r"\d", a) else 40
    if resultats < 100:
        tips.append("Ajoute des résultats chiffrés (%, €, délais, volumes).")

    clarte = 100 if 40 <= n <= 200 else (60 if 20 <= n < 40 else 35 if n < 20 else 70)
    if n < 20:
        tips.append("Réponse trop courte — développe avec un exemple concret.")

    fillers = sum(low.count(f) for f in ["euh", "je pense que", "peut-être", "un peu", "en fait", "voilà"])
    assurance = max(0, 100 - fillers * 18)
    if fillers >= 2:
        tips.append("Évite les hésitations (« euh », « peut-être ») — sois affirmatif.")

    mine = {s.lower() for s in (profile_skills or [])}
    matched = sum(1 for s in mine if s in low)
    pertinence = min(matched / 3, 1.0) * 100 if mine else 60
    if mine and matched == 0:
        tips.append("Mentionne tes compétences clés (du CV) en lien avec la question.")

    actions = sum(1 for v in _ACTION_VERBS if v in low)
    action = round(min(actions / 3, 1.0) * 100)
    if actions < 1:
        tips.append("Utilise des verbes d'action (j'ai dirigé, optimisé, livré…).")

    concision = 100 if n <= 200 else (70 if n <= 300 else 45)

    impact = 100 if any(w in low for w in _IMPACT_WORDS) else 50
    if impact < 100:
        tips.append("Termine sur l'impact concret de ton action.")

    axes = {"structure": structure, "résultats": resultats, "clarté": clarte,
            "assurance": assurance, "pertinence": round(pertinence), "verbes d'action": action,
            "concision": concision, "impact": impact}
    score = round(sum(axes.values()) / len(axes))
    if not tips:
        tips.append("Excellent — réponse structurée, concrète et percutante !")
    return {"score": score, "axes": axes, "tips": tips[:3]}


@app.post("/training/score")
def training_score(body: TrainingScoreIn, background: BackgroundTasks,
                   user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        prof = _profile(conn, user["id"])
        # for targeted training, "pertinence" is measured against the offer's skills
        relevant = prof.get("skills") or []
        if body.job_id:
            job = conn.execute("SELECT * FROM jobs WHERE id=?", (body.job_id,)).fetchone()
            if job:
                relevant = sorted(matching._job_skills(_job_row_to_dict(job)))
    res = _score_answer(body.answer, relevant)
    background.add_task(_safe_ping, user["id"])  # training counts toward the streak
    return {"score": res["score"], "tips": res["tips"], "breakdown": res["axes"]}


class TrainingSessionIn(BaseModel):
    score: int
    axes: dict
    answers: int


@app.post("/training/session")
def save_training_session(body: TrainingSessionIn, user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO training_sessions (user_id, score, axes, answers) VALUES (?,?,?,?)",
            (user["id"], body.score, json.dumps(body.axes), body.answers))
    return {"saved": True}


@app.get("/training/history")
def training_history(user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT score, axes, answers, created_at FROM training_sessions "
            "WHERE user_id=? ORDER BY id", (user["id"],)).fetchall()
    sessions = [{"score": r["score"], "axes": json.loads(r["axes"] or "{}"),
                 "answers": r["answers"], "date": r["created_at"]} for r in rows]

    # averaged radar across sessions
    radar = {}
    if sessions:
        keys = sessions[-1]["axes"].keys()
        for k in keys:
            vals = [s["axes"].get(k, 0) for s in sessions if k in s["axes"]]
            radar[k] = round(sum(vals) / len(vals)) if vals else 0

    # recommendations = weakest 3 axes (averaged)
    recos = []
    if radar:
        weakest = sorted(radar.items(), key=lambda kv: kv[1])[:3]
        advice = {
            "structure": "Travaille la méthode STAR pour des réponses charpentées.",
            "résultats": "Chiffre systématiquement tes résultats (%, €, délais).",
            "clarté": "Vise 40-200 mots : assez pour illustrer, sans diluer.",
            "assurance": "Supprime les hésitations, formule des affirmations nettes.",
            "pertinence": "Rattache chaque réponse à tes compétences clés du CV.",
            "verbes d'action": "Démarre tes phrases par des verbes d'action forts.",
            "concision": "Va à l'essentiel, une idée par phrase.",
            "impact": "Conclus toujours sur l'impact business de ton action.",
        }
        recos = [{"axis": k, "score": v, "advice": advice.get(k, "")} for k, v in weakest]

    avg = round(sum(s["score"] for s in sessions) / len(sessions)) if sessions else 0
    trend = (sessions[-1]["score"] - sessions[0]["score"]) if len(sessions) >= 2 else 0
    return {"count": len(sessions), "avg_score": avg, "trend": trend,
            "radar": radar, "recommendations": recos,
            "evolution": [{"date": s["date"], "score": s["score"]} for s in sessions]}


def _safe_ping(uid: int):
    try:
        today = date.today().isoformat()
        with get_conn() as conn:
            conn.execute(
                """INSERT INTO activity (user_id, day, count) VALUES (?, ?, 1)
                   ON CONFLICT(user_id, day) DO UPDATE SET count = activity.count + 1""",
                (uid, today))
    except Exception:
        pass


# ---------- Duolingo-style weekly activity tracking ----------
DAILY_GOAL = 3  # actions/day to keep the streak


@app.post("/activity/ping")
def activity_ping(user: dict = Depends(current_user)):
    today = date.today().isoformat()
    with get_conn() as conn:
        conn.execute(
            """INSERT INTO activity (user_id, day, count) VALUES (?, ?, 1)
               ON CONFLICT(user_id, day) DO UPDATE SET count = activity.count + 1""",
            (user["id"], today))
    return {"ok": True, "day": today}


@app.get("/activity")
def activity(user: dict = Depends(current_user)):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT day, count FROM activity WHERE user_id=?", (user["id"],)).fetchall()
    active = {r["day"]: r["count"] for r in rows}
    today = date.today()

    # current streak: consecutive active days ending today (or yesterday if not yet today)
    streak = 0
    cursor = today if today.isoformat() in active else today - timedelta(days=1)
    while cursor.isoformat() in active:
        streak += 1
        cursor -= timedelta(days=1)

    # best streak overall
    best = 0
    days_sorted = sorted(date.fromisoformat(d) for d in active)
    run = 0
    prev = None
    for d in days_sorted:
        run = run + 1 if (prev is not None and (d - prev).days == 1) else 1
        best = max(best, run)
        prev = d

    # last 7 days grid (oldest -> today)
    week = []
    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        iso = d.isoformat()
        week.append({"day": iso, "weekday": d.weekday(),
                     "active": iso in active, "count": active.get(iso, 0)})

    today_count = active.get(today.isoformat(), 0)
    return {
        "streak": streak,
        "best_streak": best,
        "daily_goal": DAILY_GOAL,
        "today_count": today_count,
        "goal_met": today_count >= DAILY_GOAL,
        "week": week,
        "active_days_total": len(active),
    }


# ---------- market insights (computed from scraped offers, no external key) ----------
def _parse_salary_amounts(s: str):
    """Extract plausible annual salary amounts (>= 1000) from a free-text salary."""
    out = []
    for m in _re.finditer(r"(\d+(?:[.,]\d+)?)\s*([kK])?", s or ""):
        try:
            val = float(m.group(1).replace(",", "."))
        except ValueError:
            continue
        if m.group(2):  # 'k' suffix
            val *= 1000
        if val >= 1000:
            out.append(int(val))
    return out


def _median(nums):
    if not nums:
        return None
    nums = sorted(nums)
    n = len(nums)
    return nums[n // 2] if n % 2 else (nums[n // 2 - 1] + nums[n // 2]) // 2


@app.get("/insights")
def market_insights(query: str = "", limit_skills: int = 15, user: dict = Depends(current_user)):
    """Market stats from the cached (recent) offers: top skills, your gap,
    indicative salary, breakdown by source — all computed locally."""
    from collections import Counter
    with get_conn() as conn:
        sql = "SELECT * FROM jobs"
        args = []
        if query:
            sql += " WHERE LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR LOWER(tags) LIKE ?"
            like = f"%{query.lower()}%"
            args += [like, like, like]
        rows = [_job_row_to_dict(r) for r in conn.execute(sql, args).fetchall()]
        profile = _profile(conn, user["id"]) if user["role"] == "seeker" else None

    # keep only recent offers (consistency with the listing)
    rows = [j for j in rows if (_job_age_days(j) or 0) <= config.JOB_RETENTION_DAYS]

    skill_counts = Counter()
    salaries = []
    by_source = Counter()
    for j in rows:
        by_source[j["source"]] += 1
        for s in matching._job_skills(j):
            skill_counts[s] += 1
        salaries.extend(_parse_salary_amounts(j.get("salary", "")))

    top = [{"skill": s, "count": c} for s, c in skill_counts.most_common(limit_skills)]

    have, missing = [], []
    if profile is not None:
        mine = {s.lower() for s in profile["skills"]}
        for item in top:
            (have if item["skill"].lower() in mine else missing).append(item["skill"])

    salary = None
    if len(salaries) >= 3:
        salary = {"median": _median(salaries), "min": min(salaries),
                  "max": max(salaries), "sample": len(salaries),
                  "note": "Indicatif — devises mêlées, basé sur les offres affichant un salaire."}

    return {
        "total_offers": len(rows),
        "top_skills": top,
        "your_skills_in_demand": have,
        "skills_to_learn": missing[:8],
        "salary": salary,
        "by_source": dict(by_source),
    }


@app.post("/favorites/{job_id}")
def toggle_favorite(job_id: int, user: dict = Depends(require_role("seeker"))):
    """Like/unlike an offer. Returns the new state."""
    with get_conn() as conn:
        exists = conn.execute("SELECT 1 FROM favorites WHERE user_id=? AND job_id=?",
                              (user["id"], job_id)).fetchone()
        if exists:
            conn.execute("DELETE FROM favorites WHERE user_id=? AND job_id=?", (user["id"], job_id))
            liked = False
        else:
            conn.execute("INSERT OR IGNORE INTO favorites (user_id, job_id) VALUES (?,?)",
                         (user["id"], job_id))
            liked = True
        count = conn.execute("SELECT COUNT(*) c FROM favorites WHERE user_id=?",
                            (user["id"],)).fetchone()["c"]
    return {"liked": liked, "count": count}


@app.post("/jobs/post")
def post_job(body: JobPostIn, user: dict = Depends(require_role("recruiter"))):
    with get_conn() as conn:
        cur = conn.execute(
            """INSERT INTO jobs (source, ext_id, title, company, location, url,
                   description, tags, salary, recruiter_id)
               VALUES ('recruiter', ?, ?, ?, ?, '', ?, ?, ?, ?)""",
            (f"r{user['id']}-{body.title[:20]}", body.title, body.company,
             body.location, body.description, json.dumps(body.tags),
             body.salary, user["id"]),
        )
    return {"id": cur.lastrowid, "status": "posted"}


# ---------- applications ----------
@app.post("/applications/auto")
def auto_apply(body: AutoApplyIn, user: dict = Depends(require_role("seeker"))):
    created = []
    with get_conn() as conn:
        profile = _profile(conn, user["id"])
        uname = conn.execute("SELECT name FROM users WHERE id=?", (user["id"],)).fetchone()["name"]
        for jid in body.job_ids:
            job = conn.execute("SELECT * FROM jobs WHERE id=?", (jid,)).fetchone()
            if not job:
                continue
            jd = _job_row_to_dict(job)
            m = matching.score(profile, jd)
            letter = cover_letter.generate(uname, profile["title"], profile["skills"], jd)
            try:
                cur = conn.execute(
                    """INSERT INTO applications (user_id, job_id, status, match_score, cover_letter)
                       VALUES (?, ?, 'auto_pending', ?, ?)""",
                    (user["id"], jid, m["score"], letter),
                )
                created.append({"application_id": cur.lastrowid, "job_id": jid,
                                "match_score": m["score"], "apply_url": jd.get("url", "")})
            except Exception:
                pass  # already applied
    return {"created": created, "status": "auto_pending",
            "note": "Une lettre de motivation a été générée pour chaque offre. "
                    "Validez la candidature puis postulez en un clic via le lien de l'offre."}


@app.post("/applications/{app_id}/applied")
def mark_applied(app_id: int, user: dict = Depends(require_role("seeker"))):
    """Candidate confirms they submitted the application on the source site."""
    return _set_status(app_id, user["id"], "applied")


@app.post("/applications/applied")
def record_applied(body: ApplyOneIn, background: BackgroundTasks,
                   user: dict = Depends(require_role("seeker"))):
    """Tapping 'Postuler' on an offer auto-records it as an application (status=applied)."""
    with get_conn() as conn:
        job = conn.execute("SELECT * FROM jobs WHERE id=?", (body.job_id,)).fetchone()
        if not job:
            raise HTTPException(404, "Offre introuvable")
        profile = _profile(conn, user["id"])
        uname = conn.execute("SELECT name FROM users WHERE id=?", (user["id"],)).fetchone()["name"]
        jd = _job_row_to_dict(job)
        m = matching.score(profile, jd)
        letter = cover_letter.generate(uname, profile["title"], profile["skills"], jd)
        conn.execute(
            """INSERT INTO applications (user_id, job_id, status, match_score, cover_letter)
               VALUES (?, ?, 'applied', ?, ?)
               ON CONFLICT(user_id, job_id) DO UPDATE SET status='applied'""",
            (user["id"], body.job_id, m["score"], letter))
        total = conn.execute(
            "SELECT COUNT(*) c FROM applications WHERE user_id=? AND status IN ('applied','validated')",
            (user["id"],)).fetchone()["c"]
    background.add_task(_safe_ping, user["id"])
    return {"status": "applied", "applied_count": total}


@app.post("/applications/{app_id}/validate")
def validate_application(app_id: int, user: dict = Depends(require_role("seeker"))):
    return _set_status(app_id, user["id"], "validated")


@app.post("/applications/{app_id}/reject")
def reject_application(app_id: int, user: dict = Depends(require_role("seeker"))):
    return _set_status(app_id, user["id"], "rejected")


def _set_status(app_id, uid, status):
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM applications WHERE id=? AND user_id=?",
                           (app_id, uid)).fetchone()
        if not row:
            raise HTTPException(404, "Application not found")
        conn.execute("UPDATE applications SET status=? WHERE id=?", (status, app_id))
    return {"id": app_id, "status": status}


@app.get("/applications")
def my_applications(user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        rows = conn.execute(
            """SELECT a.id, a.status, a.match_score, a.created_at, a.cover_letter,
                      j.title, j.company, j.location, j.url, j.source
               FROM applications a JOIN jobs j ON j.id=a.job_id
               WHERE a.user_id=? ORDER BY a.created_at DESC""",
            (user["id"],)).fetchall()
    return {"applications": [dict(r) for r in rows]}


# ---------- dashboards ----------
@app.get("/dashboard/seeker")
def seeker_dashboard(user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        profile = _profile(conn, user["id"])
        apps = conn.execute(
            "SELECT status, COUNT(*) c, AVG(match_score) avg FROM applications "
            "WHERE user_id=? GROUP BY status", (user["id"],)).fetchall()
        total = conn.execute("SELECT COUNT(*) c FROM jobs").fetchone()["c"]
    by_status = {r["status"]: r["c"] for r in apps}
    avg_match = next((round(r["avg"]) for r in apps if r["avg"] is not None), 0)
    return {
        "profile": {"title": profile["title"], "location": profile["location"],
                    "skills": profile["skills"], "skill_count": len(profile["skills"])},
        "applications": {
            "applied": by_status.get("applied", 0),
            "validated": by_status.get("validated", 0),
            "pending": by_status.get("auto_pending", 0),
            "rejected": by_status.get("rejected", 0),
            "total": sum(by_status.values()),
        },
        "avg_match_score": avg_match,
        "jobs_available": total,
    }


@app.get("/dashboard/recruiter")
def recruiter_dashboard(user: dict = Depends(require_role("recruiter"))):
    with get_conn() as conn:
        talent_count = conn.execute(
            "SELECT COUNT(*) c FROM profiles WHERE skills != '[]'").fetchone()["c"]
        my_jobs = conn.execute(
            "SELECT COUNT(*) c FROM jobs WHERE recruiter_id=?", (user["id"],)).fetchone()["c"]
        apps_to_my_jobs = conn.execute(
            """SELECT COUNT(*) c FROM applications a JOIN jobs j ON j.id=a.job_id
               WHERE j.recruiter_id=? AND a.status='validated'""",
            (user["id"],)).fetchone()["c"]
    return {
        "talent_pool_size": talent_count,
        "my_posted_jobs": my_jobs,
        "applications_received": apps_to_my_jobs,
    }


# ---------- talent access (recruiter must contact us first) ----------
def _talent_access(conn, uid) -> str:
    if config.OPEN_TALENTS:
        return "granted"  # open access: every recruiter can browse candidates
    row = conn.execute("SELECT talent_access FROM users WHERE id=?", (uid,)).fetchone()
    return (row["talent_access"] if row else "none") or "none"


@app.get("/recruiter/access-status")
def access_status(user: dict = Depends(require_role("recruiter"))):
    with get_conn() as conn:
        status = _talent_access(conn, user["id"])
    return {"status": status, "has_access": status == "granted"}


@app.post("/recruiter/request-access")
def request_access(body: ContactRequestIn, background: BackgroundTasks,
                   user: dict = Depends(require_role("recruiter"))):
    if not body.company.strip():
        raise HTTPException(400, "Le nom de l'entreprise est requis")
    with get_conn() as conn:
        current = _talent_access(conn, user["id"])
        if current == "granted":
            return {"status": "granted", "message": "Accès déjà actif."}
        conn.execute(
            "INSERT INTO contact_requests (user_id, company, phone, message) VALUES (?,?,?,?)",
            (user["id"], body.company.strip(), body.phone.strip(), body.message.strip()),
        )
        conn.execute("UPDATE users SET talent_access='pending' WHERE id=?", (user["id"],))
    # notify the platform operator by email (non-blocking)
    background.add_task(
        notifications.send_contact_notification,
        recruiter_name=user["name"], recruiter_email=user["email"],
        company=body.company.strip(), phone=body.phone.strip(), message=body.message.strip(),
    )
    return {"status": "pending",
            "message": "Demande envoyée. Notre équipe vous recontacte pour activer l'accès à la base de talents."}


@app.post("/admin/grant-access")
def grant_access(email: str, x_admin_token: Optional[str] = Header(None)):
    """Platform-side: activate a recruiter's talent access after contact.
    Protected by the dedicated CAREER_AI_ADMIN_TOKEN (never the signing secret)."""
    if not security.admin_token_ok(x_admin_token):
        raise HTTPException(403, "Forbidden")
    with get_conn() as conn:
        row = conn.execute("SELECT id FROM users WHERE email=? AND role='recruiter'", (email,)).fetchone()
        if not row:
            raise HTTPException(404, "Recruiter not found")
        conn.execute("UPDATE users SET talent_access='granted' WHERE id=?", (row["id"],))
        conn.execute("UPDATE contact_requests SET status='granted' WHERE user_id=?", (row["id"],))
    return {"email": email, "status": "granted"}


# ---------- talent base (recruiter) ----------
@app.get("/talents")
def talents(query: str = "", job_id: Optional[int] = None,
            user: dict = Depends(require_role("recruiter"))):
    """Return candidate profiles ranked by match against a query or a posted job.

    Gated: a recruiter must request access (contact us) and be granted first.
    """
    with get_conn() as conn:
        if _talent_access(conn, user["id"]) != "granted":
            raise HTTPException(403, "Accès à la base de talents non activé. Contactez-nous pour l'obtenir.")
    # Build a pseudo-job from the query or load a real posted job
    if job_id:
        with get_conn() as conn:
            jrow = conn.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        target = _job_row_to_dict(jrow) if jrow else {"title": query, "description": query, "tags": []}
    else:
        target = {"title": query, "description": query,
                  "tags": query.split() if query else []}

    with get_conn() as conn:
        # A candidate shows up once they are real & active: they uploaded a CV
        # (have skills) OR they applied to at least one offer.
        rows = conn.execute(
            """SELECT p.user_id, p.title, p.location, p.skills, p.cv_text, u.name,
                      (SELECT COUNT(*) FROM applications a WHERE a.user_id=p.user_id) AS applied
               FROM profiles p JOIN users u ON u.id=p.user_id
               WHERE p.skills != '[]'
                  OR p.user_id IN (SELECT user_id FROM applications)""").fetchall()

    results = []
    for r in rows:
        prof = {"title": r["title"], "location": r["location"],
                "cv_text": r["cv_text"], "skills": json.loads(r["skills"] or "[]")}
        m = matching.score(prof, target)
        results.append({
            # email intentionally omitted — recruiters contact via the platform
            "candidate_id": r["user_id"], "name": r["name"],
            "title": r["title"], "location": r["location"],
            "skills": prof["skills"], "match": m,
            "applied": r["applied"] or 0,
        })
    # active applicants first, then by match score
    results.sort(key=lambda x: (x["applied"] > 0, x["match"]["score"]), reverse=True)
    return {"count": len(results), "candidates": results}


# ---------- placement: company asks to be connected with a specific freelance ----------
@app.post("/talents/{candidate_id}/request")
def request_placement(candidate_id: int, body: PlacementRequestIn, background: BackgroundTasks,
                      user: dict = Depends(require_role("recruiter"))):
    """A company selects a freelance -> we get an automatic email and arrange it."""
    with get_conn() as conn:
        if _talent_access(conn, user["id"]) != "granted":
            raise HTTPException(403, "Accès non activé. Contactez-nous d'abord.")
        cand = conn.execute(
            """SELECT u.id, u.name, u.email, p.title, p.skills, p.cv_text
               FROM users u JOIN profiles p ON p.user_id=u.id
               WHERE u.id=? AND u.role='seeker'""", (candidate_id,)).fetchone()
        if not cand:
            raise HTTPException(404, "Freelance introuvable")
        # recruiter's company/phone from their access request
        cr = conn.execute(
            "SELECT company, phone FROM contact_requests WHERE user_id=? ORDER BY id DESC LIMIT 1",
            (user["id"],)).fetchone()
        company = (cr["company"] if cr else "") or user["name"]
        phone = cr["phone"] if cr else ""

        skills = json.loads(cand["skills"] or "[]")
        prof = {"title": cand["title"], "skills": skills, "cv_text": cand["cv_text"]}
        m = matching.score(prof, {"title": body.message, "description": body.message, "tags": []})
        conn.execute(
            """INSERT INTO placement_requests (recruiter_id, candidate_id, company, message, match_score)
               VALUES (?,?,?,?,?)""",
            (user["id"], candidate_id, company, body.message.strip(), m["score"]),
        )

    background.add_task(
        notifications.send_placement_request,
        company=company, recruiter_name=user["name"], recruiter_email=user["email"],
        recruiter_phone=phone, freelance_name=cand["name"], freelance_email=cand["email"],
        freelance_title=cand["title"], freelance_skills=skills,
        match_score=m["score"], message=body.message.strip(),
    )
    return {"status": "requested",
            "message": f"Demande de mise en relation avec {cand['name']} envoyée. "
                       "Notre équipe organise le contact."}


class InterviewIn(BaseModel):
    candidate_id: int
    scheduled_at: str = ""
    teams_link: str = ""
    meeting_type: str = "visio"   # visio | phone | onsite
    location: str = ""            # address (onsite) or phone number
    duration_min: int = 30
    message: str = ""


@app.post("/recruiter/interview")
def schedule_interview(body: InterviewIn, background: BackgroundTasks,
                       user: dict = Depends(require_role("recruiter"))):
    """Recruiter picks a candidate and schedules an interview with a Teams link."""
    with get_conn() as conn:
        if _talent_access(conn, user["id"]) != "granted":
            raise HTTPException(403, "Accès non activé. Contactez-nous d'abord.")
        cand = conn.execute("SELECT id, name, email FROM users WHERE id=? AND role='seeker'",
                            (body.candidate_id,)).fetchone()
        if not cand:
            raise HTTPException(404, "Candidat introuvable")
        cr = conn.execute(
            "SELECT company FROM contact_requests WHERE user_id=? ORDER BY id DESC LIMIT 1",
            (user["id"],)).fetchone()
        company = (cr["company"] if cr else "") or user["name"]
        conn.execute(
            """INSERT INTO interviews (recruiter_id, candidate_id, company, scheduled_at,
                   teams_link, meeting_type, location, duration_min, message)
               VALUES (?,?,?,?,?,?,?,?,?)""",
            (user["id"], body.candidate_id, company, body.scheduled_at.strip(),
             body.teams_link.strip(), (body.meeting_type or "visio").strip(),
             body.location.strip(), int(body.duration_min or 30), body.message.strip()))
    background.add_task(
        notifications.send_interview_invite,
        to_email=cand["email"], candidate_name=cand["name"], company=company,
        scheduled_at=body.scheduled_at.strip(), teams_link=body.teams_link.strip(),
        message=body.message.strip())
    return {"status": "proposed",
            "message": f"Entretien proposé à {cand['name']}. Il/elle le verra dans l'app."}


@app.get("/recruiter/interviews")
def recruiter_interviews(user: dict = Depends(require_role("recruiter"))):
    with get_conn() as conn:
        rows = conn.execute(
            """SELECT i.*, u.name AS candidate_name FROM interviews i
               JOIN users u ON u.id=i.candidate_id
               WHERE i.recruiter_id=? ORDER BY i.id DESC""", (user["id"],)).fetchall()
    return {"interviews": [dict(r) for r in rows]}


@app.get("/me/interviews")
def my_interviews(user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT id, company, scheduled_at, teams_link, meeting_type, location, "
            "duration_min, message, status, created_at "
            "FROM interviews WHERE candidate_id=? ORDER BY id DESC", (user["id"],)).fetchall()
    return {"interviews": [dict(r) for r in rows]}


@app.post("/interviews/{iid}/respond")
def respond_interview(iid: int, accept: bool, user: dict = Depends(require_role("seeker"))):
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM interviews WHERE id=? AND candidate_id=?",
                           (iid, user["id"])).fetchone()
        if not row:
            raise HTTPException(404, "Entretien introuvable")
        conn.execute("UPDATE interviews SET status=? WHERE id=?",
                     ("accepted" if accept else "declined", iid))
    return {"id": iid, "status": "accepted" if accept else "declined"}


@app.get("/admin/placement-requests")
def list_placements(x_admin_token: Optional[str] = Header(None)):
    """Platform-side: every freelance-placement request to arrange & bill."""
    if not security.admin_token_ok(x_admin_token):
        raise HTTPException(403, "Forbidden")
    with get_conn() as conn:
        rows = conn.execute(
            """SELECT pr.id, pr.company, pr.message, pr.match_score, pr.status, pr.created_at,
                      r.name AS recruiter_name, r.email AS recruiter_email,
                      f.name AS freelance_name, f.email AS freelance_email
               FROM placement_requests pr
               JOIN users r ON r.id=pr.recruiter_id
               JOIN users f ON f.id=pr.candidate_id
               ORDER BY pr.id DESC""").fetchall()
    return {"placement_requests": [dict(r) for r in rows]}


@app.get("/")
def root():
    return {"app": "Career AI", "status": "ok", "docs": "/docs",
            "sources_keyless": ["remoteok", "remotive", "arbeitnow", "themuse",
                                "jobicy", "linkedin"],
            "sources_with_key": ["adzuna (ADZUNA_*)", "francetravail (FT_*)",
                                 "jsearch=LinkedIn/Indeed/Glassdoor… (RAPIDAPI_KEY)"]}
