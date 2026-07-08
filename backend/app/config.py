"""Central configuration loaded from the environment.

Nothing secret is hard-coded. In production set at least:
  CAREER_AI_SECRET, CAREER_AI_ADMIN_TOKEN, CAREER_AI_CORS_ORIGINS, CAREER_AI_ENV=production
"""
import os
import secrets

ENV = os.environ.get("CAREER_AI_ENV", "development")  # development | production
IS_PROD = ENV == "production"

# --- secrets ---
_DEFAULT_SECRET = "dev-secret-change-me"
SECRET = os.environ.get("CAREER_AI_SECRET", _DEFAULT_SECRET)
# Admin actions use a *separate* token, never the signing secret.
ADMIN_TOKEN = os.environ.get("CAREER_AI_ADMIN_TOKEN", "")

# --- CORS ---
# Comma-separated allowed origins. Default = common local dev hosts.
_origins = os.environ.get(
    "CAREER_AI_CORS_ORIGINS",
    "http://localhost:8090,http://127.0.0.1:8090,http://localhost:3000",
)
CORS_ORIGINS = [o.strip() for o in _origins.split(",") if o.strip()]

# --- data retention (RGPD) ---
JOB_RETENTION_DAYS = int(os.environ.get("CAREER_AI_JOB_RETENTION_DAYS", "30"))
CONTACT_RETENTION_DAYS = int(os.environ.get("CAREER_AI_CONTACT_RETENTION_DAYS", "365"))

# --- auth policy ---
MIN_PASSWORD_LEN = 8

# Open the talent base to every recruiter (no manual approval). Candidate emails
# are never exposed — recruiters contact/schedule through the platform.
OPEN_TALENTS = os.environ.get("CAREER_AI_OPEN_TALENTS", "1") == "1"

# --- background scheduler (periodic scrape + purge) ---
SCHEDULER_ENABLED = os.environ.get("CAREER_AI_SCHEDULER", "0") == "1"
REFRESH_EVERY_SEC = int(os.environ.get("CAREER_AI_REFRESH_SEC", str(6 * 3600)))

# Public URL of this backend. On Render it's provided automatically as
# RENDER_EXTERNAL_URL — used for the keep-alive self-ping (so the free instance
# never sleeps) and to auto-enable the scheduler when running in the cloud.
PUBLIC_URL = (os.environ.get("CAREER_AI_PUBLIC_URL")
              or os.environ.get("RENDER_EXTERNAL_URL") or "").rstrip("/")
KEEPALIVE_EVERY_SEC = int(os.environ.get("CAREER_AI_KEEPALIVE_SEC", "600"))  # 10 min < Render's 15


def validate_startup():
    """Fail fast in production if dangerous defaults are still in place."""
    global ADMIN_TOKEN
    problems = []
    if IS_PROD:
        if SECRET == _DEFAULT_SECRET:
            problems.append("CAREER_AI_SECRET utilise la valeur par défaut")
        if not ADMIN_TOKEN:
            problems.append("CAREER_AI_ADMIN_TOKEN n'est pas défini")
        if "*" in CORS_ORIGINS:
            problems.append("CORS ne doit pas être '*' en production")
    if problems:
        raise RuntimeError("Configuration de production invalide : " + "; ".join(problems))
    # In dev, auto-generate an admin token if none provided and persist it so
    # the operator can read it (stdout is buffered when redirected to a file).
    if not ADMIN_TOKEN:
        ADMIN_TOKEN = secrets.token_urlsafe(24)
        print(f"[config] CAREER_AI_ADMIN_TOKEN non défini — token dev généré : {ADMIN_TOKEN}",
              flush=True)
        try:
            path = os.path.join(os.path.dirname(__file__), "..", ".admin_token")
            with open(path, "w") as f:
                f.write(ADMIN_TOKEN)
        except Exception:
            pass
