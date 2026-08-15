"""Match score between a candidate profile and a job (0-100).

Weighted blend of:
  - skill overlap (recall of job skills covered by the candidate)  -> 44%
  - semantic similarity between CV text and the ad                 -> 22%
  - seniority fit (years required vs years held)                   -> 14%
  - title/keyword similarity                                       -> 12%
  - location compatibility (remote-friendly)                       -> 8%

Semantic and seniority only apply when the data exists (a CV with text, an ad
that states a requirement); their weight is otherwise handed to skills, so an
under-informed match is never inflated by a neutral default.

Returns an int score plus the matched/missing skills so the UI can show stats.
"""
import re
import math
from collections import Counter
from .cv_parser import SKILL_VOCAB, SKILL_ALIASES

_WORD = re.compile(r"[a-zA-ZÀ-ÿ0-9+#.]+")

# Common FR/EN stopwords filtered out of TF-IDF so generic words don't inflate similarity.
_STOP = {
    "the", "and", "for", "with", "you", "our", "are", "will", "have", "this", "that",
    "from", "your", "all", "out", "who", "job", "work", "team", "role", "des", "les",
    "une", "pour", "avec", "vous", "nous", "est", "sur", "dans", "qui", "que", "aux",
    "par", "plus", "son", "ses", "nos", "leur", "etc", "and/or", "a", "an", "to", "of",
    "in", "on", "as", "we", "is", "be", "at", "or", "it", "le", "la", "de", "du", "et",
    "un", "au",
}


def _tokens(text: str) -> set:
    return {w.lower() for w in _WORD.findall(text or "")}


def _bow(text: str) -> Counter:
    """Bag of meaningful words (length>=3, not a stopword), sublinear tf."""
    words = [w.lower() for w in _WORD.findall(text or "")
             if len(w) >= 3 and w.lower() not in _STOP]
    c = Counter(words)
    return Counter({w: 1 + math.log(n) for w, n in c.items()})


def _cosine(a: Counter, b: Counter) -> float:
    if not a or not b:
        return 0.0
    common = set(a) & set(b)
    dot = sum(a[w] * b[w] for w in common)
    na = math.sqrt(sum(v * v for v in a.values()))
    nb = math.sqrt(sum(v * v for v in b.values()))
    return dot / (na * nb) if na and nb else 0.0


def _job_skills(job: dict) -> set:
    """Skills implied by the job (tags + skills mentioned in title/description)."""
    tags = [str(t) for t in (job.get("tags") or [])]
    blob = " ".join([
        job.get("title", ""), job.get("description", ""), " ".join(tags),
    ]).lower()
    skills = set()
    for skill in SKILL_VOCAB:
        pat = r"(?<![a-z0-9])" + re.escape(skill) + r"(?![a-z0-9])"
        if re.search(pat, blob):
            skills.add(skill)
    for alias, canonical in SKILL_ALIASES.items():
        pat = r"(?<![a-z0-9])" + re.escape(alias) + r"(?![a-z0-9])"
        if re.search(pat, blob):
            skills.add(canonical)
    # include raw tags as skills too
    for t in tags:
        if t:
            skills.add(t.lower())
    return skills


# --- seniority ------------------------------------------------------------
# "3 ans d'expérience", "5+ years experience", "minimum 2 ans", "3 à 5 ans"
_EXP_PATTERNS = [
    re.compile(r"(\d{1,2})\s*(?:\+|ans?|années?)\s*(?:minimum\s+)?(?:d[e'’]\s*)?exp[ée]rience", re.I),
    re.compile(r"exp[ée]rience\s*(?:professionnelle\s*)?(?:de|d[e'’]|:)?\s*(\d{1,2})\s*ans?", re.I),
    re.compile(r"(?:minimum|au moins|mini\.?)\s*(\d{1,2})\s*ans?", re.I),
    re.compile(r"(\d{1,2})\s*\+?\s*years?(?:\s+of)?\s+experience", re.I),
    re.compile(r"(?:minimum|at least)\s*(\d{1,2})\s*years?", re.I),
]
# "3 à 5 ans", "3-5 years" — the lower bound is the one that gates applications.
_EXP_RANGE = re.compile(
    r"(\d{1,2})\s*(?:à|a|-|–|—|to)\s*\d{1,2}\s*\+?\s*(?:ans?|années?|years?)", re.I)
