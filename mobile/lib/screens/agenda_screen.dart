import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'schedule_interview.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});
  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final Map<DateTime, List<Interview>> _events = {};
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _key(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<AppState>().api.recruiterInterviews();
      _events.clear();
      for (final iv in list) {
        final w = iv.when;
        if (w == null) continue;
        _events.putIfAbsent(_key(w), () => []).add(iv);
      }
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Interview> _forDay(DateTime d) {
    final l = List<Interview>.from(_events[_key(d)] ?? const []);
    l.sort((a, b) => (a.when ?? DateTime(0)).compareTo(b.when ?? DateTime(0)));
    return l;
  }

  Future<void> _newAppointment() async {
    final candidate = await pickCandidate(context);
    if (candidate == null || !mounted) return;
    final ok = await showScheduleSheet(context, candidate);
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final dayList = _forDay(_selected);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newAppointment,
        icon: const Icon(Icons.add),
        label: const Text('Rendez-vous'),
      ),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Agenda', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Vos entretiens planifiés avec les candidats.',
                style: TextStyle(color: AppTheme.muted)),
          ),
        ),
        const SizedBox(height: 8),
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(6),
          child: TableCalendar<Interview>(
            locale: 'fr_FR',
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(_selected, d),
            eventLoader: _forDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableGestures: AvailableGestures.horizontalSwipe,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              leftChevronIcon: Icon(Icons.chevron_left, color: AppTheme.muted),
              rightChevronIcon: Icon(Icons.chevron_right, color: AppTheme.muted),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: AppTheme.muted2, fontSize: 12),
              weekendStyle: TextStyle(color: AppTheme.muted2, fontSize: 12),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: const TextStyle(color: Colors.white),
              weekendTextStyle: const TextStyle(color: Colors.white70),
              todayDecoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.30),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
              ),
              markerDecoration: const BoxDecoration(color: AppTheme.violetLight, shape: BoxShape.circle),
              markersMaxCount: 3,
            ),
            onDaySelected: (sel, foc) => setState(() {
              _selected = sel;
              _focused = foc;
            }),
            onPageChanged: (foc) => _focused = foc,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? LoadErrorView(onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: dayList.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 40),
                              Center(
                                child: Text(
                                  'Aucun rendez-vous le ${DateFormat("d MMMM", 'fr_FR').format(_selected)}.',
                                  style: const TextStyle(color: AppTheme.muted),
                                ),
                              ),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                              itemCount: dayList.length,
                              itemBuilder: (_, i) => _InterviewTile(dayList[i]),
                            ),
                    ),
        ),
      ]),
    );
  }
}

class _InterviewTile extends StatelessWidget {
  final Interview iv;
  const _InterviewTile(this.iv);

  ({IconData icon, String label}) get _meta => switch (iv.meetingType) {
        'phone' => (icon: Icons.call, label: 'Téléphone'),
        'onsite' => (icon: Icons.location_on, label: 'Présentiel'),
        _ => (icon: Icons.videocam, label: 'Visio'),
      };

  Color get _statusColor => switch (iv.status) {
        'accepted' => AppTheme.green,
        'declined' => AppTheme.red,
        _ => AppTheme.amber,
      };
  String get _statusLabel => switch (iv.status) {
        'accepted' => 'Accepté',
        'declined' => 'Refusé',
        _ => 'En attente',
      };

  @override
  Widget build(BuildContext context) {
    final w = iv.when;
    final time = w != null ? DateFormat('HH:mm').format(w) : '--:--';
    final detail = iv.link.isNotEmpty ? iv.link : iv.location;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Column(children: [
            Text(time, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.violetLight)),
            Text('${iv.durationMin}min', style: const TextStyle(fontSize: 11, color: AppTheme.muted2)),
          ]),
          const SizedBox(width: 14),
          Container(width: 1, height: 34, color: AppTheme.glassBorder()),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(iv.candidateName.isEmpty ? 'Candidat' : iv.candidateName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Row(children: [
                Icon(_meta.icon, size: 13, color: AppTheme.muted),
                const SizedBox(width: 4),
                Text(_meta.label, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
              ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
            child: Text(_statusLabel,
                style: TextStyle(color: _statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (iv.message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(iv.message, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
        ],
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openDetail(context, detail),
              icon: Icon(_meta.icon, size: 16),
              label: Text(
                iv.meetingType == 'visio'
                    ? 'Rejoindre la visio'
                    : iv.meetingType == 'phone'
                        ? 'Appeler $detail'
                        : 'Voir le lieu',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _openDetail(BuildContext context, String detail) async {
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

/// Modal picker: load talents (ranked by match) and let the recruiter choose one.
Future<Candidate?> pickCandidate(BuildContext context) {
  return showModalBottomSheet<Candidate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.sheet,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => const _CandidatePicker(),
  );
}

class _CandidatePicker extends StatefulWidget {
  const _CandidatePicker();
  @override
  State<_CandidatePicker> createState() => _CandidatePickerState();
}

class _CandidatePickerState extends State<_CandidatePicker> {
  final _search = TextEditingController();
  List<Candidate> _list = [];
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
      _list = await context.read<AppState>().api.talents(query: _search.text.trim());
      _failed = false;
    } catch (_) {
      _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          const Text('Choisir un candidat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Compétences (python, design…)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                    ? const Center(child: Text('Accès à la base talents requis', style: TextStyle(color: AppTheme.muted)))
                    : _list.isEmpty
                        ? const Center(child: Text('Aucun candidat'))
                        : ListView.separated(
                            itemCount: _list.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final c = _list[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                                  child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: AppTheme.violetLight, fontWeight: FontWeight.bold)),
                                ),
                                title: Text(c.name),
                                subtitle: Text([c.title, c.location].where((s) => s.isNotEmpty).join(' · '),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: MatchGauge(score: c.match.score),
                                onTap: () => Navigator.pop(context, c),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}
