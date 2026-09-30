// 合作邀约页里的「带队申请」两路(`/api/coop/pool/received` / `/mine`)。
//
// ★★ 这一块的核心风险是**摆错按钮**:同一行申请在两个箱子里可达的动作不同
//   (真源 utils/coop-invite-view.js:160 起):
//     · 我收到的 → 拒绝 / 回邀约;
//     · 我发出的 → 撤回,而且撤回的键是 **topicId**(不是申请 id)。
//   摆错的后果不是报错,是"点了没反应"。
//
// ★ 真源:pages/coop/list/index.js:264/270(两路)、:420-424(撤回)、
//   :456 / candidates:402-406(婉拒 + scope)。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';

class _FakeCoopApi implements CoopApi {
  _FakeCoopApi({
    this.received = const <Map<String, dynamic>>[],
    this.mine = const <Map<String, dynamic>>[],
    this.failReceived = false,
    this.sentInvites = const <Map<String, dynamic>>[],
    this.receivedInvites = const <Map<String, dynamic>>[],
  });

  final List<Map<String, dynamic>> received;
  final List<Map<String, dynamic>> mine;
  final bool failReceived;

  /// 邀约两路(/api/coop/list 的 sent/received)—— 本文件主体是
  /// 带队申请,默认给空,「再邀别人」那组测试才往里塞行。
  final List<Map<String, dynamic>> sentInvites;
  final List<Map<String, dynamic>> receivedInvites;

  int? withdrawnTopicId;
  int? declinedApplyId;
  String? declinedScope;

  @override
  Future<Map<String, dynamic>> inviteList() async => <String, dynamic>{
    'received': receivedInvites,
    'sent': sentInvites,
  };

  @override
  Future<List<Map<String, dynamic>>> poolReceived() async {
    if (failReceived) throw Exception('申请没加载出来');
    return received;
  }

  @override
  Future<List<Map<String, dynamic>>> poolMine() async => mine;

  // 承接报名是另一路(「收到的」):本文件只测带队申请,这里回空即可。
  @override
  Future<List<Map<String, dynamic>>> receivedRegistrations() async =>
      const <Map<String, dynamic>>[];

  @override
  Future<void> withdraw(int topicId) async => withdrawnTopicId = topicId;

