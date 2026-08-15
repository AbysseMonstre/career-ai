"""Rebuild a readable profile from raw CV text: experiences, education, skills.

`extract_skills` in cv_parser only recognises words from a fixed vocabulary, so
a CV written in prose ("Assistance au pilotage de projets complexes…") loses
almost everything. This module instead reads the CV's own structure — its
section headers, date ranges and bullet lists — and gives back what the person
actually wrote.

PDF text layers are noisy: pypdf inserts spaces inside words and years
("202 6"), collapses tabs into runs of spaces, and mixes dash characters. Every
line goes through `_norm` before any matching.
"""
import re
import unicodedata

# --- dates -----------------------------------------------------------------

_MONTHS = {
    "janvier": 1, "janv": 1, "jan": 1, "january": 1,
    "février": 2, "fevrier": 2, "févr": 2, "fevr": 2, "feb": 2, "february": 2,
    "mars": 3, "mar": 3, "march": 3,
    "avril": 4, "avr": 4, "apr": 4, "april": 4,
    "mai": 5, "may": 5,
    "juin": 6, "jun": 6, "june": 6,
    "juillet": 7, "juil": 7, "jul": 7, "july": 7,
    "août": 8, "aout": 8, "aug": 8, "august": 8,
    "septembre": 9, "sept": 9, "sep": 9, "september": 9,
    "octobre": 10, "oct": 10, "october": 10,
    "novembre": 11, "nov": 11, "november": 11,
    "décembre": 12, "decembre": 12, "déc": 12, "dec": 12, "december": 12,
}
_MONTH_RE = (r"(?:janvier|janv|january|jan|février|fevrier|févr|fevr|february|feb|"
             r"mars|march|mar|avril|april|avr|apr|mai|may|juin|june|jun|juillet|july|juil|jul|"
             r"août|aout|august|aug|septembre|september|sept|sep|octobre|october|oct|"
             r"novembre|november|nov|décembre|decembre|december|déc|dec)\.?")
_YEAR_RE = r"(?:19|20)\d{2}"
_NOW_RE = (r"(?:aujourd'hui|aujourd’hui|présent|present|à ce jour|ce jour|"
           r"actuel(?:lement)?|en cours|now|today|current)")
_SEP_RE = r"(?:—|–|−|-|/|à|au|jusqu'à|jusqu’à|to|until)"

# "Janvier — fin juin 2026", "Oct. — Nov. 2019", "2023 - 2026", "mars 2021 – aujourd'hui"
_RANGE_RE = re.compile(
    rf"(?P<start>(?:{_MONTH_RE}\s*)?{_YEAR_RE}|{_MONTH_RE})"
    rf"\s*{_SEP_RE}\s*"
    rf"(?P<end>(?:fin\s+|début\s+|mi-)?(?:{_MONTH_RE}\s*)?(?:{_YEAR_RE})|{_NOW_RE}|{_MONTH_RE})",
    re.IGNORECASE,
)
_DURATION_RE = re.compile(r"\(\s*(\d+)\s*(mois|ans?|années?|months?|years?)\s*\)", re.IGNORECASE)
_BULLET_RE = re.compile(r"^\s*[•▪◦●·\-–—*]\s+")
_PAREN_ONLY_RE = re.compile(r"^\s*\(.*\)\s*$")

# --- sections --------------------------------------------------------------
# Order matters only for readability; matching is per-line against every entry.
_SECTIONS = [
    ("experiences", (r"experiences? professionnelles?", r"experiences?", r"parcours professionnel",
                     r"parcours", r"work experience", r"employment", r"professional experience")),
    ("education", (r"formations?", r"education", r"diplomes?", r"cursus", r"academic")),
    ("skills", (r"competences? cles?", r"competences? techniques?", r"competences?",
                r"skills", r"technical skills", r"savoir-faire")),
    ("certifications", (r"certifications?", r"certificats?", r"licenses?")),
    ("languages", (r"langues?", r"languages?")),
    ("interests", (r"centres? d.?interets?", r"loisirs", r"interests", r"hobbies")),
]


