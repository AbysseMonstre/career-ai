import 'package:flutter/material.dart';
import 'talents_screen.dart';
import 'post_job_screen.dart';
import 'recruiter_dashboard_screen.dart';

class RecruiterHome extends StatefulWidget {
  const RecruiterHome({super.key});
  @override
  State<RecruiterHome> createState() => _RecruiterHomeState();
}

class _RecruiterHomeState extends State<RecruiterHome> {
  int _index = 0;
  final _pages = const [
    TalentsScreen(),
    PostJobScreen(),
    RecruiterDashboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Talents'),
          NavigationDestination(icon: Icon(Icons.add_box_outlined), selectedIcon: Icon(Icons.add_box), label: 'Publier'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Tableau'),
        ],
      ),
    );
  }
}
