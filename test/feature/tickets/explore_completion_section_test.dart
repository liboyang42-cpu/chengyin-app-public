// 完局面这一块在订单详情里的显隐与三卡文案(P2-6 收真源)。
//
// ★★★ 后端对非探索票是 **fail-closed**:返「该订单没有探店日完局面」
//   而不是空壳。后端注释说明了为什么:「空壳会让 ①② 的订单详情
//   也渲染出一块『图鉴 0/0』的假读面」。
//   ⇒ 前端出错必须**整块收起**。渲成错误卡或空态,都等于把那道闸又打开。
//
// 文案与动作逐字钉真源 `components/cy/scene-member-order-detail`:
//   · 三卡标题「探店图鉴 / 通关奖励 / 下次再来」;
//   · revisit-actions 只有「关注主办俱乐部 / 加入俱乐部」两颗钮(没有看俱乐部入口);
//   · joinClub 回执分两种:state==='joined' →「已加入俱乐部」,否则「申请已提交，等待主理人审核」;
//   · revisit-next:没有下期也占行,写「下一期开售后会在这里出现」且点不动。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/feature/tickets/explore_completion_section.dart';

class _FakeApi implements RegistrationApi {
  _FakeApi({this.data, this.err});
  final Map<String, dynamic>? data;
  final Object? err;
  int followCalls = 0;

  @override
  Future<Map<String, dynamic>> exploreCompletion(int id) async {
    if (err != null) throw err!;
    return data ?? <String, dynamic>{};
  }

