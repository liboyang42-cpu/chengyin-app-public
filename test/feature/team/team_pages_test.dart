// 队伍详情 / 加入队伍的结构与状态门禁。
//
// ★ 这两页随 #30 的 4/6 进来,当时没有行为测试;本次收口补上,顺手钉住三处
//   对着小程序快照核出来的差异 —— 三处都是「读错字段/少一档」这种不报错的错:
//     ① 状态文案:小程序 `pages/team/detail/index.js` 的 STATUS_TEXT 是**五档**
//        (招募中/已满员/进行中/已结束/已解散),写成三档会把「进行中」和
//        「已解散」都显示成「已结束」—— 一个还能退队,一个已经没了。
//     ② 「场次开始」:小程序读 `team.expireTime` 再过 formatTime 成人话;
//        读 `startTime` 的话后端不给这个字段,这格永远「待定」。
//     ③ 当前成员数:小程序用服务端 `joinedCount`;用本地成员列表长度会在
//        「刚移出/刚加入还没重拉」时少报一个 —— 而用户正是靠这一格判断还差几个人。

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/feature/team/team_nearby_page.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/feature/team/team_pages.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Map<String, dynamic> _team({
  int status = 0,
  int joinedCount = 2,
  int maxMembers = 4,
  String? expireTime,
  String? startTime,
  String title = '一起出发的玩家队伍',
}) => <String, dynamic>{
  'id': 7,
  'title': title,
  'status': status,
  'joinedCount': joinedCount,
  'maxMembers': maxMembers,
  'inviteCode': 'CODE123',
  'expireTime': ?expireTime,
  'startTime': ?startTime,
};

Map<String, dynamic> _member(int id, {int role = 0, String name = '城瘾玩家'}) =>
    <String, dynamic>{'memberId': id, 'role': role, 'memberName': name};

TeamInfoLoader _info(Map<String, dynamic> payload) =>
    ({int? teamId, String? inviteCode}) async => payload;

/// 同一个 test 里 pump 多次时,页面类型不变会让 Flutter **复用 State**
/// (于是 initState 不再跑、数据不重取,第二次 pump 看到的还是第一次的旧队伍)。
/// 每次 pump 换一把 key,强制重建 —— 这是三处「同一用例里换夹具」的红因。
int _pumpSeq = 0;

class _FakeTeamApi extends TeamMapApi {
  _FakeTeamApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final List<({int teamId, bool inviteOnly})> calls =
      <({int teamId, bool inviteOnly})>[];

  @override
  Future<void> setJoinMode({
    required int teamId,
    required bool inviteOnly,
  }) async {
    calls.add((teamId: teamId, inviteOnly: inviteOnly));
  }
}

