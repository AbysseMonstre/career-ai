"""End-to-end smoke test of the API against the real Neon database.

Exercises the paths that the Postgres shim rewrites (INSERT OR IGNORE, upserts,
RETURNING id, datetime arithmetic) plus the new cv_structure column.
"""
import os
import time

os.environ["CAREER_AI_DATABASE_URL"] = open("/tmp/.neon_uri").read().strip()
os.environ.setdefault("CAREER_AI_SECRET", "smoke-test-secret")

from fastapi.testclient import TestClient  # noqa: E402
from app.main import app  # noqa: E402

c = TestClient(app)
email = f"smoke{int(time.time())}@example.com"
ok = True


def check(label, cond, extra=""):
    global ok
    ok = ok and cond
    print(f"{'OK  ' if cond else 'ECHEC'} {label} {extra}")


r = c.post("/auth/register", json={"email": email, "name": "Smoke",
                                   "password": "Test12345!", "role": "seeker",
                                   "consent": True})
check("register", r.status_code == 200, f"[{r.status_code}]")
token = r.json()["token"]
h = {"Authorization": f"Bearer {token}"}

r = c.post("/auth/login", json={"email": email, "password": "Test12345!"})
check("login", r.status_code == 200, f"[{r.status_code}]")

with open("/Users/maha/Desktop/The Vault Manifesto/Chef de projet junior.pdf", "rb") as f:
    r = c.post("/cv/upload", headers=h, files={"file": ("cv.pdf", f, "application/pdf")})
check("upload CV", r.status_code == 200, f"[{r.status_code}]")
if r.status_code == 200:
    s = r.json()["structure"]
    check("structure extraite", len(s["experiences"]) == 4,
          f"{len(s['experiences'])} experiences, {s['total_experience_months']} mois")

r = c.get("/cv", headers=h)
check("relecture CV (persistance)", r.status_code == 200 and
      len(r.json().get("structure", {}).get("experiences", [])) == 4,
      f"[{r.status_code}]")

r = c.get("/jobs?limit=5", headers=h)
check("recherche offres", r.status_code == 200, f"[{r.status_code}] "
      f"{len(r.json().get('jobs', []))} offres")

r = c.get("/dashboard/seeker", headers=h)
check("dashboard (upsert activity)", r.status_code == 200, f"[{r.status_code}]")

r = c.post("/activity/ping", headers=h)
check("activity ping (upsert PG)", r.status_code == 200, f"[{r.status_code}]")

r = c.delete("/me", headers=h)
check("suppression compte (RGPD)", r.status_code in (200, 204), f"[{r.status_code}]")

print("\n=>", "TOUT PASSE" if ok else "DES ETAPES ONT ECHOUE")
