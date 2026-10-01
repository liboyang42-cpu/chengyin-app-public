import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_chat_test_support.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => _state(1);
  static AuthState _state(int? id) => AuthState(
    initialized: true,
    user: id == null ? null : User(id: id, nickname: 'Owner $id', avatar: '', role: 'player'),
  );
  void switchTo(int? id) => state = _state(id);
}

void main() {
  testWidgets('account switch suppresses late message read and stops read acknowledgements', (tester) async {
    final response = Completer<ChatPage>();
    final api = FakeImChatApi(onMessages: (_, _) => response.future);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      imApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ImChatPage(conversationId: 9, peerName: 'Old private peer')),
    ));
    await tester.pump();
    expect(api.calls, hasLength(1));
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(2);
    await tester.pump();
    response.complete(ChatPage(list: [msg(1, content: 'Old private message')]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('im-session-changed')), findsOneWidget);
    expect(find.text('Old private peer'), findsNothing);
    expect(find.text('Old private message'), findsNothing);
    expect(api.readCalls, isEmpty);
    await tester.pump(const Duration(seconds: 9));
    expect(api.calls, hasLength(1), reason: 'B must reopen its own conversation; no polling of A');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('logout clears already-rendered messages and unsent input immediately', (tester) async {
    final api = FakeImChatApi(onMessages: (_, _) async => ChatPage(list: [
      msg(1, content: 'Visible only to A'),
    ]));
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      imApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ImChatPage(conversationId: 9)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Visible only to A'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), 'Private unsent draft');
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(null);
    await tester.pumpAndSettle();
    expect(find.text('Visible only to A'), findsNothing);
    expect(find.text('Private unsent draft'), findsNothing);
    expect(find.byKey(const Key('im-session-changed')), findsOneWidget);
    expect(api.calls, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
