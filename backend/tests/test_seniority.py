"""Seniority weighting: an ad's experience bar must move the match score."""
from app import matching


def test_reads_years_from_french_ads():
    assert matching.required_experience_months("Vous justifiez de 5 ans d'expérience") == 60
    assert matching.required_experience_months("Expérience de 3 ans minimum") == 36
    assert matching.required_experience_months("minimum 2 ans sur un poste similaire") == 24


def test_reads_years_from_english_ads():
    assert matching.required_experience_months("5+ years experience required") == 60
    assert matching.required_experience_months("at least 4 years in a similar role") == 48


def test_takes_the_floor_of_a_range():
    # "3 à 5 ans" — what gates the application is the lower bound
    assert matching.required_experience_months("3 à 5 ans d'expérience") == 36


def test_falls_back_to_level_keywords():
    assert matching.required_experience_months("Stage - assistant chef de projet") == 0
    assert matching.required_experience_months("Développeur senior") == 60
    assert matching.required_experience_months("Nous recrutons un développeur") is None


def test_fit_curve():
    assert matching.seniority_fit(60, 0) == 1.0        # no bar -> everyone fits
    assert matching.seniority_fit(60, 60) == 1.0       # exactly on the bar
    assert matching.seniority_fit(48, 60) == 0.85      # close enough
    assert matching.seniority_fit(30, 60) == 0.6       # half way
    assert matching.seniority_fit(6, 60) == 0.3        # far below
    assert matching.seniority_fit(240, 60) == 0.85     # over-qualified, mild penalty


def _profile(months):
    return {"skills": ["python", "sql"], "title": "développeur",
            "cv_text": "", "location": "", "experience_months": months}


def _job(text):
    return {"title": "Développeur Python", "description": text,
            "location": "Paris", "tags": ["python", "sql"]}


def test_junior_scores_lower_on_a_senior_ad():
    ad = _job("Nous cherchons un profil avec 8 ans d'expérience en Python et SQL.")
    junior = matching.score(_profile(17), ad)["score"]
    senior = matching.score(_profile(120), ad)["score"]
    assert junior < senior, f"junior={junior} senior={senior}"


def test_silent_ad_does_not_penalise_anyone():
    ad = _job("Rejoignez notre équipe Python et SQL.")
    r = matching.score(_profile(17), ad)
    assert r["seniority"] is None
    assert r["required_experience_months"] is None
    # weight fully redistributed: same score whatever the track record
    assert r["score"] == matching.score(_profile(200), ad)["score"]


def test_result_exposes_both_sides():
    ad = _job("Poste ouvert aux profils justifiant de 3 ans d'expérience.")
    r = matching.score(_profile(17), ad)
    assert r["required_experience_months"] == 36
    assert r["candidate_experience_months"] == 17
    assert 0 <= r["seniority"] <= 100
