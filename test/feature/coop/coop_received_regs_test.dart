// /coop/list「收到的」里的**承接报名**块(商家报名承接我主题的节点,跨主题聚合)。
//
// ★ 这一块此前整块缺:App 只做了合作池两路(带队申请),商家的报名没人处理。
//   真源 pages/coop/list/index.js:321-366(取数)· :560(确认占槽)· :684(婉拒)。
//
// ★★ 两条最容易错的地方:
//   · 婉拒的键是 **registrationId**(走 /api/coop/candidates/reject),
//     与婉拒**带队申请**的 /api/coop/pool/decline(键 applyId)是两条路;
//   · 「确认占槽」只占位不成单(§3.6):成功后必须接着把人引到发邀约,
//     只报一句「已确认」会让流程断在「中标了但没合同」。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';

class _FakeCoopApi implements CoopApi {
  _FakeCoopApi({
    this.regs = const <Map<String, dynamic>>[],
    this.applies = const <Map<String, dynamic>>[],
    this.failRegs = false,
    this.rejectError,
  });

  final List<Map<String, dynamic>> regs;
  final List<Map<String, dynamic>> applies;

  /// 可变:用来测「先成功后失败」这种刷新失败但仍有旧快照的情形。
  bool failRegs;
  final Object? rejectError;

  int regsFetches = 0;
  final List<int> rejected = <int>[];
  final List<int> confirmed = <int>[];

  @override
  Future<Map<String, dynamic>> inviteList() async => <String, dynamic>{
    'received': <dynamic>[],
    'sent': <dynamic>[],
  };

  @override
  Future<List<Map<String, dynamic>>> poolReceived() async => applies;

  @override
  Future<List<Map<String, dynamic>>> poolMine() async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> receivedRegistrations() async {
    regsFetches++;
    if (failRegs) throw Exception('承接报名没加载出来');
    return regs;
  }

  @override
  Future<void> rejectCandidate(int registrationId) async {
    if (rejectError != null) throw rejectError!;
    rejected.add(registrationId);
  }

