import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class TrainingHistoryScreen extends StatefulWidget {
  const TrainingHistoryScreen({super.key});
  @override
  State<TrainingHistoryScreen> createState() => _TrainingHistoryScreenState();
}

class _TrainingHistoryScreenState extends State<TrainingHistoryScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _data = await context.read<AppState>().api.trainingHistory();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bilan d'entraînement")),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _build(),
      ),
    );
  }

  Widget _build() {
    final d = _data!;
    final count = d['count'] ?? 0;
    if (count == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text("Fais une session d'entraînement pour voir ton bilan et ta progression.",
              textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
        ),
      );
    }
    final radar = Map<String, dynamic>.from(d['radar'] ?? {});
    final evolution = List<Map<String, dynamic>>.from(d['evolution'] ?? []);
    final recos = List<Map<String, dynamic>>.from(d['recommendations'] ?? []);
    final trend = d['trend'] ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          _Stat('$count', 'sessions'),
          _Stat('${d['avg_score']}%', 'score moyen'),
          _Stat('${trend >= 0 ? '+' : ''}$trend', 'tendance',
              color: trend >= 0 ? AppTheme.green : AppTheme.red),
        ]),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("OCTOGONE DE COMPÉTENCES",
                style: TextStyle(fontSize: 11, color: AppTheme.violetLight, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            RadarOctagon(radar),
          ]),
        ),
        if (evolution.length >= 2)
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("ÉVOLUTION DE TES SCORES",
                  style: TextStyle(fontSize: 11, color: AppTheme.violetLight, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 16),
              SizedBox(height: 160, child: _evolutionChart(evolution)),
            ]),
          ),
        if (recos.isNotEmpty)
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("CONSEILS PRIORITAIRES",
                  style: TextStyle(fontSize: 11, color: AppTheme.violetLight, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              const Text('Tes axes les plus faibles à travailler en priorité :',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 12),
              ...recos.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: AppTheme.scoreColor((r['score'] as num).round()).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('${r['score']}%',
                            style: TextStyle(color: AppTheme.scoreColor((r['score'] as num).round()), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['axis'], style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(r['advice'] ?? '', style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.3)),
                        ]),
                      ),
                    ]),
                  )),
            ]),
          ),
      ],
    );
  }

  Widget _evolutionChart(List<Map<String, dynamic>> ev) {
    final spots = <FlSpot>[];
    for (var i = 0; i < ev.length; i++) {
      spots.add(FlSpot(i.toDouble(), (ev[i]['score'] as num).toDouble()));
    }
    return LineChart(LineChartData(
      minY: 0, maxY: 100,
      gridData: FlGridData(show: true, drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: 0.06), strokeWidth: 1)),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: 25,
            getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: AppTheme.muted2, fontSize: 10)))),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppTheme.violetLight,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: AppTheme.violet.withValues(alpha: 0.18)),
        ),
      ],
    ));
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _Stat(this.value, this.label, {this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color ?? Colors.white)),
          Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
      );
}
