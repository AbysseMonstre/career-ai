import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Static legal pages: privacy (RGPD) + terms. Content is a sensible default —
/// the operator should review and complete company/contact details.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mentions légales & confidentialité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: const [
          _H('Éditeur'),
          _P('Career AI — plateforme de mise en relation entre candidats et recruteurs. '
              'Contact : bancmaha@gmail.com.'),
          _H('Données personnelles (RGPD)'),
          _P('Nous collectons les données que vous fournissez (email, nom, CV, compétences, '
              'candidatures) dans le seul but de vous proposer des offres pertinentes et de '
              'permettre la mise en relation avec des recruteurs. La base légale est votre '
              'consentement, recueilli à l’inscription.'),
          _P('Vos droits : accès, rectification, portabilité et effacement. Vous pouvez '
              'exporter ou supprimer définitivement votre compte et vos données à tout moment '
              'depuis votre tableau de bord (« Supprimer mon compte »).'),
          _P('Les recruteurs voient votre profil (nom, intitulé, compétences, localisation) mais '
              'pas votre email : la prise de contact et la planification passent par la plateforme.'),
          _P('Les offres d’emploi sont agrégées depuis des sources publiques. Les données sont '
              'conservées de façon limitée et les offres anciennes sont purgées automatiquement.'),
          _H('Cookies'),
          _P('L’application stocke uniquement des informations techniques nécessaires à votre '
              'session (jeton de connexion) sur votre appareil. Aucun traçage publicitaire.'),
          _H('Conditions d’utilisation'),
          _P('Le service est fourni « en l’état ». Les candidatures se font sur les sites des '
              'employeurs ; nous ne garantissons ni embauche ni disponibilité des offres. '
              'Tout usage abusif (spam, collecte massive) est interdit.'),
          _H('Responsabilité'),
          _P('Career AI agit comme intermédiaire technique et ne saurait être tenu responsable '
              'du contenu des offres ni des échanges entre candidats et recruteurs.'),
          SizedBox(height: 16),
          Text('Dernière mise à jour : 2026.',
              style: TextStyle(color: AppTheme.muted2, fontSize: 12)),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String t;
  const _H(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      );
}

class _P extends StatelessWidget {
  final String t;
  const _P(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(color: AppTheme.muted, height: 1.5)),
      );
}
