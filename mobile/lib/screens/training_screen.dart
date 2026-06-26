import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'training_history_screen.dart';

/// Persuasiv-inspired interview/pitch trainer: question -> answer -> score + tips.
class TrainingScreen extends StatefulWidget {
  final int jobId; // 0 = generic CV-based; >0 = targeted on a specific offer
  final String? jobTitle;
  const TrainingScreen({super.key, this.jobId = 0, this.jobTitle});
  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  List<Map<String, dynamic>> _questions = [];
  int _index = 0;
  bool _loading = true;
  bool _scoring = false;
  final _answer = TextEditingController();
  Map<String, dynamic>? _result;
  final List<int> _scores = [];
  final List<Map<String, dynamic>> _axesHistory = [];
  Map<String, dynamic> _sessionAxes = {};

  static const _typeLabels = {
    'pitch': 'Pitch', 'motivation': 'Motivation', 'persuasion': 'Persuasion',
    'behavioral': 'Comportemental', 'weakness': 'Point faible',
    'negotiation': 'Négociation', 'technique': 'Technique',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _questions = await context.read<AppState>().api.trainingQuestions(jobId: widget.jobId);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _evaluate() async {
    if (_answer.text.trim().length < 3) return;
    setState(() => _scoring = true);
    HapticFeedback.lightImpact();
    try {
      final q = _questions[_index];
      _result = await context.read<AppState>().api
          .trainingScore(q['q'], _answer.text.trim(), q['type'] ?? '', jobId: widget.jobId);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _scoring = false);
    }
  }

  void _next() {
    if (_result != null) {
      _scores.add(_result!['score'] ?? 0);
      _axesHistory.add(Map<String, dynamic>.from(_result!['breakdown'] ?? {}));
    }
    setState(() {
      _result = null;
      _answer.clear();
      _index++;
    });
    if (_index >= _questions.length) _saveSession();
  }

  Future<void> _saveSession() async {
    if (_axesHistory.isEmpty) return;
    final keys = _axesHistory.first.keys.toList();
    final avgAxes = <String, dynamic>{};
    for (final k in keys) {
      final vals = _axesHistory.map((m) => (m[k] ?? 0) as num);
      avgAxes[k] = (vals.reduce((a, b) => a + b) / vals.length).round();
    }
    final avgScore = (_scores.reduce((a, b) => a + b) / _scores.length).round();
    _sessionAxes = avgAxes;
    try {
      await context.read<AppState>().api.trainingSaveSession(avgScore, avgAxes, _scores.length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.jobId > 0 ? 'Entraînement ciblé' : 'Entraînement à l\'entretien'),
        bottom: widget.jobTitle != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('🎯 ${widget.jobTitle}',
                        style: const TextStyle(color: AppTheme.violetLight, fontSize: 13)),
                  ),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _index >= _questions.length
                ? _Summary(scores: _scores, axes: _sessionAxes, onRestart: () {
                    setState(() {
                      _index = 0;
                      _scores.clear();
                      _axesHistory.clear();
                      _sessionAxes = {};
                      _result = null;
                      _answer.clear();
                    });
                  })
                : _buildQuestion(),
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _questions[_index];
    final res = _result;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_index + 1) / _questions.length,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor: const AlwaysStoppedAnimation(AppTheme.violet),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('${_index + 1}/${_questions.length}', style: const TextStyle(color: AppTheme.muted)),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(_typeLabels[q['type']] ?? 'Question',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ).fitContent(),
        const SizedBox(height: 14),
        Text(q['q'],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.3)),
        const SizedBox(height: 18),
        TextField(
          controller: _answer,
          maxLines: 7,
          enabled: res == null,
          decoration: const InputDecoration(
              hintText: 'Tape ta réponse comme en entretien (méthode STAR, chiffres…)'),
        ),
        const SizedBox(height: 14),
        if (res == null)
          FilledButton.icon(
            onPressed: _scoring ? null : _evaluate,
            icon: _scoring
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.analytics_outlined),
            label: const Text('Évaluer ma réponse'),
          )
        else ...[
          _FeedbackCard(res),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _next,
            icon: const Icon(Icons.arrow_forward),
            label: Text(_index + 1 >= _questions.length ? 'Voir mon bilan' : 'Question suivante'),
          ),
        ],
      ],
    );
  }
}

extension on Widget {
  Widget fitContent() => Align(alignment: Alignment.centerLeft, child: this);
}

class _FeedbackCard extends StatelessWidget {
  final Map<String, dynamic> res;
  const _FeedbackCard(this.res);

  @override
  Widget build(BuildContext context) {
    final score = res['score'] ?? 0;
    final tips = List<String>.from(res['tips'] ?? []);
    final bd = Map<String, dynamic>.from(res['breakdown'] ?? {});
    final color = AppTheme.scoreColor(score);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          MatchGauge(score: score, size: 60),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
                score >= 70 ? 'Réponse convaincante 💪'
                    : score >= 40 ? 'Pas mal — peut être renforcée'
                        : 'À retravailler',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ),
        ]),
        const SizedBox(height: 14),
        ...bd.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 80, child: Text(e.key, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (e.value as num) / 100,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation(AppTheme.scoreColor((e.value as num).round())),
                    ),
                  ),
                ),
              ]),
            )),
        const SizedBox(height: 6),
        const Text('Conseils', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...tips.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('• ', style: TextStyle(color: AppTheme.violetLight)),
                Expanded(child: Text(t, style: const TextStyle(color: Color(0xFFD8D4EA), height: 1.4))),
              ]),
            )),
      ]),
    );
  }
}

class _Summary extends StatelessWidget {
  final List<int> scores;
  final Map<String, dynamic> axes;
  final VoidCallback onRestart;
  const _Summary({required this.scores, required this.axes, required this.onRestart});

  @override
  Widget build(BuildContext context) {
    final avg = scores.isEmpty ? 0 : (scores.reduce((a, b) => a + b) / scores.length).round();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(child: MatchGauge(score: avg, size: 96)),
        const SizedBox(height: 16),
        Center(
          child: Text('Score moyen : $avg%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('${scores.length} réponses · +1 jour de série 🔥',
              style: const TextStyle(color: AppTheme.muted)),
        ),
        const SizedBox(height: 18),
        if (axes.isNotEmpty)
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TON OCTOGONE (cette session)',
                  style: TextStyle(fontSize: 11, color: AppTheme.violetLight, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              RadarOctagon(axes),
            ]),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TrainingHistoryScreen())),
          icon: const Icon(Icons.insights),
          label: const Text('Voir mon bilan complet & évolution'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: onRestart, icon: const Icon(Icons.refresh), label: const Text('Nouvelle session')),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Terminer')),
      ],
    );
  }
}
