import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/ai/wiki_storage_service.dart';
import '../../core/state/wiki_state.dart';

class WikiBuildModal extends ConsumerStatefulWidget {
  final int sessionId;

  const WikiBuildModal({super.key, required this.sessionId});

  @override
  ConsumerState<WikiBuildModal> createState() => _WikiBuildModalState();
}

enum _WikiBuildStep { loading, building, complete }

class _WikiBuildModalState extends ConsumerState<WikiBuildModal> {
  final Object _gemmaOwnerToken = Object();
  final ScrollController _scrollController = ScrollController();
  _WikiBuildStep _step = _WikiBuildStep.loading;

  @override
  void initState() {
    super.initState();
    _loadModelAndBuild();
  }

  @override
  void dispose() {
    unawaited(QuexAi.releaseGemmaService(_gemmaOwnerToken));
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadModelAndBuild() async {
    try {
      final service = await QuexAi.acquireGemmaService(_gemmaOwnerToken);
      if (!mounted) return;
      setState(() => _step = _WikiBuildStep.building);
      await ref
          .read(wikiActionControllerProvider(widget.sessionId).notifier)
          .ingest(service);
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load model: $error')),
      );
    }
  }

  void _cancel() {
    unawaited(QuexAi.releaseGemmaService(_gemmaOwnerToken));
    if (mounted) Navigator.of(context).pop();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _statusText(WikiActionState actionState) {
    if (_step == _WikiBuildStep.loading) return 'Loading model…';
    if (_step == _WikiBuildStep.complete) return 'Wiki built! 🎉';
    if (actionState.lines.isEmpty) return 'Getting ready…';
    return actionState.runType == WikiRunType.lint
        ? 'Linting wiki…'
        : 'Building wiki…';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final actionState = ref.watch(
      wikiActionControllerProvider(widget.sessionId),
    );

    ref.listen(wikiActionControllerProvider(widget.sessionId),
        (previous, next) {
      if (previous?.status == next.status) return;
      if (!mounted) return;

      if (next.isSuccess && _step != _WikiBuildStep.complete) {
        setState(() => _step = _WikiBuildStep.complete);
        ref.invalidate(wikiTreeProvider(widget.sessionId));
        final nav = Navigator.of(context);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) nav.pop();
        });
      } else if (next.hasError && next.error != null) {
        final error = next.error!;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    });

    if (actionState.lines.isNotEmpty) _scrollToBottom();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancel,
              ),
            ),
            const Spacer(flex: 1),
            Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: _step == _WikiBuildStep.complete
                      ? Icon(
                          Icons.check_circle_rounded,
                          key: const ValueKey('check'),
                          size: 64,
                          color: scheme.primary,
                        )
                      : _step == _WikiBuildStep.loading
                          ? const _PulsingEmoji(
                              key: ValueKey('brain'),
                              emoji: '🧠',
                            )
                          : const _PulsingEmoji(
                              key: ValueKey('book'),
                              emoji: '📚',
                            ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusText(actionState),
                    key: ValueKey(_statusText(actionState)),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              child: AnimatedOpacity(
                opacity: actionState.lines.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  height: 240,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: Br.md,
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: actionState.lines.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '> ${actionState.lines[index]}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                              height: 1.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_step != _WikiBuildStep.complete)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: scheme.primaryContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
              ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}

class _PulsingEmoji extends StatefulWidget {
  final String emoji;

  const _PulsingEmoji({super.key, required this.emoji});

  @override
  State<_PulsingEmoji> createState() => _PulsingEmojiState();
}

class _PulsingEmojiState extends State<_PulsingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Text(widget.emoji, style: const TextStyle(fontSize: 64)),
    );
  }
}
