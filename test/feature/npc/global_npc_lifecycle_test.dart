import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/npc/npc_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Profiles implements AiNpcApi {
  final requests = <Completer<List<NpcProfile>>>[];

  @override
  Future<List<NpcProfile>> fetchProfiles({String scope = 'global', int? activityId}) {
    final reply = Completer<List<NpcProfile>>();
    requests.add(reply);
    return reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final staleFails in <bool>[false, true]) {
    test('global NPC ignores stale ${staleFails ? 'error' : 'profile'} after refresh', () async {
      final api = _Profiles();
      final container = ProviderContainer(overrides: [
        aiNpcApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      container.read(globalNpcProvider);
      await Future<void>.delayed(Duration.zero);
      expect(api.requests, hasLength(1));
      container.invalidate(globalNpcProvider);
      container.read(globalNpcProvider);
      await Future<void>.delayed(Duration.zero);
      expect(api.requests, hasLength(2));
      api.requests[1].complete(const [
        NpcProfile(profileId: 2, name: '当前原文', scopeType: 3),
      ]);
      await Future<void>.delayed(Duration.zero);
      if (staleFails) {
        api.requests[0].completeError(StateError('old response'));
      } else {
        api.requests[0].complete(const [
          NpcProfile(profileId: 1, name: 'Old profile', scopeType: 3),
        ]);
      }
      await Future<void>.delayed(Duration.zero);
      expect(container.read(globalNpcProvider).profile?.profileId, 2);
      expect(container.read(globalNpcProvider).profile?.name, '当前原文');
      expect(container.read(globalNpcProvider).loading, isFalse);
    });
  }

  test('disposing before scheduled load does not send a request', () async {
    final api = _Profiles();
    final container = ProviderContainer(overrides: [
      aiNpcApiProvider.overrideWithValue(api),
    ]);
    container.read(globalNpcProvider);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, isEmpty);
  });
}
