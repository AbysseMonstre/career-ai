import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'cv_profile_screen.dart';

class CvScreen extends StatefulWidget {
  const CvScreen({super.key});
  @override
  State<CvScreen> createState() => _CvScreenState();
}

class _CvScreenState extends State<CvScreen> {
  final _text = TextEditingController();
  final _title = TextEditingController();
  final _location = TextEditingController();
  List<String> _skills = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    try {
      final cv = await context.read<AppState>().api.getCv();
      setState(() {
        _skills = List<String>.from(cv['skills'] ?? []);
        _title.text = cv['title'] ?? '';
        _location.text = cv['location'] ?? '';
      });
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    // Captured before the picker's async gap so we never read a stale context.
    final api = context.read<AppState>().api;
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md'],
        withData: true,
      );
    } catch (e) {
      if (mounted) showError(context, "Impossible d'ouvrir le sélecteur de fichiers : $e");
      return;
    }
    if (res == null) return; // user cancelled — not an error
    final f = res.files.single;
    // Without bytes there is nothing to send; say so instead of failing silently.
    if (f.bytes == null) {
      if (mounted) {
        showError(context,
            "Le fichier « ${f.name} » n'a pas pu être lu. Réessayez, ou collez le texte de votre CV ci-dessous.");
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await api.uploadCvFile(
            f.bytes!, f.name,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            location: _location.text.trim().isEmpty ? null : _location.text.trim(),
          );
      final skills = List<String>.from(out['skills'] ?? []);
      setState(() {
        _skills = skills;
        if ((out['title'] ?? '').toString().isNotEmpty && _title.text.trim().isEmpty) {
          _title.text = out['title'];
        }
      });
      if (!mounted) return;
      // Show the rebuilt profile straight away — that is the point of importing.
      final structure = CvStructure.fromJson(
          Map<String, dynamic>.from(out['structure'] ?? const {}));
      if (!structure.isEmpty) {
        _openProfile(structure);
        showOk(context,
            'CV lu : ${structure.experiences.length} expériences, '
            '${structure.declaredSkills.length} compétences');
        return;
      }
      if (skills.isEmpty) {
        // The CV was read (chars > 0) but matched no known skill — that is a
        // vocabulary gap, not a success worth a green tick.
        showError(context,
            "« ${f.name} » a bien été lu (${out['chars']} caractères) mais aucune compétence connue n'a été reconnue. Complétez le texte ci-dessous.");
      } else {
        showOk(context, '${skills.length} compétences extraites de « ${f.name} »');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openProfile([CvStructure? structure]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CvProfileScreen(
        initial: structure,
        title: _title.text.trim(),
        matchedSkills: _skills,
      ),
    ));
  }

  Future<void> _submitText() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final out = await context.read<AppState>().api.uploadCvText(
            _text.text.trim(),
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            location: _location.text.trim().isEmpty ? null : _location.text.trim(),
          );
      setState(() => _skills = List<String>.from(out['skills'] ?? []));
      if (mounted) showOk(context, '${_skills.length} compétences extraites');
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
        const Text('Mon CV', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Votre CV alimente le moteur de matching.', style: TextStyle(color: Color(0xFF6B7280))),
        const SizedBox(height: 16),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Intitulé de poste recherché')),
        const SizedBox(height: 12),
        TextField(controller: _location, decoration: const InputDecoration(labelText: 'Localisation (ex: remote, Paris)')),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('Importer mon CV (PDF ou texte)'),
        ),
        const SizedBox(height: 16),
        const Row(children: [
          Expanded(child: Divider()),
          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('ou', style: TextStyle(color: AppTheme.muted))),
          Expanded(child: Divider()),
        ]),
        const SizedBox(height: 8),
        const Text('Collez le contenu de votre CV', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'Collez ici le texte de votre CV (compétences, expériences…)'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _submitText, icon: const Icon(Icons.psychology), label: const Text('Analyser mon CV')),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _openProfile(),
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Voir mon profil (compétences & expériences)'),
        ),
        const SizedBox(height: 24),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_skills.isNotEmpty) ...[
          const Text('Compétences détectées', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          SkillChips(skills: _skills, color: AppTheme.primary),
        ],
      ],
    );
  }
}
