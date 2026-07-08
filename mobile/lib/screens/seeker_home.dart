import 'package:flutter/material.dart';
import '../widgets/common.dart';
import 'jobs_screen.dart';
import 'applications_screen.dart';
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
  final _pages = const [
    JobsScreen(),
    ApplicationsScreen(),
    InsightsScreen(),
    SeekerDashboardScreen(),
    CvScreen(),
  ];

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
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work), label: 'Offres'),
          NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Candidatures'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Analyse'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Tableau'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'CV'),
        ],
      ),
    );
  }
}
