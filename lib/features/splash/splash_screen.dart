import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/ai/model_download_notifier.dart';
import '../../widgets/quex_ui.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _autoStartDownloadIfNeeded();
  }

  void _autoStartDownloadIfNeeded() {
    final downloadState = ref.read(modelDownloadProvider);
    if (!downloadState.isCompleted && !downloadState.isActive) {
      // Auto-start download if model is not ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(modelDownloadProvider.notifier).start();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadProvider);
    final scheme = Theme.of(context).colorScheme;

    // Listen for download completion and auto-redirect after 2 seconds
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: Sp.edge,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: QuexPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App title
                    Text(
                      'Quex',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                    ),
                    const SizedBox(height: Sp.lg),
                    // Download status
                    if (downloadState.isCompleted) ...[
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: Sp.md),
                      Text(
                        'Model ready',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: Sp.sm),
                      Text(
                        'Setting up your study experience…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ] else if (downloadState.isActive) ...[
                      Icon(
                        Icons.downloading_outlined,
                        size: 64,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: Sp.md),
                      Text(
                        'Downloading model…',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: Sp.xl),
                      // Progress bar
                      ClipRRect(
                        borderRadius: Br.sm,
                        child: LinearProgressIndicator(
                          value: downloadState.progress,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: scheme.primary,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: Sp.sm),
                      Text(
                        '${(downloadState.progress * 100).round()}%',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: Sp.xs),
                      Text(
                        'of ~6.6 GB',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ] else if (downloadState.hasFailed) ...[
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: scheme.error,
                      ),
                      const SizedBox(height: Sp.md),
                      Text(
                        'Download failed',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.error,
                            ),
                      ),
                      const SizedBox(height: Sp.sm),
                      Text(
                        downloadState.error ?? 'Unknown error',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Sp.lg),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(modelDownloadProvider.notifier).retry(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
