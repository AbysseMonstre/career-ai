"""Real, key-less job sources with public JSON endpoints.

These are genuinely fetchable from a server without auth/captcha. To add a
gated board (LinkedIn/Indeed) plug a new BaseScraper subclass here that goes
through your proxy layer — the aggregator picks it up automatically.
"""
import os
import re
import requests
from .base import BaseScraper, http_get, strip_html, TIMEOUT, UA


class RemoteOK(BaseScraper):
    name = "remoteok"

    def fetch(self, query="", location=""):
        try:
            data = http_get("https://remoteok.com/api").json()
        except Exception:
            return []
        out = []
        for j in data:
            if not isinstance(j, dict) or "id" not in j or "position" not in j:
                continue  # first element is legal metadata
            out.append({
                "source": self.name,
                "ext_id": str(j.get("id")),
                "title": j.get("position", ""),
                "company": j.get("company", ""),
                "location": j.get("location") or "Remote",
                "url": j.get("url", ""),
                "description": strip_html(j.get("description", "")),
                "tags": j.get("tags", []) or [],
                "salary": _salary(j.get("salary_min"), j.get("salary_max")),
                "posted_at": j.get("date", ""),
            })
        return out


class Remotive(BaseScraper):
    name = "remotive"

    def fetch(self, query="", location=""):
        params = {"search": query} if query else None
        try:
            data = http_get("https://remotive.com/api/remote-jobs", params=params).json()
        except Exception:
            return []
        out = []
        for j in data.get("jobs", []):
            out.append({
                "source": self.name,
                "ext_id": str(j.get("id")),
                "title": j.get("title", ""),
                "company": j.get("company_name", ""),
                "location": j.get("candidate_required_location") or "Remote",
                "url": j.get("url", ""),
                "description": strip_html(j.get("description", "")),
                "tags": j.get("tags", []) or [],
                "salary": j.get("salary", "") or "",
                "posted_at": j.get("publication_date", ""),
            })
        return out


class Arbeitnow(BaseScraper):
    name = "arbeitnow"

    def fetch(self, query="", location=""):
        try:
            data = http_get("https://www.arbeitnow.com/api/job-board-api").json()
        except Exception:
            return []
        out = []
        for j in data.get("data", []):
            loc = j.get("location") or ("Remote" if j.get("remote") else "")
            out.append({
                "source": self.name,
                "ext_id": str(j.get("slug")),
                "title": j.get("title", ""),
                "company": j.get("company_name", ""),
                "location": loc,
                "url": j.get("url", ""),
                "description": strip_html(j.get("description", "")),
                "tags": j.get("tags", []) or [],
                "salary": "",
                "posted_at": str(j.get("created_at", "")),
            })
        return out


class TheMuse(BaseScraper):
    name = "themuse"

    def fetch(self, query="", location=""):
        params = {"page": 1}
        if location:
            params["location"] = location
        try:
            data = http_get("https://www.themuse.com/api/public/jobs", params=params).json()
        except Exception:
            return []
        out = []
        for j in data.get("results", []):
            locs = ", ".join(l.get("name", "") for l in j.get("locations", []))
            out.append({
                "source": self.name,
                "ext_id": str(j.get("id")),
                "title": j.get("name", ""),
                "company": (j.get("company") or {}).get("name", ""),
                "location": locs or "Flexible",
                "url": (j.get("refs") or {}).get("landing_page", ""),
                "description": strip_html(j.get("contents", "")),
                "tags": [c.get("name", "") for c in j.get("categories", [])],
                "salary": "",
                "posted_at": j.get("publication_date", ""),
            })
        return out


class Jobicy(BaseScraper):
    name = "jobicy"

    def fetch(self, query="", location=""):
        params = {"count": 50}
        if query:
            params["tag"] = query
        try:
            data = http_get("https://jobicy.com/api/v2/remote-jobs", params=params).json()
        except Exception:
            return []
        out = []
        for j in data.get("jobs", []):
            ind = j.get("jobIndustry")
            tags = ind if isinstance(ind, list) else ([ind] if ind else [])
            out.append({
                "source": self.name,
                "ext_id": str(j.get("id")),
                "title": j.get("jobTitle", ""),
                "company": j.get("companyName", ""),
                "location": j.get("jobGeo") or "Remote",
                "url": j.get("url", ""),
                "description": strip_html(j.get("jobDescription", "") or j.get("jobExcerpt", "")),
                "tags": [str(t) for t in tags if t],
                "salary": "",
                "posted_at": j.get("pubDate", ""),
            })
        return out


