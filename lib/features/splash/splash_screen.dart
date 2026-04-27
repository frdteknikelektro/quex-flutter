import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quex/generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/ai/chat_prompts.dart';
import '../../core/ai/download_state.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/gemma_service_host.dart';
import '../../core/ai/model_download_notifier.dart';
import '../../core/ai/model_manager.dart';
import '../../core/state/language_state.dart';

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

  late final GemmaServiceHost _gemmaHost;
  String? _greetingContent;
  StreamSubscription<String>? _greetingSubscription;
  bool _isWarmingUp = false;
  ProviderSubscription<ModelDownloadState>? _downloadStateSubscription;

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

    _gemmaHost = GemmaServiceHost();
    _autoStartDownloadIfNeeded();

    // Handle already-downloaded case (cold start with model present)
    final initialState = ref.read(modelDownloadProvider);
    if (initialState.isCompleted && !_isWarmingUp) {
      debugPrint('[Splash] Model already downloaded, triggering warm-up');
      _warmUpModel();
    }

    // Listen for download state changes to trigger warm-up
    _downloadStateSubscription = ref.listenManual<ModelDownloadState>(
      modelDownloadProvider,
      (previous, next) {
        debugPrint('[Splash] State changed: ${previous?.status} -> ${next.status}, isWarmingUp=$_isWarmingUp');
        if (next.isCompleted && previous?.isCompleted != true && !_isWarmingUp) {
          debugPrint('[Splash] Triggering warm-up from state listener');
          _warmUpModel();
        }
      },
    );
  }

  @override
  void dispose() {
    _greetingSubscription?.cancel();
    _greetingSubscription = null;
    _isWarmingUp = false;
    _downloadStateSubscription?.close();
    
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

  Future<void> _warmUpModel() async {
    // Prevent concurrent warm-ups (hot reload scenario)
    if (_isWarmingUp) {
      debugPrint('[Splash] Warm-up already in progress, skipping');
      return;
    }

    // Get current locale
    final locale = ref.watch(localeProvider).languageCode;

    debugPrint('[Splash] Starting warm-up...');
    _isWarmingUp = true;

    // Set state to warming
    debugPrint('[Splash] Setting state to warming');
    ref.read(modelDownloadProvider.notifier).state =
        const ModelDownloadState(status: DownloadStatus.warming, progress: 1.0);
    debugPrint('[Splash] State set to warming');

    try {
      // Activate model if not already active (handles app restart scenario)
      if (!FlutterGemma.hasActiveModel()) {
        debugPrint('[Splash] Model not active, activating...');
        await ModelManager.activateModel();
        debugPrint('[Splash] Model activated');
      }

      // Initialize model (idempotent - safe if already initialized)
      await _gemmaHost.ensureInitialized();
      debugPrint('[Splash] Model initialized');

      // Close any existing session (handles hard refresh scenario)
      if (_gemmaHost.service.hasActiveSession) {
        debugPrint('[Splash] Closing existing session before warm-up');
        await _gemmaHost.service.closeSession();
      }

      // Create session for warm-up with locale-aware system instruction
      await _gemmaHost.service.createSession(
        systemInstruction: ChatPrompts.getWarmUpSystemInstruction(locale),
        temperature: 0.7,
      );
      debugPrint('[Splash] Session created');

      // Stream greeting response with locale-aware greeting
      _greetingContent = '';
      final greeting = ChatPrompts.getWarmUpGreeting(locale);
      debugPrint('[Splash] Sending greeting: $greeting');

      _greetingSubscription = _gemmaHost.service
          .sendMessageStreaming(greeting)
          .listen(
        (token) {
          if (mounted) {
            setState(() {
              _greetingContent = (_greetingContent ?? '') + token;
            });
          }
        },
        onDone: () {
          debugPrint('[Splash] Warm-up stream completed');
          _greetingSubscription?.cancel();
          _greetingSubscription = null;
          _isWarmingUp = false;

          // Close warm-up session
          _gemmaHost.service.closeSession();
          debugPrint('[Splash] Session closed');

          // Reset download state to completed
          ref.read(modelDownloadProvider.notifier).state =
              const ModelDownloadState(status: DownloadStatus.completed, progress: 1.0);

          // Delay so user can read the greeting, then navigate
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                debugPrint('[Splash] Navigating to profile selection...');
                context.go(Routes.profileSelection);
                debugPrint('[Splash] Navigation called');
              } else {
                debugPrint('[Splash] Widget not mounted in postFrameCallback, skipping navigation');
              }
            });
          });
        },
        onError: (e) {
          debugPrint('[Splash] Warm-up stream error: $e');
          _greetingSubscription?.cancel();
          _greetingSubscription = null;
          _isWarmingUp = false;

          // Reset download state to completed since warm-up failed
          ref.read(modelDownloadProvider.notifier).state =
              const ModelDownloadState(status: DownloadStatus.completed, progress: 1.0);

          // Close session if error
          try {
            _gemmaHost.service.closeSession();
          } catch (_) {}

          // Delay so user can read, then proceed anyway on warm-up failure
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                debugPrint('[Splash] Proceeding to navigation after error');
                context.go(Routes.profileSelection);
              }
            });
          });
        },
        cancelOnError: false,
      );
    } catch (e, stack) {
      debugPrint('[Splash] Initialization failed: $e');
      debugPrint('[Splash] Stack trace: $stack');
      _isWarmingUp = false;

      // Reset download state to completed since warm-up failed
      ref.read(modelDownloadProvider.notifier).state =
          const ModelDownloadState(status: DownloadStatus.completed, progress: 1.0);

      // Close session if error
      try {
        _gemmaHost.service.closeSession();
      } catch (_) {}

      // Delay so user can read, then proceed anyway on initialization failure
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            debugPrint('[Splash] Proceeding to navigation after init error');
            context.go(Routes.profileSelection);
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadProvider);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    debugPrint('[Splash] Build: state=${downloadState.status}, isWarmingUp=$_isWarmingUp');

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
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.appTagline,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

    // Warming takes priority over completed (handles cold start case)
    if (_isWarmingUp || downloadState.isWarming) {
      return Center(
        key: const ValueKey('warming'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            if (_greetingContent != null && _greetingContent!.isNotEmpty)
              Text(
                _greetingContent!,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                l10n.warmingUp,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
          ],
        ),
      );
    }

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
