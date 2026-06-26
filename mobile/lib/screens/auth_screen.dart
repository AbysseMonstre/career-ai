import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  String _role = 'seeker';
  bool _busy = false;
  bool _consent = false;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  Future<void> _submit() async {
    setState(() => _busy = true);
    final state = context.read<AppState>();
    try {
      if (_isLogin) {
        await state.login(_email.text.trim(), _password.text);
      } else {
        if (!_consent) {
          showError(context, "Veuillez accepter le traitement de vos données (RGPD)");
          return;
        }
        await state.register(_email.text.trim(), _password.text, _name.text.trim(), _role,
            consent: _consent);
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.accent]),
                      borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Text('Career AI',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              const Text('Le matching intelligent entre talents et entreprises',
                  style: TextStyle(color: Color(0xFF6B7280))),
              const SizedBox(height: 32),
              Text(_isLogin ? 'Connexion' : 'Créer un compte',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (!_isLogin) ...[
                _RoleSelector(role: _role, onChanged: (r) => setState(() => _role = r)),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom complet', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline)),
              ),
              if (!_isLogin) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _consent,
                      onChanged: (v) => setState(() => _consent = v ?? false),
                      side: const BorderSide(color: AppTheme.muted),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          "J'accepte le traitement de mes données pour la mise en relation (RGPD).",
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isLogin ? 'Se connecter' : "S'inscrire"),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? "Pas de compte ? S'inscrire" : 'Déjà un compte ? Se connecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final String role;
  final ValueChanged<String> onChanged;
  const _RoleSelector({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tile(String value, String label, IconData icon) {
      final selected = role == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: selected ? AppTheme.violet.withValues(alpha: 0.18) : AppTheme.glass(),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: selected ? AppTheme.violetLight : AppTheme.glassBorder(),
                  width: selected ? 1.5 : 1),
            ),
            child: Column(children: [
              Icon(icon, color: selected ? Colors.white : AppTheme.muted),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : AppTheme.muted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      tile('seeker', "Chercheur d'emploi", Icons.search),
      const SizedBox(width: 12),
      tile('recruiter', 'Recruteur', Icons.business_center),
    ]);
  }
}
