import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quex/core/ai/model_manager.dart';

class _RecordingInstallFactory {
  _RecordingInstallFactory({this.onInstall});

  final builders = <_RecordingInferenceInstallationBuilder>[];
  final Future<void> Function()? onInstall;

  gemma.InferenceInstallationBuilder call({
    required gemma.ModelType modelType,
    gemma.ModelFileType fileType = gemma.ModelFileType.task,
  }) {
    final builder = _RecordingInferenceInstallationBuilder(
      modelType: modelType,
      fileType: fileType,
      onInstall: onInstall,
    );
    builders.add(builder);
    return builder;
  }
}

class _RecordingInferenceInstallationBuilder
    extends gemma.InferenceInstallationBuilder {
  final gemma.ModelType recordedModelType;
  final gemma.ModelFileType recordedFileType;
  String? networkUrl;
  String? token;
  bool? foreground;
  gemma.CancelToken? cancelToken;
  void Function(int progress)? progressCallback;
  int installCalls = 0;
  final List<int> progressEvents = [];
  final Future<void> Function()? onInstall;

  _RecordingInferenceInstallationBuilder({
    required super.modelType,
    required super.fileType,
    this.onInstall,
  })  : recordedModelType = modelType,
        recordedFileType = fileType;

  @override
  _RecordingInferenceInstallationBuilder fromNetwork(
    String url, {
    String? token,
    bool? foreground,
  }) {
    networkUrl = url;
    this.token = token;
    this.foreground = foreground;
    return this;
  }

  @override
  _RecordingInferenceInstallationBuilder withProgress(
    void Function(int progress) onProgress,
  ) {
    progressCallback = onProgress;
    return this;
  }

  @override
  _RecordingInferenceInstallationBuilder withCancelToken(
    gemma.CancelToken cancelToken,
  ) {
    this.cancelToken = cancelToken;
    return this;
  }

  @override
  Future<gemma.InferenceInstallation> install() async {
    installCalls++;
    progressCallback?.call(-1);
    progressCallback?.call(50);
    progressEvents.addAll([-1, 50]);

    if (onInstall != null) {
      await onInstall!();
    }

    final spec = gemma.InferenceModelSpec.fromLegacyUrl(
      name: 'gemma-4-test',
      modelUrl: networkUrl ?? 'https://example.com/gemma-4-test.litertlm',
      modelType: recordedModelType,
      fileType: recordedFileType,
    );
    gemma.FlutterGemmaPlugin.instance.modelManager.setActiveModel(spec);
    return gemma.InferenceInstallation(spec: spec);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingInstallFactory factory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ModelManager.reset();
    SharedPreferences.setMockInitialValues({
      ModelManager.modelVariantKey: ModelManager.variantE2B,
      ModelManager.modelReadyKey: false,
      ModelManager.modelProgressKey: 0.0,
    });
    factory = _RecordingInstallFactory();
    ModelManager.installModelFactory = factory.call;
  });

  tearDown(() async {
    await gemma.FlutterGemmaPlugin.instance.modelManager.clearModelCache();
    ModelManager.installModelFactory = gemma.FlutterGemma.installModel;
    await ModelManager.reset();
  });

  test('downloadModel uses the shared Gemma installer and emits progress',
      () async {
    final progress = await ModelManager.downloadModel().toList();

    expect(factory.builders, hasLength(1));
    final builder = factory.builders.single;
    expect(builder.recordedModelType, gemma.ModelType.gemma4);
    expect(builder.recordedFileType, gemma.ModelFileType.litertlm);
    expect(builder.networkUrl, ModelManager.gemmaE2BModelUrl);
    expect(builder.installCalls, 1);
    expect(builder.token, isNull);
    expect(builder.foreground, isNull);
    expect(builder.cancelToken, isNotNull);
    expect(progress, hasLength(3));
    expect(progress[0], 0.0);
    expect(progress[1], closeTo(0.5, 1e-9));
    expect(progress[2], 1.0);
    expect(builder.progressEvents, [-1, 50]);
    expect(await ModelManager.progress(), 1.0);
  });

  test('activateModel skips install when a model is already active', () async {
    final activeSpec = gemma.InferenceModelSpec.fromLegacyUrl(
      name: 'already-active',
      modelUrl: ModelManager.gemmaE2BModelUrl,
      modelType: gemma.ModelType.gemmaIt,
      fileType: gemma.ModelFileType.litertlm,
    );
    gemma.FlutterGemmaPlugin.instance.modelManager.setActiveModel(activeSpec);

    await ModelManager.activateModel();

    expect(factory.builders, isEmpty);
  });

  test('downloadModel rejects concurrent installs while one is in progress',
      () async {
    final gate = Completer<void>();
    factory = _RecordingInstallFactory(onInstall: () => gate.future);
    ModelManager.installModelFactory = factory.call;

    final firstFuture = ModelManager.downloadModel().toList();
    await Future<void>.delayed(Duration.zero);
    final secondProgress = await ModelManager.downloadModel().toList();
    expect(secondProgress, isEmpty);
    expect(factory.builders, hasLength(1));

    gate.complete();

    final firstProgress = await firstFuture;
    expect(firstProgress, isNotEmpty);
    expect(firstProgress.last, 1.0);
  });
}