def _norm(line: str) -> str:
    """Repair one line of PDF-extracted text."""
    s = line.replace(" ", " ").replace("\t", " ")
    # pypdf splits digits of a year: "202 6" -> "2026"
    s = re.sub(r"\b(19|20)\s*(\d)\s*(\d)\b", r"\1\2\3", s)
    # and glues words to digits: "1erannée" -> "1er année"
    s = re.sub(r"(\d(?:er|ère|eme|ème))([A-Za-zÀ-ÿ])", r"\1 \2", s)
    # "comptes -rendus" -> "comptes-rendus", "projet , à" -> "projet, à"
    s = re.sub(r"(\w)\s+-(\w)", r"\1-\2", s)
    s = re.sub(r"\s+([,;:.!?])", r"\1", s)
    s = re.sub(r"\s{2,}", " ", s)
    return s.strip()


def _fold(s: str) -> str:
    """Lowercase, accent-free, punctuation-light — for header matching only."""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn").lower()
    return re.sub(r"[^a-z0-9 ]+", " ", s).strip()


def _section_of(line: str):
    """Return the section key if `line` is a section header, else None."""
    folded = _fold(line)
    if not folded or len(folded) > 42 or _BULLET_RE.match(line):
        return None
    for key, patterns in _SECTIONS:
        for p in patterns:
            if re.fullmatch(p, folded):
                return key
    return None


def split_sections(lines):
    """Map section key -> its lines. Text before any header goes to 'header'."""
    out, current = {"header": []}, "header"
    for raw in lines:
        line = _norm(raw)
        key = _section_of(line)
        if key:
            current = key
            out.setdefault(key, [])
            continue
        out.setdefault(current, []).append(line)
    return out


def _month_year(fragment: str):
    """('juin 2026') -> (6, 2026); ('2023') -> (None, 2023)."""
    if not fragment:
        return None, None
    frag = _fold(fragment)
    year = None
    m = re.search(r"(19|20)\d{2}", fragment)
    if m:
        year = int(m.group(0))
    month = None
    for name, num in _MONTHS.items():
        if re.search(rf"\b{re.escape(_fold(name))}", frag):
            month = num
            break
    return month, year


def _duration_months(start, end, explicit):
    if explicit:
        n, unit = explicit
        return n * 12 if unit.lower().startswith(("an", "ann", "year")) else n
    (sm, sy), (em, ey) = start, end
    if not sy or not ey:
        return None
    months = (ey - sy) * 12 + ((em or 1) - (sm or 1)) + 1
    return months if 0 < months < 600 else None


def _clean_company(text: str) -> tuple:
    """Split a trailing company fragment into (company, location)."""
    t = text.strip(" .,;:|")
    t = re.sub(r"^[–—−\-]+\s*", "", t).strip()
    if not t:
        return "", ""
    if "," in t:
        company, _, loc = t.rpartition(",")
        return company.strip(), loc.strip()
    return t, ""


def parse_experiences(lines):
    """Split an experience section into entries anchored on their date range."""
    entries, current = [], None
    for line in lines:
        if not line:
            continue
        m = _RANGE_RE.search(line)
        if m and not _BULLET_RE.match(line):
            if current:
                entries.append(current)
            rest = line[m.end():]
            dur = _DURATION_RE.search(line)
            rest = _DURATION_RE.sub("", rest)
            start = _month_year(m.group("start"))
            end_raw = m.group("end")
            ongoing = bool(re.search(_NOW_RE, end_raw, re.IGNORECASE))
            end = (None, None) if ongoing else _month_year(end_raw)
            # a start written without a year inherits the end's year
            if start[1] is None and end[1]:
                start = (start[0], end[1])
            company, location = _clean_company(rest)
            current = {
                "period": _norm(m.group(0)),
                "start_year": start[1], "start_month": start[0],
                "end_year": end[1], "end_month": end[0],
                "ongoing": ongoing,
                "duration_months": _duration_months(
                    start, end, (int(dur.group(1)), dur.group(2)) if dur else None),
                "company": company, "location": location,
                "role": "", "context": "", "bullets": [],
            }
            continue
        if current is None:
            continue
        if _BULLET_RE.match(line):
            current["bullets"].append(_BULLET_RE.sub("", line).strip())
        elif current["bullets"]:
            # wrapped continuation of the previous bullet
            current["bullets"][-1] = f"{current['bullets'][-1]} {line}".strip()
        elif _PAREN_ONLY_RE.match(line):
            current["context"] = line.strip("() ")
        elif not current["role"]:
            current["role"] = line
        elif not current["company"]:
            current["company"] = line
    if current:
        entries.append(current)
    # newest first; undated entries last
    entries.sort(key=lambda e: (e["start_year"] or 0, e["start_month"] or 0), reverse=True)
    return entries


