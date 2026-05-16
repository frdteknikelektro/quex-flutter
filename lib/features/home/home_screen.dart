import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/breakpoints.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../generated/l10n/app_localizations.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _headerController;
  late final AnimationController _contentController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    _contentController = AnimationController(
      duration: const Duration(milliseconds: 760),
      vsync: this,
    );

    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOutCubic,
    ));

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _headerController.forward();
    });
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _contentController.forward();
    });
  }

  @override
  void dispose() {
    _headerController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profilesAsync = ref.watch(profilesProvider);
    final activeProfileId = ref.watch(activeProfileProvider);

    return profilesAsync.when(
      data: (profiles) {
        if (profiles.isEmpty) {
          return const _HomeSurface(
            child: _NoProfileState(),
          );
        }

        final activeProfile = profiles.firstWhere(
          (profile) => profile.id == activeProfileId,
          orElse: () => profiles.first,
        );

        if (activeProfileId != activeProfile.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            ref.read(activeProfileProvider.notifier).state = activeProfile.id;
            await saveActiveProfileId(activeProfile.id!);
          });
        }

        final sessionsAsync =
            ref.watch(recentSessionsProvider(activeProfile.id!));

        return sessionsAsync.when(
          loading: () => _HomeDashboard(
            headerFade: _headerFade,
            headerSlide: _headerSlide,
            activeProfile: activeProfile,
            onRefresh: () async {
              ref.invalidate(profilesProvider);
              ref.invalidate(recentSessionsProvider(activeProfile.id!));
            },
            child: const _DashboardLoading(),
          ),
          error: (error, _) => _HomeDashboard(
            headerFade: _headerFade,
            headerSlide: _headerSlide,
            activeProfile: activeProfile,
            onRefresh: () async {
              ref.invalidate(profilesProvider);
              ref.invalidate(recentSessionsProvider(activeProfile.id!));
            },
            child: _DashboardMessage(
              icon: Icons.refresh_rounded,
              message: l10n.homeFailedToLoadSessions(error.toString()),
            ),
          ),
          data: (sessions) {
            return _HomeDashboard(
              headerFade: _headerFade,
              headerSlide: _headerSlide,
              activeProfile: activeProfile,
              onRefresh: () async {
                ref.invalidate(profilesProvider);
                ref.invalidate(recentSessionsProvider(activeProfile.id!));
              },
              child: sessions.isEmpty
                  ? _AnimatedDashboardEntry(
                      animation: _contentController,
                      delay: 0,
                      child: _EmptySessions(
                        onCreate: () => context.push(Routes.newSession),
                      ),
                    )
                  : _RecentSessionsSection(
                      animation: _contentController,
                      sessions: sessions,
                      onDeleteSession: (session) async {
                        await SessionDAO().delete(session.id!);
                      },
                      onSessionsChanged: () {
                        ref.invalidate(
                            recentSessionsProvider(activeProfile.id!));
                      },
                    ),
            );
          },
        );
      },
      loading: () => const _HomeSurface(
        child: _DashboardLoading(),
      ),
      error: (error, _) => _HomeSurface(
        child: _DashboardMessage(
          icon: Icons.error_outline_rounded,
          message: l10n.homeFailedToLoadProfiles(error.toString()),
        ),
      ),
    );
  }
}

class _HomeSurface extends StatelessWidget {
  final Widget child;

  const _HomeSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: child,
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  final Animation<double> headerFade;
  final Animation<Offset> headerSlide;
  final Profile activeProfile;
  final Future<void> Function() onRefresh;
  final Widget child;

  const _HomeDashboard({
    required this.headerFade,
    required this.headerSlide,
    required this.activeProfile,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return _HomeSurface(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= QuexBreakpoints.tablet;
            final sidePadding = wide ? Sp.xl + Sp.md : Sp.lg - Sp.xs;
            final contentWidth = wide ? 760.0 : double.infinity;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                sidePadding,
                Sp.lg,
                sidePadding,
                120 + bottomInset,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeTransition(
                        opacity: headerFade,
                        child: SlideTransition(
                          position: headerSlide,
                          child: _GreetingHeader(profile: activeProfile),
                        ),
                      ),
                      const SizedBox(height: Sp.xl),
                      child,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final Profile profile;

  const _GreetingHeader({required this.profile});

  String _getGreeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour < 12) return l10n.homeGoodMorning;
    if (hour < 18) return l10n.homeGoodAfternoon;
    return l10n.homeGoodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hai, ${profile.name}! 👋',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Sp.sm),
                Text(
                  '${_getGreeting(l10n)}!',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.md),
          _ProfileEmojiBadge(emoji: profile.emoji),
        ],
      ),
    );
  }
}

class _ProfileEmojiBadge extends StatelessWidget {
  final String emoji;

  const _ProfileEmojiBadge({required this.emoji});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: Br.full,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: theme.textTheme.headlineMedium,
      ),
    );
  }
}

class _RecentSessionsSection extends StatefulWidget {
  final Animation<double> animation;
  final List<Session> sessions;
  final Future<void> Function(Session session) onDeleteSession;
  final VoidCallback onSessionsChanged;

  const _RecentSessionsSection({
    required this.animation,
    required this.sessions,
    required this.onDeleteSession,
    required this.onSessionsChanged,
  });

  @override
  State<_RecentSessionsSection> createState() => _RecentSessionsSectionState();
}

class _RecentSessionsSectionState extends State<_RecentSessionsSection> {
  static const int _initialCount = 5;

