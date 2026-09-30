// 准实时:停在聊天页时每 8 秒拉一次新消息。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.js` 的
//      `startPoll/stopPoll/pollNew`(onShow 起 8s setInterval,onHide 停;
//        `cursor_id:0, size:15`,只留 id 比本地最大 id 新的)。
//
// ★ 此前 App 只在「进页 / 下拉刷新 / 发完一条」时拉:对方在我盯着页面时
//   发来的消息,要等我自己手动刷一下才出现。

import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_chat_test_support.dart';

void main() {
  testWidgets('停在页面上 8 秒,对方的新消息自己出现', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    List<ChatMessage> server = <ChatMessage>[msg(1, content: '我先到了')];
    api.onMessages = (int cursorId, int size) async =>
        ChatPage(list: server, hasMore: false);

    await pumpChat(tester, api: api);
    expect(find.text('我先到了'), findsOneWidget);
    expect(find.text('路上堵,晚十分钟'), findsNothing);

    // 对方在这 8 秒里发了新消息 —— 客户端没做任何操作。
    server = <ChatMessage>[
      msg(1, content: '我先到了'),
      msg(2, content: '路上堵,晚十分钟', time: '2026-01-15 20:12:00'),
    ];
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('路上堵,晚十分钟'), findsOneWidget);
    expect(
      api.calls.map((MessagesCall c) => c.size).toList(),
      <int>[30, 15],
      reason: '轮询增量页与首屏不是一档(小程序 cursor_id:0, size:15)',
    );
    expect(api.readCalls, isNotEmpty, reason: '读到新消息要顺带标已读');
  });

  testWidgets('负控:不到 8 秒不发请求(轮询不是打点)', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(list: <ChatMessage>[]);

    await pumpChat(tester, api: api);
    final int baseline = api.calls.length;

    await tester.pump(const Duration(seconds: 7));
    expect(api.calls.length, baseline);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(api.calls.length, baseline + 1);
  });

  testWidgets('轮询失败静默:不弹错,也不动已有消息', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    bool failPoll = false;
    api.onMessages = (int cursorId, int size) async {
      if (failPoll) throw Exception('轮询网络断了');
      return ChatPage(list: <ChatMessage>[msg(1, content: '在的')]);
    };

    await pumpChat(tester, api: api);
    failPoll = true;
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('在的'), findsOneWidget);
    expect(find.text('消息没加载出来'), findsNothing, reason: '轮询失败不该把整页打成错误态');
    expect(find.textContaining('轮询网络断了'), findsNothing, reason: '轮询失败不该弹提示');
  });

  testWidgets('轮询不会把已在本地的消息插两遍', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    List<ChatMessage> server = <ChatMessage>[msg(1, content: '同一句')];
    api.onMessages = (_, _) async => ChatPage(list: server);

    await pumpChat(tester, api: api);
    server = <ChatMessage>[
      msg(1, content: '同一句'),
      msg(2, content: '新的一句', time: '2026-01-15 20:11:00'),
    ];
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('同一句'), findsOneWidget);
    expect(find.text('新的一句'), findsOneWidget);
  });
}
