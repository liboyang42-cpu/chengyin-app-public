// 气泡不许出现「空壳」。
//
// ★★ 整页渲染时看图发现的:content 为 null 的文本消息渲染成一个
//   什么都没有的小圆角块 —— 看起来像渲染坏了,而不像「这条消息没内容」。
//   `message.content ?? ''` 就是这个来源。
//
// ★ 同一个分支还接住了**未知 msgType**:isText/isImage 都为 false 时
//   会掉进文本分支。后端将来加一种消息类型(语音/系统卡),
//   老版本 App 就会给用户一排空气泡,而不是「这条看不了,去更新」。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';

class _FakeImApi implements ImApi {
  _FakeImApi(this._page);
  final ChatPage _page;
  @override
  Future<ChatPage> messages(int conversationId,
          {int cursorId = 0, int size = 30}) async =>
      _page;
  @override
  Future<void> read(int conversationId) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, List<ChatMessage> msgs) async {
  await t.binding.setSurfaceSize(const Size(390, 800));
  await t.pumpWidget(ProviderScope(
    overrides: <dynamic>[
      imApiProvider.overrideWithValue(_FakeImApi(ChatPage(list: msgs))),
    ].cast(),
    child: const MaterialApp(
      home: ImChatPage(conversationId: 9, peerName: '小李', peerMemberId: 2),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★ content 为空的文本消息不渲染成空气泡', (WidgetTester t) async {
    await _pump(t, <ChatMessage>[
      ChatMessage(id: 1, conversationId: 9, senderId: 2, msgType: kMsgText),
    ]);
    expect(find.text('[消息为空]'), findsOneWidget,
        reason: '空内容渲染成了一个没有字的圆角块 —— 看着像渲染坏了');
  });

  testWidgets('★★ 未知 msgType 说清楚,而不是掉进文本分支变空气泡',
      (WidgetTester t) async {
    await _pump(t, <ChatMessage>[
      ChatMessage(
        id: 1,
        conversationId: 9,
        senderId: 2,
        msgType: 99, // 后端将来新增的类型
        content: '{"card":"..."}',
      ),
    ]);
    expect(find.text('[这条消息当前版本显示不了]'), findsOneWidget,
        reason: '未知类型被当文本渲染 —— 用户会看到一段 JSON 或一个空壳');
    expect(find.textContaining('card'), findsNothing,
        reason: '不许把原始载荷直接摊给用户看');
  });

  testWidgets('★ 正常文本照旧', (WidgetTester t) async {
    await _pump(t, <ChatMessage>[
      ChatMessage(
        id: 1,
        conversationId: 9,
        senderId: 2,
        msgType: kMsgText,
        content: '周六见',
      ),
    ]);
    expect(find.text('周六见'), findsOneWidget);
    expect(find.text('[消息为空]'), findsNothing);
  });
}
