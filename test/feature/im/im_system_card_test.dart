// 系统卡(`cardType:generic`)—— 本轮最扎眼的一处占位气泡。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.wxml` 92-113(通用卡分支)
//      + `index.js` 的 decorate / onCardTap / onCardBtn。
//
// ★ 三条判据各有一个负控:
//   · 处理结果按钮**只认系统发的卡**(senderId=0)—— extra_json 是发送方可控字段;
//   · 按钮的 action 只有 `/` 开头才跳,否则提示「已处理」;
//   · 一个字段都渲不出来的卡仍然退回占位气泡(不装成一张空壳卡)。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'im_chat_test_support.dart';

const String _plainCard =
    '{"cardType":"generic","title":"举报处理结果",'
    '"sub":"你举报的内容已处理","meta":"2026-09-17 已处置"}';

const String _resultCard =
    '{"cardType":"generic","title":"通知",'
    '"result":{"taskId":11,"bizId":22,"outcome":"已删除该条评论",'
    '"reason":"含有违法违规内容","followUp":"如有疑问可联系客服"}}';

/// 只认 click 回流的方法,其余交给 noSuchMethod。
class _FakeOfficialApi implements OfficialApi {
  final List<int> clicks = <int>[];

  @override
  Future<void> reportBroadcastClick(int broadcastId, {String? channel}) async {
    clicks.add(broadcastId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpCard(
  WidgetTester tester,
  String extraJson, {
  int senderId = 0,
  String? content = '[卡片]',
  List<RouteBase> routes = const <RouteBase>[],
  _FakeOfficialApi? official,
}) async {
  final FakeImChatApi api = FakeImChatApi();
  api.onMessages = (_, _) async => ChatPage(
    list: <ChatMessage>[
      msg(
        1,
        senderId: senderId,
        msgType: kMsgCard,
        content: content,
        extraJson: extraJson,
      ),
    ],
  );
  await pumpChatRouted(
    tester,
    api: api,
    extraRoutes: routes,
    extra: <dynamic>[
      if (official != null) officialApiProvider.overrideWithValue(official),
    ],
  );
}

void main() {
  testWidgets('系统卡渲染标题 / 副标题 / meta —— 不再是占位气泡', (tester) async {
    await _pumpCard(tester, _plainCard);

    expect(find.text('举报处理结果'), findsOneWidget);
    expect(find.text('你举报的内容已处理'), findsOneWidget);
    expect(find.text('2026-09-17 已处置'), findsOneWidget);
    expect(
      find.textContaining('显示不了'),
      findsNothing,
      reason: '认得出的卡片不能再落到「不认识的类型」兜底',
    );
  });

  testWidgets('处理结果按钮只在系统发的卡上出现(用户发的同名卡片没有)', (tester) async {
    await _pumpCard(tester, _resultCard, senderId: 0);
    expect(find.text('查看处理结果'), findsOneWidget);

    await _pumpCard(tester, _resultCard, senderId: 5);
    expect(
      find.text('查看处理结果'),
      findsNothing,
      reason: 'extra_json 是发送方可控字段;不判发送方,人就能自己伪造一张平台处置卡',
    );
  });

  testWidgets('查看处理结果 → 打开处理结果面板(任务/业务/结论/原因/后续)', (tester) async {
    await _pumpCard(tester, _resultCard);

    await tester.tap(find.text('查看处理结果'));
    await tester.pumpAndSettle();

    expect(find.text('处理结果'), findsOneWidget, reason: '面板标题');
    expect(find.textContaining('审核任务 #11'), findsOneWidget);
    expect(find.text('已删除该条评论'), findsOneWidget);
    expect(find.textContaining('原因：含有违法违规内容'), findsOneWidget);
    expect(find.text('如有疑问可联系客服'), findsOneWidget);
  });

  testWidgets('自定义按钮:站内路径按钮跳到那一页', (tester) async {
    const String json =
        '{"cardType":"generic","title":"同行申请",'
        '"buttons":[{"text":"查看资料","action":"/user/9"}]}';
    await _pumpCard(
      tester,
      json,
      routes: <RouteBase>[
        GoRoute(
          path: '/user/9',
          builder: (_, _) => const Scaffold(body: Text('用户资料页')),
        ),
      ],
    );

    expect(find.text('查看资料'), findsOneWidget);
    await tester.tap(find.text('查看资料'));
    await tester.pumpAndSettle();
    expect(find.text('用户资料页'), findsOneWidget);
  });

  testWidgets('自定义按钮:不是站内路径的动作提示「已处理」,不是死按钮', (tester) async {
    const String json =
        '{"cardType":"generic","title":"同行申请",'
        '"buttons":[{"text":"拒绝","key":"apply.reject","type":"reject"}]}';
    await _pumpCard(tester, json);

    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(
      find.text('已处理'),
      findsOneWidget,
      reason: '按小程序 onCardBtn:非路径动作给一次明确反馈,不能点了什么都不发生',
    );
  });

  testWidgets('只有 action 的卡渲「查看详情」并跳过去', (tester) async {
    await _pumpCard(
      tester,
      '{"cardType":"generic","title":"官方通知","action":"/official/3"}',
      routes: <RouteBase>[
        GoRoute(
          path: '/official/3',
          builder: (_, _) => const Scaffold(body: Text('官方活动页')),
        ),
      ],
    );

    expect(find.text('查看详情'), findsOneWidget);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('官方活动页'), findsOneWidget);
  });

  testWidgets('带 bcId 的官方通知点击回流(best-effort,失败不拦跳转)', (tester) async {
    final _FakeOfficialApi official = _FakeOfficialApi();
    await _pumpCard(
      tester,
      '{"cardType":"generic","title":"官方通知","bcId":7,"action":"/official/3"}',
      official: official,
      routes: <RouteBase>[
        GoRoute(
          path: '/official/3',
          builder: (_, _) => const Scaffold(body: Text('官方活动页')),
        ),
      ],
    );

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(official.clicks, <int>[7]);
    expect(find.text('官方活动页'), findsOneWidget);
  });

  testWidgets('老卡片没有 cardType 但有标题 → 仍渲成系统卡(不判成坏数据)', (tester) async {
    await _pumpCard(tester, '{"title":"历史通知","sub":"这条卡片比 cardType 字段还老"}');

    expect(find.text('历史通知'), findsOneWidget);
    expect(find.text('这条卡片比 cardType 字段还老'), findsOneWidget);
  });

  testWidgets('负控:非站内路径的 action 不跳转、也不炸(extra_json 可控)', (tester) async {
    await _pumpCard(
      tester,
      '{"cardType":"generic","title":"官方通知","action":"https://example.invalid/x"}',
    );

    await tester.tap(find.text('官方通知').first);
    await tester.pumpAndSettle();
    // 不校验的话 GoRouter 会为「没有这条路由」抛异常 —— 而这张卡是
    // 发送方可控的 extra_json,等于让别人决定我这儿崩不崩。
    expect(tester.takeException(), isNull);
    expect(find.text('处理结果'), findsNothing);
  });

  testWidgets('负控:一个字段都渲不出来的卡片退回占位气泡', (tester) async {
    await _pumpCard(tester, '{"cardType":"generic"}', content: null);

    expect(
      find.textContaining('显示不了'),
      findsOneWidget,
      reason: '空壳卡不该渲成一张只有底色的方块 —— 那看起来像渲染坏了',
    );
  });
}
