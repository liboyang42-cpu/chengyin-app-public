// 加载更早消息:hasMore + cursor 分页 + 失败重试。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.js` 的 loadMore / _setLoadMoreError
//      + `tests/unit/im-uiux-recovery-contract.test.js`
//        「加载更多单飞,失败保留现有消息与同一游标重试入口」。
//
// ★ 此前 App 只有第一页(size 默认 30),再往前的历史**够不着**;
//   「下拉刷新」只会重新拉最新一页,翻不出更早的。

import 'dart:async';

import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_chat_test_support.dart';

void main() {
  testWidgets('hasMore 时给入口,点了按回执游标往前翻,插在列表**上方**', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (int cursorId, int size) async {
      if (cursorId == 0) {
        return ChatPage(
          list: <ChatMessage>[msg(9, content: '最近的一句')],
          hasMore: true,
          nextCursor: 42,
        );
      }
      return ChatPage(
        list: <ChatMessage>[msg(1, content: '更早的一句')],
        hasMore: false,
        nextCursor: 0,
      );
    };

    await pumpChat(tester, api: api);
    expect(find.text('加载更早消息'), findsOneWidget);

    await tester.tap(find.text('加载更早消息'));
    await tester.pumpAndSettle();

    expect(
      api.calls.map((MessagesCall c) => c.cursorId).toList(),
      <int>[0, 42],
      reason: '第二页必须用回执给的 nextCursor,不能自己 +1 猜',
    );
    expect(find.text('更早的一句'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('更早的一句')).dy <
          tester.getTopLeft(find.text('最近的一句')).dy,
      isTrue,
      reason: '更早的消息要插在上面,顺序错了整条时间线就反了',
    );
    expect(
      find.text('加载更早消息'),
      findsNothing,
      reason: 'hasMore=false 之后不能再摆一个点了没反应的入口',
    );
  });

  testWidgets('没有更多时不摆入口(空会话也一样)', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[msg(1, content: '就这一句')],
      hasMore: false,
    );
    await pumpChat(tester, api: api);

    expect(find.text('加载更早消息'), findsNothing);
    expect(find.text('更早消息没有加载'), findsNothing);
  });

  testWidgets('加载失败:保留现有消息、说清原因、**同一个游标**重试', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (int cursorId, int size) async {
      if (cursorId == 0) {
        return ChatPage(
          list: <ChatMessage>[msg(9, content: '已经看到的话')],
          hasMore: true,
          nextCursor: 42,
        );
      }
      throw Exception('更早消息暂时不可用');
    };

    await pumpChat(tester, api: api);
    await tester.tap(find.text('加载更早消息'));
    await tester.pumpAndSettle();

    expect(find.text('已经看到的话'), findsOneWidget, reason: '失败不能把已有消息吞掉');
    expect(find.text('更早消息没有加载'), findsOneWidget);
    expect(find.text('更早消息暂时不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(
      api.calls.map((MessagesCall c) => c.cursorId).toList(),
      <int>[0, 42, 42],
      reason: '重试必须还是同一个 cursor —— 推进游标会跳着丢一段历史',
    );
  });

  testWidgets('单飞:加载中不重复发请求,且给出「正在加载」的可见反馈', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    final Completer<ChatPage> gate = Completer<ChatPage>();
    api.onMessages = (int cursorId, int size) {
      if (cursorId == 0) {
        return Future<ChatPage>.value(
          ChatPage(
            list: <ChatMessage>[msg(9, content: '最近的一句')],
            hasMore: true,
            nextCursor: 42,
          ),
        );
      }
      return gate.future;
    };

    await pumpChat(tester, api: api);
    await tester.tap(find.text('加载更早消息'));
    await tester.pump();

    expect(find.text('加载更早消息'), findsNothing);
    expect(
      find.byType(CupertinoActivityIndicator),
      findsOneWidget,
      reason: '加载中要有反馈,不能摆着一个还能点的入口',
    );
    expect(
      api.calls.where((MessagesCall c) => c.cursorId == 42).length,
      1,
    );

    gate.complete(
      ChatPage(
        list: <ChatMessage>[msg(1, content: '更早的一句')],
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('更早的一句'), findsOneWidget);
  });
}
