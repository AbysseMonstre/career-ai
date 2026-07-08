import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

/// 8-axis radar ("octagon") for the training breakdown.
class RadarOctagon extends StatelessWidget {
  final Map<String, dynamic> axes;
  const RadarOctagon(this.axes, {super.key});

  @override
  Widget build(BuildContext context) {
    final keys = axes.keys.toList();
    if (keys.length < 3) return const SizedBox.shrink();
    return SizedBox(
      height: 250,
      child: RadarChart(RadarChartData(
        radarShape: RadarShape.polygon,
        dataSets: [
          RadarDataSet(
            dataEntries: keys.map((k) => RadarEntry(value: (axes[k] as num).toDouble())).toList(),
            borderColor: AppTheme.violetLight,
            fillColor: AppTheme.violet.withValues(alpha: 0.35),
            borderWidth: 2,
            entryRadius: 2.5,
          ),
        ],
        getTitle: (i, angle) => RadarChartTitle(text: keys[i % keys.length]),
        titlePositionPercentageOffset: 0.14,
        titleTextStyle: const TextStyle(color: AppTheme.muted, fontSize: 9),
        tickCount: 4,
        ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 1),
        radarBorderData: BorderSide(color: AppTheme.glassBorder()),
        gridBorderData: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        tickBorderData: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        radarBackgroundColor: Colors.transparent,
      )),
    );
  }
}

/// Always-visible logout control. `labeled` shows a full red button; otherwise
/// a compact icon. Works from anywhere, even a screen that failed to load.
class LogoutButton extends StatelessWidget {
  final bool labeled;
  const LogoutButton({super.key, this.labeled = false});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.sheet,
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous pourrez vous reconnecter avec votre email et mot de passe.',
            style: TextStyle(color: AppTheme.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<AppState>().logout();
  }

  @override
  Widget build(BuildContext context) {
    if (labeled) {
      return OutlinedButton.icon(
        onPressed: () => _logout(context),
        icon: const Icon(Icons.logout, size: 18, color: AppTheme.red),
        label: const Text('Se déconnecter', style: TextStyle(color: AppTheme.red)),
        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.red)),
      );
    }
    return IconButton(
      onPressed: () => _logout(context),
      icon: const Icon(Icons.logout),
      color: AppTheme.red,
      tooltip: 'Se déconnecter',
    );
  }
}

/// Fallback shown when a screen can't reach the server — keeps logout reachable.
class LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;
  const LoadErrorView({super.key, required this.onRetry,
      this.message = 'Connexion au serveur impossible (le serveur gratuit peut mettre ~30 s à se réveiller).'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: AppTheme.muted2),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          const SizedBox(height: 8),
          const LogoutButton(labeled: true),
        ]),
      ),
    );
  }
}

/// Account actions: logout + RGPD account deletion (right to erasure).
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      color: AppTheme.sheet,
      onSelected: (v) async {
        final state = context.read<AppState>();
        if (v == 'logout') {
          await state.logout();
        } else if (v == 'delete') {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.sheet,
              title: const Text('Supprimer mon compte ?'),
              content: const Text(
                'Toutes vos données personnelles (profil, CV, candidatures) seront '
                'définitivement effacées. Action irréversible (RGPD).',
                style: TextStyle(color: AppTheme.muted),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          );
          if (ok == true) {
            try {
              await state.deleteAccount();
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
        PopupMenuItem(value: 'delete', child: Text('Supprimer mon compte (RGPD)')),
      ],
    );
  }
}

/// Full-screen animated aurora: drifting/pulsing light blobs behind every screen.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _blob(double size, Color color, Alignment align) {
    return Align(
      alignment: align,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
            stops: const [0.0, 0.7],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.1),
          radius: 1.3,
          colors: [Color(0xFF4C2C83), AppTheme.bgTop, AppTheme.bgMid, AppTheme.bgBottom],
          stops: [0.0, 0.38, 0.7, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // animated light blobs (slow, looping, eased) — repaint isolated from child
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = _c.value * 2 * 3.14159;
                final dx1 = 0.6 * math.sin(t);
                final dy1 = 0.5 * math.cos(t * 0.8);
                final dx2 = 0.7 * math.cos(t * 0.7 + 1.0);
                final dy2 = 0.6 * math.sin(t * 0.9 + 0.5);
                final pulse = 0.5 + 0.5 * math.sin(t);
                return Stack(children: [
                  _blob(360, AppTheme.violet.withValues(alpha: 0.30 + 0.12 * pulse),
                      Alignment(-0.6 + dx1, -1.0 + dy1)),
                  _blob(340, AppTheme.cyan.withValues(alpha: 0.16 + 0.08 * (1 - pulse)),
                      Alignment(0.9 + dx2, 0.2 + dy2)),
                  _blob(300, AppTheme.indigo.withValues(alpha: 0.20),
                      Alignment(0.2 - dx1 * 0.6, 1.0 - dy2 * 0.5)),
                ]);
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Sweeping shimmer used for skeleton loading states.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final dx = rect.width * (_c.value * 2 - 1);
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: 0.04),
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.04),
            ],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlideGradient(dx),
          ).createShader(rect);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double dx;
  const _SlideGradient(this.dx);
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// A grey rounded placeholder block (use inside [Shimmer]).
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radius)),
      );
}

/// Fade + slide-up entrance for list items (staggered by index).
class FadeInItem extends StatelessWidget {
  final int index;
  final Widget child;
  const FadeInItem({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + (index.clamp(0, 8) * 60)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
      ),
      child: child,
    );
  }
}

/// Frosted translucent panel (visionOS-style).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppTheme.glass(),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.glassBorder()),
            boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.06), blurRadius: 1, offset: const Offset(0, 1))],
          ),
          child: child,
        ),
      ),
    );
    final outer = margin ?? const EdgeInsets.symmetric(vertical: 6);
    if (onTap == null) return Padding(padding: outer, child: card);
    return Padding(
      padding: outer,
      child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: card),
    );
  }
}

/// Circular match-score gauge (0-100).
class MatchGauge extends StatelessWidget {
  final int score;
  final double size;
  const MatchGauge({super.key, required this.score, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.scoreColor(score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: color.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text('$score%',
              style: TextStyle(
                  fontSize: size * 0.26, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// Wrapped list of skill chips, optionally highlighting matched ones.
class SkillChips extends StatelessWidget {
  final List<String> skills;
  final List<String> highlight;
  final Color? color;
  const SkillChips({super.key, required this.skills, this.highlight = const [], this.color});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: skills.map((s) {
        final hit = highlight.contains(s.toLowerCase());
        final c = color ?? (hit ? AppTheme.violetLight : AppTheme.muted);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.withValues(alpha: 0.25)),
          ),
          child: Text(s,
              style: TextStyle(fontSize: 12, color: c, fontWeight: hit ? FontWeight.w600 : FontWeight.w400)),
        );
      }).toList(),
    );
  }
}

/// Glass stat tile with an icon, big value and label.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const StatCard(
      {super.key, required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w300, color: Colors.white)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
        ],
      ),
    );
  }
}

Future<void> showError(BuildContext context, Object e) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.red),
  );
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppTheme.green),
  );
}
