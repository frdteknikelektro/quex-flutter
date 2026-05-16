import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quex/generated/l10n/app_localizations.dart';

import '../../app/theme.dart';
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
  static const _duckAsset = 'assets/images/splash/duck_mascot.png';
  static const _skyAccentsLeftAsset = 'assets/images/splash/sky_accents-left.png';
  static const _skyAccentsRightAsset = 'assets/images/splash/sky_accents-right.png';
  static const _skyAccentsLeftDarkAsset = 'assets/images/splash/sky_accents-left-dark.png';
  static const _skyAccentsRightDarkAsset = 'assets/images/splash/sky_accents-right-dark.png';
  static const _foregroundFloraLeftAsset =
      'assets/images/splash/foreground_flora-left.png';
  static const _foregroundFloraRightAsset =
      'assets/images/splash/foreground_flora-right.png';
  static const _foregroundFloraLeftDarkAsset =
      'assets/images/splash/foreground_flora-left-dark.png';
  static const _foregroundFloraRightDarkAsset =
      'assets/images/splash/foreground_flora-right-dark.png';

  late final AnimationController _bounceController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _bounceAnimation;

  ProviderSubscription<ModelDownloadState>? _downloadStateSubscription;

  @override
  void initState() {
    super.initState();

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _bounceAnimation = Tween<Offset>(
      begin: const Offset(0, -0.16),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _bounceController.forward();
    });
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _fadeController.forward();
    });

    _autoStartDownloadIfNeeded();

    _downloadStateSubscription = ref.listenManual<ModelDownloadState>(
      modelDownloadProvider,
      (previous, next) {
        debugPrint(
            '[Splash] State changed: ${previous?.status} -> ${next.status}');
        if (next.isCompleted && previous?.isCompleted != true) {
          debugPrint(
              '[Splash] Download completed, navigating to profile selection');
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (mounted) {
              context.go(Routes.profileSelection);
            }
          });
        }
      },
    );
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadProvider);
    final theme = Theme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    debugPrint('[Splash] Build: state=${downloadState.status}');

    return Scaffold(
      backgroundColor: scheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final isTablet = size.width >= 840;
          final isLandscape = size.width > size.height;
          final sidePadding = isTablet ? 48.0 : 24.0;
          final contentWidth = math.min(
              size.width - (sidePadding * 2), isTablet ? 420.0 : 300.0);
          final topInset = MediaQuery.paddingOf(context).top;
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          final duckSize = _duckSize(size, isTablet, isLandscape);
          final floraHeight = size.height * 0.6;
          final statusBottom = _statusBottom(size, bottomInset, isLandscape);
          final duckBottom = _duckBottom(size, isTablet, isLandscape);
          final statusWidth = downloadState.isActive
              ? math.min(size.width - (sidePadding * 2), 360.0)
              : contentWidth;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: theme.brightness == Brightness.dark
                          ? [
                              const Color(0xFF0D1B2A), // Midnight blue
                              const Color(0xFF1B263B), // Dark blue
                              const Color(0xFF2C3E50), // Slate blue
                            ]
                          : [
                              const Color(0xFFEAF8FF), // Light blue
                              const Color(0xFFF9FDFF), // Very light blue
                              const Color(0xFFFFFBF4), // Warm yellow
                            ],
                      stops: const [0.0, 0.56, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _SplashLandscapePainter(isDark: theme.brightness == Brightness.dark),
                ),
              ),
              // Left half of sky accents
              Positioned(
                left: 0,
                top: math.max(0.0, topInset - Sp.xs),
                child: IgnorePointer(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: size.width / 2,
                      maxHeight: size.height * 0.3, // Limit to 30% of screen height
                    ),
                    child: Opacity(
                      opacity: 0.86,
                      child: Image.asset(
                        theme.brightness == Brightness.dark
                            ? _skyAccentsLeftDarkAsset
                            : _skyAccentsLeftAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
              // Right half of sky accents
              Positioned(
                right: 0,
                top: math.max(0.0, topInset - Sp.xs),
                child: IgnorePointer(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: size.width / 2,
                      maxHeight:
                          size.height * 0.3, // Limit to 30% of screen height
                    ),
                    child: Opacity(
                      opacity: 0.86,
                      child: Image.asset(
                        theme.brightness == Brightness.dark
                            ? _skyAccentsRightDarkAsset
                            : _skyAccentsRightAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
              // Left half of flora
              Positioned(
                left: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: size.width / 2,
                      maxHeight: floraHeight,
                    ),
                    child: Image.asset(
                      theme.brightness == Brightness.dark
                          ? _foregroundFloraLeftDarkAsset
                          : _foregroundFloraLeftAsset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              // Right half of flora
              Positioned(
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: size.width / 2,
                      maxHeight: floraHeight,
                    ),
                    child: Image.asset(
                      theme.brightness == Brightness.dark
                          ? _foregroundFloraRightDarkAsset
                          : _foregroundFloraRightAsset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (size.width - duckSize) / 2,
                bottom: duckBottom,
                width: duckSize,
                child: GestureDetector(
                  onTap: () => _bounceController.forward(from: 0),
                  child: SlideTransition(
                    position: _bounceAnimation,
                    child: Image.asset(
                      _duckAsset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: sidePadding),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentWidth),
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: _brandTopPadding(size, isTablet, isLandscape),
                        ),
                        child: GestureDetector(
                          onTap: () => _bounceController.forward(from: 0),
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _QuexWordmark(text: l10n.appTitle),
                                const SizedBox(height: Sp.lg),
                                Text(
                                  l10n.appSubtitle,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: Sp.md * 0.75),
                                Text(
                                  l10n.appTagline,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    height: 1.05,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: statusBottom,
                left: sidePadding,
                right: sidePadding,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: statusWidth),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: Tween<double>(begin: 0.96, end: 1).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _buildStateIndicator(
                        downloadState,
                        scheme,
                        statusWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _brandTopPadding(Size size, bool isTablet, bool isLandscape) {
    return (size.height * 0.225).toDouble();
  }

  double _duckSize(Size size, bool isTablet, bool isLandscape) {
    if (isLandscape) return math.min(size.height * 0.42, isTablet ? 280 : 200);
    if (isTablet) return math.min(size.width * 0.28, 300);
    return math.min(size.width * 0.45, size.height < 700 ? 190 : 220);
  }

  double _duckBottom(Size size, bool isTablet, bool isLandscape) {
    if (isLandscape) return math.max(96, size.height * 0.16);
    if (isTablet) return math.max(192, size.height * 0.22);
    return math.max(size.height * 0.235, size.height < 700 ? 156 : 262);
  }

  double _statusBottom(Size size, double bottomInset, bool isLandscape) {
    if (isLandscape) return math.max(bottomInset + 24, size.height * 0.09);
    return math.max(bottomInset + 84, size.height * 0.13);
  }

  Widget _buildStateIndicator(
    ModelDownloadState downloadState,
    ColorScheme scheme,
    double maxWidth,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (downloadState.isCompleted) {
      final modelName =
          'Gemma 4 ${(downloadState.modelVariant ?? 'e4b') == 'e2b' ? 'E2B' : 'E4B'}';
      final completedWidth = math.min(maxWidth, 280.0);
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: math.min(completedWidth, 220.0),
          maxWidth: completedWidth,
        ),
        child: _StatusPanel(
          key: const ValueKey('ready'),
          child: Text(
            l10n.poweredByDownloadedModel(modelName),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    if (downloadState.hasFailed) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 216, maxWidth: 240),
        child: _StatusPanel(
          key: const ValueKey('error'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.oopsSomethingWentWrong,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Sp.sm + Sp.xs / 2),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(modelDownloadProvider.notifier).retry(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.tryAgain),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Sp.md,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: Br.sm),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final percent = (downloadState.progress.clamp(0.0, 1.0) * 100).round();
    final variant = downloadState.modelVariant ?? 'e4b';
    final variantName = variant == 'e2b' ? 'E2B' : 'E4B';
    final size = variant == 'e2b' ? '2.58 GB' : '3.65 GB';
    final downloadingWidth = math.min(maxWidth, 360.0);

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: math.min(downloadingWidth, 320.0),
        maxWidth: downloadingWidth,
      ),
      child: _StatusPanel(
        key: const ValueKey('downloading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
              child: ClipRRect(
                borderRadius: Br.full,
                child: LinearProgressIndicator(
                  minHeight: Sp.sm - 1,
                  value: downloadState.progress.clamp(0.0, 1.0),
                  backgroundColor: scheme.primaryContainer,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(height: Sp.sm + Sp.xs / 2),
            Text(
              l10n.downloadingBrain(percent),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
            ),
            const SizedBox(height: Sp.xs / 2),
            Text(
              l10n.downloadingModelVariant(variantName, size),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuexWordmark extends StatelessWidget {
  final String text;

  const _QuexWordmark({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.displayLarge?.copyWith(
      height: 0.88,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle?.copyWith(
            color: QuexTheme.primaryBlue,
            shadows: [
              Shadow(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.3)
                    : const Color(0x330D5DC3),
                blurRadius: 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final Widget child;

  const _StatusPanel({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: Br.full,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1E4A90E2),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Sp.lg - Sp.sm,
          vertical: Sp.sm + Sp.xs + 2,
        ),
        child: child,
      ),
    );
  }
}

class _SplashLandscapePainter extends CustomPainter {
  final bool isDark;

  const _SplashLandscapePainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Cloud colors
    final cloudColor = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.5);
    final cloudColorHighlight = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.62);

    final cloudPaint = Paint()..color = cloudColor;
    _drawCloud(
      canvas,
      Offset(size.width * 0.02, size.height * 0.34),
      size.width * 0.22,
      cloudPaint..color = cloudColorHighlight,
    );

    // Hill colors - day vs night
    final farHillColor =
        isDark ? const Color(0xFF2D4A2B) : const Color(0xFFC7ED62);
    final nearHillColor =
        isDark ? const Color(0xFF1F3A1F) : const Color(0xFF9BDD32);
    final foregroundColor =
        isDark ? const Color(0xFF152F15) : const Color(0xFF79C92D);

    final farHill = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.44,
        size.height * 0.58,
        size.width,
        size.height * 0.71,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      farHill,
      Paint()..color = farHillColor,
    );

    final nearHill = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.8)
      ..quadraticBezierTo(
        size.width * 0.32,
        size.height * 0.68,
        size.width * 0.64,
        size.height * 0.76,
      )
      ..quadraticBezierTo(
        size.width * 0.84,
        size.height * 0.82,
        size.width,
        size.height * 0.75,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      nearHill,
      Paint()..color = nearHillColor,
    );

    final foreground = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.9)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.82,
        size.width,
        size.height * 0.88,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      foreground,
      Paint()..color = foregroundColor,
    );
  }

  void _drawCloud(Canvas canvas, Offset center, double width, Paint paint) {
    final height = width * 0.45;
    final path = Path()
      ..addOval(Rect.fromCenter(
        center: center.translate(-width * 0.25, height * 0.08),
        width: width * 0.46,
        height: height * 0.58,
      ))
      ..addOval(Rect.fromCenter(
        center: center.translate(-width * 0.02, -height * 0.1),
        width: width * 0.54,
        height: height * 0.74,
      ))
      ..addOval(Rect.fromCenter(
        center: center.translate(width * 0.28, height * 0.08),
        width: width * 0.5,
        height: height * 0.6,
      ))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, height * 0.22),
          width: width,
          height: height * 0.48,
        ),
        Radius.circular(height * 0.24),
      ));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SplashLandscapePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
