// 连续图片合成一组(D9:会话内容页的图片网格)。
//
// ★ 小程序 im/chat 是一条图片 = 一个气泡竖着排;一次发四张就占满整屏,
//   而且看不出"这是一组"。App 侧按「信息」的做法合成分组网格。
//
// ⚠️ 单张**必须**走原来的单图路径 —— 这条同时是基准图(page_im_chat.png
//   里只有一张图)不被动到的保证。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeImApi implements ImApi {
  _FakeImApi(this._page);
  final ChatPage _page;

  @override
  Future<ChatPage> messages(
    int conversationId, {
    int cursorId = 0,
    int size = 30,
  }) async => _page;

  @override
  Future<void> read(int conversationId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChatMessage _img(int id, {int senderId = 2}) => ChatMessage(
  id: id,
  conversationId: 9,
  senderId: senderId,
  msgType: kMsgImage,
  content: 'https://example.invalid/$id.png',
  createTime: '2026-01-15 20:1$id:00',
);

Future<void> _pump(WidgetTester tester, List<ChatMessage> msgs) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        imApiProvider.overrideWithValue(_FakeImApi(ChatPage(list: msgs))),
      ].cast(),
      child: const MaterialApp(
        home: ImChatPage(conversationId: 9, peerName: '小李', peerMemberId: 2),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('同一人连发三张图 = 一条分组消息，带张数语义', (WidgetTester tester) async {
    await _pump(tester, <ChatMessage>[_img(1), _img(2), _img(3)]);

    expect(find.bySemanticsLabel('图片消息，共 3 张'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('单张图不分组（走原来的单图气泡）', (WidgetTester tester) async {
    await _pump(tester, <ChatMessage>[_img(1)]);

    expect(find.bySemanticsLabel('图片消息，共 1 张'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('两个人各发一张相邻的图，不合成一组', (WidgetTester tester) async {
    await _pump(tester, <ChatMessage>[
      _img(1, senderId: 2),
      _img(2, senderId: 3),
    ]);

    expect(find.bySemanticsLabel('图片消息，共 2 张'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('文本把图片序列切开', (WidgetTester tester) async {
    await _pump(tester, <ChatMessage>[
      _img(1),
      ChatMessage(
        id: 2,
        conversationId: 9,
        senderId: 2,
        msgType: kMsgText,
        content: '看这两张',
        createTime: '2026-01-15 20:12:00',
      ),
      _img(3),
    ]);

    expect(find.bySemanticsLabel('图片消息，共 2 张'), findsNothing);
    expect(find.text('看这两张'), findsOneWidget);
  });
}
