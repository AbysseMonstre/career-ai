import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// "Mon profil" — the CV given back as readable sections: competencies as the
/// candidate wrote them, then a timeline of jobs with their bullet points.
///
/// Everything here comes from the uploaded PDF. Sections the CV did not
/// contain are simply absent rather than shown empty.
class CvProfileScreen extends StatefulWidget {
  /// Passed straight after an import so the result shows without a round-trip.
  final CvStructure? initial;
  final String? title;
  final List<String> matchedSkills;
  const CvProfileScreen({super.key, this.initial, this.title, this.matchedSkills = const []});

  @override
  State<CvProfileScreen> createState() => _CvProfileScreenState();
}

class _CvProfileScreenState extends State<CvProfileScreen> {
  CvStructure? _cv;
  String _title = '';
  String _location = '';
  List<String> _matched = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _cv = widget.initial;
    _title = widget.title ?? '';
    _matched = widget.matchedSkills;
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await context.read<AppState>().api.getCv();
      if (!mounted) return;
      setState(() {
        _cv = CvStructure.fromJson(Map<String, dynamic>.from(raw['structure'] ?? {}));
        _title = (raw['title'] ?? '').toString();
        _location = (raw['location'] ?? '').toString();
        _matched = List<String>.from(raw['skills'] ?? const []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cv = _cv;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Retour',
              ),
              const Expanded(
                child: Text('Mon profil',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: _loading ? null : () { setState(() => _loading = true); _load(); },
                icon: const Icon(Icons.refresh),
                tooltip: 'Recharger depuis mon CV',
              ),
            ]),
          ),
          Expanded(
            child: _loading && cv == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && cv == null
                    ? _Message(
                        icon: Icons.cloud_off,
                        title: 'Profil indisponible',
                        body: '$_error')
                    : cv == null || cv.isEmpty
                        ? const _Message(
                            icon: Icons.description_outlined,
                            title: 'Rien à afficher pour l’instant',
                            body: "Importez votre CV en PDF depuis l’onglet CV : "
                                "vos compétences et vos expériences apparaîtront ici, "
                                "reconstituées section par section.")
                        : _content(cv),
          ),
        ]),
      ),
    );
  }

  Widget _content(CvStructure cv) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _Summary(title: _title, location: _location, cv: cv),
          if (cv.declaredSkills.isNotEmpty)
            _Section(
              icon: Icons.workspace_premium_outlined,
              label: 'Compétences',
              count: cv.declaredSkills.length,
              child: Column(
                children: [
                  for (final s in cv.declaredSkills) _SkillRow(skill: s),
                ],
              ),
            ),
          if (_matched.isNotEmpty)
            _Section(
              icon: Icons.tag,
              label: 'Mots-clés reconnus pour le matching',
              count: _matched.length,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                    'Ce sont les termes que le moteur compare aux offres.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                const SizedBox(height: 10),
                SkillChips(skills: _matched, color: AppTheme.primary),
              ]),
            ),
          if (cv.experiences.isNotEmpty)
            _Section(
              icon: Icons.work_history_outlined,
              label: 'Expériences',
              count: cv.experiences.length,
              child: Column(children: [
                for (var i = 0; i < cv.experiences.length; i++)
                  _ExperienceTile(
                    exp: cv.experiences[i],
                    isLast: i == cv.experiences.length - 1,
                  ),
              ]),
            ),
          if (cv.education.isNotEmpty)
            _Section(
              icon: Icons.school_outlined,
              label: 'Formation',
              count: cv.education.length,
              child: Column(children: [for (final e in cv.education) _EntryRow(entry: e)]),
            ),
          if (cv.certifications.isNotEmpty)
            _Section(
              icon: Icons.verified_outlined,
              label: 'Certifications',
              count: cv.certifications.length,
              child: Column(children: [for (final e in cv.certifications) _EntryRow(entry: e)]),
            ),
          if (cv.languages.isNotEmpty)
            _Section(
              icon: Icons.translate,
              label: 'Langues',
              count: cv.languages.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in cv.languages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(l, style: const TextStyle(height: 1.45)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Contenu extrait automatiquement de votre PDF. Si une ligne est mal '
            'découpée, cela vient de la mise en page du document — réexportez-le '
            'ou complétez le texte depuis l’onglet CV.',
            style: TextStyle(color: AppTheme.muted2, fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Headline: job title, location and what the CV adds up to.
class _Summary extends StatelessWidget {
  final String title, location;
  final CvStructure cv;
  const _Summary({required this.title, required this.location, required this.cv});

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (cv.totalLabel.isNotEmpty) cv.totalLabel,
      if (cv.experiences.isNotEmpty) '${cv.experiences.length} postes',
      if (cv.declaredSkills.isNotEmpty) '${cv.declaredSkills.length} compétences',
    ];
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
                gradient: AppTheme.brandGradient, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.badge_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.isEmpty ? 'Profil extrait du CV' : title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.2)),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 13, color: AppTheme.muted2),
                  const SizedBox(width: 3),
                  Text(location, style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
                ]),
              ],
            ]),
          ),
        ]),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.violet.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.violetLight.withValues(alpha: 0.45)),
                ),
                child: Text(c,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Glass panel with an icon header and a count badge.
class _Section extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Widget child;
  const _Section({required this.icon, required this.label, required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 17, color: AppTheme.violetLight),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.violetLight,
                      fontWeight: FontWeight.w700, letterSpacing: 0.7)),
            ),
            Text('$count',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.muted2, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  final CvSkill skill;
  const _SkillRow({required this.skill});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6, height: 6,
          decoration: const BoxDecoration(color: AppTheme.cyan, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(skill.label,
                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
            if (skill.detail.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(skill.detail,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.45)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// One job, drawn as a timeline node.
class _ExperienceTile extends StatelessWidget {
  final CvExperience exp;
  final bool isLast;
  const _ExperienceTile({required this.exp, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // timeline rail
        Column(children: [
          Container(
            width: 11, height: 11,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: exp.ongoing ? AppTheme.green : AppTheme.violetLight,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: (exp.ongoing ? AppTheme.green : AppTheme.violetLight)
                        .withValues(alpha: 0.4),
                    blurRadius: 8),
              ],
            ),
          ),
          if (!isLast)
            Expanded(
              child: Container(width: 1.5, color: AppTheme.glassBorder(0.22)),
            ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (exp.period.isNotEmpty)
                    Text(exp.period,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.cyan, fontWeight: FontWeight.w700)),
                  if (exp.durationLabel.isNotEmpty)
                    Text('· ${exp.durationLabel}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.muted2)),
                  if (exp.ongoing)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.green.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Text('En cours',
                          style: TextStyle(
                              fontSize: 10.5, color: AppTheme.green, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (exp.role.isNotEmpty)
                Text(exp.role,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.25)),
              if (exp.company.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.apartment_outlined, size: 13, color: AppTheme.muted2),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        exp.location.isEmpty ? exp.company : '${exp.company} · ${exp.location}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ],
              if (exp.context.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(exp.context,
                    style: const TextStyle(
                        color: AppTheme.muted2, fontSize: 11.5, fontStyle: FontStyle.italic)),
              ],
              if (exp.bullets.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final b in exp.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: SizedBox(
                          width: 4, height: 4,
                          child: DecoratedBox(decoration: BoxDecoration(
                              color: AppTheme.muted, shape: BoxShape.circle)),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(b,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFFD8D4EA), height: 1.5)),
                      ),
                    ]),
                  ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final CvEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 84,
          child: Text(entry.period.isEmpty ? '—' : entry.period,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.cyan, fontWeight: FontWeight.w700, height: 1.45)),
        ),
        Expanded(
          child: Text(entry.label,
              style: const TextStyle(fontSize: 13, height: 1.45)),
        ),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 50, color: AppTheme.muted2),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, height: 1.5)),
          ]),
        ),
      );
}
