# Career AI

Plateforme de mise en relation **chercheurs d'emploi ↔ recruteurs**, avec matching IA basé sur le CV.

- **Backend** : Python / FastAPI — scraping multi-sources, parsing CV, moteur de matching, auth, dashboards.
- **Mobile** : Flutter (iOS / Android).

```
CareerAI/
├── backend/                 # API FastAPI (testée et fonctionnelle)
│   ├── app/
│   │   ├── main.py          # routes
│   │   ├── database.py      # SQLite (stdlib)
│   │   ├── security.py      # hash mot de passe + tokens (stdlib)
│   │   ├── cv_parser.py     # extraction texte + compétences
│   │   ├── matching.py      # score de correspondance 0-100
│   │   └── scrapers/        # RemoteOK, Remotive, Arbeitnow, The Muse + agrégateur
│   ├── requirements.txt
│   └── run.sh
└── mobile/                  # app Flutter
    ├── pubspec.yaml
    └── lib/
        ├── models/          # modèles de données
        ├── services/        # client API + état (Provider)
        ├── screens/         # auth, offres, candidatures, dashboards, talents, CV
        ├── widgets/         # jauge de score, puces de compétences, cartes stat
        └── theme/
```

## Fonctionnalités

### Chercheur d'emploi
- Import du **CV** (PDF ou texte) → extraction automatique des compétences.
- **Agrégation d'offres** depuis plusieurs job boards (scraping réel).
- **Score de correspondance** par offre + compétences en commun / manquantes.
- **Candidature automatique** multi-offres, puis **validation** pour enregistrement.
- **Tableau de bord** : score moyen, répartition des candidatures, profil.

### Recruteur
- **Accès sur demande** : la base de talents est verrouillée tant qu'un recruteur
  n'a pas fait de demande de contact (entreprise + besoin) **et** que la plateforme
  ne l'a pas validée. Statuts : `none` → `pending` → `granted`.