  bool _isExpanded = false;
  final Set<int> _deletedIds = {};

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  void didUpdateWidget(covariant _RecentSessionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.sessions.map((session) => session.id!).toSet();
    _deletedIds.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final filteredSessions = widget.sessions
        .where((session) => !_deletedIds.contains(session.id))
        .toList();
    final displayCount = _isExpanded ? filteredSessions.length : _initialCount;
    final visibleSessions = filteredSessions.take(displayCount).toList();
    final hasMore = filteredSessions.length > _initialCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnimatedDashboardEntry(
          animation: widget.animation,
          delay: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeRecentSessions,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (hasMore)
                  TextButton(
                    onPressed: _toggleExpanded,
                    child: Text(
                      _isExpanded ? l10n.homeSeeLess : l10n.homeSeeMore,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sp.sm + Sp.xs),
        ...visibleSessions.asMap().entries.map((entry) {
          final session = entry.value;
          return _AnimatedDashboardEntry(
            animation: widget.animation,
            delay: (entry.key + 1) * 0.06,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Sp.md - Sp.xs),
              child: Dismissible(
                key: ValueKey('session-${session.id}'),
                direction: DismissDirection.endToStart,
                background: const SizedBox.shrink(),
                secondaryBackground: Container(
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: Br.lg,
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: Sp.lg),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: scheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) async {
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _deletedIds.add(session.id!));
                  try {
                    await widget.onDeleteSession(session);
                    widget.onSessionsChanged();
                  } catch (error) {
                    if (!mounted) return;
                    setState(() => _deletedIds.remove(session.id!));
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Could not delete "${session.title}": $error',
                        ),
                      ),
                    );
                  }
                },
                child: _SessionTile(
                  session: session,
                  toneIndex: entry.key,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SessionTile extends StatefulWidget {
  final Session session;
  final int toneIndex;

  const _SessionTile({
    required this.session,
    required this.toneIndex,
  });

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  String _formatDate(DateTime dt, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    final locale = Localizations.localeOf(context).toString();

    if (diff == 0) return l10n.homeToday;
    if (diff == 1) return l10n.homeYesterday;
    if (dt.year == now.year) return DateFormat('MMM d', locale).format(dt);
    return DateFormat('MMM d, y', locale).format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = _sessionTone(context, widget.toneIndex);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () => context.push('/session/${widget.session.id}'),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: tone.background,
            borderRadius: Br.lg,
            border: Border.all(
              color: _pressed
                  ? tone.foreground
                  : scheme.outlineVariant.withValues(alpha: 0.72),
              width: _pressed ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: _pressed ? 0.1 : 0.05),
                blurRadius: _pressed ? 12 : 8,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sp.md,
              vertical: Sp.sm + Sp.xs,
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: tone.badge,
                    borderRadius: Br.md,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.session.emoji,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.session.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Sp.sm),
                      Wrap(
                        spacing: Sp.sm,
                        runSpacing: Sp.xs,
                        children: [
                          _MetaChip(
                            icon: Icons.today_rounded,
                            label: _formatDate(
                              widget.session.createdAt,
                              context,
                            ),
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: Sp.xs),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _EmptySessions extends StatefulWidget {
  final VoidCallback onCreate;

  const _EmptySessions({required this.onCreate});

  @override
  State<_EmptySessions> createState() => _EmptySessionsState();
}

class _EmptySessionsState extends State<_EmptySessions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -20.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: -20.0, end: 0.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 0.0), weight: 30),
    ]).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeInOut,
      ),
    );
    _bounceController.forward();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final quexColors = Theme.of(context).extension<QuexColors>();
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Approximate available space (appBar ~56, bottomNav ~80, greeting ~100, padding ~120)
    final availableHeight = screenHeight - 360 - bottomPadding;

    return SizedBox(
      height: availableHeight.clamp(380, 600),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _bounceAnimation.value),
                child: child,
              );
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    quexColors?.warmRed?.withValues(alpha: 0.3) ??
                        scheme.secondaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Center(
                child: Text(
                  '🚀',
                  style: TextStyle(fontSize: 64),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.homeLetsStartLearning,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              l10n.homeCreateFirstSession,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.rocket_launch),
            label: Text(l10n.homeStartMyAdventure),
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, 56),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoProfileState extends StatelessWidget {
  const _NoProfileState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.92),
            borderRadius: Br.lg,
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(Sp.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: Br.lg,
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 38,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: Sp.lg),
                Text(
                  l10n.homeNoProfilesYet,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Sp.sm),
                Text(
                  l10n.homeSwitchToProfile,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.28,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: CircularProgressIndicator(color: scheme.primary),
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _DashboardMessage({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: scheme.primary),
            const SizedBox(height: Sp.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDashboardEntry extends StatelessWidget {
  final Animation<double> animation;
  final double delay;
  final Widget child;

  const _AnimatedDashboardEntry({
    required this.animation,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delayedAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        delay.clamp(0.0, 0.6),
        (delay + 0.34).clamp(0.34, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: delayedAnimation,
      builder: (context, child) {
        final value = delayedAnimation.value;
        return Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SessionTone {
  final Color background;
  final Color badge;
  final Color foreground;

  const _SessionTone({
    required this.background,
    required this.badge,
    required this.foreground,
  });
}

_SessionTone _sessionTone(BuildContext context, int index) {
  final scheme = Theme.of(context).colorScheme;

  return _SessionTone(
    background: scheme.surfaceContainerLow,
    badge: scheme.primaryContainer,
    foreground: scheme.primary,
  );
}
