import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'training_screen.dart';

const Map<String, String> _sourceLabels = {
  'linkedin': 'LinkedIn', 'remoteok': 'RemoteOK', 'remotive': 'Remotive',
  'arbeitnow': 'Arbeitnow', 'themuse': 'The Muse', 'jobicy': 'Jobicy',
  'adzuna': 'Adzuna', 'francetravail': 'France Travail', 'jsearch': 'LinkedIn/Indeed…',
  'recruiter': 'Offre directe',
};

/// Open a job's real listing page in the browser.
Future<void> openJobUrl(BuildContext context, String url) async {
  HapticFeedback.lightImpact();
  if (url.isEmpty) {
    showError(context, "Lien indisponible pour cette offre");
    return;
  }
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showError(context, "Impossible d'ouvrir le lien");
}

/// Tapping "Postuler": auto-record the application, then open the listing.
Future<void> applyToJob(BuildContext context, Job job) async {
  HapticFeedback.mediumImpact();
  int count = 0;
  try {
    count = await context.read<AppState>().api.recordApplied(job.id);
  } catch (_) {}
  if (context.mounted) {
    showOk(context, count > 0
        ? 'Candidature enregistrée ($count au total)'
        : 'Candidature enregistrée');
    await openJobUrl(context, job.url);
  }
}

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final _search = TextEditingController();
  final _location = TextEditingController();
  List<Job> _jobs = [];
  final Set<int> _selected = {};
  bool _loading = false;
  String _contract = ''; // '' | cdi | cdd | freelance | stage | alternance
  bool _remote = false;
  bool _favoritesOnly = false;
  bool _alternance = false; // work-study mode: aggressively fetch alternance offers
  String _sort = 'match'; // match | recent

  static const _categories = {
    'Tech': 'développeur', 'Data': 'data', 'Design': 'designer',
    'Marketing': 'marketing', 'Commercial': 'commercial', 'Finance': 'finance',
    'RH': 'ressources humaines', 'Santé': 'infirmier', 'Logistique': 'logistique',
  };
  List<String> _history = []; // "query|location" entries, most recent first
  String _profileTitle = '';
  List<String> _profileSkills = [];
  String _profileLoc = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadProfile();
    _load();
  }

  Future<void> _loadProfile() async {
    try {
      final cv = await context.read<AppState>().api.getCv();
      if (mounted) {
        setState(() {
          _profileTitle = cv['title'] ?? '';
          _profileSkills = List<String>.from(cv['skills'] ?? []);
          _profileLoc = cv['location'] ?? '';
        });
      }
    } catch (_) {}
  }

  // Scrape every source for the candidate's title + top CV skills.
  Future<void> _syncProfile() async {
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);
    try {
      final api = context.read<AppState>().api;
      await api.activityPing();
      _jobs = await api.jobs(
          syncProfile: true, location: _location.text.trim(),
          contract: _contract, remote: _remote, sort: _sort);
      if (mounted) showOk(context, '${_jobs.length} offres trouvées pour ton profil');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Open Google for Jobs pre-filled with the profile (or current search).
  void _openGoogleJobs() {
    HapticFeedback.lightImpact();
    final q = _search.text.trim().isNotEmpty ? _search.text.trim() : _profileTitle;
    final loc = _location.text.trim().isNotEmpty ? _location.text.trim() : _profileLoc;
    final skills = _profileSkills.take(3).join(' ');
    final full = [q, skills, loc].where((s) => s.isNotEmpty).join(' ').trim();
    final query = full.isEmpty ? 'emploi' : full;
    final url = 'https://www.google.com/search?ibp=htl;jobs&q=${Uri.encodeComponent(query)}';
    openJobUrl(context, url);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _history = prefs.getStringList('searchHistory') ?? []);
  }

  Future<void> _saveSearch(String q, String loc) async {
    if (q.isEmpty && loc.isEmpty) return;
    final entry = '$q|$loc';
    _history.remove(entry);
    _history.insert(0, entry);
    if (_history.length > 8) _history = _history.sublist(0, 8);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('searchHistory', _history);
    if (mounted) setState(() {});
  }

  // Read the current cache (fast). Used on first open / pull-to-refresh.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<AppState>().api;
      _jobs = await api.jobs(
          query: _search.text.trim(), location: _location.text.trim(),
          contract: _contract, remote: _remote, sort: _sort,
          favoritesOnly: _favoritesOnly, alternance: _alternance);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Work-study mode: ask the backend to scrape alternance across many domains
  // and return only work-study offers (with recruiter contact when available).
  Future<void> _loadAlternance() async {
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);
    try {
      final api = context.read<AppState>().api;
      await api.activityPing();
      _jobs = await api.jobs(
          query: _search.text.trim(), location: _location.text.trim(),
          alternance: true, sync: true, sort: _sort, favoritesOnly: _favoritesOnly);
      if (mounted) showOk(context, '${_jobs.length} offres en alternance');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _runCategory(String query) {
    _search.text = query;
    _searchAndSync();
  }

  Future<void> _toggleLike(Job job) async {
    HapticFeedback.selectionClick();
    try {
      final liked = await context.read<AppState>().api.toggleFavorite(job.id);
      setState(() => job.liked = liked);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _runHistory(String entry) {
    final parts = entry.split('|');
    _search.text = parts.isNotEmpty ? parts[0] : '';
    _location.text = parts.length > 1 ? parts[1] : '';
    _searchAndSync();
  }

  // Search = synchronize: scrape every source for this query + location, then show.
  Future<void> _searchAndSync() async {
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);
    final q = _search.text.trim(), loc = _location.text.trim();
    _saveSearch(q, loc);
    try {
      final api = context.read<AppState>().api;
      _jobs = await api.jobs(
          query: q, location: loc, sync: true,
          contract: _contract, remote: _remote, sort: _sort,
          favoritesOnly: _favoritesOnly, alternance: _alternance);
      if (mounted) {
        showOk(context, '${_jobs.length} offres synchronisées${loc.isEmpty ? '' : ' · $loc'}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applySelected() async {
    if (_selected.isEmpty) return;
    try {
      final created = await context.read<AppState>().api.autoApply(_selected.toList());
      if (mounted) {
        showOk(context, '${created.length} candidatures auto créées — validez-les dans "Candidatures"');
        setState(() => _selected.clear());
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Offres pour vous',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            IconButton.filledTonal(
              onPressed: _loading ? null : _searchAndSync,
              icon: const Icon(Icons.refresh),
              tooltip: 'Rafraîchir (chercher de nouvelles offres)',
            ),
          ]),
        ),
        // categories
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _categories.entries
                .map((e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(e.key, style: const TextStyle(fontSize: 13)),
                        backgroundColor: AppTheme.glass(),
                        side: BorderSide(color: AppTheme.glassBorder()),
                        onPressed: () => _runCategory(e.value),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _searchAndSync(),
            decoration: const InputDecoration(
              hintText: 'Métier, techno (python, design, marketing...)',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _location,
                onSubmitted: (_) => _searchAndSync(),
                decoration: const InputDecoration(
                  hintText: 'Localisation (Paris, remote...)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _loading ? null : _searchAndSync,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Synchroniser'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: 'Alternance',
                icon: Icons.school,
                selected: _alternance,
                onTap: () {
                  setState(() => _alternance = !_alternance);
                  _alternance ? _loadAlternance() : _load();
                },
              ),
              const _ChipGap(),
              _FilterChip(
                label: 'Favoris',
                icon: Icons.favorite,
                selected: _favoritesOnly,
                onTap: () { setState(() => _favoritesOnly = !_favoritesOnly); _load(); },
              ),
              const _ChipGap(),
              _FilterChip(
                label: 'Remote',
                icon: Icons.wifi,
                selected: _remote,
                onTap: () { setState(() => _remote = !_remote); _load(); },
              ),
              const _ChipGap(),
              ...{
                '': 'Tous', 'cdi': 'CDI', 'cdd': 'CDD', 'freelance': 'Freelance',
                'stage': 'Stage',
              }.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: e.value,
                      selected: _contract == e.key,
                      onTap: () { setState(() => _contract = e.key); _load(); },
                    ),
                  )),
              _FilterChip(
                label: _sort == 'recent' ? 'Récent' : 'Pertinence',
                icon: Icons.sort,
                selected: false,
                onTap: () {
                  setState(() => _sort = _sort == 'recent' ? 'match' : 'recent');
                  _load();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(children: [
            FilledButton.icon(
              onPressed: _loading ? null : _syncProfile,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Trouver les offres pour mon CV'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openGoogleJobs,
              icon: const Icon(Icons.travel_explore, size: 18),
              label: const Text('Voir aussi sur Google'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ]),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text('Récent :', style: TextStyle(color: AppTheme.muted2, fontSize: 12)),
                  ),
                ),
                ..._history.map((h) {
                  final p = h.split('|');
                  final label = [p[0], if (p.length > 1 && p[1].isNotEmpty) p[1]]
                      .where((s) => s.isNotEmpty).join(' · ');
                  if (label.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      backgroundColor: AppTheme.glass(),
                      side: BorderSide(color: AppTheme.glassBorder()),
                      onPressed: () => _runHistory(h),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const _JobsSkeleton()
              : _jobs.isEmpty
                  ? const _Empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: _jobs.length,
                        itemBuilder: (_, i) => FadeInItem(
                          index: i,
                          child: _JobCard(
                            job: _jobs[i],
                            selected: _selected.contains(_jobs[i].id),
                            onToggle: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                final id = _jobs[i].id;
                                _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
                              });
                            },
                            onLike: () => _toggleLike(_jobs[i]),
                          ),
                        ),
                      ),
                    ),
        ),
      ],
    ).withApplyBar(context, _selected.length, _applySelected);
  }
}

