import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final activeProfileId = ref.watch(activeProfileProvider);

    return profilesAsync.when(
      data: (profiles) {
        if (profiles.isEmpty) {
          return const _NoProfileState();
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

        final sessionsAsync = ref.watch(recentSessionsProvider(activeProfile.id!));

        return sessionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Failed to load sessions: $error')),
          data: (sessions) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(profilesProvider);
                ref.invalidate(recentSessionsProvider(activeProfile.id!));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GreetingHeader(profileName: activeProfile.name),
                    const SizedBox(height: 32),
                    if (sessions.isNotEmpty) ...[
                      Text(
                        'Recent Sessions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (sessions.isEmpty)
                      _EmptySessions(onCreate: () => context.push(Routes.newSession))
                    else
                      _RecentSessionsList(sessions: sessions),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load profiles: $error')),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final String profileName;

  const _GreetingHeader({required this.profileName});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_getGreeting()}!',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        Text(
          profileName,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RecentSessionsList extends StatefulWidget {
  final List<Session> sessions;

  const _RecentSessionsList({required this.sessions});

  @override
  State<_RecentSessionsList> createState() => _RecentSessionsListState();
}

class _RecentSessionsListState extends State<_RecentSessionsList> {
  bool _isExpanded = false;
  static const int _initialCount = 5;

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final displayCount = _isExpanded ? widget.sessions.length : _initialCount.clamp(0, widget.sessions.length);
    final hasMore = widget.sessions.length > _initialCount;

    return Column(
      children: [
        ...widget.sessions.take(displayCount).map((session) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SessionTile(session: session),
            )),
        if (hasMore)
          Center(
            child: TextButton.icon(
              onPressed: _toggleExpanded,
              icon: AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down),
              ),
              label: Text(_isExpanded ? 'See less' : 'See more'),
            ),
          ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;

  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      child: InkWell(
        onTap: () => context.push('/session/${session.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  session.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  session.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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
            "Let's start learning!",
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
              'Create your very first study session and blast off into a world of fun!',
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
            label: const Text('Start my adventure!'),
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
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.school_outlined,
              size: 48,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No profiles yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Switch to a profile to start a new study flow.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
