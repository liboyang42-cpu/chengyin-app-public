import 'dart:async';
import 'dart:convert';

import 'package:chengyin_app/feature/account/pending_inviter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> memory;
  late List<String> sent;
  int? user;
  bool fail = false;
  late PendingInviter service;

  PendingInviter create() => PendingInviter(
    read: (key) async => memory[key],
    write: (key, value) async { memory[key] = value; },
    remove: (key) async { memory.remove(key); },
    currentUserId: () => user,
    bind: (id) async {
      if (fail) throw StateError('offline');
      sent.add('$user:$id');
    },
  );

  setUp(() {
    memory = <String, String>{};
    sent = <String>[];
    user = null;
    fail = false;
    service = create();
  });

  test('guest link survives restart and replays only once after login', () async {
    await service.capture('007');
    expect(sent, isEmpty);
    expect(memory, contains(PendingInviter.pendingKey));
    service = create();
    user = 42;
    await Future.wait([service.replay(), service.replay()]);
    expect(sent, ['42:7']);
    expect(memory['has_inviter_v1_42'], '1');
    expect(memory, isNot(contains(PendingInviter.pendingKey)));
  });

  test('failed bind remains owned by A and cannot replay for B', () async {
    await service.capture('7');
    user = 42;
    fail = true;
    await service.replay();
    expect(jsonDecode(memory[PendingInviter.pendingKey]!)['owner'], 42);
    user = 43;
    fail = false;
    await create().replay();
    expect(sent, isEmpty);
    user = 42;
    await service.replay();
    expect(sent, ['42:7']);
  });

  test('bound flags are account-scoped; legacy global flag is ignored', () async {
    memory['has_inviter'] = '1';
    user = 42;
    await service.capture('7');
    await service.capture('8');
    user = 43;
    await service.capture('9');
    expect(sent, ['42:7', '43:9']);
  });

  test('self and invalid invitations never bind', () async {
    user = 42;
    for (final value in ['42', '0042', '0', '-1', 'abc', '']) {
      await service.capture(value);
    }
    expect(sent, isEmpty);
    expect(memory, isEmpty);
  });

  test('account switch during storage read prevents a request', () async {
    await service.capture('7');
    user = 42;
    final gate = Completer<String?>();
    service = PendingInviter(
      read: (key) => gate.future,
      write: (key, value) async { memory[key] = value; },
      remove: (key) async { memory.remove(key); },
      currentUserId: () => user,
      bind: (id) async { sent.add(id); },
    );
    final replay = service.replay();
    await Future<void>.delayed(Duration.zero);
    user = 43;
    gate.complete(memory[PendingInviter.pendingKey]);
    await replay;
    expect(sent, isEmpty);
  });
}