# A CV's skills block often also holds the "about me" paragraph. It is prose,
# not a competency, and it is the only thing there written in the first person.
_PROSE_RE = re.compile(r"\b(je|j'|mes|mon|ma)\b", re.IGNORECASE)


def parse_declared_skills(lines):
    """Competencies as the candidate wrote them: '<label> : <detail>'."""
    out, buffer = [], []

    def flush():
        if not buffer:
            return
        text = re.sub(r"\s{2,}", " ", " ".join(buffer)).strip(" .;")
        buffer.clear()
        if len(text) < 3:
            return
        label, sep, detail = text.partition(":")
        if sep and 2 < len(label.strip()) < 70:
            out.append({"label": label.strip(), "detail": detail.strip()})
        elif not _PROSE_RE.search(text):  # drop the "about me" paragraph
            out.append({"label": text[:160], "detail": ""})

    for line in lines:
        if not line:
            flush()
            continue
        if _BULLET_RE.match(line):
            flush()
            buffer.append(_BULLET_RE.sub("", line).strip())
        elif buffer and (line[:1].islower() or len(line) < 45):
            buffer.append(line)  # wrapped continuation
        else:
            flush()
            buffer.append(line)
    flush()
    return out


def _parse_listing(lines):
    """Generic '<year/label> <content>' rows used for education & certifications."""
    out, buffer = [], []

    def flush():
        text = re.sub(r"\s{2,}", " ", " ".join(buffer)).strip(" .;")
        buffer.clear()
        if len(text) < 4:
            return
        years = re.findall(_YEAR_RE, text)
        period = ""
        if years:
            period = years[0] if len(years) == 1 else f"{years[0]} – {years[-1]}"
        label = re.sub(rf"^(?:{_YEAR_RE}|[/\s–—-])+", "", text).strip(" /–—-")
        out.append({"period": period, "label": label or text})

    pending_year = False
    for line in lines:
        if not line:
            continue
        # A period split over two lines ("2026 /" then "2027 Mastère…") belongs to
        # the row that follows it, not to the one that precedes it.
        if re.fullmatch(rf"\s*{_YEAR_RE}\s*[/–—-]?\s*", line):
            flush()
            buffer.append(line.strip())
            pending_year = True
            continue
        if buffer and not pending_year and re.match(rf"^\s*{_YEAR_RE}", line):
            flush()
        buffer.append(_BULLET_RE.sub("", line).strip())
        pending_year = False
    flush()
    return [r for r in out if r["label"] and not _is_table_header(r["label"])]


# Column headers of the little tables CVs use for certifications / education.
_HEADER_WORDS = {"annee", "year", "certification", "certifications", "statut",
                 "status", "intitule", "date", "dates", "diplome", "diplomes",
                 "etablissement", "ecole", "formation", "formations", "periode"}


def _is_table_header(label: str) -> bool:
    words = _fold(label).split()
    return bool(words) and len(words) <= 5 and all(w in _HEADER_WORDS for w in words)


def parse_structure(text: str) -> dict:
    """Full structured view of a CV. Every list may legitimately be empty."""
    lines = (text or "").splitlines()
    sections = split_sections(lines)
    experiences = parse_experiences(sections.get("experiences", []))
    total = sum(e["duration_months"] or 0 for e in experiences)
    return {
        "experiences": experiences,
        "education": _parse_listing(sections.get("education", [])),
        "certifications": _parse_listing(sections.get("certifications", [])),
        "declared_skills": parse_declared_skills(sections.get("skills", [])),
        "languages": [l for l in sections.get("languages", []) if l],
        "total_experience_months": total,
        "sections_found": sorted(k for k in sections if k != "header" and sections[k]),
    }
