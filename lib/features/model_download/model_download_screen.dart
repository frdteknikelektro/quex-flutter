import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/download_state.dart';
import '../../core/ai/model_download_notifier.dart';
import '../../core/ai/model_manager.dart';
import '../../widgets/quex_ui.dart';

class ModelDownloadScreen extends ConsumerWidget {
  const ModelDownloadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelDownloadProvider);
    final notifier = ref.read(modelDownloadProvider.notifier);

    return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final statusPanel = _StatusPanel(
              state: state,
              onDownload: state.status == DownloadStatus.idle
                  ? notifier.start
                  : null,
              onCancel: state.isActive ? notifier.cancel : null,
              onRetry: state.hasFailed ? notifier.retry : null,
              onReset: state.isCompleted ? notifier.reset : null,
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: statusPanel),
                  const SizedBox(width: 16),
                  const SizedBox(width: 360, child: _InfoPanel()),
                ],
              );
            }

            return Column(
              children: [
                statusPanel,
                const SizedBox(height: 16),
                const _InfoPanel(),
              ],
            );
          },
        ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final ModelDownloadState state;
  final VoidCallback? onDownload;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onReset;

  const _StatusPanel({
    required this.state,
    required this.onDownload,
    required this.onCancel,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (state.progress * 100).round();

    final statusLabel = switch (state.status) {
      DownloadStatus.idle => state.progress > 0 ? 'Paused at $percent%' : 'Not downloaded yet',
      DownloadStatus.downloading => 'Downloading…  $percent%',
      DownloadStatus.cancelling => 'Cancelling…',
      DownloadStatus.completed => 'Ready to use',
      DownloadStatus.failed => 'Download failed',
    };

    final statusColor = switch (state.status) {
      DownloadStatus.completed => scheme.primary,
      DownloadStatus.failed => scheme.error,
      _ => scheme.onSurface,
    };

    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Study engine',
            subtitle: 'Track and control the local model download.',
          ),
          const SizedBox(height: 16),
          Text(
            statusLabel,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<String>(
            future: ModelManager.version(),
            builder: (context, snap) =>
                Text('Version: ${snap.data ?? ModelManager.currentVersion}'),
          ),
          if (state.hasFailed && state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.status == DownloadStatus.cancelling
                  ? null
                  : (state.isActive || state.isCompleted)
                      ? state.progress
                      : state.progress > 0
                          ? state.progress
                          : 0,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Text('$percent% of ~6.6 GB'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onDownload != null)
                FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download),
                  label: Text(
                    state.progress > 0 ? 'Resume download' : 'Download',
                  ),
                ),
              if (onCancel != null)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: state.status == DownloadStatus.cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop_circle_outlined),
                  label: const Text('Cancel'),
                ),
              if (onRetry != null)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              if (onReset != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete model?'),
                        content: const Text(
                          'This will delete the downloaded model (~6.6 GB) from your device. '
                          'You will need to download it again to use the AI features.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      onReset!();
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Reset'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel();

  @override
  Widget build(BuildContext context) {
    return const QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuexSectionHeader(
            title: 'About the model',
            subtitle: 'Gemma 4 E4B — your on-device study engine.',
          ),
          SizedBox(height: 16),
          Text(
            'The model runs entirely on your device — no internet required after download. '
            'You can navigate away freely while it downloads; progress is preserved and '
            'a notification will alert you when it finishes.',
          ),
          SizedBox(height: 12),
          Text(
            'Size: ~6.6 GB  •  Format: LiteRT-LM  •  Capabilities: text, image, audio',
          ),
        ],
      ),
    );
  }
}
