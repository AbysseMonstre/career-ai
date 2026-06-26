import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});
  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  List<Application> _apps = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _apps = await context.read<AppState>().api.applications();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _validate(int id) async {
    try {
      await context.read<AppState>().api.validateApplication(id);
      if (mounted) showOk(context, 'Candidature validée et enregistrée');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reject(int id) async {
    try {
      await context.read<AppState>().api.rejectApplication(id);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _markApplied(int id) async {
    try {
      await context.read<AppState>().api.markApplied(id);
      if (mounted) showOk(context, 'Candidature marquée comme postulée');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _apps.where((a) => a.status == 'auto_pending').toList();
    final validated = _apps.where((a) => a.status == 'validated' || a.status == 'applied').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const Text('Mes candidatures',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Validez vos candidatures auto pour les enregistrer.',
                    style: TextStyle(color: Color(0xFF6B7280))),
                const SizedBox(height: 16),
                if (pending.isNotEmpty) ...[
                  const _SectionTitle('À valider', AppTheme.amber),
                  ...pending.map((a) => _AppCard(app: a, onValidate: () => _validate(a.id),
                      onReject: () => _reject(a.id), onApplied: () => _markApplied(a.id))),
                  const SizedBox(height: 16),
                ],
                _SectionTitle('Enregistrées (${validated.length})', AppTheme.green),
                if (validated.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucune candidature validée pour l’instant.', style: TextStyle(color: AppTheme.muted)),
                  ),
                ...validated.map((a) => _AppCard(app: a, onApplied: () => _markApplied(a.id))),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionTitle(this.text, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
      );
}

class _AppCard extends StatelessWidget {
  final Application app;
  final VoidCallback? onValidate;
  final VoidCallback? onReject;
  final VoidCallback? onApplied;
  const _AppCard({required this.app, this.onValidate, this.onReject, this.onApplied});

  void _openLetterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          children: [
            Text(app.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${app.company} · ${app.location}', style: const TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 16),
            const Text('Lettre de motivation générée', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(
              app.coverLetter.isEmpty ? 'Aucune lettre.' : app.coverLetter,
              style: const TextStyle(height: 1.5, color: Color(0xFFD8D4EA)),
            ),
            const SizedBox(height: 20),
            if (app.url.isNotEmpty)
              FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse(app.url), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text("Ouvrir l'offre et postuler"),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onApplied == null ? null : () {
                Navigator.pop(context);
                onApplied!();
              },
              icon: const Icon(Icons.check),
              label: const Text("J'ai postulé"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(app.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${app.company} · ${app.location}', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                ]),
              ),
              MatchGauge(score: app.matchScore, size: 48),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _StatusChip(app.status),
              const Spacer(),
              if (onValidate != null) ...[
                TextButton(onPressed: onReject, child: const Text('Rejeter', style: TextStyle(color: AppTheme.red))),
                FilledButton(onPressed: onValidate, style: FilledButton.styleFrom(minimumSize: const Size(0, 38)), child: const Text('Valider')),
              ] else
                TextButton.icon(
                  onPressed: () => _openLetterSheet(context),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Lettre & postuler'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) {
    final map = {
      'auto_pending': ('En attente de validation', AppTheme.amber),
      'validated': ('Enregistrée', AppTheme.green),
      'applied': ('Postulé', AppTheme.violetLight),
      'rejected': ('Rejetée', AppTheme.red),
    };
    final (label, color) = map[status] ?? ('?', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
