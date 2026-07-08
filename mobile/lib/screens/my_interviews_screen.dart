import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class MyInterviewsScreen extends StatefulWidget {
  const MyInterviewsScreen({super.key});
  @override
  State<MyInterviewsScreen> createState() => _MyInterviewsScreenState();
}

class _MyInterviewsScreenState extends State<MyInterviewsScreen> {
  List<Interview>? _items;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await context.read<AppState>().api.myInterviews();
      _failed = false;
    } catch (_) {
      _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(Interview iv, bool accept) async {
    try {
      await context.read<AppState>().api.respondInterview(iv.id, accept);
      if (mounted) {
        showOk(context, accept ? 'Entretien accepté' : 'Entretien refusé');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Mes entretiens', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Les rendez-vous proposés par les recruteurs.',
              style: TextStyle(color: AppTheme.muted)),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
                ? LoadErrorView(onRetry: _load)
                : (_items == null || _items!.isEmpty)
                    ? _empty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: _items!.length,
                          itemBuilder: (_, i) => _InterviewCard(_items![i], onRespond: _respond),
                        ),
                      ),
      ),
    ]);
  }

  Widget _empty() => ListView(children: const [
        SizedBox(height: 80),
        Icon(Icons.event_available_outlined, size: 56, color: AppTheme.muted2),
        SizedBox(height: 12),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Aucun entretien pour l'instant.\nPostulez et importez votre CV pour être repéré par les recruteurs.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.5),
            ),
          ),
        ),
      ]);
}

class _InterviewCard extends StatelessWidget {
  final Interview iv;
  final Future<void> Function(Interview, bool) onRespond;
  const _InterviewCard(this.iv, {required this.onRespond});

  ({IconData icon, String label}) get _meta => switch (iv.meetingType) {
        'phone' => (icon: Icons.call, label: 'Téléphone'),
        'onsite' => (icon: Icons.location_on, label: 'Présentiel'),
        _ => (icon: Icons.videocam, label: 'Visio'),
      };

  @override
  Widget build(BuildContext context) {
    final w = iv.when;
    final whenStr = w != null
        ? DateFormat("EEEE d MMMM 'à' HH:mm", 'fr_FR').format(w)
        : 'Date à confirmer';
    final proposed = iv.status == 'proposed';
    final detail = iv.link.isNotEmpty ? iv.link : iv.location;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_meta.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(iv.company.isEmpty ? 'Entretien' : iv.company,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${_meta.label} · ${iv.durationMin} min',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ]),
          ),
          _statusChip(),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.event, size: 15, color: AppTheme.violetLight),
          const SizedBox(width: 6),
          Expanded(child: Text(whenStr, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        if (iv.message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(iv.message, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
        ],
        if (proposed) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => onRespond(iv, true),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Accepter'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onRespond(iv, false),
                icon: const Icon(Icons.close, size: 18, color: AppTheme.red),
                label: const Text('Refuser', style: TextStyle(color: AppTheme.red)),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44), side: const BorderSide(color: AppTheme.red)),
              ),
            ),
          ]),
        ] else if (iv.status == 'accepted' && detail.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _open(context, detail),
              icon: Icon(_meta.icon, size: 16),
              label: Text(iv.meetingType == 'visio'
                  ? 'Rejoindre la visio'
                  : iv.meetingType == 'phone' ? 'Appeler' : 'Voir le lieu'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _statusChip() {
    final (color, label) = switch (iv.status) {
      'accepted' => (AppTheme.green, 'Accepté'),
      'declined' => (AppTheme.red, 'Refusé'),
      _ => (AppTheme.amber, 'À répondre'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _open(BuildContext context, String detail) async {
    Uri? uri;
    if (iv.meetingType == 'visio') {
      uri = Uri.tryParse(detail.startsWith('http') ? detail : 'https://$detail');
    } else if (iv.meetingType == 'phone') {
      uri = Uri.parse('tel:${detail.replaceAll(' ', '')}');
    } else {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(detail)}');
    }
    if (uri != null && !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) showError(context, detail);
    }
  }
}
