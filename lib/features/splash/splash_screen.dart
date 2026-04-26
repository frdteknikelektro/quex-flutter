import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quex/generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/ai/download_state.dart';
import '../../core/ai/model_download_notifier.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _bounceAnimation;

  @override
  void initState() {
    super.initState();

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Bounce from above (start at -100, end at 0)
    final tween = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    );
    final curved = CurvedAnimation(
      parent: _bounceController,
      curve: Curves.elasticOut,
    );
    _bounceAnimation = tween.animate(curved);

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Staggered animations
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _bounceController.forward();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _fadeController.forward();
    });

    _autoStartDownloadIfNeeded();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _autoStartDownloadIfNeeded() {
    final downloadState = ref.read(modelDownloadProvider);
    if (!downloadState.isCompleted && !downloadState.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(modelDownloadProvider.notifier).start();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadProvider);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    ref.listen(modelDownloadProvider, (previous, next) {
      if (next.isCompleted && previous?.isCompleted != true) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            context.go(Routes.profileSelection);
          }
        });
      }
    });

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // Center: Brand mark
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bouncing duck emoji
                  GestureDetector(
                    onTap: () {
                      _bounceController.forward(from: 0);
                    },
                    child: SlideTransition(
                      position: _bounceAnimation,
                      child: Text(
                        '🦆',
                        style: TextStyle(
                          fontSize: 72,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Fading text - also triggers duck bounce
                  GestureDetector(
                    onTap: () {
                      _bounceController.forward(from: 0);
                    },
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          Text(
                            l10n.appTitle,
                            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                  letterSpacing: -0.5,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.appSubtitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            l10n.appTagline,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          // Balance padding to center the content visually (duck is 72px)
                          const SizedBox(height: 88),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom: State indicator
            Positioned(
              bottom: 48,
              left: 32,
              right: 32,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                child: _buildStateIndicator(downloadState, scheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateIndicator(
    ModelDownloadState downloadState,
    ColorScheme scheme,
  ) {
    final l10n = AppLocalizations.of(context)!;

    if (downloadState.isCompleted) {
      return Center(
        key: const ValueKey('ready'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.ready,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
    }

    if (downloadState.hasFailed) {
      return Center(
        key: const ValueKey('error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.oopsSomethingWentWrong,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () =>
                  ref.read(modelDownloadProvider.notifier).retry(),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.tryAgain),
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    // Active downloading state
    final percent = (downloadState.progress * 100).round();
    return Center(
      key: const ValueKey('downloading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rounded pill progress bar
          Container(
            height: 8,
            width: 200,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: downloadState.progress,
                child: Container(
                  height: 8,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.downloadingBrain(percent),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
