import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Opens the scheduling sheet for [candidate]. Returns true if an appointment
/// was created.
Future<bool> showScheduleSheet(BuildContext context, Candidate candidate) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.sheet,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _ScheduleSheet(candidate: candidate),
  );
  return ok == true;
}

class _ScheduleSheet extends StatefulWidget {
  final Candidate candidate;
  const _ScheduleSheet({required this.candidate});
  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  String _type = 'visio'; // visio | phone | onsite
  int _duration = 30;
  final _link = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  String get _detailLabel => switch (_type) {
        'phone' => 'Numéro à appeler',
        'onsite' => 'Adresse du rendez-vous',
        _ => 'Lien de la réunion (Teams, Meet, Zoom…)',
      };

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _confirm() async {
    final dt = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    if (dt.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
      showError(context, 'Choisissez une date/heure à venir');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = context.read<AppState>().api;
      final detail = _link.text.trim();
      await api.scheduleInterview(
        widget.candidate.candidateId,
        scheduledAt: dt.toIso8601String(),
        meetingType: _type,
        link: _type == 'visio' ? detail : '',
        location: _type == 'visio' ? '' : detail,
        durationMin: _duration,
        message: _message.text.trim(),
      );
      if (mounted) {
        showOk(context, 'Rendez-vous planifié avec ${widget.candidate.name}');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final df = DateFormat("EEEE d MMMM", 'fr_FR');
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.muted2, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
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
                  Text('Planifier un rendez-vous',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('${c.name} · ${c.match.score}% de correspondance',
                      style: const TextStyle(color: AppTheme.violetLight, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            // date + time
            Row(children: [
              Expanded(child: _pickerTile(Icons.event, df.format(_date), _pickDate)),
              const SizedBox(width: 10),
              Expanded(child: _pickerTile(Icons.schedule, _time.format(context), _pickTime)),
            ]),
            const SizedBox(height: 16),
            const Text('Type de rendez-vous', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              _typeChip('visio', Icons.videocam, 'Visio'),
              _typeChip('phone', Icons.call, 'Téléphone'),
              _typeChip('onsite', Icons.location_on, 'Présentiel'),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              decoration: InputDecoration(
                labelText: _detailLabel,
                prefixIcon: Icon(_type == 'visio'
                    ? Icons.link
                    : _type == 'phone' ? Icons.call : Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Durée', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final d in [30, 45, 60, 90]) _durationChip(d),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message au candidat (optionnel)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: const Text('Confirmer le rendez-vous'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 6),
            const Text('Le candidat recevra la proposition dans son espace et par email.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]),
      ),
    );
  }

  Widget _pickerTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.glass(),
          border: Border.all(color: AppTheme.glassBorder()),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: AppTheme.violetLight),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
        ]),
      ),
    );
  }

  Widget _typeChip(String value, IconData icon, String label) {
    final sel = _type == value;
    return ChoiceChip(
      selected: sel,
      onSelected: (_) => setState(() => _type = value),
      avatar: Icon(icon, size: 17, color: sel ? Colors.white : AppTheme.muted),
      label: Text(label),
      selectedColor: AppTheme.primary,
      labelStyle: TextStyle(color: sel ? Colors.white : AppTheme.muted),
      backgroundColor: AppTheme.glass(),
    );
  }

  Widget _durationChip(int d) {
    final sel = _duration == d;
    return ChoiceChip(
      selected: sel,
      onSelected: (_) => setState(() => _duration = d),
      label: Text('$d min'),
      selectedColor: AppTheme.primary,
      labelStyle: TextStyle(color: sel ? Colors.white : AppTheme.muted),
      backgroundColor: AppTheme.glass(),
    );
  }
}
