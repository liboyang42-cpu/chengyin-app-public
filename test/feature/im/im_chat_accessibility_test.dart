import 'dart:ui' show SemanticsAction, Tristate;

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeImApi implements ImApi {
  @override
  Future<ChatPage> messages(
    int conversationId, {
    int cursorId = 0,
    int size = 30,
  }) async => ChatPage(list: <ChatMessage>[]);

  @override
  Future<void> read(int conversationId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpChat(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        imApiProvider.overrideWithValue(_FakeImApi()),
      ].cast(),
      child: const MaterialApp(
        home: ImChatPage(conversationId: 9, peerName: '小李', peerMemberId: 2),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('聊天页纯图标动作具有独立语义和 44pt 热区', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpChat(tester);

    // 「+」2026-09-17 从「只发路线」改成动作菜单(图片/位置/路线),
    // 标签跟着换成与小程序同一个 aria-label。
    for (final String label in <String>['拉黑此人', '添加图片、位置或路线']) {
      final Finder action = find.bySemanticsLabel(label);
      expect(action, findsOneWidget);
      expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(44));
      final SemanticsData data = tester.getSemantics(action).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue, reason: label);
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
    }

    semantics.dispose();
  });

  testWidgets('发送键会告知 VoiceOver 当前是否可用', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpChat(tester);

    Finder send = find.bySemanticsLabel('发送消息');
    expect(send, findsOneWidget);
    expect(tester.getSize(send).shortestSide, greaterThanOrEqualTo(44));
    SemanticsData data = tester.getSemantics(send).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);

    await tester.enterText(find.byType(CupertinoTextField), '周六见');
    await tester.pump();

    send = find.bySemanticsLabel('发送消息');
    data = tester.getSemantics(send).getSemanticsData();
    expect(data.flagsCollection.isEnabled, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    semantics.dispose();
  });
}
