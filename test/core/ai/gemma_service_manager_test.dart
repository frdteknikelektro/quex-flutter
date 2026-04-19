import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/gemma_service_manager.dart';

import '../../support/fake_gemma_inference_service.dart';

void main() {
  group('GemmaServiceManager', () {
    late List<FakeGemmaInferenceService> created;
    late GemmaServiceManager manager;

    setUp(() {
      created = [];
      manager = GemmaServiceManager(serviceFactory: () {
        final service = FakeGemmaInferenceService();
        created.add(service);
        return service;
      });
    });

    tearDown(() async {
      await manager.reset();
    });

    test('acquire loads once for same owner', () async {
      final owner = Object();

      final first = await manager.acquire(owner);
      final second = await manager.acquire(owner);

      expect(first, same(second));
      expect(created, hasLength(1));
      expect(created.single.initializeCalls, 1);
      expect(created.single.disposeCalls, 0);
    });

    test('release unloads current service', () async {
      final owner = Object();

      await manager.acquire(owner);
      await manager.release(owner);

      expect(created, hasLength(1));
      expect(created.single.disposeCalls, 1);
      expect(manager.current, isNull);
      expect(manager.isReady, isFalse);
    });

    test('re-acquire after release creates fresh instance', () async {
      final owner = Object();

      final first = await manager.acquire(owner);
      await manager.release(owner);
      final second = await manager.acquire(owner);

      expect(first, isNot(same(second)));
      expect(created, hasLength(2));
      expect(created[0].disposeCalls, 1);
      expect(created[1].initializeCalls, 1);
    });

    test('new owner evicts previous owner', () async {
      final ownerA = Object();
      final ownerB = Object();

      final first = await manager.acquire(ownerA);
      final second = await manager.acquire(ownerB);

      expect(first, isNot(same(second)));
      expect(created, hasLength(2));
      expect(created[0].disposeCalls, 1);
      expect(created[1].initializeCalls, 1);
      expect(manager.current, same(second));
      expect(manager.isCurrentOwner(ownerB), isTrue);
    });

    test('stale release from non-owner is ignored', () async {
      final ownerA = Object();
      final ownerB = Object();

      await manager.acquire(ownerA);
      await manager.acquire(ownerB);
      await manager.release(ownerA);

      expect(created, hasLength(2));
      expect(created[0].disposeCalls, 1);
      expect(created[1].disposeCalls, 0);
      expect(manager.current, same(created[1]));
      expect(manager.isCurrentOwner(ownerB), isTrue);
    });
  });
}
