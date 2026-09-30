// 「更多」里的清空聊天。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.js` 的
//      `onMore / onMoreSelect / clearConversation`(moreSheetItems 里的「清空聊天」,
//      `POST /api/im/delete` 成功后回消息列表)。
//
// ★ App 这一格原来什么都没有:聊天页只有导航栏的「拉黑」,
//   清空只能回列表页滑动删除 —— 而人就站在这个会话里。
// ⚠️ 文案与列表页的删除**逐字同口径**(同一个接口、同一件事),
//   而且明确说「不会清除对方消息记录」——不能写成「撤回」。

import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_chat_test_support.dart';

Future<FakeImChatApi> _pump(WidgetTester tester) async {
  final FakeImChatApi api = FakeImChatApi();
  api.onMessages = (_, _) async =>
      ChatPage(list: <ChatMessage>[msg(1, content: '历史消息')]);
  await pumpChatRouted(tester, api: api);
  return api;
}

Future<void> _openClear(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('更多'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('清空聊天'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('更多 → 清空聊天 → 二次确认 → 删会话并回消息列表', (tester) async {
    final FakeImChatApi api = await _pump(tester);
    expect(find.text('历史消息'), findsOneWidget);

    await _openClear(tester);
    expect(
      find.text('删除后不会清除对方消息记录，确定清空这条会话吗？'),
      findsOneWidget,
      reason: '破坏性动作必须二次确认,且说实话:清的是我这一侧',
    );
    expect(api.deleted, isEmpty, reason: '还没确认就不能删');

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(api.deleted, <int>[9]);
    expect(find.text('消息列表'), findsOneWidget, reason: '清完回消息列表,不能停在空壳会话里');
  });

  testWidgets('负控:二次确认点「取消」就不动会话,人还留在聊天页', (tester) async {
    final FakeImChatApi api = await _pump(tester);

    await _openClear(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(api.deleted, isEmpty);
    expect(find.text('历史消息'), findsOneWidget);
    expect(find.text('更多'), findsNothing, reason: '取消后弹层该收掉');
  });

  testWidgets('清空失败如实说,不假装成功', (tester) async {
    final FakeImChatApi api = await _pump(tester);
    api.onMessages = (_, _) async =>
        ChatPage(list: <ChatMessage>[msg(1, content: '历史消息')]);
    // 覆盖 deleteConversation 的实现:抛错。
    api.onDelete = (int id) async => throw Exception('清空失败');

    await _openClear(tester);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('清空失败'), findsOneWidget);
    expect(find.text('历史消息'), findsOneWidget, reason: '没删掉就不能离开会话');
  });
}
