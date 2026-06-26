import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'training_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await context.read<AppState>().api.insights();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final d = _data;
    if (d == null) return const Center(child: Text('Erreur de chargement'));

    final topSkills = List<Map<String, dynamic>>.from(d['top_skills'] ?? []);
    final maxCount = topSkills.isEmpty ? 1 : (topSkills.first['count'] as int);
    final have = List<String>.from(d['your_skills_in_demand'] ?? []);
    final learn = List<String>.from(d['skills_to_learn'] ?? []);
    final salary = d['salary'] as Map<String, dynamic>?;
    final bySource = Map<String, dynamic>.from(d['by_source'] ?? {});
    final fmt = NumberFormat.decimalPattern('fr');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text('Analyse & Entraînement',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('${d['total_offers']} offres récentes analysées',
              style: const TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 16),

          // training entry (persuasiv-inspired)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrainingScreen())),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppTheme.ctaGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(color: AppTheme.indigo.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 8)),
                ],
              ),
              child: Row(children: [
                const Icon(Icons.fitness_center, color: Colors.white, size: 30),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Entraînement à l'entretien",
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    SizedBox(height: 3),
                    Text('Pitch, motivation, persuasion — réponds et reçois un score + des conseils.',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // salary
          if (salary != null)
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _Label('SALAIRE INDICATIF'),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${fmt.format(salary['median'])}',
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: Colors.white)),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6, left: 4),
                    child: Text('médian', style: TextStyle(color: AppTheme.muted)),
                  ),
                ]),
                Text('fourchette ${fmt.format(salary['min'])} – ${fmt.format(salary['max'])} · ${salary['sample']} offres',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Text(salary['note'] ?? '', style: const TextStyle(color: AppTheme.muted2, fontSize: 11)),
              ]),
            ),

          // top skills with bars
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _Label('COMPÉTENCES LES PLUS DEMANDÉES'),
              const SizedBox(height: 14),
              ...topSkills.take(10).map((s) {
                final count = s['count'] as int;
                final mine = have.contains(s['skill']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (mine)
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(Icons.check_circle, size: 14, color: AppTheme.green),
                        ),
                      Expanded(
                        child: Text(s['skill'],
                            style: TextStyle(
                                fontSize: 13,
                                color: mine ? Colors.white : AppTheme.muted,
                                fontWeight: mine ? FontWeight.w600 : FontWeight.w400)),
                      ),
                      Text('$count', style: const TextStyle(color: AppTheme.muted2, fontSize: 12)),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: count / maxCount,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation(
                            mine ? AppTheme.green : AppTheme.violet),
                      ),
                    ),
                  ]),
                );
              }),
            ]),
          ),

          // gap
          if (learn.isNotEmpty)
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _Label('À APPRENDRE POUR LE MARCHÉ'),
                const SizedBox(height: 10),
                const Text('Compétences très demandées que ton CV ne mentionne pas encore :',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 12),
                SkillChips(skills: learn, color: AppTheme.amber),
              ]),
            ),

          // by source
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _Label('OFFRES PAR SOURCE'),
              const SizedBox(height: 12),
              ...bySource.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(e.key, style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
                      Text('${e.value}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ]),
                  )),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11, color: AppTheme.violetLight, fontWeight: FontWeight.w700, letterSpacing: 0.8));
}
