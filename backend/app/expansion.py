"""Query expansion: turn one search into several (FR<->EN + related roles),
so the same sources return many more, more varied offers — no extra API key."""

# term (lowercase, found in the query) -> equivalent search terms
_SYN = {
    "développeur": ["developer", "software engineer", "programmeur"],
    "developpeur": ["developer", "software engineer"],
    "developer": ["développeur", "software engineer", "programmeur"],
    "ingénieur": ["engineer", "ingénieur logiciel"],
    "engineer": ["ingénieur", "ingénieur logiciel"],
    "data": ["data scientist", "data analyst", "data engineer"],
    "designer": ["ux designer", "ui designer", "graphiste"],
    "graphiste": ["graphic designer", "designer"],
    "commercial": ["sales", "business developer", "account manager"],
    "sales": ["commercial", "business developer"],
    "marketing": ["growth", "digital marketing", "marketing"],
    "communication": ["content", "social media", "communication"],
    "chef de projet": ["project manager", "product manager"],
    "product manager": ["chef de produit", "product owner"],
    "comptable": ["accountant", "comptabilité"],
    "comptabilité": ["accounting", "comptable"],
    "rh": ["ressources humaines", "human resources", "recruteur"],
    "ressources humaines": ["human resources", "talent acquisition"],
    "infirmier": ["nurse", "infirmière"],
    "vendeur": ["retail", "sales associate", "conseiller de vente"],
    "logistique": ["logistics", "supply chain"],
    "support": ["customer support", "support client", "customer success"],
    "finance": ["finance", "analyste financier", "financial analyst"],
    "juriste": ["legal", "lawyer", "juridique"],
    "professeur": ["teacher", "enseignant", "formateur"],
    "chef de produit": ["product manager", "product owner"],
    # work-study / apprenticeship (alternance) — bidirectional, so one search
    # for "alternance" also pulls offers worded as apprentissage, alternant, etc.
    "alternance": ["apprentissage", "alternant", "contrat de professionnalisation", "work-study"],
    "apprentissage": ["alternance", "alternant", "apprenti"],
    "alternant": ["alternance", "apprentissage", "apprenti"],
    "apprenti": ["apprentissage", "alternance", "alternant"],
    # --- métiers physiques / secteurs non-tech ---
    "serveur": ["serveuse", "service en salle", "restauration", "runner"],
    "cuisinier": ["cuisine", "chef de partie", "commis de cuisine", "cook", "chef"],
    "restauration": ["serveur", "cuisinier", "hôtellerie", "restauration rapide"],
    "restaurant": ["restauration", "serveur", "cuisinier"],
    "aéronautique": ["aeronautique", "aviation", "aerospace", "aéronef"],
    "aeronautique": ["aéronautique", "aviation", "aerospace"],
    "mécanicien": ["mecanicien", "mécanique", "technicien mécanique", "mechanic"],
    "maçon": ["macon", "maçonnerie", "gros œuvre", "btp"],
    "électricien": ["electricien", "électricité", "electrical"],
    "plombier": ["plomberie", "chauffagiste"],
    "chauffeur": ["conducteur", "livreur", "routier", "driver"],
    "cariste": ["magasinier", "préparateur de commandes", "manutentionnaire"],
    "aide-soignant": ["aide soignant", "aide-soignante", "soignant"],
    "soudeur": ["soudure", "chaudronnier", "welder"],
    "boulanger": ["boulangerie", "pâtissier", "boulanger-pâtissier"],
    "coiffeur": ["coiffeuse", "coiffure", "hairdresser"],
    "sécurité": ["agent de sécurité", "gardien", "vigile", "security"],
    "réceptionniste": ["réception", "front desk", "accueil"],
    "caissier": ["caissière", "hôte de caisse", "encaissement"],
    "btp": ["bâtiment", "construction", "gros œuvre", "chantier"],
    "industrie": ["production", "usine", "manufacturing", "maintenance industrielle"],
}


def expand_query(q: str, limit: int = 6) -> list:
    """Return the original query plus synonym/translation variants."""
    q = (q or "").strip()
    if not q:
        return [""]
    low = q.lower()
    variants = [q]
    seen = {low}
    # multi-word keys first (more specific), then single words
    for term in sorted(_SYN, key=lambda t: -len(t)):
        if term in low:
            for syn in _SYN[term]:
                v = low.replace(term, syn)
                if v not in seen:
                    seen.add(v)
                    variants.append(v)
        if len(variants) >= limit:
            break
    return variants[:limit]