# Fallbacks when the ad states a level instead of a number of years.
_JUNIOR_TERMS = ("junior", "débutant", "debutant", "entry level", "entry-level",
                 "graduate", "stage", "stagiaire", "alternance", "alternant",
                 "apprenti", "apprentissage", "first experience", "première expérience")
_SENIOR_TERMS = ("senior", "confirmé", "confirme", "expérimenté", "experimente",
                 "lead ", "principal", "head of", "expert", "8 ans", "10 ans")


def required_experience_months(text: str):
    """Months of experience an ad asks for, or None when it does not say."""
    if not text:
        return None
    years = [int(m.group(1)) for p in (*_EXP_PATTERNS, _EXP_RANGE)
             for m in p.finditer(text) if 0 < int(m.group(1)) <= 20]
    if years:
        return min(years) * 12  # "3 à 5 ans" -> the floor is what gates you
    low = text.lower()
    if any(t in low for t in _JUNIOR_TERMS):
        return 0
    if any(t in low for t in _SENIOR_TERMS):
        return 60
    return None


def seniority_fit(candidate_months: int, required_months: int) -> float:
    """1.0 when the candidate clears the bar, degrading as the gap widens."""
    if required_months <= 0:
        return 1.0
    ratio = candidate_months / required_months
    if ratio >= 1.0:
        # far above the ask is its own kind of mismatch, but a mild one
        return 0.85 if candidate_months > required_months + 96 else 1.0
    if ratio >= 0.7:
        return 0.85
    if ratio >= 0.4:
        return 0.6
    return 0.3


def score(profile: dict, job: dict) -> dict:
    cand_skills = {s.lower() for s in profile.get("skills", [])}
    job_skills = _job_skills(job)

    # 1) skill overlap. Floor the denominator at 3 so an under-specified job
    #    (e.g. one that only mentions "python") can't trivially hit 100% and
    #    out-rank a job where the candidate genuinely matches many skills.
    if job_skills:
        matched = cand_skills & job_skills
        skill_score = len(matched) / max(len(job_skills), 3)
    else:
        matched = set()
        skill_score = 0.3  # neutral when the job lists no detectable skills

    # 2) title / keyword similarity (Jaccard over tokens)
    cand_text = (profile.get("title", "") + " " + " ".join(cand_skills))
    a, b = _tokens(cand_text), _tokens(job.get("title", ""))
    title_score = len(a & b) / len(a | b) if (a | b) else 0.0

    # 3) semantic similarity: TF-IDF-ish cosine between CV text and job description
    cv_text = profile.get("cv_text", "")
    job_text = (job.get("title", "") + " " + job.get("description", ""))
    if cv_text and job.get("description"):
        sem_score = _cosine(_bow(cv_text), _bow(job_text))
        sem_w = 0.25
    else:
        sem_score = 0.0
        sem_w = 0.0  # redistribute to skills when no CV text available

    # 4) location compatibility
    loc = (job.get("location", "") or "").lower()
    pref = (profile.get("location", "") or "").lower()
    if "remote" in loc or "télétravail" in loc or not pref:
        loc_score = 1.0
    elif pref and pref in loc:
        loc_score = 1.0
    else:
        loc_score = 0.4

    # 5) seniority: only scored when the ad states a level and we know the
    #    candidate's track record (rebuilt from their CV by cv_structure).
    cand_months = int(profile.get("experience_months") or 0)
    req_months = required_experience_months(job_text)
    if req_months is not None and cand_months > 0:
        sen_score = seniority_fit(cand_months, req_months)
        sen_w = 0.14
    else:
        sen_score = 0.0
        sen_w = 0.0

    # weights (unused semantic/seniority weight is handed back to skills)
    w_skill = 0.44 + (0.22 - sem_w) + (0.14 - sen_w)
    total = (w_skill * skill_score + sem_w * sem_score + sen_w * sen_score
             + 0.12 * title_score + 0.08 * loc_score)
    return {
        "score": round(min(total, 1.0) * 100),
        "matched_skills": sorted(matched),
        "missing_skills": sorted(job_skills - cand_skills)[:8],
        "job_skill_count": len(job_skills),
        "semantic": round(sem_score * 100),
        "required_experience_months": req_months,
        "candidate_experience_months": cand_months,
        "seniority": round(sen_score * 100) if sen_w else None,
    }
