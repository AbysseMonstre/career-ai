"""Optional AI matching explanation via the Anthropic API.

Inert (returns "") unless CAREER_AI_ANTHROPIC_KEY is set, so the app runs
keyless by default. Uses plain HTTP (requests) — no SDK dependency.
"""
import requests

from . import config


def available() -> bool:
    return bool(config.ANTHROPIC_API_KEY)


def explain_match(profile: dict, job: dict) -> str:
    if not config.ANTHROPIC_API_KEY:
        return ""
    skills = ", ".join((profile.get("skills") or [])[:20]) or "non renseignées"
    prompt = (
        "Tu es un assistant de recrutement. En 2 à 3 phrases concises, en français, "
        "explique honnêtement pourquoi ce profil correspond (ou pas) à cette offre, "
        "et donne 1 conseil si utile.\n\n"
        f"PROFIL — Intitulé : {profile.get('title','')}. "
        f"Compétences : {skills}. Localisation : {profile.get('location','')}.\n\n"
        f"OFFRE — Intitulé : {job.get('title','')}. Entreprise : {job.get('company','')}. "
        f"Lieu : {job.get('location','')}.\n"
        f"Description : {(job.get('description','') or '')[:1200]}"
    )
    try:
        r = requests.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": config.ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": config.ANTHROPIC_MODEL,
                "max_tokens": 250,
                "messages": [{"role": "user", "content": prompt}],
            },
            timeout=30,
        )
        r.raise_for_status()
        parts = r.json().get("content", [])
        return "".join(p.get("text", "") for p in parts).strip()
    except Exception as e:  # never break the API because the LLM failed
        print(f"[ai] explain_match échec: {e}")
        return ""
