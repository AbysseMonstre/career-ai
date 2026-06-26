import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});
  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final _title = TextEditingController();
  final _company = TextEditingController();
  final _location = TextEditingController();
  final _salary = TextEditingController();
  final _tags = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _company.text.trim().isEmpty) {
      showError(context, 'Titre et entreprise requis');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.postJob({
        'title': _title.text.trim(),
        'company': _company.text.trim(),
        'location': _location.text.trim(),
        'salary': _salary.text.trim(),
        'description': _description.text.trim(),
        'tags': _tags.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      });
      if (mounted) {
        showOk(context, 'Offre publiée');
        for (final c in [_title, _company, _location, _salary, _tags, _description]) {
          c.clear();
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Publier une offre', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Votre offre alimente le matching des candidats.', style: TextStyle(color: Color(0xFF6B7280))),
        const SizedBox(height: 16),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Intitulé du poste *')),
        const SizedBox(height: 12),
        TextField(controller: _company, decoration: const InputDecoration(labelText: 'Entreprise *')),
        const SizedBox(height: 12),
        TextField(controller: _location, decoration: const InputDecoration(labelText: 'Localisation')),
        const SizedBox(height: 12),
        TextField(controller: _salary, decoration: const InputDecoration(labelText: 'Salaire (optionnel)')),
        const SizedBox(height: 12),
        TextField(controller: _tags, decoration: const InputDecoration(labelText: 'Compétences (séparées par des virgules)', hintText: 'python, django, aws')),
        const SizedBox(height: 12),
        TextField(controller: _description, maxLines: 5, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.publish),
          label: const Text("Publier l'offre"),
        ),
      ],
    );
  }
}
