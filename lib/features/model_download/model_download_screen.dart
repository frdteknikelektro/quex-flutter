import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../core/ai/model_manager.dart';
import '../../widgets/quex_ui.dart';

class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  bool _ready = false;
  double _progress = 0;
  bool _downloading = false;
  String _version = ModelManager.currentVersion;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final ready = await ModelManager.isReady();
    final progress = await ModelManager.progress();
    final version = await ModelManager.version();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _progress = progress;
      _version = version;
    });
  }

  Future<void> _downloadModel() async {
    setState(() => _downloading = true);
    try {
      await for (final progress in ModelManager.downloadModel()) {
        if (!mounted) return;
        setState(() => _progress = progress);
      }
      await ModelManager.markReady(progress: 1.0);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _downloading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $error')),
      );
    }
  }

  Future<void> _reset() async {
    await ModelManager.reset();
    if (!mounted) return;
    setState(() {
      _ready = false;
      _progress = 0;
      _downloading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return QuexAppShell(
      destination: QuexDestination.model,
      title: 'Model',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final panels = [
              _StatusPanel(
                ready: _ready,
                progress: _progress,
                version: _version,
                downloading: _downloading,
                onDownload: _downloading || _ready ? null : _downloadModel,
                onReset: _ready ? _reset : null,
              ),
              const SizedBox(height: 16),
              const _InfoPanel(),
            ];

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: panels[0]),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: panels[2]),
                ],
              );
            }

            return Column(children: panels);
          },
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final bool ready;
  final double progress;
  final String version;
  final bool downloading;
  final VoidCallback? onDownload;
  final VoidCallback? onReset;

  const _StatusPanel({
    required this.ready,
    required this.progress,
    required this.version,
    required this.downloading,
    required this.onDownload,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Study engine',
            subtitle: 'Track the local model state without leaving the app.',
          ),
          const SizedBox(height: 16),
          Text(
            ready ? 'Ready to use' : 'Not downloaded yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text('Version: $version'),
          const SizedBox(height: 20),
          LinearProgressIndicator(value: downloading || ready ? progress : 0),
          const SizedBox(height: 12),
          Text('${(progress * 100).round()}%'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onDownload,
                icon: downloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(downloading ? 'Downloading...' : 'Download'),
              ),
              OutlinedButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh),
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
            title: 'Best practice',
            subtitle: 'This screen keeps the model state explicit and recoverable.',
          ),
          SizedBox(height: 16),
          Text(
            'On tablet, this screen leaves room for status and guidance side by side. '
            'On phone, it stays linear and easy to scan.',
          ),
        ],
      ),
    );
  }
}