  @override
  Future<void> declineApply(int applyId, {String? scope}) async {
    declinedApplyId = applyId;
    declinedScope = scope;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> row({
  int applyId = 31,
  int topicId = 8,
  int status = 0,
  int? clubId = 7,
  String clubName = '夜跑团',
  String? scope,
}) => <String, dynamic>{
  'applyId': applyId,
  'topicId': topicId,
  'status': status,
  'clubId': clubId,
  'clubName': clubName,
  'merchantNick': '老街咖啡',
  'topicName': '周末路线',
  'scope': scope,
};

Widget _app(_FakeCoopApi api, {String tab = 'received'}) {
  final GoRouter router = GoRouter(
    initialLocation: '/coop/list',
    routes: <RouteBase>[
      GoRoute(
        path: '/coop/list',
        builder: (_, _) => CoopListPage(initialTab: tab),
      ),
      GoRoute(
        path: '/coop/invite/:topicId',
        // 把回邀约带过去的参数原样渲染出来,便于断言。
        builder: (_, GoRouterState state) => Text(
          'invite/${state.pathParameters['topicId']}'
          '?toId=${state.uri.queryParameters['toId']}'
          '&originApplyId=${state.uri.queryParameters['originApplyId']}'
          '&scope=${state.uri.queryParameters['scope']}',
        ),
      ),
      GoRoute(
        path: '/coop/nearby',
        builder: (_, GoRouterState state) =>
            Text('nearby?topicId=${state.uri.queryParameters['topicId']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      coopApiProvider.overrideWithValue(api),
      // 「收到的」这一档还并了官方邀约那一路(真源 2026-09-15 收编),
      // 不挡掉它会去发真的商家请求,pumpAndSettle 永远不静。
      merchantInvitesProvider.overrideWith(
        (ref) async => const <MerchantInvite>[],
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Finder _dialogButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(CupertinoDialogAction),
);

void main() {
  testWidgets('★★ 我收到的:申请卡带「拒绝」与「回邀约」', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(
      received: <Map<String, dynamic>>[row()],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('带队申请'), findsOneWidget);
    expect(find.byKey(const Key('coop-apply-31')), findsOneWidget);
    expect(find.text('来自 夜跑团'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.byKey(const Key('coop-apply-decline-31')), findsOneWidget);
    expect(find.byKey(const Key('coop-apply-reply-31')), findsOneWidget);
    expect(
      find.byKey(const Key('coop-apply-withdraw-31')),
      findsNothing,
      reason: '撤回是"我发出的"才有的动作',
    );
  });

  testWidgets('★★ 拒绝走 /decline,键是 applyId,且带上行上的 scope', (
    WidgetTester tester,
  ) async {
    final _FakeCoopApi api = _FakeCoopApi(
      received: <Map<String, dynamic>>[row(scope: 'MERCHANT')],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-apply-decline-31')));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('拒绝'));
    await tester.pumpAndSettle();

    expect(api.declinedApplyId, 31);
    expect(
      api.declinedScope,
      'MERCHANT',
      reason: '商家员工处理 owner 主题的申请,漏了 scope 会被判成无权处理',
    );
  });

  testWidgets('★★ 回邀约把 topicId / toId / originApplyId / scope 都带过去', (
    WidgetTester tester,
  ) async {
    final _FakeCoopApi api = _FakeCoopApi(
      received: <Map<String, dynamic>>[row(scope: 'MERCHANT')],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-apply-reply-31')));
    await tester.pumpAndSettle();

    expect(
      find.text('invite/8?toId=7&originApplyId=31&scope=MERCHANT'),
      findsOneWidget,
      reason: '少任一个参数,发出去的邀约要么溯源不上、要么被判无权处理',
    );
  });

  testWidgets('★★ 我发出的:只有「撤回申请」,且回传的是 topicId', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(mine: <Map<String, dynamic>>[row()]);
    await tester.pumpWidget(_app(api, tab: 'sent'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coop-apply-withdraw-31')), findsOneWidget);
    expect(find.byKey(const Key('coop-apply-decline-31')), findsNothing);
    expect(find.byKey(const Key('coop-apply-reply-31')), findsNothing);
    expect(find.text('发给 老街咖啡'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coop-apply-withdraw-31')));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('撤回'));
    await tester.pumpAndSettle();

    expect(
      api.withdrawnTopicId,
      8,
      reason: '撤回的键是 topicId(真源钉死);发 applyId 不报错,只是永远撤不掉',
    );
  });

  testWidgets('★ 已处理的申请不摆动作(点了必被拒)', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(
      received: <Map<String, dynamic>>[row(status: 1)],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('已拒绝'), findsOneWidget);
    expect(find.byKey(const Key('coop-apply-decline-31')), findsNothing);
    expect(find.byKey(const Key('coop-apply-reply-31')), findsNothing);
  });

  testWidgets('★★ 申请那一路挂了:只让这一块落错误态,邀约那一路照常', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(failReceived: true);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coop-applies-error')), findsOneWidget);
    expect(find.byKey(const Key('coop-applies-retry')), findsOneWidget);
    expect(
      find.text('还没有收到协作邀请'),
      findsNothing,
      reason: '加载失败说成"还没有"就是把人骗走了 —— 他不会再等',
    );
  });

  testWidgets('★ 两路都空才是真的空态', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_FakeCoopApi()));
    await tester.pumpAndSettle();
    expect(find.text('还没有收到协作邀请'), findsOneWidget);
    expect(find.textContaining('带队申请'), findsWidgets);
  });

  // ── 孤岛链入口:发出的邀约被拒 → 「再邀别人」→ 找商家承接(coop/nearby?topicId)。
  //    真源 pages/coop/list/index.js:617-621 / wxml:190-197。
  Map<String, dynamic> inviteRow({
    int id = 5,
    int inviteType = 0,
    int status = 2,
    int? topicId = 9,
  }) => <String, dynamic>{
    'id': id,
    'inviteType': inviteType,
    'fromId': 7,
    'toType': 'merchant',
    'toId': 8,
    'topicId': topicId,
    'status': status,
    'partner': <String, dynamic>{'name': '静安咖啡'},
  };

  group('再邀别人(coop/nearby 孤岛链)', () {
    testWidgets('发出的被拒卡:事实句 + 按钮,点了带 topicId 去找商家承接', (
      WidgetTester tester,
    ) async {
      final _FakeCoopApi api = _FakeCoopApi(
        sentInvites: <Map<String, dynamic>>[inviteRow()],
      );
      await tester.pumpWidget(_app(api, tab: 'sent'));
      await tester.pumpAndSettle();

      expect(find.text('对方已拒绝，可再邀其他商家。'), findsOneWidget);
      expect(find.byKey(const Key('coop-reinvite-5')), findsOneWidget);

      await tester.tap(find.byKey(const Key('coop-reinvite-5')));
      await tester.pumpAndSettle();
      expect(
        find.text('nearby?topicId=9'),
        findsOneWidget,
        reason: 'topicId 必须一路带着 —— 候选池页已下线,这条是被拒后唯一的活路',
      );
    });

    testWidgets('legacy 只读卡与没主题的行不给入口', (WidgetTester tester) async {
      final _FakeCoopApi api = _FakeCoopApi(
        sentInvites: <Map<String, dynamic>>[
          inviteRow(id: 6, inviteType: 2),
          inviteRow(id: 7, topicId: null),
        ],
      );
      await tester.pumpWidget(_app(api, tab: 'sent'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coop-reinvite-6')), findsNothing);
      expect(find.byKey(const Key('coop-reinvite-7')), findsNothing);
    });

    testWidgets('收到侧不摆「再邀别人」、也不冒充「对方已拒绝」', (WidgetTester tester) async {
      final _FakeCoopApi api = _FakeCoopApi(
        receivedInvites: <Map<String, dynamic>>[inviteRow(id: 8)],
      );
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coop-reinvite-8')), findsNothing);
      expect(
        find.text('对方已拒绝，可再邀其他商家。'),
        findsNothing,
        reason: '收到侧的 status 2 是「我拒了别人」,那句反了就是假话',
      );
    });
  });
}
