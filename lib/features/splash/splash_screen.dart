import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quex/generated/l10n/app_localizations.dart';

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
  static const _skyAccentsAsset = 'assets/images/splash/sky_accents.png';
  static const _foregroundFloraAsset =
      'assets/images/splash/foreground_flora.png';

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
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    debugPrint('[Splash] Build: state=${downloadState.status}');

    return Scaffold(
      backgroundColor: const Color(0xFFEAF8FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final isTablet = size.width >= 840;
          final isLandscape = size.width > size.height;
          final sidePadding = isTablet ? 48.0 : 24.0;
          final contentWidth = math.min(
              size.width - (sidePadding * 2), isTablet ? 520.0 : 360.0);
          final topInset = MediaQuery.paddingOf(context).top;
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          final duckSize = _duckSize(size, isTablet, isLandscape);
          final floraWidth = math.min(size.width * (isTablet ? 1.12 : 1.28),
              isLandscape ? 960.0 : 760.0);
          final skyWidth =
              math.min(size.width * (isTablet ? 0.88 : 1.14), 760.0);
          final statusBottom = _statusBottom(size, bottomInset, isLandscape);
          final duckBottom = _duckBottom(size, isTablet, isLandscape);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFEAF8FF),
                        Color(0xFFF9FDFF),
                        Color(0xFFFFFBF4),
                      ],
                      stops: [0.0, 0.56, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _SplashLandscapePainter(),
                ),
              ),
              _PositionedAccentLayer(
                asset: _skyAccentsAsset,
                width: skyWidth,
                top: math.max(0.0, topInset - 2.0),
                left: isTablet ? (size.width - skyWidth) / 2 : -28.0,
                opacity: 0.78,
              ),
              Positioned(
                left: (size.width - floraWidth) / 2,
                bottom: -18,
                width: floraWidth,
                child: IgnorePointer(
                  child: Image.asset(
                    _foregroundFloraAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
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
                                const SizedBox(height: 12),
                                Text(
                                  l10n.appSubtitle,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.appTagline,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF356078),
                                        fontWeight: FontWeight.w700,
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
                    constraints: BoxConstraints(maxWidth: contentWidth),
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
                      child: _buildStateIndicator(downloadState, scheme),
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
    if (isLandscape) return isTablet ? 30 : 18;
    if (isTablet) return 70;
    return size.height < 700 ? 44 : 72;
  }

  double _duckSize(Size size, bool isTablet, bool isLandscape) {
    if (isLandscape) return math.min(size.height * 0.48, isTablet ? 300 : 220);
    if (isTablet) return math.min(size.width * 0.34, 330);
    return math.min(size.width * 0.58, size.height < 700 ? 200 : 260);
  }

  double _duckBottom(Size size, bool isTablet, bool isLandscape) {
    if (isLandscape) return math.max(104, size.height * 0.18);
    if (isTablet) return math.max(210, size.height * 0.24);
    return math.max(size.height * 0.27, size.height < 700 ? 168 : 290);
  }

  double _statusBottom(Size size, double bottomInset, bool isLandscape) {
    if (isLandscape) return math.max(bottomInset + 28, size.height * 0.1);
    return math.max(bottomInset + 96, size.height * 0.14);
  }

  Widget _buildStateIndicator(
    ModelDownloadState downloadState,
    ColorScheme scheme,
  ) {
    final l10n = AppLocalizations.of(context)!;

    if (downloadState.isCompleted) {
      return _StatusPanel(
        key: const ValueKey('ready'),
        child: Text(
          l10n.ready,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w900,
              ),
        ),
      );
    }

    if (downloadState.hasFailed) {
      return _StatusPanel(
        key: const ValueKey('error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.oopsSomethingWentWrong,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF31556B),
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => ref.read(modelDownloadProvider.notifier).retry(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.tryAgain),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                minimumSize: const Size(0, 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final percent = (downloadState.progress.clamp(0.0, 1.0) * 100).round();
    final variant = downloadState.modelVariant ?? 'e4b';
    final variantName = variant == 'e2b' ? 'E2B' : 'E4B';
    final size = variant == 'e2b' ? '2.58 GB' : '3.65 GB';

    return _StatusPanel(
      key: const ValueKey('downloading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: downloadState.progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFD8EDFF),
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.downloadingBrain(percent),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF31556B),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            l10n.downloadingModelVariant(variantName, size),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5F7C8F),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _QuexWordmark extends StatelessWidget {
  final String text;

  const _QuexWordmark({required this.text});

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).width >= 840;
    final fontSize = isTablet ? 86.0 : 66.0;
    final baseStyle = Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: fontSize,
          height: 0.9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -fontSize * 0.2,
          top: -fontSize * 0.2,
          child: Transform.rotate(
            angle: -0.2,
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Color(0xFFFFC83D),
              size: 28,
            ),
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle?.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isTablet ? 15 : 12
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
            shadows: const [
              Shadow(
                color: Color(0x3F1E6BCB),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle?.copyWith(
            color: const Color(0xFF2378F2),
            shadows: const [
              Shadow(
                color: Color(0x330D5DC3),
                blurRadius: 2,
                offset: Offset(0, 2),
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
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.84),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x242172C7),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: child,
      ),
    );
  }
}

class _PositionedAccentLayer extends StatelessWidget {
  final String asset;
  final double width;
  final double top;
  final double opacity;
  final double? left;

  const _PositionedAccentLayer({
    required this.asset,
    required this.width,
    required this.top,
    required this.opacity,
    this.left,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      width: width,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

class _SplashLandscapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    _drawCloud(
      canvas,
      Offset(size.width * 0.02, size.height * 0.34),
      size.width * 0.22,
      cloudPaint..color = Colors.white.withValues(alpha: 0.62),
    );

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
      Paint()..color = const Color(0xFFC7ED62),
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
      Paint()..color = const Color(0xFF9BDD32),
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
      Paint()..color = const Color(0xFF79C92D),
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
