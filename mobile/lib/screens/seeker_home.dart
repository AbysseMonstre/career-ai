import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'jobs_screen.dart';
import 'applications_screen.dart';
import 'my_interviews_screen.dart';
import 'insights_screen.dart';
import 'seeker_dashboard_screen.dart';
import 'cv_screen.dart';

class SeekerHome extends StatefulWidget {
  const SeekerHome({super.key});
  @override
  State<SeekerHome> createState() => _SeekerHomeState();
}

class _SeekerHomeState extends State<SeekerHome> {
  int _index = 0;
  int _pendingInterviews = 0;
  final _pages = const [
    JobsScreen(),
    ApplicationsScreen(),
    MyInterviewsScreen(),
    InsightsScreen(),
    SeekerDashboardScreen(),
    CvScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _refreshBadge();
  }

  Future<void> _refreshBadge() async {
    try {
      final ivs = await context.read<AppState>().api.myInterviews();
      if (mounted) {
        setState(() => _pendingInterviews = ivs.where((i) => i.status == 'proposed').length);
      }
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const CareerTopBar(),
          Expanded(child: _pages[_index]),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 2) _refreshBadge(); // opened Entretiens -> refresh count
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work), label: 'Offres'),
          const NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Candidatures'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _pendingInterviews > 0,
              label: Text('$_pendingInterviews'),
              child: const Icon(Icons.event_outlined),
            ),
            selectedIcon: const Icon(Icons.event),
            label: 'Entretiens',
          ),
          const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Analyse'),
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Tableau'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'CV'),
        ],
      ),
    );
  }
}
