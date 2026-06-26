"""Generate a tailored cover-letter draft for a candidate/job pair.

This is the honest version of "auto-apply": we don't silently submit forms on
third-party boards (against their ToS and technically brittle). Instead we
produce a ready-to-send letter and hand back the real application URL so the
candidate applies in one click, in control.

Template-based and deterministic. Swap `generate` for an LLM call later for
richer phrasing — the call site doesn't change.
"""


def generate(candidate_name: str, candidate_title: str, skills: list, job: dict) -> str:
    name = candidate_name or "Le/La candidat·e"
    role = candidate_title or "professionnel·le"
    company = job.get("company") or "votre entreprise"
    title = job.get("title") or "le poste proposé"

    job_skills = {s.lower() for s in job.get("tags", [])}
    matched = [s for s in skills if s.lower() in job_skills] or skills[:4]
    skills_txt = ", ".join(matched[:5]) if matched else "mes compétences techniques"

    return (
        f"Objet : Candidature au poste de {title}\n\n"
        f"Madame, Monsieur,\n\n"
        f"Actuellement {role}, je souhaite rejoindre {company} pour le poste de "
        f"{title}. Le profil recherché correspond étroitement à mon parcours.\n\n"
        f"Mes compétences en {skills_txt} me permettraient de contribuer "
        f"rapidement à vos projets. J'attache une grande importance à la qualité "
        f"de mon travail et à la collaboration en équipe.\n\n"
        f"Je serais ravi·e d'échanger sur la façon dont je peux apporter de la "
        f"valeur à {company}. Je me tiens à votre disposition pour un entretien.\n\n"
        f"Cordialement,\n{name}"
    )
