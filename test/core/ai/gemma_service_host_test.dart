import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/gemma_service_host.dart';

import '../../support/fake_gemma_inference_service.dart';

void main() {
  test('separate hosts keep separate Gemma lifetimes', () async {
    final serviceA = FakeGemmaInferenceService();
    final serviceB = FakeGemmaInferenceService();

    final hostA = GemmaServiceHost(service: serviceA);
    final hostB = GemmaServiceHost(service: serviceB);

    final initializedA = await hostA.ensureInitialized();
    final initializedB = await hostB.ensureInitialized();

    expect(initializedA, same(serviceA));
    expect(initializedB, same(serviceB));
    expect(serviceA.initializeCalls, 1);
    expect(serviceB.initializeCalls, 1);

    await hostA.dispose();

    expect(serviceA.disposeCalls, 1);
    expect(serviceA.closeSessionCalls, 1);
    expect(serviceB.disposeCalls, 0);
    expect(serviceB.isInitialized, isTrue);

    await hostB.dispose();

    expect(serviceB.disposeCalls, 1);
    expect(serviceB.closeSessionCalls, 1);
  });
}
