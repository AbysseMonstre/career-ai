import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SeekerDashboardScreen extends StatefulWidget {
  const SeekerDashboardScreen({super.key});
  @override
  State<SeekerDashboardScreen> createState() => _SeekerDashboardScreenState();
}

class _SeekerDashboardScreenState extends State<SeekerDashboardScreen> {
  SeekerDashboard? _data;
  Map<String, dynamic>? _activity;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<AppState>().api;
      await api.activityPing(); // opening the dashboard counts as activity
      _data = await api.seekerDashboard();
      _activity = await api.activity();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: const [
            Expanded(child: Text('Tableau de bord', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            LogoutButton(labeled: true),
            AccountMenu(),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : d == null
                  ? LoadErrorView(onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
          const SizedBox(height: 12),
          if (_activity != null) _StreakCard(_activity!),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              StatCard(label: 'Postulées', value: '${d.applied}', icon: Icons.send, color: AppTheme.violetLight),
              StatCard(label: 'Score moyen', value: '${d.avgMatchScore}%', icon: Icons.insights, color: AppTheme.scoreColor(d.avgMatchScore)),
              StatCard(label: 'Validées', value: '${d.validated}', icon: Icons.check_circle, color: AppTheme.green),
              StatCard(label: 'Offres dispo', value: '${d.jobsAvailable}', icon: Icons.work, color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Répartition des candidatures', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: d.totalApplications == 0
                      ? const Center(child: Text('Aucune candidature', style: TextStyle(color: Color(0xFF6B7280))))
                      : PieChart(PieChartData(sections: [
                          _slice(d.validated, 'Validées', const Color(0xFF16A34A)),
                          _slice(d.pending, 'Attente', const Color(0xFFF59E0B)),
                          _slice(d.rejected, 'Rejetées', const Color(0xFFEF4444)),
                        ].where((s) => s.value > 0).toList(), sectionsSpace: 2, centerSpaceRadius: 40)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title.isEmpty ? 'Profil' : d.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (d.location.isNotEmpty) Text(d.location, style: const TextStyle(color: Color(0xFF6B7280))),
                const SizedBox(height: 12),
                const Text('Mes compétences', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                d.skills.isEmpty
                    ? const Text('Importez votre CV pour extraire vos compétences.', style: TextStyle(color: Color(0xFF6B7280)))
                    : SkillChips(skills: d.skills, color: AppTheme.primary),
              ]),
            ),
          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  PieChartSectionData _slice(int value, String title, Color color) =>
      PieChartSectionData(value: value.toDouble(), title: value > 0 ? '$value' : '', color: color, radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
}
/// Duolingo-style weekly streak: flame, daily goal, 7-day grid.
class _StreakCard extends StatelessWidget {
  final Map<String, dynamic> a;
  const _StreakCard(this.a);

  @override
  Widget build(BuildContext context) {
    final streak = a['streak'] ?? 0;
    final goal = a['daily_goal'] ?? 3;
    final todayCount = a['today_count'] ?? 0;
    final goalMet = a['goal_met'] == true;
    final week = List<Map<String, dynamic>>.from(a['week'] ?? []);
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final progress = goal == 0 ? 1.0 : (todayCount / goal).clamp(0.0, 1.0);

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(goalMet ? '🔥' : '✨', style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$streak jour${streak > 1 ? 's' : ''} de série',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(goalMet
                      ? 'Objectif du jour atteint, bravo !'
                      : 'Objectif du jour : $todayCount/$goal actions',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
            ]),
          ),
          if ((a['best_streak'] ?? 0) > 0)
            Column(children: [
              Text('${a['best_streak']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.violetLight)),
              const Text('record', style: TextStyle(fontSize: 10, color: AppTheme.muted2)),
            ]),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(goalMet ? AppTheme.green : AppTheme.violet),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(week.length, (i) {
            final w = week[i];
            final active = w['active'] == true;
            final wd = (w['weekday'] ?? i) as int;
            return Column(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: active ? AppTheme.brandGradient : null,
                  color: active ? null : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                      color: active ? Colors.transparent : AppTheme.glassBorder()),
                ),
                child: Icon(active ? Icons.check : Icons.circle_outlined,
                    size: 15, color: active ? Colors.white : AppTheme.muted2),
              ),
              const SizedBox(height: 4),
              Text(labels[wd % 7], style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            ]);
          }),
        ),
      ]),
    );
  }
}
