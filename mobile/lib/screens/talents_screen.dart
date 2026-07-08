import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'schedule_interview.dart';

class TalentsScreen extends StatefulWidget {
  const TalentsScreen({super.key});
  @override
  State<TalentsScreen> createState() => _TalentsScreenState();
}

class _TalentsScreenState extends State<TalentsScreen> {
  final _search = TextEditingController(text: 'python django aws');
  List<Candidate> _candidates = [];
  bool _loading = false;
  String _access = 'loading'; // loading | none | pending | granted

  @override
  void initState() {
    super.initState();
    _initAccess();
  }

  Future<void> _initAccess() async {
    try {
      final s = await context.read<AppState>().api.talentAccessStatus();
      _access = s['status'] ?? 'none';
      if (_access == 'granted') {
        await _load();
      } else if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        _access = 'none';
        showError(context, e);
        setState(() {});
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _candidates = await context.read<AppState>().api.talents(query: _search.text.trim());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_access == 'loading') {
      return const Center(child: CircularProgressIndicator());
    }
    if (_access != 'granted') {
      return _AccessGate(
        pending: _access == 'pending',
        onRequested: () => setState(() => _access = 'pending'),
      );
    }
    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Base de talents', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Candidats classés par correspondance avec vos critères.',
              style: TextStyle(color: AppTheme.muted)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            hintText: 'Compétences recherchées (python, react, design...)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
          ),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _candidates.isEmpty
                ? const Center(child: Text('Aucun candidat. Les chercheurs doivent importer leur CV.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _candidates.length,
                      itemBuilder: (_, i) => _CandidateCard(_candidates[i]),
                    ),
                  ),
      ),
    ]);
  }
}

/// Shown to recruiters who have not yet been granted talent-base access.
class _AccessGate extends StatefulWidget {
  final bool pending;
  final VoidCallback onRequested;
  const _AccessGate({required this.pending, required this.onRequested});
  @override
  State<_AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<_AccessGate> {
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (_company.text.trim().isEmpty) {
      showError(context, "Indiquez le nom de votre entreprise");
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.requestTalentAccess(
          _company.text.trim(), _phone.text.trim(), _message.text.trim());
      if (mounted) {
        showOk(context, 'Demande envoyée — notre équipe vous recontacte');
        widget.onRequested();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.hourglass_top_rounded, size: 48, color: AppTheme.amber),
              SizedBox(height: 16),
              Text('Demande en cours',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                "Votre demande d'accès à la base de talents a bien été transmise. "
                "Notre équipe vous recontacte pour l'activer.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, height: 1.5),
              ),
            ]),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.lock_outline, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 18),
        const Text('Accès sur demande',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          "La base de talents est réservée aux recruteurs partenaires. "
          "Contactez-nous pour activer votre accès — notre équipe valide votre demande.",
          style: TextStyle(color: AppTheme.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        TextField(controller: _company, decoration: const InputDecoration(labelText: 'Entreprise *')),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
        const SizedBox(height: 12),
        TextField(controller: _message, maxLines: 4, decoration: const InputDecoration(labelText: 'Votre besoin (postes, volumes…)', alignLabelWithHint: true)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send),
          label: const Text('Demander l\'accès'),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final Candidate c;
  const _CandidateCard(this.c);

  Future<void> _requestPlacement(BuildContext context) async {
    final msgCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.sheet,
        title: Text('Mise en relation — ${c.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            "Notre équipe organise le contact avec ce freelance et gère la suite. "
            "Décrivez votre besoin (mission, durée, budget) :",
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(controller: msgCtrl, maxLines: 3,
              decoration: const InputDecoration(hintText: 'Votre besoin…')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Demander')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final res = await context.read<AppState>().api.requestPlacement(c.candidateId, msgCtrl.text.trim());
      if (context.mounted) showOk(context, res['message'] ?? 'Demande envoyée');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.violetLight, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(c.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  if (c.applied > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppTheme.green.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(7)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.send, size: 10, color: AppTheme.green),
                        const SizedBox(width: 3),
                        Text(c.applied > 1 ? 'A postulé (${c.applied})' : 'A postulé',
                            style: const TextStyle(fontSize: 10, color: AppTheme.green, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ],
                ]),
                Text([c.title, c.location].where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 2),
                Text('${c.match.score}% de correspondance',
                    style: const TextStyle(fontSize: 12, color: AppTheme.violetLight, fontWeight: FontWeight.w700)),
              ]),
            ),
            MatchGauge(score: c.match.score),
          ]),
          const SizedBox(height: 12),
          SkillChips(skills: c.skills, highlight: c.match.matchedSkills),
          const SizedBox(height: 14),
          Text('${c.match.matchedSkills.length} compétences en commun',
              style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => showScheduleSheet(context, c),
                icon: const Icon(Icons.event_available, size: 17),
                label: const Text('Planifier un RDV'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _requestPlacement(context),
                icon: const Icon(Icons.connect_without_contact, size: 17),
                label: const Text('Mise en relation'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