class Adzuna(BaseScraper):
    """Activated when ADZUNA_APP_ID + ADZUNA_APP_KEY are set. Country via ADZUNA_COUNTRY (default fr)."""
    name = "adzuna"

    def fetch(self, query="", location=""):
        app_id = os.environ.get("ADZUNA_APP_ID")
        app_key = os.environ.get("ADZUNA_APP_KEY")
        if not (app_id and app_key):
            return []
        country = os.environ.get("ADZUNA_COUNTRY", "fr")
        pages = int(os.environ.get("ADZUNA_PAGES", "2"))  # 50 results/page
        out = []
        for page in range(1, pages + 1):
            params = {"app_id": app_id, "app_key": app_key, "results_per_page": 50,
                      "what": query or "developer", "content-type": "application/json"}
            if location:
                params["where"] = location
            try:
                url = f"https://api.adzuna.com/v1/api/jobs/{country}/search/{page}"
                results = http_get(url, params=params).json().get("results", [])
            except Exception:
                break
            for j in results:
                out.append({
                    "source": self.name,
                    "ext_id": str(j.get("id")),
                    "title": j.get("title", ""),
                    "company": (j.get("company") or {}).get("display_name", ""),
                    "location": (j.get("location") or {}).get("display_name", ""),
                    "url": j.get("redirect_url", ""),
                    "description": strip_html(j.get("description", "")),
                    "tags": [(j.get("category") or {}).get("label", "")] if j.get("category") else [],
                    "salary": _salary(j.get("salary_min"), j.get("salary_max")),
                    "posted_at": j.get("created", ""),
                })
            if len(results) < 50:
                break
        return out


class FranceTravail(BaseScraper):
    """Pôle emploi / France Travail offers API (OAuth2 client credentials).
    Activated when FT_CLIENT_ID + FT_CLIENT_SECRET are set."""
    name = "francetravail"

    def _token(self, cid, secret):
        resp = requests.post(
            "https://entreprise.francetravail.fr/connexion/oauth2/access_token",
            params={"realm": "/partenaire"},
            data={"grant_type": "client_credentials", "client_id": cid,
                  "client_secret": secret,
                  "scope": "api_offresdemploiv2 o2dsoffre"},
            timeout=TIMEOUT,
        )
        resp.raise_for_status()
        return resp.json()["access_token"]

    def fetch(self, query="", location=""):
        cid = os.environ.get("FT_CLIENT_ID")
        secret = os.environ.get("FT_CLIENT_SECRET")
        if not (cid and secret):
            return []
        try:
            token = self._token(cid, secret)
        except Exception:
            return []
        headers = {"Authorization": f"Bearer {token}"}
        pages = int(os.environ.get("FT_PAGES", "2"))  # 150 results per page
        out = []
        for i in range(pages):
            start = i * 150
            params = {"range": f"{start}-{start + 149}"}
            if query:
                params["motsCles"] = query
            try:
                resp = requests.get(
                    "https://api.francetravail.io/partenaire/offresdemploi/v2/offres/search",
                    headers=headers, params=params, timeout=TIMEOUT)
                if resp.status_code not in (200, 206):
                    break
                res = resp.json().get("resultats", [])
            except Exception:
                break
            for j in res:
                out.append({
                    "source": self.name,
                    "ext_id": str(j.get("id")),
                    "title": j.get("intitule", ""),
                    "company": (j.get("entreprise") or {}).get("nom", ""),
                    "location": (j.get("lieuTravail") or {}).get("libelle", ""),
                    "url": (j.get("origineOffre") or {}).get("urlOrigine", ""),
                    "description": strip_html(j.get("description", "")),
                    "tags": [c.get("libelle", "") for c in (j.get("competences") or [])][:5],
                    "salary": (j.get("salaire") or {}).get("libelle", "") or "",
                    "posted_at": j.get("dateCreation", ""),
                })
            if len(res) < 150:
                break
        return out