  @override
  Future<void> confirmCandidate(int registrationId) async =>
      confirmed.add(registrationId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> reg({
  int id = 42,
  int auditStatus = 0,
  int? memberId = 9,
  String merchantName = '老王菜馆',
  String topicName = '周末路线',
  String addressName = '老街咖啡门口',
  String merchantMeta = '太平街 12 号',
  int topicId = 8,
}) => <String, dynamic>{
  'id': id,
  'memberId': memberId,
  'auditStatus': auditStatus,
  'merchantName': merchantName,
  'merchantMeta': merchantMeta,
  'addressName': addressName,
  'topicId': topicId,
  'topicName': topicName,
};

Map<String, dynamic> apply() => <String, dynamic>{
  'applyId': 31,
  'topicId': 8,
  'status': 0,
  'clubId': 7,
  'clubName': '夜跑团',
  'topicName': '周末路线',
};

class _FakeOfficialApi implements OfficialApi {
  final List<int> accepted = <int>[];
  final List<int> declined = <int>[];

  @override
  Future<void> respondInvite(int partyId, {required bool accept}) async {
    (accept ? accepted : declined).add(partyId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(
  _FakeCoopApi api, {
  String tab = 'received',
  List<MerchantInvite> official = const <MerchantInvite>[],
  Object? officialError,
  OfficialApi? officialApi,
}) {
  final GoRouter router = GoRouter(
    initialLocation: '/coop/list',
    routes: <RouteBase>[
      GoRoute(
        path: '/coop/list',
        builder: (_, _) => CoopListPage(initialTab: tab),
      ),
      GoRoute(
        path: '/coop/invite/:topicId',
        // 把带过去的参数原样渲染出来,便于断言。
        builder: (_, GoRouterState state) => Text(
          'invite/${state.pathParameters['topicId']}'
          '?type=${state.uri.queryParameters['type']}'
          '&toId=${state.uri.queryParameters['toId']}'
          '&toName=${state.uri.queryParameters['toName']}',
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      coopApiProvider.overrideWithValue(api),
      // 官方邀约是同一页的第四块(另一条端点,走 /api/official/merchant-invites)。
      merchantInvitesProvider.overrideWith((ref) async {
        if (officialError != null) throw officialError;
        return official;
      }),
      if (officialApi != null)
        officialApiProvider.overrideWithValue(officialApi),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Finder _dialogButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(CupertinoDialogAction),
);

void main() {
  testWidgets('★★ 收到的:承接报名按真源字段渲染,只有待调配给按钮', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(
      regs: <Map<String, dynamic>>[
        reg(),
        reg(
          id: 43,
          auditStatus: 2,
          merchantName: '阿香面馆',
          merchantMeta: '城南 3 号',
          addressName: '城南广场',
          topicName: '城市定向夜',
        ),
      ],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('承接报名'), findsOneWidget);
    expect(find.byKey(const Key('coop-reg-42')), findsOneWidget);
    // 分档:待调配 / 已落选,各自的徽章字。
    expect(find.text('待调配'), findsOneWidget);
    expect(find.text('已落选'), findsOneWidget);
    // 字段:商家名 / 商家 meta / 报名地点 / 挂在哪张主题下。
    expect(find.text('老王菜馆'), findsOneWidget);
    expect(find.text('阿香面馆'), findsOneWidget);
    expect(find.text('太平街 12 号'), findsOneWidget);
    expect(find.text('老街咖啡门口'), findsOneWidget);
    expect(find.text('城南广场'), findsOneWidget);
    expect(find.text('周末路线'), findsOneWidget);
    expect(find.text('城市定向夜'), findsOneWidget);

    expect(find.byKey(const Key('coop-reg-reject-42')), findsOneWidget);
    expect(find.byKey(const Key('coop-reg-confirm-42')), findsOneWidget);
    expect(
      find.byKey(const Key('coop-reg-reject-43')),
      findsNothing,
      reason: '已落选还摆按钮,点下去后端必拒',
    );
  });

  testWidgets('★★ 婉拒走 /candidates/reject,键是 registrationId', (
    WidgetTester tester,
  ) async {
    final _FakeCoopApi api = _FakeCoopApi(regs: <Map<String, dynamic>>[reg()]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-reg-reject-42')));
    await tester.pumpAndSettle();
    expect(find.textContaining('婉拒「老王菜馆」'), findsOneWidget);
    await tester.tap(_dialogButton('婉拒'));
    await tester.pumpAndSettle();

    expect(api.rejected, <int>[42]);
    expect(find.text('已婉拒「老王菜馆」'), findsOneWidget);
  });

  testWidgets('★★ 婉拒失败:把后端原话端出来,并把列表回读一次', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(
      regs: <Map<String, dynamic>>[reg()],
      rejectError: Exception('仅主题发布者可婉拒候选'),
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    final int before = api.regsFetches;

    await tester.tap(find.byKey(const Key('coop-reg-reject-42')));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('婉拒'));
    await tester.pumpAndSettle();

    expect(
      find.text('仅主题发布者可婉拒候选'),
      findsOneWidget,
      reason: '说人话、点名失败的是什么 —— 不能吞成「操作失败」',
    );
    expect(
      api.regsFetches,
      greaterThan(before),
      reason: '结果未知要回读,不让人对着旧状态再点一次',
    );
  });

  testWidgets('★★ 有旧快照时刷新失败也要说话,不能只留一排过期的报名', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(
      regs: <Map<String, dynamic>>[reg()],
      rejectError: Exception('仅主题发布者可婉拒候选'),
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coop-reg-42')), findsOneWidget);

    // 这一次回读会失败(真源 :345-351 同款:报错行照显,旧行也还在)。
    api.failRegs = true;
    await tester.tap(find.byKey(const Key('coop-reg-reject-42')));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('婉拒'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coop-reg-42')), findsOneWidget);
    expect(find.text('承接报名没加载出来'), findsOneWidget);
    expect(find.byKey(const Key('coop-regs-retry')), findsOneWidget);
  });

  testWidgets('★★ 确认占槽:调 /candidates/confirm 后把人引到发邀约', (
    WidgetTester tester,
  ) async {
    final _FakeCoopApi api = _FakeCoopApi(regs: <Map<String, dynamic>>[reg()]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-reg-confirm-42')));
    await tester.pumpAndSettle();
    expect(find.textContaining('确认「老王菜馆」占住这个候选位置'), findsOneWidget);
    expect(find.textContaining('他接受后才成合作单'), findsWidgets);
    await tester.tap(_dialogButton('确认'));
    await tester.pumpAndSettle();

    expect(api.confirmed, <int>[42]);
    expect(find.text('已确认「老王菜馆」占住候选位置'), findsOneWidget);

    await tester.tap(_dialogButton('去发邀约'));
    await tester.pumpAndSettle();
    expect(
      find.text('invite/8?type=0&toId=9&toName=老王菜馆'),
      findsOneWidget,
      reason: '占槽只是占位,衔接到带条款的邀约才算把流程接上',
    );
  });

  testWidgets('★ 报名那一路挂了只压它自己:带队申请照常显示', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(
      applies: <Map<String, dynamic>>[apply()],
      failRegs: true,
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('带队申请'), findsOneWidget);
    expect(find.byKey(const Key('coop-apply-31')), findsOneWidget);
    expect(find.text('承接报名没加载出来'), findsOneWidget);
    expect(find.byKey(const Key('coop-regs-retry')), findsOneWidget);
  });

  testWidgets('★ 「我发出的」不请求报名那一路', (WidgetTester tester) async {
    final _FakeCoopApi api = _FakeCoopApi(regs: <Map<String, dynamic>>[reg()]);
    await tester.pumpWidget(_app(api, tab: 'sent'));
    await tester.pumpAndSettle();

    expect(api.regsFetches, 0, reason: '报名是「收到的」口径 —— 发件箱不该白打这一趟');
    expect(find.text('承接报名'), findsNothing);
  });
  testWidgets('★★ 收到的:官方邀约段(来自 平台/报酬/截止),只有待确认才给按钮', (
    WidgetTester tester,
  ) async {
    final _FakeOfficialApi officialApi = _FakeOfficialApi();
    await tester.pumpWidget(
      _app(
        _FakeCoopApi(),
        official: <MerchantInvite>[
          MerchantInvite.fromJson(<String, dynamic>{
            'id': 91,
            'title': '外滩夜行官方场',
            'status': 0,
            'shareMode': 1,
            'shareRate': 15,
            'expireTime': '2026-10-03 23:59:59',
          }),
          MerchantInvite.fromJson(<String, dynamic>{
            'id': 92,
            'title': '已拒的官方场',
            'status': 2,
            'shareMode': 0,
          }),
        ],
        officialApi: officialApi,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('官方邀约'), findsOneWidget);
    expect(find.text('来自 平台'), findsNWidgets(2));
    // 数字状态 → 阶段文案(真源 stageText),不是「待处理」这种泛称。
    expect(find.text('待你确认'), findsOneWidget);
    expect(find.text('已拒绝'), findsOneWidget);
    // 报酬与截止(真源 rewardText / timeText)。
    expect(find.text('分成 15%'), findsOneWidget);
    expect(find.text('资源支持'), findsOneWidget);
    expect(find.text('截止 10月3日'), findsOneWidget);
    // ★ 只有待确认那条摆按钮:已拒的摆上去点了必然失败。
    expect(find.byKey(const Key('coop-official-91')), findsOneWidget);
    expect(find.byKey(const Key('coop-official-92')), findsOneWidget);
    expect(find.text('接受合作'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);

    await tester.tap(find.text('接受合作'));
    await tester.pumpAndSettle();
    expect(officialApi.accepted, <int>[91]);
  });

  testWidgets('★★ 官方邀约没加载出来:点名这一块 + 只有这一块给重试', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(_FakeCoopApi(), officialError: Exception('boom')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coop-official-error')), findsOneWidget);
    expect(find.text('官方邀约没加载出来'), findsOneWidget);
    expect(find.byKey(const Key('coop-official-retry')), findsOneWidget);
    // 别的块好好的,不能被这一块拖成整页错误。
    expect(find.text('还没有收到协作邀请'), findsNothing);
  });
}
