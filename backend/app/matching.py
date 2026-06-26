"""Match score between a candidate profile and a job (0-100).

Weighted blend of:
  - skill overlap (recall of job skills covered by the candidate)  -> 60%
  - title/keyword similarity                                       -> 25%
  - location compatibility (remote-friendly)                       -> 15%

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

    # weights (redistribute the semantic weight onto skills when absent)
    w_skill = 0.50 + (0.25 - sem_w)
    total = w_skill * skill_score + sem_w * sem_score + 0.15 * title_score + 0.10 * loc_score
    return {
        "score": round(min(total, 1.0) * 100),
        "matched_skills": sorted(matched),
        "missing_skills": sorted(job_skills - cand_skills)[:8],
        "job_skill_count": len(job_skills),
        "semantic": round(sem_score * 100),
    }
