// 会话四态补齐:loading / ready / error / missing / closed。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.js` 的 loadState + _setMessageLoadError
//      + `tests/unit/im-uiux-recovery-contract.test.js`(关闭的组局 = 终态,不是网络错误)。
//
// ★ 此前 App 只有 loading / error / empty 三条:坏链接、组局已结束、
//   真的没消息,三种状态全渲染成「还没有消息」——用户以为自己发丢过消息。

import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_chat_test_support.dart';

void main() {
  testWidgets('missing:没有会话 id = 坏链接,不打后端也不给可用输入栏', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    await pumpChat(tester, api: api, conversationId: 0, peerName: '');

    expect(find.text('这个会话打不开'), findsOneWidget);
    expect(find.text('链接可能已失效，回消息列表重新进入'), findsOneWidget);
    expect(find.text('还没有消息'), findsNothing, reason: '坏链接不是「空对话」');
    expect(api.calls, isEmpty, reason: '没有 conversation_id,不该拿 0 去打后端');
    expect(find.text('会话不可用'), findsOneWidget, reason: '输入框要看得出来点不动');
    expect(find.text('链接已失效，回消息列表重新进入'), findsOneWidget);
  });

  testWidgets('closed:组局已结束是终态,给返回消息列表的出口', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => throw const ImApiException(
      '该组局已结束，聊天已关闭',
      errorCode: 'HANGOUT_CLOSED',
    );
    await pumpChatRouted(tester, api: api);

    expect(find.text('这个组局已结束'), findsOneWidget);
    expect(
      find.text('聊天已关闭。如有平台处置，可在消息列表的系统通知中查看处理结果。'),
      findsOneWidget,
    );
    expect(find.text('组局已结束，不能继续聊天'), findsOneWidget);
    expect(find.text('会话不可用'), findsOneWidget);

    final int before = api.calls.length;
    await tester.pump(const Duration(seconds: 9));
    expect(
      api.calls.length,
      before,
      reason: '已结束的组局不会再变,轮询必须停 —— 否则每 8 秒白打一次后端',
    );

    await tester.tap(find.text('返回消息列表'));
    await tester.pumpAndSettle();
    expect(find.text('消息列表'), findsOneWidget);
  });

  testWidgets('负控:普通失败不能被当成「组局已结束」', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => throw Exception('网络断了');
    await pumpChat(tester, api: api);

    expect(find.text('这个组局已结束'), findsNothing);
    expect(find.text('消息没加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('消息没加载出来，点上方「重试」再试'), findsOneWidget);
  });

  testWidgets('「重试」真的重新拉一次(失败不是死胡同)', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    int calls = 0;
    api.onMessages = (_, _) async {
      calls += 1;
      if (calls == 1) throw Exception('网络断了');
      return ChatPage(
        list: <ChatMessage>[msg(1, content: '在的,几点集合?')],
      );
    };
    await pumpChat(tester, api: api);

    expect(find.text('消息没加载出来'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('在的,几点集合?'), findsOneWidget);
    expect(find.text('消息没加载出来'), findsNothing);
    expect(find.text('发消息...'), findsOneWidget, reason: '恢复成 ready 后输入栏要活过来');
  });

  testWidgets('ready 的空会话才是「还没有消息」', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(list: <ChatMessage>[]);
    await pumpChat(tester, api: api);

    expect(find.text('还没有消息'), findsOneWidget);
    expect(find.text('这个会话打不开'), findsNothing);
    expect(find.text('发消息...'), findsOneWidget);
    expect(find.text('会话不可用'), findsNothing);
  });

  testWidgets('轮询读到消息后,错误态自动解开(不用用户手点重试)', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    int calls = 0;
    api.onMessages = (cursorId, size) async {
      calls += 1;
      if (calls == 1) throw Exception('网络断了');
      return ChatPage(list: <ChatMessage>[msg(1, content: '刚连上')]);
    };
    await pumpChat(tester, api: api);
    expect(find.text('消息没加载出来'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();

    expect(find.text('刚连上'), findsOneWidget);
    expect(find.text('消息没加载出来'), findsNothing);
  });
}
