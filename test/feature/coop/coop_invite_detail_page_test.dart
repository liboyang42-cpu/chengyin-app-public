// 协作邀约详情(`pages/coop/invite-detail`)。
//
// 这一页存在的理由就是列表放不下的那两样:**对方给的理由**与**当时的条款快照**;
// 以及小程序裁决 2026-09-15 之后从列表卡搬过来的履约动作(联系合作方 / 申报供给 /
// 评价 / 发件箱的取消合作)。这里逐条盯住「错了会让人做错决定」的地方:
//   · 缺编号 / 编号非法 / 邀约不在这一侧 —— 三种「打不开」不能混成一句「加载失败」;
//   · 撤回不带理由不许发出去(后端也拒);
//   · 已锁价不许发单方取消(后端拒,界面先挡住);
//   · 保证金只给入口 —— 涉资链路在列表那一份,这里不复制第二份。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/feature/coop/coop_invite_detail_page.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeCoopApi implements CoopApi {
  _FakeCoopApi({
    this.listData = const <String, dynamic>{},
    this.throwOnList = false,
    this.credit = const <String, dynamic>{},
    this.reviews = const <String, dynamic>{},
    this.creditError,
    this.reviewError,
  });

  final Map<String, dynamic> listData;
  final bool throwOnList;
  final Map<String, dynamic> credit;
  final Map<String, dynamic> reviews;

  /// 非 null = 对应端点这条失败(b1 报告 P2-2:一条挂不许连坐另一条)。
  final Object? creditError;
  final Object? reviewError;

  /// 信誉浮层是按对方 memberId 查的 —— 查成自己或查成另一侧都是静默的错人。
  final List<int> creditQueried = <int>[];
  final List<int> reviewQueried = <int>[];

  @override
  Future<Map<String, dynamic>> creditSummary({int? memberId}) async {
    creditQueried.add(memberId ?? -1);
    if (creditError != null) throw creditError!;
    return credit;
  }

  @override
  Future<Map<String, dynamic>> reviewSummary(int toId) async {
    reviewQueried.add(toId);
    if (reviewError != null) throw reviewError!;
    return reviews;
  }

  int listCalls = 0;
  final List<(CoopHandleAction, int, String?)> handled =
      <(CoopHandleAction, int, String?)>[];
  int contactCalls = 0;

  @override
  Future<Map<String, dynamic>> inviteList() async {
    listCalls += 1;
    if (throwOnList) throw Exception('协作邀请没加载出来');
    return listData;
  }

  @override
  Future<void> handleInvite({
    required int inviteId,
    required CoopHandleAction action,
    String? reason,
  }) async {
    handled.add((action, inviteId, reason));
  }

  @override
  Future<int> contact(int inviteId) async {
    contactCalls += 1;
    return 77;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _row({
  required int id,
  int status = 0,
  int inviteType = 0,
  String? handleReason,
  bool depositOwed = false,
  double? depositAmount,
  bool termsFrozen = false,
  int? topicId = 12,
  String toType = 'merchant',
}) => <String, dynamic>{
  'id': id,
  'inviteType': inviteType,
  'fromId': 5,
  'toType': toType,
  'toId': 9,
  'status': status,
  'topicId': topicId,
  'shareMode': 2,
  'fixedFee': 15,
  'message': '周六档期可以',
  'handleReason': handleReason,
  'depositOwed': depositOwed,
  'depositAmount': depositAmount,
  'termsFrozen': termsFrozen,
  'partner': <String, dynamic>{
    'name': '黑胶俱乐部',
    // §3.8:联系方式只在已接受(status=1)时由后端下发,待确认的行里本来就没有。
    'leaderName': status == 1 ? '张三' : null,
    'phone': status == 1 ? '13800001111' : null,
  },
  'createTime': '2026-09-10 09:30:00',
};

/// `cyConfirm` 的标题与确认键文案往往一样(「接受合作」/「撤回邀约」),
/// 直接 `find.text` 会同时命中标题与按钮。这里只认按钮那一份。
Finder _dialogButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(CupertinoDialogAction),
);

Map<String, dynamic> _list({
  List<Map<String, dynamic>> received = const [],
  List<Map<String, dynamic>> sent = const [],
}) => <String, dynamic>{'received': received, 'sent': sent};

