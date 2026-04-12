import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_shell.dart';
import '../../app/breakpoints.dart';
import '../../app/router.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    _restoreActiveProfile();
  }

  Future<void> _restoreActiveProfile() async {
    final saved = await readActiveProfileId();
    if (!mounted) return;
    ref.read(activeProfileProvider.notifier).state = saved;
  }

  Future<void> _setActiveProfile(Profile profile) async {
    await saveActiveProfileId(profile.id!);
    if (!mounted) return;
    ref.read(activeProfileProvider.notifier).state = profile.id;
    setState(() {
      _selectedSessionId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final activeProfileId = ref.watch(activeProfileProvider);
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;

    return profilesAsync.when(
      data: (profiles) {
        if (profiles.isEmpty) {
          return QuexAppShell(
            destination: QuexDestination.home,
            title: 'Quex',
            actions: [
              IconButton(
                onPressed: () => context.go(Routes.settings),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
            child: const QuexEmptyState(
              icon: Icons.school_outlined,
              title: 'No profiles yet',
              message: 'Create a profile in Settings to start a new study flow.',
            ),
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

        final sessionsAsync = ref.watch(recentSessionsProvider(activeProfile.id!));

        return QuexAppShell(
          destination: QuexDestination.home,
          title: 'Quex',
          actions: [
            IconButton(
              onPressed: () => context.go(Routes.newSession),
              icon: const Icon(Icons.add_circle_outline),
            ),
            IconButton(
              onPressed: () => context.go(Routes.settings),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          floatingActionButton: compact
              ? FloatingActionButton.extended(
                  onPressed: () => context.go(Routes.newSession),
                  icon: const Icon(Icons.add),
                  label: const Text('New session'),
                )
              : null,
          child: sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Failed to load sessions: $error')),
            data: (sessions) {
              if (sessions.isNotEmpty &&
                  (_selectedSessionId == null ||
                      !sessions.any((session) => session.id == _selectedSessionId))) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _selectedSessionId = sessions.first.id);
                });
              }

              if (sessions.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(profilesProvider);
                    ref.invalidate(recentSessionsProvider(activeProfile.id!));
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      child: Column(
                        children: [
                          _HomeHero(
                            profile: activeProfile,
                            onSwitchProfile: (profile) => _setActiveProfile(profile),
                            onCreateSession: () => context.go(Routes.newSession),
                            profiles: profiles,
                          ),
                          const SizedBox(height: 16),
                          const QuexEmptyState(
                            icon: Icons.auto_stories_outlined,
                            title: 'No sessions yet',
                            message: 'Create a session first, then add materials and generate a quiz.',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final selectedSession = sessions.firstWhere(
                (session) => session.id == _selectedSessionId,
                orElse: () => sessions.first,
              );

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(profilesProvider);
                  ref.invalidate(recentSessionsProvider(activeProfile.id!));
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= QuexBreakpoints.tablet;
                    final content = wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 380,
                                child: _HomeSidebar(
                                  profile: activeProfile,
                                  profiles: profiles,
                                  onSwitchProfile: _setActiveProfile,
                                  sessions: sessions,
                                  selectedSessionId: _selectedSessionId,
                                  onSelectSession: (sessionId) {
                                    setState(() => _selectedSessionId = sessionId);
                                  },
                                  onCreateSession: () => context.go(Routes.newSession),
                                  onManageProfiles: () => context.go(Routes.settings),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _HomeDetail(
                                  profile: activeProfile,
                                  session: selectedSession,
                                  onOpenSession: (sessionId) =>
                                      context.go('/session/$sessionId'),
                                  onOpenMaterials: (sessionId) =>
                                      context.go('/session/$sessionId/material'),
                                  onOpenQuiz: (sessionId) async {
                                    final quizzes = await QuizDAO().getBySession(sessionId);
                                    if (!context.mounted) return;
                                    if (quizzes.isEmpty) {
                                      context.go('/session/$sessionId/processing');
                                    } else {
                                      final quizId = quizzes.first.id!;
                                      context.go('/session/$sessionId/quiz/$quizId');
                                    }
                                  },
                                  onOpenChat: (sessionId) =>
                                      context.go('/session/$sessionId/chat'),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _HomeHero(
                                profile: activeProfile,
                                onSwitchProfile: (profile) => _setActiveProfile(profile),
                                onCreateSession: () => context.go(Routes.newSession),
                                profiles: profiles,
                              ),
                              const SizedBox(height: 16),
                              _HomeDetail(
                                profile: activeProfile,
                                session: selectedSession,
                                onOpenSession: (sessionId) =>
                                    context.go('/session/$sessionId'),
                                onOpenMaterials: (sessionId) =>
                                    context.go('/session/$sessionId/material'),
                                onOpenQuiz: (sessionId) async {
                                  final quizzes = await QuizDAO().getBySession(sessionId);
                                  if (!context.mounted) return;
                                  if (quizzes.isEmpty) {
                                    context.go('/session/$sessionId/processing');
                                  } else {
                                    final quizId = quizzes.first.id!;
                                    context.go('/session/$sessionId/quiz/$quizId');
                                  }
                                },
                                onOpenChat: (sessionId) =>
                                    context.go('/session/$sessionId/chat'),
                              ),
                              const SizedBox(height: 16),
                              _RecentSessionsList(
                                sessions: sessions,
                                selectedSessionId: _selectedSessionId,
                                onSelectSession: (sessionId) {
                                  setState(() => _selectedSessionId = sessionId);
                                },
                                onCreateSession: () => context.go(Routes.newSession),
                              ),
                            ],
                          );

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      child: content,
                    );
                  },
                ),
              );
            },
          ),
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

class _HomeHero extends StatelessWidget {
  final Profile profile;
  final List<Profile> profiles;
  final ValueChanged<Profile> onSwitchProfile;
  final VoidCallback onCreateSession;

  const _HomeHero({
    required this.profile,
    required this.profiles,
    required this.onSwitchProfile,
    required this.onCreateSession,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QuexAvatar(emoji: profile.emoji, size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Grade ${profile.grade} • ${profile.defaultQuestionCount} questions by default',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: profiles
                .map(
                  (item) => ChoiceChip(
                    label: Text(item.name),
                    selected: item.id == profile.id,
                    onSelected: (_) => onSwitchProfile(item),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onCreateSession,
                icon: const Icon(Icons.add),
                label: const Text('New session'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.settings),
                icon: const Icon(Icons.tune),
                label: const Text('Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSessionsList extends StatelessWidget {
  final List<Session> sessions;
  final int? selectedSessionId;
  final ValueChanged<int> onSelectSession;
  final VoidCallback onCreateSession;

  const _RecentSessionsList({
    required this.sessions,
    required this.selectedSessionId,
    required this.onSelectSession,
    required this.onCreateSession,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuexSectionHeader(
            title: 'Recent sessions',
            subtitle: 'Tap a session to continue where you left off.',
            trailing: TextButton(
              onPressed: onCreateSession,
              child: const Text('Create'),
            ),
          ),
          const SizedBox(height: 16),
          if (sessions.isEmpty)
            const QuexEmptyState(
              icon: Icons.auto_stories_outlined,
              title: 'No sessions yet',
              message: 'Create your first session to add materials and generate a quiz.',
            )
          else
            ...sessions.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  selected: session.id == selectedSessionId,
                  selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  leading: QuexAvatar(emoji: session.emoji),
                  title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    'Grade ${session.gradeOverride} • ${DateFormat.MMMd().format(session.createdAt)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onSelectSession(session.id!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeSidebar extends StatelessWidget {
  final Profile profile;
  final List<Profile> profiles;
  final ValueChanged<Profile> onSwitchProfile;
  final List<Session> sessions;
  final int? selectedSessionId;
  final ValueChanged<int> onSelectSession;
  final VoidCallback onCreateSession;
  final VoidCallback onManageProfiles;

  const _HomeSidebar({
    required this.profile,
    required this.profiles,
    required this.onSwitchProfile,
    required this.sessions,
    required this.selectedSessionId,
    required this.onSelectSession,
    required this.onCreateSession,
    required this.onManageProfiles,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HomeHero(
          profile: profile,
          profiles: profiles,
          onSwitchProfile: onSwitchProfile,
          onCreateSession: onCreateSession,
        ),
        const SizedBox(height: 16),
        _RecentSessionsList(
          sessions: sessions,
          selectedSessionId: selectedSessionId,
          onSelectSession: onSelectSession,
          onCreateSession: onCreateSession,
        ),
        const SizedBox(height: 16),
        QuexPanel(
          child: Row(
            children: [
              Expanded(
                child: QuexMetricCard(
                  label: 'Grade',
                  value: '${profile.grade}',
                  icon: Icons.school_outlined,
                  accent: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuexMetricCard(
                  label: 'Questions',
                  value: '${profile.defaultQuestionCount}',
                  icon: Icons.quiz_outlined,
                  accent: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: onManageProfiles,
          icon: const Icon(Icons.manage_accounts_outlined),
          label: const Text('Manage profiles'),
        ),
      ],
    );
  }
}

class _HomeDetail extends StatelessWidget {
  final Profile profile;
  final Session session;
  final ValueChanged<int> onOpenSession;
  final ValueChanged<int> onOpenMaterials;
  final ValueChanged<int> onOpenQuiz;
  final ValueChanged<int> onOpenChat;

  const _HomeDetail({
    required this.profile,
    required this.session,
    required this.onOpenSession,
    required this.onOpenMaterials,
    required this.onOpenQuiz,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Object?>>(
      future: Future.wait([
        MaterialDAO().countBySession(session.id!),
        QuizDAO().getBySession(session.id!),
        ChatDAO().getBySession(session.id!),
      ]),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final materials = data != null ? data[0] as int : 0;
        final quizzes = data != null ? data[1] as List<Quiz> : const <Quiz>[];
        final chats = data != null ? data[2] as List<ChatMessage> : const <ChatMessage>[];
        final latestQuiz = quizzes.isNotEmpty ? quizzes.first : null;

        return Column(
          children: [
            QuexPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      QuexAvatar(emoji: session.emoji, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.title,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Grade ${session.gradeOverride} • ${DateFormat.yMMMMd().format(session.createdAt)}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      QuexTonePill(label: '$materials materials'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => onOpenMaterials(session.id!),
                        icon: const Icon(Icons.library_books_outlined),
                        label: const Text('Materials'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => onOpenQuiz(session.id!),
                        icon: const Icon(Icons.quiz_outlined),
                        label: Text(latestQuiz == null ? 'Generate quiz' : 'Open quiz'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => onOpenChat(session.id!),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Chat'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => onOpenSession(session.id!),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open session'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: QuexMetricCard(
                    label: 'Materials',
                    value: '$materials',
                    icon: Icons.library_books_outlined,
                    accent: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuexMetricCard(
                    label: 'Quizzes',
                    value: '${quizzes.length}',
                    icon: Icons.quiz_outlined,
                    accent: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuexMetricCard(
                    label: 'Messages',
                    value: '${chats.length}',
                    icon: Icons.chat_bubble_outline,
                    accent: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (latestQuiz != null)
              QuexPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest quiz',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      latestQuiz.isCompleted
                          ? 'Score ${latestQuiz.score}/${latestQuiz.questionCount}'
                          : 'In progress',
                    ),
                  ],
                ),
              )
            else
              const QuexPanel(
                child: Text('Add materials, then generate the first quiz for this session.'),
              ),
          ],
        );
      },
    );
  }
}
