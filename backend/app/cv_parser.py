"""Extract raw text from a CV (PDF or plain text) and pull out skills.

Skill extraction uses a curated dictionary plus generic capitalized-token
heuristics. Good enough for matching; swap in spaCy/an LLM later if needed.
"""
import io
import re

# Curated skill vocabulary (extend freely). Multi-word phrases checked first.
SKILL_VOCAB = [
    # languages
    "python", "java", "javascript", "typescript", "go", "golang", "rust", "c++",
    "c#", "php", "ruby", "kotlin", "swift", "scala", "dart", "sql",
    # web / frameworks
    "react", "vue", "angular", "svelte", "next.js", "node.js", "express",
    "django", "flask", "fastapi", "spring", "spring boot", "laravel", "rails",
    "flutter", "react native", "tailwind", "graphql", "rest api",
    # data / ml
    "machine learning", "deep learning", "tensorflow", "pytorch", "pandas",
    "numpy", "scikit-learn", "nlp", "computer vision", "data analysis",
    "data engineering", "spark", "hadoop", "airflow", "etl", "power bi", "tableau",
    # cloud / devops
    "aws", "azure", "gcp", "docker", "kubernetes", "terraform", "ansible",
    "ci/cd", "jenkins", "github actions", "linux", "bash",
    # databases
    "postgresql", "mysql", "mongodb", "redis", "elasticsearch", "sqlite",
    # mobile / design
    "ios", "android", "figma", "ui/ux", "ux design",
    # soft / business
    "agile", "scrum", "project management", "product management", "leadership",
    "communication", "seo", "marketing", "sales", "accounting", "finance",
    # French business / soft skills
    "gestion de projet", "vente", "comptabilité", "ressources humaines",
    "communication", "rédaction", "négociation", "service client",
    # extra dev / tools
    "objective-c", "matlab", "perl", "elixir", "haskell",
    "spring boot", "fastapi", "nestjs", "symfony", ".net", "asp.net",
    "svelte", "nuxt", "gatsby", "redux", "jest", "cypress", "selenium",
    "git", "github", "gitlab", "jenkins", "ci/cd", "terraform", "ansible",
    "kafka", "rabbitmq", "grpc", "rest", "soap", "microservices", "graphql",
    "firebase", "supabase", "snowflake", "databricks", "airflow", "dbt",
    "looker", "power bi", "tableau", "qlik", "excel", "vba",
    # data / ml extra
    "pytorch", "keras", "hugging face", "llm", "mlops", "spark", "hadoop",
    "opencv", "spacy", "statistics", "data visualization",
    # security / infra
    "cybersecurity", "penetration testing", "siem", "iso 27001", "networking",
    "vmware", "active directory", "windows server",
    # design / marketing / product
    "figma", "sketch", "adobe xd", "photoshop", "illustrator", "indesign",
    "ux research", "wireframing", "prototyping", "google ads", "facebook ads",
    "sea", "content marketing", "copywriting", "growth", "crm", "salesforce",
    "hubspot", "wordpress", "shopify", "google analytics",
    # business / FR
    "management", "paie", "droit", "juridique", "logistique", "supply chain",
    "achats", "audit", "contrôle de gestion", "relation client", "anglais",
    "espagnol", "allemand", "italien",
]

# Variant spellings / abbreviations / FR terms -> canonical skill in SKILL_VOCAB.
SKILL_ALIASES = {
    "js": "javascript", "ts": "typescript", "py": "python", "golang": "go",
    "ml": "machine learning", "dl": "deep learning", "ia": "machine learning",
    "ai": "machine learning", "k8s": "kubernetes", "postgres": "postgresql",
    "node": "node.js", "nodejs": "node.js", "nextjs": "next.js",
    "reactjs": "react", "vuejs": "vue", "tf": "tensorflow",
    "gcp": "gcp", "amazon web services": "aws",
    # French -> canonical
    "apprentissage automatique": "machine learning",
    "apprentissage profond": "deep learning",
    "gestion de projet": "project management",
    "vente": "sales", "comptabilité": "accounting", "finance": "finance",
    "rédaction": "communication", "anglais": "communication",
    "base de données": "sql", "informatique décisionnelle": "data analysis",
}

_WORD = re.compile(r"[a-zA-ZÀ-ÿ0-9+#.]+")


class CvExtractionError(Exception):
    """The file could not be turned into text — the caller should say why."""


def extract_text(filename: str, content: bytes) -> str:
    name = (filename or "").lower()
    if not content:
        raise CvExtractionError("Le fichier est vide.")
    if name.endswith(".pdf"):
        return _pdf_text(content)
    if name.endswith((".doc", ".docx")):
        raise CvExtractionError(
            "Les fichiers Word ne sont pas encore pris en charge. "
            "Exportez votre CV en PDF, ou collez son texte ci-dessous.")
    # treat everything else as utf-8 text
    try:
        return content.decode("utf-8", errors="ignore")
    except Exception:
        raise CvExtractionError("Fichier illisible : utilisez un PDF ou du texte brut.")


def _pdf_text(content: bytes) -> str:
    """Text layer of a PDF. Raises CvExtractionError with an actionable reason.

    A scanned CV (photo/image export) has no text layer: pypdf returns empty
    strings rather than failing, so we detect it here instead of silently
    storing an empty CV.
    """
    try:
        from pypdf import PdfReader
        reader = PdfReader(io.BytesIO(content))
    except Exception as exc:
        raise CvExtractionError(
            "PDF illisible ou endommagé — réexportez-le puis réessayez.") from exc
    if getattr(reader, "is_encrypted", False):
        try:
            reader.decrypt("")  # many CVs are "protected" with an empty password
        except Exception:
            raise CvExtractionError(
                "Ce PDF est protégé par mot de passe — retirez la protection puis réessayez.")
    try:
        text = "\n".join((page.extract_text() or "") for page in reader.pages)
    except Exception as exc:
        raise CvExtractionError(
            "Impossible de lire le texte de ce PDF — réexportez-le puis réessayez.") from exc
    if not text.strip():
        raise CvExtractionError(
            "Ce PDF ne contient aucun texte : c'est une image (CV scanné ou exporté en image). "
            "Réexportez-le depuis Word/Canva en PDF texte, ou collez le contenu ci-dessous.")
    return text


def extract_skills(text: str) -> list:
    if not text:
        return []
    low = text.lower()
    found = set()
    for skill in SKILL_VOCAB:
        # word-boundary-ish match (handles c++, c#, next.js)
        pattern = r"(?<![a-z0-9])" + re.escape(skill) + r"(?![a-z0-9])"
        if re.search(pattern, low):
            found.add(skill)
    # resolve aliases / abbreviations / French terms to canonical skills
    for alias, canonical in SKILL_ALIASES.items():
        pattern = r"(?<![a-z0-9])" + re.escape(alias) + r"(?![a-z0-9])"
        if re.search(pattern, low):
            found.add(canonical)
    return sorted(found)


def guess_title(text: str) -> str:
    """Heuristic: first non-empty line that looks like a role, else ''."""
    for line in text.splitlines():
        line = line.strip()
        if 3 < len(line) < 60 and any(k in line.lower() for k in
                ("developer", "engineer", "designer", "manager", "analyst",
                 "scientist", "consultant", "lead", "architect", "développeur",
                 "ingénieur", "chef de projet")):
            return line
    return ""