Widget _app({
  required List<dynamic> overrides,
  String location = '/coop/invite-detail?inviteId=5&box=received',
  bool withList = false,
}) {
  final router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const Text('首页')),
      GoRoute(
        path: '/coop/invite-detail',
        builder: (_, GoRouterState state) => CoopInviteDetailPage(
          inviteId: state.uri.queryParameters['inviteId'],
          box: state.uri.queryParameters['box'] ?? 'received',
        ),
      ),
      if (withList)
        GoRoute(
          path: '/coop/list',
          builder: (_, GoRouterState state) => CoopListPage(
            initialTab: state.uri.queryParameters['tab'] ?? 'received',
          ),
        ),
    ],
  );
  // 「收到的」列表这一档还并了官方邀约那一路(真源 2026-09-15 收编),
  // 不挡掉它会发真的商家请求,pumpAndSettle 永远不静。
  final List<dynamic> scoped = <dynamic>[
    merchantInvitesProvider.overrideWith(
      (ref) async => const <MerchantInvite>[],
    ),
    ...overrides,
  ];
  return ProviderScope(
    overrides: scoped.cast(),
    child: MaterialApp.router(routerConfig: router),
  );
}

/// 详情页是一整条竖排内容(封面 2:1,很占地方)。测试视口默认只有 800×600:
/// 屏外那几张卡**建出来了却算 offstage**,而 `find.text` 默认跳过 offstage ——
/// 断言会莫名其妙地找不到东西。统一给一块够高的画布,让整页都在屏内。
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('★ 待确认(收件箱):状态大字 + 条款 + 留言 + 两个决策按钮', (
    WidgetTester tester,
  ) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5)]),
    );
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('来自 黑胶俱乐部'), findsOneWidget);
    expect(find.text('合作条款'), findsOneWidget);
    // 条款快照是这一页的存档:分润按后端下发的值念,不本地算。
    expect(find.text('固定型 · ¥15.0 / 核销人头'), findsOneWidget);
    expect(find.text('无'), findsOneWidget, reason: '没欠保证金就写「无」,不是空白');
    // 留言与输入框(回复是选填,随接受/拒绝一起发出)。
    expect(find.text('周六档期可以'), findsOneWidget);
    expect(find.text('回复对方(选填，随本次决定一起发出)'), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-accept')), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-reject')), findsOneWidget);
    // 未接受不显示「合作操作」那组履约动作。
    expect(find.text('合作操作'), findsNothing);
    // 联系方式由后端定(§3.8 只在已接受时下发)—— 没下发就照实说明。
    expect(find.text('对方接受后下发(§3.8)'), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-copy-phone')), findsNothing);
  });

  testWidgets('★ 接受合作带上写好的回复(handleReason 走对了字段)', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5)]),
    );
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('coop-detail-draft')), '档期没问题');
    await tester.tap(find.byKey(const Key('coop-detail-accept')));
    await tester.pumpAndSettle();
    // 接受前要确认一句「接受后条款即冻结」。
    await tester.tap(_dialogButton('接受合作'));
    await tester.pumpAndSettle();

    expect(api.handled.single.$1, CoopHandleAction.accept);
    expect(api.handled.single.$2, 5);
    expect(api.handled.single.$3, '档期没问题');
  });

  testWidgets('★★ 撤回必须带理由:空理由连请求都不发', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(sent: <Map<String, dynamic>>[_row(id: 6, topicId: 12)]),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=6&box=sent',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发给 黑胶俱乐部'), findsOneWidget);
    expect(find.text('撤回理由(必填，会发给对方)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coop-detail-withdraw')));
    await tester.pumpAndSettle();
    // 内联错误件的标题 + 说明,两句都在(小程序同一件:title 说该做什么,sub 说为什么)。
    expect(find.text('撤回要写个理由'), findsOneWidget);
    expect(find.text('对方拿着这句话才知道下一步该怎么改。'), findsOneWidget);
    expect(api.handled, isEmpty, reason: '空理由后端会拒,界面先挡住');

    await tester.enterText(find.byKey(const Key('coop-detail-draft')), '档期撞了');
    await tester.tap(find.byKey(const Key('coop-detail-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('撤回邀约'));
    await tester.pumpAndSettle();

    expect(api.handled.single.$1, CoopHandleAction.cancel);
    expect(api.handled.single.$3, '档期撞了');
  });

  testWidgets('★★ 已接受欠保证金:给唯一实心「去缴纳保证金」,并带上履约动作行', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(
        received: <Map<String, dynamic>>[
          _row(id: 7, status: 1, depositOwed: true, depositAmount: 50),
        ],
      ),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=7&box=received',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已接受'), findsOneWidget);
    expect(find.text('锁价后待缴 ¥50 保证金'), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-deposit')), findsOneWidget);
    // 已接受后联系方式才下发,复制入口这时才在。
    expect(find.text('张三 · 13800001111'), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-copy-phone')), findsOneWidget);
    // 从列表卡搬来的履约动作。
    expect(find.text('合作操作'), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-contact')), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-perk')), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-review')), findsOneWidget);
    // 收件箱不给「取消合作」(小程序同此)。
    expect(find.byKey(const Key('coop-detail-cancel')), findsNothing);
  });

  testWidgets('★★ 已锁价:取消合作置灰只做说明,不发单方取消', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(
        sent: <Map<String, dynamic>>[_row(id: 8, status: 1, termsFrozen: true)],
      ),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=8&box=sent',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已锁价，需联系客服'), findsOneWidget);
    expect(find.byKey(const Key('coop-detail-cancel')), findsNothing);
    await tester.tap(find.text('取消合作'));
    await tester.pumpAndSettle();
    expect(find.text('主题已锁价，不能单方取消合作，请联系客服协商'), findsOneWidget);
    expect(api.handled, isEmpty, reason: '后端拒单方取消 —— 不发出去让它拒');
  });

  testWidgets('★★ 发件箱已接受:取消合作先说清退款界,理由必填', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(sent: <Map<String, dynamic>>[_row(id: 11, status: 1)]),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=11&box=sent',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-detail-cancel')));
    await tester.pumpAndSettle();
    // 退款界必须先讲清:锁价开卖前可取消,锁价后只能找客服 —— 用户据此决定要不要取消。
    expect(find.text('锁价开卖前可取消;锁价后需联系客服协商。'), findsOneWidget);
    expect(find.text('请填写取消理由(必填)'), findsOneWidget);
    // 空理由按不动(后端也拒),不会白发一次请求。
    expect(
      tester
          .widget<CupertinoDialogAction>(
            find.byKey(const Key('coop-cancel-confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const Key('coop-cancel-reason')), '档期冲突');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coop-cancel-confirm')));
    await tester.pumpAndSettle();

    // 取消(3)的理由走后端的 `message`,不是 `handleReason`。
    expect(api.handled.single.$1, CoopHandleAction.cancel);
    expect(api.handled.single.$2, 11);
    expect(api.handled.single.$3, '档期冲突');
  });

  testWidgets('★★ 终态:把对方给的理由摆出来,并说明没有可执行的操作', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(
        received: <Map<String, dynamic>>[
          _row(id: 9, status: 2, handleReason: '档期撞了'),
        ],
      ),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=9&box=received',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已拒绝'), findsOneWidget);
    expect(find.text('档期撞了'), findsOneWidget, reason: '这句才是详情页存在的理由');
    expect(find.text('处理理由'), findsOneWidget);
    expect(find.text('这条邀约已失效，没有可执行的操作'), findsOneWidget);
    expect(find.text('这条邀约已失效，不能再留言。'), findsOneWidget);
  });

  testWidgets('★★ 三种「打不开」分开说:缺编号不发请求、不在这一侧给出回列表出口', (
    WidgetTester tester,
  ) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5)]),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('打不开这条邀约'), findsOneWidget);
    expect(find.text('缺少邀约编号，请从协作邀请列表重新进入'), findsOneWidget);
    expect(api.listCalls, 0, reason: '编号都没有,不该发请求');

    // 编号非法(不是数字)也要说清是编号的问题。
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=abc',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('邀约编号无效，请从协作邀请列表重新进入'), findsOneWidget);
    expect(api.listCalls, 0);

    // 编号合法但不在这一侧:不是故障,是它已经不在这里了。
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=404&box=received',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这条邀约不在当前列表里了'), findsOneWidget);
    expect(find.text('回协作邀请'), findsOneWidget);
  });

  testWidgets('★ 加载失败才给重试,且说清是什么没加载出来', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(throwOnList: true);
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('协作详情没加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('★★ 接线:列表卡整卡点进详情,带上编号与收发侧', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5, status: 1)]),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/list',
        withList: true,
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('主题发布者 → 商家'));
    await tester.pumpAndSettle();

    expect(find.text('协作详情'), findsOneWidget, reason: '点了卡就该到详情');
    // 详情是**重新问服务端要的**(列表那一刻的快照不算数),所以列表之外又调了一次。
    expect(api.listCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('★★ 合作方信誉:收件箱按发起方 fromId 查履约与评价', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5, status: 1)]),
      credit: <String, dynamic>{'fulfillmentRate': 96, 'violationCount': 1},
      reviews: <String, dynamic>{
        'summary': <String, dynamic>{'avg': 4.6, 'count': 12},
        'reviews': <dynamic>[],
      },
    );
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();

    // 详情页初次渲染**不该**顺手打这两条 —— 只想看详情的用户不多付两次往返。
    expect(api.creditQueried, isEmpty);
    expect(api.reviewQueried, isEmpty);

    await tester.tap(find.byKey(const Key('coop-detail-peer-credit')));
    await tester.pumpAndSettle();

    expect(api.creditQueried, <int>[5], reason: '收件箱查的是发起方(fromId=5)');
    expect(api.reviewQueried, <int>[5]);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('1 次违约'), findsOneWidget);
    expect(find.text('4.6 分'), findsOneWidget);
    expect(find.text('12 条'), findsOneWidget);
  });

  testWidgets('★ 合作方信誉:发件箱按商家对象的 toId 查', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(sent: <Map<String, dynamic>>[_row(id: 8, status: 1)]),
      credit: <String, dynamic>{'fulfillmentRate': 100},
      reviews: <String, dynamic>{
        'summary': <String, dynamic>{'avg': 5, 'count': 2},
      },
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=8&box=sent',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-detail-peer-credit')));
    await tester.pumpAndSettle();

    expect(api.creditQueried, <int>[9], reason: '发件箱查的是商家对象(toId=9)');
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('5.0 分'), findsOneWidget);
  });

  testWidgets('★ 俱乐部对象没有 memberId 语义:信誉入口整个不给', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(
        sent: <Map<String, dynamic>>[_row(id: 9, status: 1, toType: 'club')],
      ),
    );
    await tester.pumpWidget(
      _app(
        location: '/coop/invite-detail?inviteId=9&box=sent',
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coop-detail-peer-credit')), findsNothing);
    expect(api.creditQueried, isEmpty);
  });

  testWidgets('★ 信誉两端点都空:给明确空态,不拿「—」占位装成数据', (WidgetTester tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5, status: 1)]),
    );
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-detail-peer-credit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('coop-peer-credit-empty')),
      findsOneWidget,
      reason: '查了没有 ≠ 数据坏了,空态要说人话',
    );
    expect(find.text('—'), findsNothing);
  });

  // b1 报告 P2-2:两条端点是两块独立面板,一条挂了就看不出另一条是好的。
  testWidgets('★ 信誉浮层:评价摘要挂了,履约率照常渲染(不连坐)', (tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5, status: 1)]),
      credit: <String, dynamic>{'fulfillmentRate': 96, 'violationCount': 1},
      reviewError: Exception('评价摘要服务没响应'),
    );
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-detail-peer-credit')));
    await tester.pumpAndSettle();

    expect(find.text('96%'), findsOneWidget, reason: '到达的一半不许被丢弃');
    expect(find.text('1 次违约'), findsOneWidget);
    expect(find.text('评价摘要服务没响应'), findsOneWidget);
    expect(
      find.byKey(const Key('coop-peer-credit-review-retry')),
      findsOneWidget,
    );
    // 失败半边不该伪装成整块错误态或空态。
    expect(find.byKey(const Key('coop-peer-credit-error')), findsNothing);
    expect(find.byKey(const Key('coop-peer-credit-empty')), findsNothing);
    expect(find.text('—'), findsNothing, reason: '坏数据不许拿破折号占位');
  });

  testWidgets('★ 信誉浮层:履约率挂了,评价摘要照常渲染(不连坐)', (tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5, status: 1)]),
      creditError: Exception('履约记录没加载出来'),
      reviews: <String, dynamic>{
        'summary': <String, dynamic>{'avg': 4.6, 'count': 12},
      },
    );
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-detail-peer-credit')));
    await tester.pumpAndSettle();

    expect(find.text('4.6 分'), findsOneWidget);
    expect(find.text('12 条'), findsOneWidget);
    expect(find.text('履约记录没加载出来'), findsOneWidget);
    expect(
      find.byKey(const Key('coop-peer-credit-fulfill-retry')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('coop-peer-credit-error')), findsNothing);
  });

  testWidgets('★ 信誉浮层:两条都挂才是整块错误态 + 重试', (tester) async {
    _tallView(tester);
    final api = _FakeCoopApi(
      listData: _list(received: <Map<String, dynamic>>[_row(id: 5, status: 1)]),
      creditError: Exception('履约记录没加载出来'),
      reviewError: Exception('评价摘要服务没响应'),
    );
    await tester.pumpWidget(
      _app(overrides: <dynamic>[coopApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-detail-peer-credit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coop-peer-credit-error')), findsOneWidget);
    expect(find.textContaining('履约记录没加载出来'), findsOneWidget);
    expect(find.textContaining('评价摘要服务没响应'), findsOneWidget);
    expect(find.byKey(const Key('coop-peer-credit-retry')), findsOneWidget);
  });
}
