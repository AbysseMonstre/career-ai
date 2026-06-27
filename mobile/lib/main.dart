import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/seeker_home.dart';
import 'screens/recruiter_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On web, read the backend URL from config.json so it can be changed after
  // deployment (no rebuild). Falls back to the compiled default otherwise.
  String? apiBase;
  if (kIsWeb) {
    try {
      final r = await http.get(Uri.parse('config.json'));
      if (r.statusCode == 200) {
        final u = (jsonDecode(r.body) as Map)['apiBaseUrl'];
        if (u is String && u.isNotEmpty) apiBase = u;
      }
    } catch (_) {/* use default */}
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(apiBaseUrl: apiBase)..bootstrap(),
      child: const CareerAIApp(),
    ),
  );
}

class CareerAIApp extends StatelessWidget {
  const CareerAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Career AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      builder: (context, child) => AuroraBackground(child: child ?? const SizedBox()),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.loading) return const _Splash();
    if (!state.onboarded) return const OnboardingScreen();
    if (!state.isLoggedIn) return const AuthScreen();
    return state.user!.isRecruiter ? const RecruiterHome() : const SeekerHome();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: AppTheme.violet.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 4),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 46),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Career AI',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Le matching intelligent', style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 28),
          const SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.violetLight),
          ),
        ]),
      ),
    );
  }
}