- **Base de talents** classée par correspondance avec des critères (une fois l'accès accordé).
- **Publication d'offres** (alimente le matching).
- **Tableau de bord** : taille du vivier, offres publiées, candidatures reçues.

#### Notification email à chaque demande
Quand un recruteur demande l'accès, la plateforme reçoit un email récapitulatif
(`app/notifications.py`, envoi non bloquant). Sans config SMTP, la notification est
journalisée dans `backend/contact_notifications.log`. Pour **recevoir réellement** le mail,
exportez ces variables avant de lancer le backend :

```bash
export ADMIN_EMAIL="bancmaha@gmail.com"      # destinataire
export SMTP_HOST="smtp.gmail.com"
export SMTP_PORT="587"                        # 587 (STARTTLS) ou 465 (SSL)
export SMTP_USER="votre.adresse@gmail.com"
export SMTP_PASSWORD="xxxx xxxx xxxx xxxx"    # mot de passe d'application Gmail
export SMTP_FROM="$SMTP_USER"
./run.sh
```
> Gmail exige un **mot de passe d'application** (compte Google → Sécurité → Validation en 2 étapes → Mots de passe des applications), pas votre mot de passe habituel.

#### Activer l'accès d'un recruteur (côté plateforme)
```bash
curl -X POST "http://127.0.0.1:8077/admin/grant-access?email=rh@acme.co" \
     -H "x-admin-secret: $CAREER_AI_SECRET"   # défaut: dev-secret-change-me
```

## Sources de scraping (réelles, sans clé)

| Source     | Endpoint                                            |
|------------|-----------------------------------------------------|
| RemoteOK   | `https://remoteok.com/api`                          |
| Remotive   | `https://remotive.com/api/remote-jobs`              |
| Arbeitnow  | `https://www.arbeitnow.com/api/job-board-api`       |
| The Muse   | `https://www.themuse.com/api/public/jobs`           |
| Jobicy     | `https://jobicy.com/api/v2/remote-jobs`             |
| LinkedIn   | endpoint *guest* public (offres FR par ville ; fragile, rate-limité par IP) |

### Sources sur clé (s'activent via variables d'environnement)
| Source | Variables | Couvre |
|---|---|---|
| Adzuna | `ADZUNA_APP_ID`, `ADZUNA_APP_KEY` | offres FR/internationales |
| France Travail | `FT_CLIENT_ID`, `FT_CLIENT_SECRET` | offres France (officiel) |
| JSearch (RapidAPI) | `RAPIDAPI_KEY` | **agrège LinkedIn, Indeed, Glassdoor, ZipRecruiter, Google for Jobs** |

> **Indeed / HelloWork** bloquent le scraping direct (HTTP 403) et l'interdisent dans leurs CGU :
> on les obtient légalement via **JSearch** (clé gratuite RapidAPI). LinkedIn direct passe par
> son endpoint *guest* public mais reste fragile (peut être limité par IP) ; JSearch est plus stable.

> Pour ajouter une source verrouillée (LinkedIn, Indeed…), créez une sous-classe de
> `BaseScraper` dans `backend/app/scrapers/sources.py` (idéalement derrière un proxy) ;
> l'agrégateur la prend en compte automatiquement. Ces sources bloquent le scraping
> serveur direct et imposent des contraintes juridiques — d'où le choix d'APIs ouvertes ici.

## Lancer le backend

```bash
cd backend
./run.sh              # crée le venv, installe les deps, lance uvicorn
# -> http://0.0.0.0:8077   (doc interactive : http://127.0.0.1:8077/docs)
```

Test rapide :
```bash
curl -X POST http://127.0.0.1:8077/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"a@a.io","password":"pass123","name":"Alice","role":"seeker"}'
```

## Lancer l'app dans le navigateur (le plus rapide)
Le code est validé avec **Flutter 3.44.2** (`flutter analyze` : 0 erreur ; `flutter build web` : OK).
```bash
cd mobile && flutter build web
python3 -m http.server 8090 --directory build/web   # puis ouvrir http://127.0.0.1:8090
```
> En web, l'app cible automatiquement le backend sur `http://127.0.0.1:8077`.

## Déployer sur iOS
Le projet iOS est prêt (`mobile/ios/`) : nom « Career AI », bundle id `com.careerai.app`,
exception ATS dev pour le backend HTTP local, URL backend résolue par plateforme.

**Prérequis (sur un Mac) :** Xcode (App Store), CocoaPods (`sudo gem install cocoapods`),
et — pour un vrai iPhone/TestFlight/App Store — un compte **Apple Developer**.

```bash
cd mobile
flutter pub get
cd ios && pod install && cd ..

# 1) Simulateur iOS (le plus simple, backend sur le Mac en 127.0.0.1) :
flutter run -d iphone        # ou: open -a Simulator puis flutter run

# 2) iPhone physique / TestFlight : pointer vers un backend joignable
flutter build ios --release \
  --dart-define=API_BASE_URL=https://api.votre-domaine.com
# puis ouvrir ios/Runner.xcworkspace dans Xcode → Signing (votre équipe Apple) → Run/Archive
```
> Sur un **iPhone réel**, `127.0.0.1` désigne le téléphone : il faut l'IP LAN du Mac
> (`http://192.168.x.x:8077`) ou un backend déployé, passé via `--dart-define=API_BASE_URL`.
> Pour l'App Store, servez l'API en **HTTPS** et retirez l'exception ATS de `Info.plist`.

## Lancer l'app Flutter (mobile)

Flutter n'est pas requis pour le backend. Pour l'app :

```bash
# 1. Installer Flutter : https://docs.flutter.dev/get-started/install
cd mobile

# 2. Générer les dossiers de plateforme (android/ ios/) à partir du code lib/ existant
flutter create .

# 3. Récupérer les dépendances
flutter pub get

# 4. Lancer (émulateur ou device branché)
flutter run
```

### Configurer l'URL du backend
Dans `mobile/lib/services/api_service.dart`, `defaultBaseUrl` :
- Émulateur **Android** : `http://10.0.2.2:8077` (valeur par défaut)
- Simulateur **iOS** : `http://127.0.0.1:8077`
- **Device physique** : `http://<IP-LAN-de-votre-machine>:8077`

## Parcours de démo
1. Lancez le backend.
2. Inscrivez-vous comme **chercheur** → onglet **CV** : importez/collez un CV.
3. Onglet **Offres** → bouton nuage pour scraper, cochez des offres → *Postuler automatiquement*.
4. Onglet **Candidatures** → **Valider** une candidature.
5. Onglet **Tableau** → stats.
6. Déconnectez-vous, inscrivez-vous comme **recruteur** → **Talents** : le candidat apparaît avec son score.

## Modèle économique (freelances)
Les **talents sont des freelances** ; la plateforme se rémunère en les **facturant** lors d'une mise en relation. Parcours :
1. Un recruteur partenaire (accès accordé) parcourt les freelances — **sans voir leur contact direct**.
2. Il clique **« Mise en relation »** sur un freelance et décrit son besoin.
3. Un **email automatique** part vers la plateforme (`POST /talents/{id}/request`) avec société + freelance + match + message.
4. La plateforme contacte le freelance, convient de la commission, organise l'entretien.
5. Suivi des demandes : `GET /admin/placement-requests` (header `x-admin-token`).

## Sécurité & RGPD
- **Auth** : pbkdf2 (240k rounds), tokens HMAC, secret via `CAREER_AI_SECRET`. Token admin **séparé** (`CAREER_AI_ADMIN_TOKEN`). En production, l'app refuse de démarrer avec les valeurs par défaut.
- **Protections** : CORS restreint (`CAREER_AI_CORS_ORIGINS`), rate-limiting (login/inscription), en-têtes de sécurité, validation email/mot de passe.
- **RGPD** : consentement obligatoire à l'inscription ; **export** des données (`GET /me/export`), **effacement** (`DELETE /me`), **purge** automatique des données expirées, mentions légales (`GET /legal/privacy`).

## Tests
```bash
cd backend && ./venv/bin/pip install -r requirements-dev.txt
./venv/bin/python -m pytest tests/ -q          # 10 tests : auth, RGPD, gating, placement
```

## Déploiement (Docker)
```bash
cp backend/.env.example backend/.env   # renseigner SECRET, ADMIN_TOKEN, SMTP…
docker compose up --build              # backend sur :8077 (volume SQLite persistant)
```
Un service **Postgres** est inclus (`--profile postgres`) et prêt : migrer la couche données SQLite→Postgres est la prochaine étape infra documentée.

## Vers la production — ce qui reste
- Migration de la persistance **SQLite → PostgreSQL** (le service est prêt dans `docker-compose.yml`).
- Couverture d'offres FR : activer **France Travail / Adzuna** (clés dans `.env`).
- Matching : passer du TF-IDF aux **embeddings** pour un classement plus fin.
- Page d'admin web pour valider les accès et gérer les mises en relation (au lieu de `curl`).

## Notes
- **Matching** : heuristique transparente (overlap de compétences 60 %, similarité de titre 25 %, localisation 15 %) dans `backend/app/matching.py`. Facilement remplaçable par des embeddings / un LLM.
- **Sécurité** : auth volontairement sans dépendance native (pbkdf2 + token HMAC). Pour la prod : passez à bcrypt + JWT et chargez `CAREER_AI_SECRET` depuis l'environnement.
- **Base de données** : SQLite (`backend/career_ai.db`), créée automatiquement.