Future<void> _pumpDetail(
  WidgetTester tester,
  Map<String, dynamic> payload, {
  List<Map<String, dynamic>> members = const <Map<String, dynamic>>[],
  bool joined = false,
  bool leader = false,
  List<dynamic> overrides = const <dynamic>[],
  // 传了它 = 这一页读队伍注定失败,看的是错误态怎么说话。
  Object? loadError,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        home: TeamDetailPage(
          key: ValueKey<int>(_pumpSeq++),
          teamId: 7,
          loadTeam: loadError == null
              ? _info(<String, dynamic>{
                  'team': payload,
                  'members': members,
                  'joined': joined,
                  'leader': leader,
                })
              : ({int? teamId, String? inviteCode}) async => throw loadError,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpJoin(
  WidgetTester tester,
  Map<String, dynamic> payload, {
  String code = 'CODE123',
  bool joined = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: TeamJoinPage(
          key: ValueKey<int>(_pumpSeq++),
          code: code,
          loadTeam: _info(<String, dynamic>{
            'team': payload,
            'joined': joined,
          }),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★ 状态文案是五档,不许把「进行中」「已解散」压成「已结束」', (
    WidgetTester tester,
  ) async {
    const Map<int, String> expected = <int, String>{
      0: '招募中',
      1: '已满员',
      2: '进行中',
      3: '已结束',
      4: '已解散',
    };
    for (final MapEntry<int, String> entry in expected.entries) {
      await _pumpDetail(tester, _team(status: entry.key));
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: 'status=${entry.key} 该显示「${entry.value}」',
      );
    }
    // 状态未知时不猜(后端将来加档位,宁可显示「状态未知」也不要错报成进行中)。
    await _pumpDetail(tester, _team(status: 9));
    expect(find.text('状态未知'), findsOneWidget);
  });

  testWidgets('★ 状态胶囊:缩成胶囊不撑满整行,且招募中/已满员走 brand 档', (
    WidgetTester tester,
  ) async {
    // 小程序 `.team-status` 是 inline-flex + `status < 2 ? 'live'`(brand-soft
    // 底 + brand 字)。App 侧用 CyTag —— 它内部带 `alignment`,直接放进
    // Align/Column 这种**有界宽**父级会撑满整行,必须由 Row 承载。
    await _pumpDetail(tester, _team(status: 0));
    expect(
      tester.getSize(find.byType(CyTag)).width,
      lessThan(200),
      reason: '胶囊得缩成胶囊;撑满整行说明父级给了有界宽约束',
    );
    expect(tester.widget<CyTag>(find.byType(CyTag)).brand, isTrue);

    await _pumpDetail(tester, _team(status: 3));
    expect(tester.widget<CyTag>(find.byType(CyTag)).brand, isFalse);
  });

  testWidgets('★「场次开始」读 expireTime 并格式化成人话', (WidgetTester tester) async {
    await _pumpDetail(tester, _team(expireTime: '2026-09-20 10:30:00'));
    expect(find.text('9月20日 10:30'), findsOneWidget);
  });

  testWidgets('★ 负控:后端不给 expireTime 时显示「待定」,不许拿 startTime 顶替', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester, _team(startTime: '2026-01-02 03:04:05'));
    expect(find.text('待定'), findsOneWidget);
    expect(find.text('1月2日 03:04'), findsNothing,
        reason: 'startTime 不是「场次开始」的字段,读它等于把别的时刻当场次时间');
  });

  testWidgets('★ 当前成员数用服务端 joinedCount,不是本地列表长度', (
    WidgetTester tester,
  ) async {
    // 服务端说 3 人,本地只回了 1 条(列表还没刷新)。
    await _pumpDetail(
      tester,
      _team(joinedCount: 3),
      members: <Map<String, dynamic>>[_member(11)],
    );
    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.text('1 / 4'), findsNothing,
        reason: '少报成员数会让用户以为还差人,反而去拉更多人');
  });

  testWidgets('没有队员 → 空态文案;没有旁人时不出现「移出」', (WidgetTester tester) async {
    await _pumpDetail(tester, _team(), joined: true, leader: true);
    expect(find.text('还没有队员'), findsOneWidget);
    expect(find.text('把邀请发给同行的朋友，他们加入后会出现在这里'), findsOneWidget);
    expect(find.text('移出'), findsNothing);
  });

  testWidgets('队长可见「移出」;普通队员不可见', (WidgetTester tester) async {
    final List<Map<String, dynamic>> members = <Map<String, dynamic>>[
      _member(11, role: 1, name: '队长甲'),
      _member(12, name: '队员乙'),
    ];
    await _pumpDetail(tester, _team(), members: members, joined: true, leader: true);
    expect(find.text('队长甲'), findsOneWidget);
    expect(find.text('队长'), findsOneWidget);
    expect(find.text('队员乙'), findsOneWidget);
    expect(find.text('队员'), findsOneWidget);
    expect(find.text('移出'), findsOneWidget);

    await _pumpDetail(tester, _team(), members: members, joined: true);
    expect(find.text('移出'), findsNothing,
        reason: '不是队长就没有移人权,摆出来只会通向 403');
  });

  testWidgets('退队 / 解散只在自己是成员且队伍还没结束时出现', (WidgetTester tester) async {
    await _pumpDetail(tester, _team(), joined: true, leader: true);
    expect(find.text('退出并移交队长'), findsOneWidget);
    expect(find.text('解散队伍'), findsOneWidget);
    expect(find.text('退队不会退款；如需退票，请在订单中单独处理。'), findsOneWidget);

    await _pumpDetail(tester, _team(), joined: true);
    expect(find.text('退出队伍'), findsOneWidget);
    expect(find.text('解散队伍'), findsNothing);

    await _pumpDetail(tester, _team(status: 3), joined: true, leader: true);
    expect(find.text('退出队伍'), findsNothing,
        reason: '队伍已结束就不该再有退队入口');
  });

  testWidgets('加入队伍:按状态给「接受邀请并加入 / 队伍已满 / 队伍已结束」', (
    WidgetTester tester,
  ) async {
    await _pumpJoin(tester, _team(status: 0));
    expect(find.text('TEAM INVITATION'), findsOneWidget);
    expect(find.text('接受邀请并加入'), findsOneWidget);

    await _pumpJoin(tester, _team(status: 1));
    expect(find.text('队伍已满'), findsOneWidget);

    await _pumpJoin(tester, _team(status: 3));
    expect(find.text('队伍已结束'), findsOneWidget);

    await _pumpJoin(tester, _team(status: 1), joined: true);
    expect(find.text('查看队伍'), findsOneWidget,
        reason: '已加入的人不该再看到「接受邀请」');
  });

  testWidgets('★ 加入页按钮档位跟真源:「查看队伍」是主档,走不通的那档才是次档', (
    WidgetTester tester,
  ) async {
    // 真源 `pages/team/join/index.wxml`:joined → `team-action primary`,
    // status==0 → `team-action primary`,else → `team-action disabled secondary`。
    // 把「查看队伍」降成灰色 = 告诉用户这条邀请没用了,而他其实已经在队伍里。
    CyNativeButtonRole roleOf(WidgetTester t) =>
        t.widget<CyNativeButton>(find.byType(CyNativeButton)).role;

    await _pumpJoin(tester, _team(status: 0));
    expect(roleOf(tester), CyNativeButtonRole.primary);

    await _pumpJoin(tester, _team(status: 1), joined: true);
    expect(roleOf(tester), CyNativeButtonRole.primary,
        reason: '已加入 → 查看队伍仍是主档');

    await _pumpJoin(tester, _team(status: 1));
    expect(roleOf(tester), CyNativeButtonRole.secondary);
  });

  testWidgets('邀请码缺失 → 明说链接不完整,不装作能加入', (WidgetTester tester) async {
    await _pumpJoin(tester, _team(), code: '  ');
    expect(find.text('邀请链接不完整'), findsOneWidget);
    expect(find.text('接受邀请并加入'), findsNothing);
  });

  testWidgets('★★ 队长 + 服务端下发 joinMode 才画开关,切换走 setJoinMode', (
    WidgetTester tester,
  ) async {
    // 真源 `.team-member-name` 是「公开招募」,开关的**开**=公开(joinMode=2)。
    // 标签写成「仅邀请可加入」会把这一档说反:后端没下发 joinMode 时真源按
    // 「仅邀请」渲染,那句标签就成了反话。
    final _FakeTeamApi api = _FakeTeamApi();
    await _pumpDetail(
      tester,
      _team()..['joinMode'] = 2,
      leader: true,
      joined: true,
      overrides: <dynamic>[teamMapApiProvider.overrideWithValue(api)],
    );
    expect(find.text('公开招募'), findsOneWidget);
    expect(find.text('陌生人可在附近队伍里申请加入'), findsOneWidget);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isTrue,
      reason: 'joinMode=2 = 公开招募 = 开关打开',
    );

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(api.calls.single.teamId, 7);
    expect(api.calls.single.inviteOnly, isTrue, reason: '关掉公开 = 仅邀请');
  });

  testWidgets('★★ joinMode=1(仅邀请)时开关是关的,打开才改回公开', (
    WidgetTester tester,
  ) async {
    final _FakeTeamApi api = _FakeTeamApi();
    await _pumpDetail(
      tester,
      _team()..['joinMode'] = 1,
      leader: true,
      joined: true,
      overrides: <dynamic>[teamMapApiProvider.overrideWithValue(api)],
    );
    expect(find.text('只有拿到邀请链接的人能加入'), findsOneWidget);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(api.calls.single.inviteOnly, isFalse);
  });

  testWidgets('★★ 服务端没下发 joinMode 就不画开关 —— 不盲切', (
    WidgetTester tester,
  ) async {
    final _FakeTeamApi api = _FakeTeamApi();
    await _pumpDetail(
      tester,
      _team(),
      leader: true,
      joined: true,
      overrides: <dynamic>[teamMapApiProvider.overrideWithValue(api)],
    );
    expect(
      find.text('公开招募'),
      findsNothing,
      reason: '拿不到当前值就画开关,会把「改回公开」也做成「改成仅邀请」',
    );
  });

  testWidgets('★ 队员看不到这个开关(只有队长能切)', (WidgetTester tester) async {
    final _FakeTeamApi api = _FakeTeamApi();
    await _pumpDetail(
      tester,
      _team()..['joinMode'] = 2,
      leader: false,
      joined: true,
      overrides: <dynamic>[teamMapApiProvider.overrideWithValue(api)],
    );
    expect(find.text('公开招募'), findsNothing);
  });

  testWidgets('★ 队伍不在招募中就不画开关(真源 `leader && team.status == 0`)', (
    WidgetTester tester,
  ) async {
    // 真源 `pages/team/detail/index.wxml:33` 的注释:满员/进行中/已结束的队伍
    // 已经不在「附近的队伍」里,切了也无处生效 —— 摆一个不生效的开关,
    // 等于给用户一个只会拿到 403 的按钮。
    final _FakeTeamApi api = _FakeTeamApi();
    await _pumpDetail(
      tester,
      _team(status: 2)..['joinMode'] = 2,
      leader: true,
      joined: true,
      overrides: <dynamic>[teamMapApiProvider.overrideWithValue(api)],
    );
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('★ 加入方式按 joinMode 分档,不写死「邀请制队伍」', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester, _team()..['joinMode'] = 2);
    expect(find.text('公开招募 · 陌生人可在附近队伍里申请 · 组队与否不影响活动举行'),
        findsOneWidget);

    await _pumpDetail(tester, _team()..['joinMode'] = 1);
    expect(find.text('仅邀请 · 只能通过邀请链接加入 · 组队与否不影响活动举行'),
        findsOneWidget);
  });

  testWidgets('★★ 读取失败:错误壳说人话,异常原文一句都不上屏', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(
      tester,
      _team(),
      loadError: DioException(
        requestOptions: RequestOptions(path: '/api/team/info'),
        type: DioExceptionType.connectionError,
        error: const SocketException('Failed host lookup: api.chengyinhub.com'),
      ),
    );
    // 真源 `fail()` 那一档:标题「网络没连上」+ 下一步「检查网络连接后重试」。
    expect(find.text('网络没连上'), findsOneWidget);
    expect(find.text('检查网络连接后重试'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget,
        reason: '真源 errorAction 逐字是「重新加载」,不是 StatusView 默认的「重试」');
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('api.chengyinhub.com'), findsNothing);
  });

  testWidgets('★ 服务端回了非 200:报「队伍暂时不可用」并带上服务端那句话', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(
      tester,
      _team(),
      loadError: const PageParityApiException('队伍不存在或已解散'),
    );
    expect(find.text('队伍暂时不可用'), findsOneWidget);
    expect(find.text('队伍不存在或已解散'), findsOneWidget);
  });

  testWidgets('★★ 已经有队伍时重拉失败:不清屏,弹一句「队伍状态暂未更新」', (
    WidgetTester tester,
  ) async {
    // 重拉触发点 = 改加入方式成功后的那次回读(`_setJoinMode` → `_load`)。
    // 真源 `autoErrorToast: hasTeam`:上一次的队伍信息留着看,失败弹一句。
    int calls = 0;
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeTeamApi api = _FakeTeamApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          teamMapApiProvider.overrideWithValue(api),
        ].cast(),
        child: MaterialApp(
          home: TeamDetailPage(
            key: ValueKey<int>(_pumpSeq++),
            teamId: 7,
            loadTeam: ({int? teamId, String? inviteCode}) async {
              if (++calls == 1) {
                return <String, dynamic>{
                  'team': _team(title: '夜行队伍')..['joinMode'] = 2,
                  'members': <Map<String, dynamic>>[],
                  'leader': true,
                };
              }
              throw DioException(
                requestOptions: RequestOptions(path: '/api/team/info'),
                type: DioExceptionType.connectionError,
                error: const SocketException('Failed host lookup'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('夜行队伍'), findsOneWidget);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();

    expect(find.text('夜行队伍'), findsOneWidget,
        reason: '重拉失败不该把已经确认过的队伍信息抹掉');
    expect(find.text('网络没连上'), findsNothing,
        reason: '整页错误壳只给「什么都没有」那一档');
    expect(find.text('队伍状态暂未更新'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('★ 加入失败走页内错误条,不是一闪而过的 toast;邀请卡不跳走', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: TeamJoinPage(
            key: ValueKey<int>(_pumpSeq++),
            code: 'CODE123',
            loadTeam: _info(<String, dynamic>{'team': _team(title: '夜行队伍')}),
            joinTeam: (String code) async {
              throw const PageParityApiException('邀请状态可能已变化，请重试');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('接受邀请并加入'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加入'), findsOneWidget);
    expect(find.text('邀请状态可能已变化，请重试'), findsOneWidget);
    expect(find.text('重试加入'), findsOneWidget,
        reason: '真源 cy-inline-error 的 action 必须给得出下一步');
    expect(find.text('夜行队伍'), findsOneWidget,
        reason: '失败只把动作那一档说清楚,邀请卡得留着(§9.3 D4 加载不跳版)');
  });

  testWidgets('★ 读邀请失败同样说人话,并给「重新加载」', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: TeamJoinPage(
            key: ValueKey<int>(_pumpSeq++),
            code: 'CODE123',
            loadTeam: ({int? teamId, String? inviteCode}) async {
              throw const PageParityApiException('邀请已过期');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('邀请暂时不可用'), findsOneWidget);
    expect(find.text('邀请已过期'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.textContaining('PageParityApiException'), findsNothing);
  });
}