  @override
  Future<bool> toggleFollow(int followMemberId) async {
    followCalls++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeClubApi implements ClubApi {
  _FakeClubApi({this.state});
  final String? state;
  int joinCalls = 0;

  @override
  Future<String?> join(int clubId) async {
    joinCalls++;
    return state;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, _FakeApi api, {_FakeClubApi? club}) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  final router = GoRouter(
    initialLocation: '/x',
    routes: <RouteBase>[
      GoRoute(
        path: '/x',
        builder: (_, _) => const SingleChildScrollView(
          child: ExploreCompletionSection(registrationId: 1),
        ),
      ),
      GoRoute(
        path: '/topic/:id',
        builder: (_, GoRouterState s) =>
            Scaffold(body: Text('topic-${s.pathParameters['id']}')),
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      // ★★★ 必须带上 App 的重试策略。不带的话走 Riverpod 3 默认值:
      //   业务失败会被自动重试,状态停在 AsyncLoading ⇒ 整块渲染为空,
      //   于是「非探索票整块消失」这条断言**恒真**——它第一版就是这么空过的
      //   (负控注入了一张错误卡,测试照样绿,因为压根没走到 error 分支)。
      retry: chengyinRetry,
      overrides: <dynamic>[
        registrationApiProvider.overrideWithValue(api),
        clubApiProvider.overrideWithValue(club ?? _FakeClubApi()),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await t.pumpAndSettle();
}

Map<String, dynamic> _revisit({
  bool joined = false,
  bool followed = false,
  Object? clubLeaderMemberId = 5,
  Map<String, dynamic>? nextEdition,
}) => <String, dynamic>{
  'revisit': <String, dynamic>{
    'clubId': 7,
    'clubName': '夜骑俱乐部',
    'joined': joined,
    'followed': followed,
    if (clubLeaderMemberId != null) 'clubLeaderMemberId': clubLeaderMemberId,
    if (nextEdition != null) 'nextEdition': nextEdition,
  },
};

void main() {
  testWidgets('★★★ 非探索票被拒 ⇒ 整块消失,不留任何痕迹', (WidgetTester t) async {
    await _pump(t, _FakeApi(err: Exception('该订单没有探店日完局面')));
    expect(find.text('探店图鉴'), findsNothing);
    expect(find.textContaining('图鉴'), findsNothing);
    expect(
      find.textContaining('失败'),
      findsNothing,
      reason: '连错误卡都不该有 —— 对 ①② 的订单这不是错误,是"本来就没有"',
    );
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('★★ 走完了、奖励已到账:逐条列出,没数量的不显示数字', (WidgetTester t) async {
    await _pump(
      t,
      _FakeApi(
        data: <String, dynamic>{
          'completed': true,
          'requiredChapterCount': 2,
          'redeemedChapterCount': 2,
          'stamps': <dynamic>[
            <String, dynamic>{
              'chapterId': 1,
              'title': '静安咖啡',
              'collected': true,
            },
            <String, dynamic>{'chapterId': 2, 'collected': true},
          ],
          'awards': <String, dynamic>{
            'credited': true,
            'items': <dynamic>[
              <String, dynamic>{'kind': 'BADGE', 'title': '静安夜行徽章'},
              <String, dynamic>{'kind': 'POINTS', 'title': '积分', 'amount': 120},
            ],
          },
        },
      ),
    );
    expect(find.text('已集齐 2/2'), findsOneWidget);
    expect(find.text('章节 2'), findsOneWidget, reason: '没标题要用章节号兜底');
    expect(find.text('+120'), findsOneWidget);
    expect(find.text('静安夜行徽章'), findsOneWidget);
    expect(find.text('+0'), findsNothing, reason: '勋章没有"数量",别编一个 0 出来');
  });

  testWidgets('★★ 还没走完:说清还差什么,而不是「暂无奖励」', (WidgetTester t) async {
    await _pump(
      t,
      _FakeApi(
        data: <String, dynamic>{
          'completed': false,
          'requiredChapterCount': 4,
          'redeemedChapterCount': 1,
        },
      ),
    );
    expect(find.text('走完全部 4 家店后发放'), findsOneWidget);
    expect(find.text('已集齐 1/4'), findsOneWidget);
  });

  testWidgets('★ 三卡标题逐字真源:探店图鉴 / 通关奖励 / 下次再来(旧自造文案不许回来)', (
    WidgetTester t,
  ) async {
    await _pump(t, _FakeApi(data: _revisit()));
    expect(find.text('探店图鉴'), findsOneWidget);
    expect(find.text('通关奖励'), findsOneWidget);
    expect(find.text('下次再来'), findsOneWidget);
    expect(find.text('这次的收获'), findsNothing);
    expect(find.text('再来一次'), findsNothing);
  });

  testWidgets('★ 没有 leaderMemberId 时不给关注钮,但加入钮照给(真源 canJoin=!joined)', (
    WidgetTester t,
  ) async {
    await _pump(t, _FakeApi(data: _revisit(clubLeaderMemberId: null)));
    expect(find.text('夜骑俱乐部'), findsOneWidget);
    expect(
      find.byKey(const Key('explore-follow-club')),
      findsNothing,
      reason: '关注接口要 member id,没有它这个钮点下去必然失败',
    );
    expect(find.byKey(const Key('explore-join-club')), findsOneWidget);
    // 真源 revisit-actions 只有两颗钮;"看俱乐部"是自造的,收掉了。
    expect(find.text('看俱乐部'), findsNothing);
    expect(find.text('查看俱乐部'), findsNothing);
  });

  testWidgets('★ 已入团的票不再给加入钮(真源 joined ⇒ canJoin=false)', (
    WidgetTester t,
  ) async {
    await _pump(t, _FakeApi(data: _revisit(joined: true)));
    expect(find.byKey(const Key('explore-join-club')), findsNothing);
    expect(find.text('加入俱乐部'), findsNothing);
  });

  testWidgets('加入:公开团直进说「已加入俱乐部」,钮撤下;pending 不许显示成已入群', (WidgetTester t) async {
    final club = _FakeClubApi(state: 'joined');
    await _pump(
      t,
      _FakeApi(data: _revisit(clubLeaderMemberId: null)),
      club: club,
    );
    await t.tap(find.byKey(const Key('explore-join-club')));
    await t.pumpAndSettle();
    expect(club.joinCalls, 1);
    expect(find.text('已加入俱乐部'), findsOneWidget);
    expect(find.text('申请已提交，等待主理人审核'), findsNothing);
    expect(find.byKey(const Key('explore-join-club')), findsNothing);
  });

  testWidgets('加入:私密团进待审要说「申请已提交，等待主理人审核」', (WidgetTester t) async {
    final club = _FakeClubApi(state: 'pending');
    await _pump(
      t,
      _FakeApi(data: _revisit(clubLeaderMemberId: null)),
      club: club,
    );
    await t.tap(find.byKey(const Key('explore-join-club')));
    await t.pumpAndSettle();
    expect(find.text('申请已提交，等待主理人审核'), findsOneWidget);
    expect(find.text('已加入俱乐部'), findsNothing);
  });

  testWidgets('关注成功:真源只 toast「已关注」,不常驻状态文字;钮撤下', (WidgetTester t) async {
    final api = _FakeApi(data: _revisit(joined: true));
    await _pump(t, api);
    await t.tap(find.byKey(const Key('explore-follow-club')));
    await t.pumpAndSettle();
    expect(api.followCalls, 1);
    expect(find.text('已关注'), findsOneWidget); // toast 在场
    expect(find.text('关注主办俱乐部'), findsNothing);
    // toast 自动收起后屏幕上不留常驻的「已关注」文字(真源无此状态行)。
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.text('已关注'), findsNothing);
  });

  testWidgets('下期回访行:有下期 → 名字 · MM-DD 开场,点了进主题详情;没下期 → 占行文案且点不动', (
    WidgetTester t,
  ) async {
    await _pump(
      t,
      _FakeApi(
        data: _revisit(
          joined: true,
          followed: true,
          clubLeaderMemberId: null,
          nextEdition: <String, dynamic>{
            'topicId': 88,
            'name': '静安探店日 · 第二期',
            'startDate': '2026-10-01 14:00:00',
          },
        ),
      ),
    );
    expect(find.text('静安探店日 · 第二期 · 10-01 开场'), findsOneWidget);
    await t.tap(find.byKey(const Key('explore-next-edition')));
    await t.pumpAndSettle();
    expect(find.text('topic-88'), findsOneWidget);

    await _pump(
      t,
      _FakeApi(data: _revisit(joined: true, clubLeaderMemberId: null)),
    );
    expect(find.text('下一期开售后会在这里出现'), findsOneWidget);
    await t.tap(find.byKey(const Key('explore-next-edition')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('topic-'),
      findsNothing,
      reason: 'goNextEdition 对无下期原地不动',
    );
  });

  // ★★ 前置判据:只对「已支付的 ③ 探索票」发这个请求。
  //   小程序注释原话:「无条件拉 = 每笔订单白查五张表」。
  //   这条锁的是**有没有发请求**,不是"发了被拒之后长什么样"。
  test('★★ 非 ③ / 未支付的票根本不发这个请求', () {
    final String code = File(
      'lib/feature/tickets/ticket_detail_page.dart',
    ).readAsStringSync();
    final int at = code.indexOf('ExploreCompletionSection(');
    expect(at, greaterThan(0), reason: '找不到这块 —— 断言写法失效了');
    final String guard = code.substring((at - 200).clamp(0, code.length), at);
    expect(
      guard.contains('registrationStatus == 2'),
      isTrue,
      reason: '未支付的单也去拉 —— 后端只会给空壳,白查五张表',
    );
    expect(
      guard.contains('entitlements.isNotEmpty'),
      isTrue,
      reason: '①② 的票也去拉 —— 每开一张普通票都白打一次必然被拒的请求',
    );
  });
}
