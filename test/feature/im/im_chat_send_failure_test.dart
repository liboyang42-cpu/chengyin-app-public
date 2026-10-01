// 发送失败要**留在列表里**,不是弹个 toast 就算交代了。
//
// ★ 原来失败只弹 toast:2.4 秒后消失,用户手上只剩输入框里那句
//   不知道发没发出去的话(再打一个字就被覆盖)。失败态必须是一个
//   看得见、点得动、能回答"发出去了没有"的东西。

import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:chengyin_app/feature/im/im_controller.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeImApi implements ImApi {
  _FakeImApi({this.failuresLeft = 1});

  /// 还要失败几次;到 0 之后正常返回一条新消息。
  int failuresLeft;
  final List<String> sentTexts = <String>[];
  final List<String?> attemptIds = <String?>[];
  ChatMessage? serverMessage;
  Completer<ChatMessage>? pendingSend;

  @override
  Future<ChatPage> messages(
    int conversationId, {
    int cursorId = 0,
    int size = 30,
  }) async => ChatPage(list: <ChatMessage>[
    if (serverMessage != null) serverMessage!,
  ]);

  @override
  Future<void> read(int conversationId) async {}

  @override
  Future<ChatMessage> send(
    int conversationId, {
    required String content,
    int msgType = kMsgText,
    String? extraJson,
    String? clientMessageId,
  }) async {
    attemptIds.add(clientMessageId);
    if (failuresLeft > 0) {
      failuresLeft -= 1;
      throw Exception('网络断了');
    }
    if (pendingSend != null) return pendingSend!.future;
    sentTexts.add(content);
    return ChatMessage(
      id: 100 + sentTexts.length,
      conversationId: conversationId,
      senderId: 1,
      msgType: msgType,
      content: content,
      extraJson: extraJson,
      createTime: '2026-01-15 20:20:00',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeImApi api, {Locale locale = const Locale('zh')}) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[imApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const ImChatPage(conversationId: 9, peerName: '小李', peerMemberId: 2),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(CupertinoTextField), text);
  await tester.pump();
}

void main() {
  testWidgets('pending send cannot append after account changes', (tester) async {
    final _FakeImApi api = _FakeImApi(failuresLeft: 0);
    api.pendingSend = Completer<ChatMessage>();
    int memberId = 1;
    final ProviderContainer container = ProviderContainer(overrides: [
      imApiProvider.overrideWithValue(api),
      currentMemberIdProvider.overrideWith((ref) => memberId),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ImChatPage(conversationId: 9)),
    ));
    await tester.pumpAndSettle();
    await _type(tester, 'old account message');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pump();
    memberId = 2;
    container.invalidate(currentMemberIdProvider);
    api.pendingSend!.complete(ChatMessage(
      id: 101,
      conversationId: 9,
      senderId: 1,
      msgType: kMsgText,
      content: 'old account message',
    ));
    await tester.pumpAndSettle();
    expect(find.text('old account message'), findsNothing);
    expect(find.text('未发送，点按重试'), findsNothing);
  });

  testWidgets('English retry UI preserves Chinese user message and retry identity', (tester) async {
    final _FakeImApi api = _FakeImApi();
    await _pump(tester, api, locale: const Locale('en'));
    await _type(tester, '我在集合点');
    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Not sent. Tap to retry.'), findsOneWidget);
    expect(find.text('我在集合点'), findsOneWidget);
    await tester.tap(find.text('Not sent. Tap to retry.'));
    await tester.pumpAndSettle();
    expect(api.sentTexts, <String>['我在集合点']);
    expect(api.attemptIds.last, api.attemptIds.first);
    expect(find.text('我在集合点'), findsOneWidget);
    expect(find.text('Not sent. Tap to retry.'), findsNothing);
  });

  testWidgets('poll before send response renders the acknowledged message once', (tester) async {
    final _FakeImApi api = _FakeImApi(failuresLeft: 0);
    api.pendingSend = Completer<ChatMessage>();
    await _pump(tester, api);
    await _type(tester, 'same server message');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pump();
    api.serverMessage = ChatMessage(
      id: 101,
      conversationId: 9,
      senderId: 1,
      msgType: kMsgText,
      content: 'same server message',
      createTime: '2026-01-15 20:20:00',
    );
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    api.pendingSend!.complete(api.serverMessage!);
    await tester.pumpAndSettle();
    expect(find.text('same server message'), findsOneWidget);
  });

  testWidgets('发失败后消息留在列表里，带可点重试', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi();
    await _pump(tester, api);
    await _type(tester, '会议改到三点');

    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();

    expect(find.text('会议改到三点'), findsOneWidget, reason: '失败的话不能凭空消失');
    expect(find.text('未发送，点按重试'), findsOneWidget);
  });

  testWidgets('点重试原样重发，成功后失败态消失', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi();
    await _pump(tester, api);
    await _type(tester, '会议改到三点');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('未发送，点按重试'));
    await tester.pumpAndSettle();

    expect(api.sentTexts, <String>['会议改到三点']);
    expect(api.attemptIds, hasLength(2));
    expect(api.attemptIds.first, matches(RegExp(r'^[A-Za-z0-9_-]{16,64}$')));
    expect(api.attemptIds.last, api.attemptIds.first);
    await _type(tester, '下一条');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();
    expect(api.attemptIds.last, isNot(api.attemptIds.first));
    expect(find.text('未发送，点按重试'), findsNothing);
    expect(find.text('会议改到三点'), findsOneWidget, reason: '这次是真发出去了');
  });

  testWidgets('失败后输入框已清空（文字活在气泡里，不再和输入框抢同一句话）', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi();
    await _pump(tester, api);
    await _type(tester, '会议改到三点');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();

    final EditableText field = tester.widget<EditableText>(
      find.byType(EditableText),
    );
    expect(field.controller.text, isEmpty);
  });

  testWidgets('重试时不给连点：发送中再点一次不会多发一条', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi(failuresLeft: 0);
    await _pump(tester, api);
    await _type(tester, '在的');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();

    expect(api.sentTexts, <String>['在的']);
    expect(find.text('未发送，点按重试'), findsNothing);
  });

  testWidgets('空消息不发送（不产生一条只有空白的失败气泡）', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi();
    await _pump(tester, api);
    await _type(tester, '   ');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();

    expect(find.text('未发送，点按重试'), findsNothing);
    expect(api.sentTexts, isEmpty);
  });

  testWidgets('发送成功给一次轻触感（§3.9 IM7），失败不给', (WidgetTester tester) async {
    final List<String> haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments.toString());
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, _FakeImApi(failuresLeft: 1));
    await _type(tester, '到了说一声');
    await tester.tap(find.bySemanticsLabel('发送消息'));
    await tester.pumpAndSettle();

    // ⚠️ 不能用 "isEmpty" 判 —— 失败时 CyNativeNotice(isError) 会打 heavyImpact,
    //   那是「出错了」的信号,与「发出去了」是两回事。这里盯的是 selectionClick。
    expect(haptics, isNot(contains('HapticFeedbackType.selectionClick')));

    await tester.tap(find.text('未发送，点按重试'));
    await tester.pumpAndSettle();

    expect(haptics, contains('HapticFeedbackType.selectionClick'));
  });
}