class LinkedIn(BaseScraper):
    """LinkedIn public *guest* job-search endpoint (no auth).

    Returns HTML job cards. Fragile: LinkedIn rate-limits/blocks by IP over time,
    so treat results as best-effort. No description in the listing payload.
    """
    name = "linkedin"
    _CARD = re.compile(r'base-card__full-link[^"]*"\s+href="([^"?]+)', re.S)
    _TITLE = re.compile(r'base-search-card__title[^"]*">\s*(.*?)\s*</h3>', re.S)
    _COMPANY = re.compile(r'base-search-card__subtitle[^"]*">.*?>\s*(.*?)\s*</a>', re.S)
    _LOC = re.compile(r'job-search-card__location[^"]*">\s*(.*?)\s*</span>', re.S)

    def fetch(self, query="", location=""):
        out = []
        seen = set()
        for start in (0, 25, 50):  # paginate for more volume
            params = {"keywords": query or "developer", "location": location or "", "start": start}
            try:
                html = http_get(
                    "https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search",
                    params=params, headers={"Accept": "text/html"}).text
            except Exception:
                break
            urls = self._CARD.findall(html)
            if not urls:
                break
            titles = self._TITLE.findall(html)
            companies = self._COMPANY.findall(html)
            locs = self._LOC.findall(html)
            for i, url in enumerate(urls):
                m = re.search(r"-(\d+)$", url)
                ext = m.group(1) if m else str(abs(hash(url)))
                if ext in seen:
                    continue
                seen.add(ext)
                out.append({
                    "source": self.name,
                    "ext_id": ext,
                    "title": strip_html(titles[i]) if i < len(titles) else "",
                    "company": strip_html(companies[i]) if i < len(companies) else "",
                    "location": strip_html(locs[i]) if i < len(locs) else (location or ""),
                    "url": url,
                    "description": "",
                    "tags": [],
                    "salary": "",
                    "posted_at": "",
                })
        return out


class JSearch(BaseScraper):
    """Legal aggregator (RapidAPI) of LinkedIn, Indeed, Glassdoor, ZipRecruiter,
    Google for Jobs… Activated when RAPIDAPI_KEY is set."""
    name = "jsearch"

    def fetch(self, query="", location=""):
        key = os.environ.get("RAPIDAPI_KEY")
        if not key:
            return []
        q = query or "developer"
        if location:
            q = f"{q} in {location}"
        try:
            resp = requests.get(
                "https://jsearch.p.rapidapi.com/search",
                params={"query": q, "page": "1", "num_pages": "1"},
                headers={"X-RapidAPI-Key": key, "X-RapidAPI-Host": "jsearch.p.rapidapi.com"},
                timeout=TIMEOUT)
            resp.raise_for_status()
            data = resp.json()
        except Exception:
            return []
        out = []
        for j in data.get("data", []):
            city = j.get("job_city") or ""
            country = j.get("job_country") or ""
            loc = ", ".join([p for p in (city, country) if p]) or "—"
            publisher = j.get("job_publisher") or ""
            out.append({
                "source": self.name,
                "ext_id": str(j.get("job_id")),
                "title": j.get("job_title", ""),
                "company": j.get("employer_name", ""),
                "location": loc,
                "url": j.get("job_apply_link", ""),
                "description": strip_html(j.get("job_description", "")),
                "tags": [t for t in [publisher, j.get("job_employment_type")] if t],
                "salary": "",
                "posted_at": j.get("job_posted_at_datetime_utc", ""),
            })
        return out


class Apec(BaseScraper):
    """APEC — French executive/cadre job board. Public search API, no key.
    Returns French offers with city + salary text."""
    name = "apec"

    def fetch(self, query="", location=""):
        body = {"motsCles": query or "", "sorts": [], "typesContrat": [],
                "pagination": {"startIndex": 0, "range": 100}}
        try:
            resp = requests.post(
                "https://www.apec.fr/cms/webservices/rechercheOffre",
                json=body, timeout=TIMEOUT,
                headers={"User-Agent": UA, "Referer": "https://www.apec.fr/",
                         "Accept": "application/json", "Content-Type": "application/json"})
            resp.raise_for_status()
            data = resp.json()
        except Exception:
            return []
        out = []
        for j in data.get("resultats", []):
            jid = str(j.get("id"))
            out.append({
                "source": self.name,
                "ext_id": jid,
                "title": j.get("intitule", ""),
                "company": j.get("nomCommercial", ""),
                "location": j.get("lieuTexte", "") or "France",
                "url": f"https://www.apec.fr/candidat/recherche-emploi.html/emploi/detail-offre/{jid}",
                "description": strip_html(j.get("texteOffre", "")),
                "tags": [],
                "salary": j.get("salaireTexte", "") or "",
                "posted_at": j.get("datePublication", ""),
            })
        return out


def _salary(lo, hi):
    if lo and hi:
        return f"{int(lo):,} - {int(hi):,}"
    if lo:
        return f"{int(lo):,}+"
    return ""


# keyless sources are always active; Adzuna/FranceTravail/JSearch self-disable without keys
ALL_SCRAPERS = [RemoteOK(), Remotive(), Arbeitnow(), TheMuse(), Jobicy(), LinkedIn(),
                Apec(), Adzuna(), FranceTravail(), JSearch()]
