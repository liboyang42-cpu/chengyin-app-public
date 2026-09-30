import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/network/request_session_scope.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/npc/npc_controller.dart';
import 'package:chengyin_app/feature/npc/merchant_npc_chat_controller.dart';

class TestNpcAuth extends AuthController {
  @override
  AuthState build() => value(1);
  AuthState value(int? id) => AuthState(initialized: true,
    user: id == null ? null : User(id: id, nickname: 'user', avatar: '', role: 'player'));
  void switchTo(int? id) => state = value(id);
}
class _Merchant implements MerchantNpcApi {
  final replies = <Completer<NpcChatResult>>[];
  final scopes = <RequestSessionScope?>[];
  final ids = <String>[];
  @override
  Future<NpcChatResult> chat({required int merchantId, required String message, required String requestId}) {
    ids.add(requestId); scopes.add(RequestSessionScope.current);
    final reply = Completer<NpcChatResult>(); replies.add(reply); return reply.future;
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Activity implements AiNpcApi {
  final streams = <StreamController<String>>[];
  final messages = <String>[];
  final events = <Completer<NpcLine>>[];
  @override
  Future<List<NpcProfile>> fetchProfiles({String scope = 'global', int? activityId}) async =>
    const [NpcProfile(profileId: 7, name: 'raw NPC', scopeType: 1)];
  @override
  Future<NpcLine> fetchEventLine({required int profileId, required String eventType, int? nodeId}) {
    final result = Completer<NpcLine>(); events.add(result); return result.future;
  }
  @override
  Stream<String> chatStream({required int activityId, required int profileId, required String message}) {
    messages.add(message); final stream = StreamController<String>(); streams.add(stream); return stream.stream;
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
void main() {
  test('merchant delayed A reply cannot clear B pending retry or enter B history', () async {
    final api = _Merchant();
    final c = ProviderContainer(overrides: [authControllerProvider.overrideWith(TestNpcAuth.new), merchantNpcApiProvider.overrideWithValue(api)]);
    final sub = c.listen(merchantNpcChatProvider(7), (_, _) {});
    addTearDown(() { sub.close(); c.dispose(); });
    final ctrl = c.read(merchantNpcChatProvider(7).notifier);
    final a = ctrl.send('A text');
    (c.read(authControllerProvider.notifier) as TestNpcAuth).switchTo(2);
    expect(c.read(merchantNpcChatProvider(7)).messages, isEmpty);
    final b = ctrl.send('B 原文');
    api.replies[0].complete(const NpcChatResult(status: 'SUCCEEDED', safeText: 'A secret'));
    await a;
    expect(api.scopes.first!.isCurrent(), isFalse);
    expect(c.read(merchantNpcChatProvider(7)).sending, isTrue);
    api.replies[1].complete(const NpcChatResult(status: 'FAILED'));
    await b;
    final retry = ctrl.retry();
    expect(api.ids[2], api.ids[1]);
    api.replies[2].complete(const NpcChatResult(status: 'SUCCEEDED', safeText: 'B reply'));
    await retry;
    expect(c.read(merchantNpcChatProvider(7)).messages.map((m) => m.text), ['B 原文', 'B reply']);
    (c.read(authControllerProvider.notifier) as TestNpcAuth).switchTo(null);
    expect(c.read(merchantNpcChatProvider(7)).messages, isEmpty);
    await ctrl.send('guest'); await ctrl.retry();
    expect(api.ids, hasLength(3));
  });
  test('disposed merchant conversation ignores delayed errors', () async {
    final api = _Merchant();
    final c = ProviderContainer(overrides: [authControllerProvider.overrideWith(TestNpcAuth.new), merchantNpcApiProvider.overrideWithValue(api)]);
    c.listen(merchantNpcChatProvider(7), (_, _) {});
    final pending = c.read(merchantNpcChatProvider(7).notifier).send('private');
    c.dispose();
    api.replies.single.completeError(StateError('late failure'));
    await pending;
    expect(api.scopes.single!.isCurrent(), isFalse);
  });
  test('activity clears A delta and ignores late events and chunks after B switch', () async {
    final api = _Activity();
    final c = ProviderContainer(overrides: [authControllerProvider.overrideWith(TestNpcAuth.new), aiNpcApiProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    final ctrl = c.read(npcSessionProvider(7).notifier);
    await ctrl.loadProfiles();
    final event = ctrl.onEvent(NpcEventType.enter);
    final a = ctrl.sendChat('  raw user 原文  ');
    api.streams[0].add('{"delta":"A private"}');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(npcSessionProvider(7)).streamDelta, 'A private');
    (c.read(authControllerProvider.notifier) as TestNpcAuth).switchTo(2);
    expect(c.read(npcSessionProvider(7)).streamDelta, isNull);
    await ctrl.loadProfiles();
    final b = ctrl.sendChat('B');
    api.events[0].complete(const NpcLine(profileId: 7, line: 'A event'));
    api.streams[0].add('{"done":true}');
    await event; await a;
    expect(c.read(npcSessionProvider(7)).loading, isTrue);
    api.streams[1].add('{"delta":"B reply"}'); api.streams[1].add('{"done":true}');
    await b;
    expect(c.read(npcSessionProvider(7)).history.map((e) => e.line), ['B reply']);
    expect(api.messages.first, '  raw user 原文  ');
    (c.read(authControllerProvider.notifier) as TestNpcAuth).switchTo(null);
    expect(c.read(npcSessionProvider(7)).history, isEmpty);
    await ctrl.loadProfiles(); await ctrl.sendChat('guest');
    expect(api.streams, hasLength(2));
    for (final stream in api.streams) { await stream.close(); }
  });
}