extension on Widget {
  Widget withApplyBar(BuildContext context, int count, VoidCallback onApply) {
    return Stack(children: [
      this,
      if (count > 0)
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: FilledButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.bookmark_added),
            label: Text('Suivre $count offre${count > 1 ? 's' : ''} (lettre + tableau de bord)'),
          ),
        ),
    ]);
  }
}

class _ChipGap extends StatelessWidget {
  const _ChipGap();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 8),
        width: 1, height: 20, color: AppTheme.glassBorder(0.2),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.violet.withValues(alpha: 0.22) : AppTheme.glass(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppTheme.violetLight : AppTheme.glassBorder()),
        ),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: selected ? Colors.white : AppTheme.muted),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : AppTheme.muted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Job job;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onLike;
  const _JobCard({required this.job, required this.selected, required this.onToggle, required this.onLike});

  String get _initial => job.company.isNotEmpty ? job.company[0].toUpperCase() : '•';

  @override
  Widget build(BuildContext context) {
    final score = job.match?.score ?? 0;
    return GlassCard(
      onTap: () => _showDetail(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(_initial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.2)),
                    const SizedBox(height: 3),
                    Text(job.company,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Row(children: [
                      const Icon(Icons.place_outlined, size: 13, color: AppTheme.muted2),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(job.location,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                      ),
                    ]),
                  ],
                ),
              ),
              if (job.match != null) ...[const SizedBox(width: 8), MatchGauge(score: score)],
            ],
          ),
          if (job.match != null && job.match!.matchedSkills.isNotEmpty) ...[
            const SizedBox(height: 12),
            SkillChips(skills: job.match!.matchedSkills.take(5).toList(),
                highlight: job.match!.matchedSkills),
          ],
          const SizedBox(height: 14),
          Row(children: [
            _SourceBadge(job.source),
            if (job.isAlternance) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.violetLight.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.school, size: 12, color: AppTheme.violetLight),
                  SizedBox(width: 3),
                  Text('Alternance',
                      style: TextStyle(fontSize: 11, color: AppTheme.violetLight,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            if (job.salary.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(job.salary,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.green, fontWeight: FontWeight.w600)),
              ),
            ],
            const Spacer(),
            IconButton(
              onPressed: onLike,
              visualDensity: VisualDensity.compact,
              tooltip: 'Aimer',
              icon: Icon(job.liked ? Icons.favorite : Icons.favorite_border,
                  color: job.liked ? AppTheme.red : AppTheme.muted2, size: 22),
            ),
            IconButton(
              onPressed: onToggle,
              visualDensity: VisualDensity.compact,
              tooltip: 'Ajouter à mon suivi',
              icon: Icon(selected ? Icons.bookmark : Icons.bookmark_add_outlined,
                  color: selected ? AppTheme.violetLight : AppTheme.muted2, size: 22),
            ),
            const SizedBox(width: 2),
            FilledButton.icon(
              onPressed: () => applyToJob(context, job),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Postuler'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16)),
            ),
          ]),
          if (job.contactEmail != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => openJobUrl(context,
                    'mailto:${job.contactEmail}?subject=${Uri.encodeComponent('Candidature — ${job.title}')}'),
                icon: const Icon(Icons.alternate_email, size: 16),
                label: Text('Contacter le recruteur · ${job.contactEmail}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final loc = job.location.toLowerCase();
    final isRemote = loc.contains('remote') || loc.contains('télétravail') ||
        loc.contains('anywhere') || loc.contains('worldwide');
    final m = job.match;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (_, ctrl) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: ColoredBox(
            color: AppTheme.sheet,
            child: Column(children: [
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: EdgeInsets.zero,
                  children: [
                    // ---- gradient header (Inhusk-style) ----
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF6A41B8), Color(0xFF3C2470), AppTheme.sheet],
                          stops: [0.0, 0.55, 1.0],
                        ),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Center(
                          child: Container(
                            width: 42, height: 5,
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          width: 66, height: 66,
                          decoration: BoxDecoration(
                            gradient: AppTheme.brandGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8)),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(_initial,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
                        ),
                        const SizedBox(height: 18),
                        Text(job.title,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, height: 1.15)),
                        const SizedBox(height: 6),
                        Text('${job.company} · ${job.location}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14)),
                        const SizedBox(height: 18),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _Tag(_sourceLabels[job.source] ?? job.source, filled: true),
                          if (isRemote) const _Tag('Remote', icon: Icons.wifi),
                          _Tag(job.salary.isNotEmpty ? job.salary : 'Salaire non communiqué',
                              icon: Icons.payments_outlined,
                              color: job.salary.isNotEmpty ? AppTheme.green : AppTheme.muted),
                          if (m != null) _Tag('${m.score}% match',
                              icon: Icons.insights, color: AppTheme.scoreColor(m.score)),
                        ]),
                      ]),
                    ),
                    // ---- body panels ----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: Column(children: [
                        if (m != null)
                          _DetailPanel(
                            label: 'Votre correspondance',
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                MatchGauge(score: m.score, size: 58),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                      'Vous couvrez ${m.matchedSkills.length} des ${m.jobSkillCount} compétences attendues.',
                                      style: const TextStyle(color: AppTheme.muted, height: 1.4)),
                                ),
                              ]),
                              if (m.matchedSkills.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                SkillChips(skills: m.matchedSkills, highlight: m.matchedSkills),
                              ],
                            ]),
                          ),
                        if (m != null && m.missingSkills.isNotEmpty)
                          _DetailPanel(
                            label: 'Compétences à acquérir',
                            child: SkillChips(skills: m.missingSkills, color: AppTheme.red),
                          ),
                        _DetailPanel(
                          label: 'Aperçu du poste',
                          child: Text(
                              job.description.isEmpty
                                  ? 'Pas de description fournie par la source.'
                                  : job.description,
                              style: const TextStyle(height: 1.55, color: Color(0xFFD8D4EA))),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
              // ---- train for this offer ----
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => TrainingScreen(jobId: job.id, jobTitle: job.title)));
                  },
                  icon: const Icon(Icons.fitness_center, size: 18),
                  label: const Text("S'entraîner pour cette offre"),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ),
              // ---- sticky gradient CTA ----
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
                child: GestureDetector(
                  onTap: () => applyToJob(context, job),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppTheme.ctaGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: AppTheme.indigo.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 8)),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.open_in_new, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text("Postuler sur le site de l'annonce",
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Glass section card with a small label header (detail sheet).
class _DetailPanel extends StatelessWidget {
  final String label;
  final Widget child;
  const _DetailPanel({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.glass(),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.glassBorder()),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.violetLight, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 12),
              child,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pill tag for the detail header (filled gradient or glass).
class _Tag extends StatelessWidget {
  final String text;
  final bool filled;
  final IconData? icon;
  final Color? color;
  const _Tag(this.text, {this.filled = false, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.violetLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        gradient: filled ? AppTheme.brandGradient : null,
        color: filled ? null : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: filled ? Colors.white : c),
          const SizedBox(width: 5),
        ],
        Text(text,
            style: TextStyle(
                fontSize: 12.5,
                color: filled ? Colors.white : c,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge(this.source);
  @override
  Widget build(BuildContext context) {
    final label = _sourceLabels[source] ?? source;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: AppTheme.cyan.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.25))),
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppTheme.cyan, fontWeight: FontWeight.w600)),
    );
  }
}

class _JobsSkeleton extends StatelessWidget {
  const _JobsSkeleton();

  Widget _card() => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.glass(),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.glassBorder()),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SkeletonBox(width: 46, height: 46, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                SkeletonBox(width: 180, height: 15),
                SizedBox(height: 8),
                SkeletonBox(width: 120, height: 12),
              ]),
            ),
            const SkeletonBox(width: 46, height: 46, radius: 23),
          ]),
          const SizedBox(height: 14),
          Row(children: const [
            SkeletonBox(width: 70, height: 22, radius: 12),
            SizedBox(width: 8),
            SkeletonBox(width: 90, height: 22, radius: 12),
            Spacer(),
            SkeletonBox(width: 90, height: 36, radius: 12),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: List.generate(5, (_) => _card()),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.travel_explore, size: 52, color: AppTheme.muted2),
            const SizedBox(height: 14),
            const Text('Aucune offre pour cette recherche',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Saisis un métier et une localisation, puis appuie sur « Synchroniser » pour récupérer les offres du web.',
                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
          ]),
        ),
      );
}
