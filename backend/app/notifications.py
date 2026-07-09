"""Email notifications for the platform operator.

Sends a mail when a recruiter requests access to the talent base.
Configured entirely through environment variables so no secret lives in code:

    ADMIN_EMAIL     destination (default: bancmaha@gmail.com)
    SMTP_HOST       e.g. smtp.gmail.com
    SMTP_PORT       587 (STARTTLS) or 465 (SSL)   — default 587
    SMTP_USER       SMTP login (often the full email address)
    SMTP_PASSWORD   SMTP password / Gmail app password
    SMTP_FROM       From: header (default: SMTP_USER)

If SMTP is not configured, the notification is logged to stdout and appended to
`contact_notifications.log` so nothing is silently lost during development.
"""
import os
import ssl
import smtplib
from datetime import datetime
from email.message import EmailMessage

ADMIN_EMAIL = os.environ.get("ADMIN_EMAIL", "bancmaha@gmail.com")
SMTP_HOST = os.environ.get("SMTP_HOST")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD")
SMTP_FROM = os.environ.get("SMTP_FROM", SMTP_USER or "no-reply@careerai.app")

_LOG = os.path.join(os.path.dirname(__file__), "..", "contact_notifications.log")


def send_contact_notification(*, recruiter_name: str, recruiter_email: str,
                              company: str, phone: str, message: str) -> bool:
    """Build and send the access-request notification. Returns True if emailed."""
    subject = f"[Career AI] Demande d'accès talents — {company}"
    body = (
        "Nouvelle demande d'accès à la base de talents.\n\n"
        f"Entreprise : {company}\n"
        f"Recruteur  : {recruiter_name} <{recruiter_email}>\n"
        f"Téléphone  : {phone or '—'}\n"
        f"Reçu le    : {datetime.now():%Y-%m-%d %H:%M}\n\n"
        f"Message :\n{message or '(aucun)'}\n\n"
        "— Pour activer l'accès :\n"
        f"  POST /admin/grant-access?email={recruiter_email}\n"
    )
    return _send(subject, body)


def send_placement_request(*, company: str, recruiter_name: str, recruiter_email: str,
                           recruiter_phone: str, freelance_name: str, freelance_email: str,
                           freelance_title: str, freelance_skills: list,
                           match_score: int, message: str) -> bool:
    """Automatic email to the platform when a company selects a freelance.
    Contains everything we need to arrange the connection and bill the freelance."""
    subject = f"[Career AI] Mise en relation demandée — {company} ↔ {freelance_name}"
    body = (
        "Une société souhaite être mise en relation avec un freelance.\n"
        "À nous d'organiser la mise en relation et de facturer le freelance.\n\n"
        "── SOCIÉTÉ (demandeur) ──\n"
        f"Entreprise : {company}\n"
        f"Contact    : {recruiter_name} <{recruiter_email}>\n"
        f"Téléphone  : {recruiter_phone or '—'}\n\n"
        "── FREELANCE demandé ──\n"
        f"Nom        : {freelance_name} <{freelance_email}>\n"
        f"Profil     : {freelance_title or '—'}\n"
        f"Compétences: {', '.join(freelance_skills) or '—'}\n"
        f"Score match: {match_score}%\n\n"
        f"── MESSAGE de la société ──\n{message or '(aucun)'}\n\n"
        f"Reçu le {datetime.now():%Y-%m-%d %H:%M}.\n"
        "Prochaine étape : contacter le freelance, convenir de la commission, "
        "puis organiser l'entretien avec la société.\n"
    )
    return _send(subject, body)


def send_interview_invite(*, to_email: str, candidate_name: str, company: str,
                          scheduled_at: str, teams_link: str, message: str) -> bool:
    subject = f"[Career AI] Entretien proposé par {company}"
    body = (
        f"Bonjour {candidate_name},\n\n"
        f"{company} souhaite vous rencontrer en entretien.\n\n"
        f"Date proposée : {scheduled_at or 'à convenir'}\n"
        f"Lien Teams    : {teams_link or '(communiqué ultérieurement)'}\n\n"
        f"Message du recruteur :\n{message or '(aucun)'}\n\n"
        "Retrouvez l'invitation et répondez directement dans l'application Career AI."
    )
    return _send(subject, body, to=to_email)


def send_password_reset(*, to_email: str, reset_link: str) -> bool:
    subject = "[Career AI] Réinitialisation de votre mot de passe"
    body = (
        "Bonjour,\n\n"
        "Vous avez demandé à réinitialiser votre mot de passe Career AI.\n"
        "Cliquez sur le lien ci-dessous (valable 1 heure) :\n\n"
        f"{reset_link}\n\n"
        "Si vous n'êtes pas à l'origine de cette demande, ignorez cet email — "
        "votre mot de passe reste inchangé."
    )
    return _send(subject, body, to=to_email)


def send_job_alert(*, to_email: str, name: str, jobs: list) -> bool:
    """Digest of top matching offers for a candidate who opted in to alerts."""
    lines = []
    for j in jobs:
        score = (j.get("match") or {}).get("score", 0)
        lines.append(f"  • {j.get('title','')} — {j.get('company','')} "
                     f"({score}% de correspondance)\n    {j.get('url','')}")
    subject = f"[Career AI] {len(jobs)} offres pour votre profil"
    body = (
        f"Bonjour {name},\n\n"
        "Voici les offres les plus pertinentes pour votre profil :\n\n"
        + "\n".join(lines)
        + "\n\nRetrouvez-les dans l'application Career AI.\n"
        "Pour ne plus recevoir ces alertes, désactivez-les dans votre tableau de bord."
    )
    return _send(subject, body, to=to_email)


def _send(subject: str, body: str, to: str = None) -> bool:
    recipient = to or ADMIN_EMAIL
    if not (SMTP_HOST and SMTP_USER and SMTP_PASSWORD):
        _log_only(subject, body, recipient)
        return False
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM
    msg["To"] = recipient
    msg.set_content(body)
    try:
        ctx = ssl.create_default_context()
        if SMTP_PORT == 465:
            with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=ctx) as s:
                s.login(SMTP_USER, SMTP_PASSWORD)
                s.send_message(msg)
        else:
            with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as s:
                s.starttls(context=ctx)
                s.login(SMTP_USER, SMTP_PASSWORD)
                s.send_message(msg)
        print(f"[notifications] Email envoyé à {recipient} : {subject}")
        return True
    except Exception as e:  # never break the API because mail failed
        print(f"[notifications] Échec d'envoi ({e}). Notification journalisée à la place.")
        _log_only(subject, body, recipient)
        return False


def _log_only(subject: str, body: str, recipient: str = None):
    line = f"\n===== {datetime.now():%Y-%m-%d %H:%M:%S} =====\nÀ: {recipient or ADMIN_EMAIL}\nSujet: {subject}\n{body}\n"
    print("[notifications] SMTP non configuré — notification journalisée :")
    print(line)
    try:
        with open(_LOG, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass
