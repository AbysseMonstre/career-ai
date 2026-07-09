import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String token;
  const ResetPasswordScreen({super.key, required this.token});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  Future<void> _submit() async {
    final p = _pw.text.trim();
    if (p.length < 8) {
      showError(context, 'Mot de passe trop court (min 8 caractères)');
      return;
    }
    if (p != _pw2.text.trim()) {
      showError(context, 'Les mots de passe ne correspondent pas');
      return;
    }
    setState(() => _busy = true);
    try {
      final state = context.read<AppState>();
      await state.api.resetPassword(widget.token, p);
      if (mounted) {
        showOk(context, 'Mot de passe réinitialisé — connectez-vous.');
        state.clearReset(); // returns to the auth screen
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.lock_reset, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 18),
              const Text('Nouveau mot de passe',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Choisissez un nouveau mot de passe pour votre compte.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 22),
              TextField(
                controller: _pw,
                obscureText: _hide,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw2,
                obscureText: _hide,
                decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Réinitialiser'),
              ),
              TextButton(
                onPressed: () => context.read<AppState>().clearReset(),
                child: const Text('Annuler', style: TextStyle(color: AppTheme.muted)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
