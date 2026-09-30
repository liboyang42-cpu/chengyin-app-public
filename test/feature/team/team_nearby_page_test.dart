// 「附近的队伍」页(地图组队 P 方案)的行为门禁。
//
// ★ 判据只认「用户点了以后真调了哪个接口 / 界面真的变成什么样」,不认文案好看。
//   产品判据(线卡 4-D)四条在这里各有着落:
//     ① 满员 / 进行中 / 审核中 → 申请入口消失(撤卡 + 撤下队伍);
//     ② 24h / 活动结束失效 → PENDING 卡说明 + withdraw「已经处理或失效」+ 重拉;
//     ③ 被拒不能再申 → REJECTED 卡没有任何按钮;
//     ④ 全流程可点开:买票跳活动详情 / 申请 / 撤回 / 队长同意 / 我的队伍三态。
// ★ 私密字段(inviteCode / leaderMemberId / ownerType)不进 UI,单独一条钉住。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:chengyin_app/core/map/device_location.dart';
import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/team/team_nearby_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 生产里 502 就是这个形状(dio 的 validateStatus 走 `DioException.badResponse`)。
/// ⚠️ 手搓 `DioException(...)` 的 message 是 null,toString 里没有状态码,测不出真身。
DioException _badResponse502(String path) => DioException.badResponse(
  statusCode: 502,
  requestOptions: RequestOptions(path: path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 502,
  ),
);

class _FakeTeamMapApi extends TeamMapApi {
  _FakeTeamMapApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<Map<String, dynamic>> teams = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> joined = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> applicationsRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> applicants = <Map<String, dynamic>>[];

  Object? nearbyError;
  Object? applyError;
  /// 申请成功回执里的 applyExpireTime(可注入;null = 服务端没带)。
  Object? applyReceipt;
  Object? withdrawError;
  Object? handleError;
  Object? applicationsError;

  /// 同意之后的后端世界变化(例如队伍被同意到满员从地图消失)。
  void Function()? afterHandle;

  final List<int> radii = <int>[];
  final List<int> applied = <int>[];
  final List<int> withdrawn = <int>[];
  final List<({int teamId, int memberId, bool approved})> handled =
      <({int teamId, int memberId, bool approved})>[];
  int myTeamsCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    radii.add(radiusM);
    if (nearbyError != null) throw nearbyError!;
    return teams;
  }

  @override
  Future<Object?> apply(int teamId) async {
    if (applyError != null) throw applyError!;
    applied.add(teamId);
    return applyReceipt;
  }

  @override
  Future<void> withdraw(int teamId) async {
    if (withdrawError != null) throw withdrawError!;
    withdrawn.add(teamId);
  }

  @override
  Future<List<Map<String, dynamic>>> applications(int teamId) async {
    if (applicationsError != null) throw applicationsError!;
    return applicants;
  }

  @override
  Future<void> handle({
    required int teamId,
    required int memberId,
    required bool approved,
  }) async {
    if (handleError != null) throw handleError!;
    handled.add((teamId: teamId, memberId: memberId, approved: approved));
    afterHandle?.call();
  }

  @override
  Future<List<Map<String, dynamic>>> myTeams() async {
    myTeamsCalls += 1;
    return joined;
  }

  @override
  Future<List<Map<String, dynamic>>> myApplications() async => applicationsRows;
}

Map<String, dynamic> _team({
  int teamId = 7,
  String viewerStatus = 'NONE',
  bool viewerHasTicket = false,
  int joinedCount = 3,
  int maxMembers = 4,
  int? pendingCount,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) => <String, dynamic>{
  'teamId': teamId,
  'title': '外滩夜行',
  'activityId': 11,
  'activityName': '外滩夜行路线 · 周五 19:30 场',
  'productType': 1,
  'addressName': '外滩源',
  'coordSource': 'GATHER',
  'latitude': 31.2,
  'longitude': 121.4,
  'distance': 600,
  'leaderName': '小周',
  'joinedCount': joinedCount,
  'maxMembers': maxMembers,
  'memberAvatars': const <String>['a.png'],
  'viewerStatus': viewerStatus,
  'viewerHasTicket': viewerHasTicket,
  'pendingCount': pendingCount,
  ...extra,
};

/// 同一个 test 里 pump 多次时,页面类型不变会让 Flutter **复用 State**
/// (initState 不再跑、数据不重取)。每次 pump 换一把 key,强制重建。
int _pumpSeq = 0;

/// 根 RepaintBoundary:半屏合成出来的像素要能整块截下来(P1-2 的观测口)。
const Key _rootShotKey = Key('team-nearby-root-shot');

/// 已登录态。本页的数据(viewerStatus / 我的队伍计数)本来就要登录才有,
/// 除游客用例外,所有用例都站在这个态上。
class _SignedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

/// 可切换的登录态:给「游客 → 点去登录 → 登完就地重拉」这条链用。
class _MutableAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);

  void signIn() {
    state = AuthState(
      initialized: true,
      user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeTeamMapApi api,
  List<int>? openedTeams,
  List<int>? openedActivities,
  bool signedIn = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: _rootShotKey,
      child: ProviderScope(
        overrides: <dynamic>[
          if (signedIn) authControllerProvider.overrideWith(_SignedInAuth.new),
        ].cast(),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TeamNearbyPage(
            key: ValueKey<int>(_pumpSeq++),
            api: api,
            locate: () async =>
                const MapCoordinate(latitude: 31.2304, longitude: 121.4737),
            openTeam: openedTeams?.add,
            openActivity: openedActivities?.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 半屏盖住的那一带(屏幕 y 200–1380)的像素。
///
/// 半屏顶部留白 = 8% × 1400 = 112pt,所以这一带**整块归半屏**:
/// 半屏自己画了不透明底时,它只由半屏内容决定;半屏透明时,下层页面就透进来。
Future<Uint8List> _sheetBand(WidgetTester tester) async {
  const int width = 390;
  const int top = 200;
  const int bottom = 1380;
  final ByteData? screen = await tester.runAsync(() async {
    final RenderRepaintBoundary boundary = tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_rootShotKey));
    final ui.Image image = await boundary.toImage();
    final ByteData bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    image.dispose();
    return bytes;
  });
  final Uint8List source = screen!.buffer.asUint8List();
  final Uint8List band = Uint8List((bottom - top) * width * 4);
  for (int y = top; y < bottom; y++) {
    band.setRange(
      (y - top) * width * 4,
      (y - top + 1) * width * 4,
      source,
      y * width * 4,
    );
  }
  return band;
}

/// 开「我的队伍」半屏,截它盖住的那一带;只改下层页面内容(teams)。
Future<Uint8List> _myTeamsSheetBand(
  WidgetTester tester, {
  required List<Map<String, dynamic>> teams,
}) async {
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetDevicePixelRatio);
  final _FakeTeamMapApi api = _FakeTeamMapApi()
    ..teams = teams
    ..joined = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 7,
        'title': '外滩夜行',
        'joinedCount': 3,
        'maxMembers': 4,
        'status': 0,
      },
    ]
    ..applicationsRows = <Map<String, dynamic>>[
      <String, dynamic>{
        'teamId': 8,
        'title': '苏河湾探店日',
        'leaderName': '阿May',
        'applyStatus': 'PENDING',
      },
    ];
  await _pump(tester, api: api);
  await tester.tap(find.text('我的队伍 · 2'));
  await tester.pumpAndSettle();
  expect(find.text('我的队伍'), findsOneWidget, reason: '半屏标题在 = 半屏真的开了');
  final Uint8List band = await _sheetBand(tester);
  // 同一个 test 里第二次 pump 会复用同一个 Navigator:半屏不关,它会盖住
  // 第二次要点的那枚角控件(点击落到半屏内容上)。
  Navigator.of(tester.element(find.text('我的队伍'))).pop();
  await tester.pumpAndSettle();
  return band;
}

Future<void> _openCard(WidgetTester tester) async {
  await tester.tap(find.text('外滩夜行路线 · 周五 19:30 场'));
  await tester.pumpAndSettle();
}

/// N-1(b1-sim-team-3)的用证台:走真路由栈进本页,而不只是 `home:`。
/// 无栈 = 冷启动深链(栈底即本页);有栈 = 从上一页 push 进来。
Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required bool withStack,
  required _FakeTeamMapApi api,
  bool signedIn = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    initialLocation: withStack ? '/from' : '/team/nearby',
    routes: <RouteBase>[
      GoRoute(
        path: '/from',
        builder: (BuildContext context, GoRouterState state) => CupertinoButton(
          child: const Text('go-nearby'),
          onPressed: () => context.push('/team/nearby'),
        ),
      ),
      GoRoute(
        path: '/team/nearby',
        builder: (BuildContext context, GoRouterState state) => TeamNearbyPage(
          key: ValueKey<int>(_pumpSeq++),
          api: api,
          locate: () async =>
              const MapCoordinate(latitude: 31.2304, longitude: 121.4737),
        ),
      ),
      GoRoute(
        path: '/feed',
        builder: (BuildContext context, GoRouterState state) =>
            const Text('feed-home'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        if (signedIn)
          authControllerProvider.overrideWith(_SignedInAuth.new)
        else
          authControllerProvider.overrideWith(_MutableAuth.new),
      ].cast(),
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  if (withStack) {
    await tester.tap(find.text('go-nearby'));
    await tester.pumpAndSettle();
  }
  return router;
}

void main() {
  testWidgets('顶部条计数 + 首屏范围 1 km + 队伍行(短胶囊 / 卡片 plate)', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    await _pump(tester, api: api);

    expect(find.text('附近的队伍 · 1 支在招募'), findsOneWidget);
    // 稿 591:1020 写死「范围 1 km」—— 首屏不取接口的 3000 缺省。
    expect(api.radii, <int>[1000]);
    expect(find.text('外滩夜行路线 · 周五 19:30 场'), findsOneWidget);
    // 行尾是短胶囊(「招募中」= 详情页 STATUS_TEXT 第一档,见 _rowBadge);
    // 完整 plate(快照 decorateTeam()「外滩夜行 · 3/4」)只在打开的半屏卡里,
    // 不在行上重复队名。
    expect(find.text('招募中'), findsOneWidget);
    expect(find.text('外滩夜行 · 3/4'), findsNothing);
    await _openCard(tester);
    expect(find.text('外滩夜行 · 3/4'), findsOneWidget);
  });

  testWidgets('范围控件按档位走并重拉(1 → 3 → 5 km)', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    await _pump(tester, api: api);

    await tester.tap(find.text('范围 1 km'));
    await tester.pumpAndSettle();
    expect(find.text('范围 3 km'), findsOneWidget);
    await tester.tap(find.text('范围 3 km'));
    await tester.pumpAndSettle();
    expect(find.text('范围 5 km'), findsOneWidget);
    expect(api.radii, <int>[1000, 3000, 5000]);
  });

  testWidgets('没票:主按钮「去买这场的票」跳活动详情购票', (WidgetTester tester) async {
    final List<int> openedActivities = <int>[];
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    await _pump(tester, api: api, openedActivities: openedActivities);

    await _openCard(tester);
    expect(find.text('加入队伍需要先持有这一场的票'), findsOneWidget);
    await tester.tap(find.text('去买这场的票'));
    await tester.pumpAndSettle();
    expect(openedActivities, <int>[11]);
  });

  testWidgets('有票 → 申请加入 → 成功变 PENDING(只剩撤回;列表胶囊同步)', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team(viewerHasTicket: true)];
    await _pump(tester, api: api);

    await _openCard(tester);
    await tester.tap(find.text('申请加入'));
    await tester.pumpAndSettle();

    expect(api.applied, <int>[7]);
    expect(find.text('◷ 已申请 · 等队长同意'), findsOneWidget);
    expect(find.text('队长没处理或活动开始时,申请自动失效'), findsOneWidget);
    expect(find.text('撤回申请'), findsOneWidget);
    expect(find.text('申请加入'), findsNothing);
    // 关掉半屏后列表那行的胶囊也已经是「申请中」。
    await tester.tap(find.text('撤回申请'));
    await tester.pumpAndSettle();
    expect(api.withdrawn, <int>[7]);
    expect(find.text('申请加入'), findsOneWidget);
  });

  testWidgets('PENDING 卡:撤回后回到买票/申请态', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team(viewerStatus: 'PENDING')];
    await _pump(tester, api: api);

    await _openCard(tester);
    expect(find.text('队长没处理或活动开始时,申请自动失效'), findsOneWidget);
    await tester.tap(find.text('撤回申请'));
    await tester.pumpAndSettle();
    expect(api.withdrawn, <int>[7]);
    expect(find.text('去买这场的票'), findsOneWidget);
  });

  testWidgets('被拒:说明在、申请与撤回按钮都不在', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(viewerStatus: 'REJECTED', viewerHasTicket: true),
      ];
    await _pump(tester, api: api);

    await _openCard(tester);
    expect(find.text('不能再申请这支队伍'), findsOneWidget);
    expect(find.text('申请加入'), findsNothing);
    expect(find.text('撤回申请'), findsNothing);
    expect(find.text('去买这场的票'), findsNothing);
  });

  testWidgets('errorCode=TEAM_FULL:撤卡 + 从列表撤下 + 说明「申请不了」', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team(viewerHasTicket: true)]
      ..applyError = const TeamMapApiException('已满', errorCode: 'TEAM_FULL');
    await _pump(tester, api: api);

    await _openCard(tester);
    await tester.tap(find.text('申请加入'));
    await tester.pumpAndSettle();

    expect(find.text('这支队伍现在申请不了'), findsOneWidget);
    expect(find.text('队伍已满、活动已开始或正在审核,地图上已经刷新'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    // 半屏收起、队伍从列表消失(地图上不再有申请入口)。
    expect(find.text('外滩夜行路线 · 周五 19:30 场'), findsNothing);
    expect(find.text('附近的队伍 · 0 支在招募'), findsOneWidget);
  });

  testWidgets('errorCode=ACTIVITY_STARTED / TEAM_UNDER_REVIEW 同样撤下队伍', (
    WidgetTester tester,
  ) async {
    for (final String code in <String>[
      'ACTIVITY_STARTED',
      'TEAM_UNDER_REVIEW',
    ]) {
      final _FakeTeamMapApi api = _FakeTeamMapApi()
        ..teams = <Map<String, dynamic>>[_team(viewerHasTicket: true)]
        ..applyError = TeamMapApiException('x', errorCode: code);
      await _pump(tester, api: api);
      await _openCard(tester);
      await tester.tap(find.text('申请加入'));
      await tester.pumpAndSettle();
      expect(find.text('这支队伍现在申请不了'), findsOneWidget, reason: code);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('附近的队伍 · 0 支在招募'), findsOneWidget, reason: code);
    }
  });

  testWidgets('errorCode=TICKET_REQUIRED:卡片回买票态 +「去买票 / 先不买」', (
    WidgetTester tester,
  ) async {
    final List<int> openedActivities = <int>[];
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team(viewerHasTicket: true)]
      ..applyError = const TeamMapApiException(
        '请先购票',
        errorCode: 'TICKET_REQUIRED',
      );
    await _pump(tester, api: api, openedActivities: openedActivities);

    await _openCard(tester);
    await tester.tap(find.text('申请加入'));
    await tester.pumpAndSettle();

    expect(find.text('要先买这一场的票'), findsOneWidget);
    expect(find.text('去买票'), findsOneWidget);
    expect(find.text('先不买'), findsOneWidget);
    await tester.tap(find.text('去买票'));
    await tester.pumpAndSettle();
    expect(openedActivities, <int>[11]);
    // 卡片自己也已经回到买票态。
    expect(find.text('去买这场的票'), findsOneWidget);
  });

  testWidgets('没有 errorCode 只报失败:标题走兜底、msg 只当原因、状态不动', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team(viewerHasTicket: true)]
      ..applyError = const TeamMapApiException('TEAM_FULL 已满');
    await _pump(tester, api: api);

    await _openCard(tester);
    await tester.tap(find.text('申请加入'));
    await tester.pumpAndSettle();

    expect(find.text('申请没发出去'), findsOneWidget);
    expect(find.text('TEAM_FULL 已满'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    // 卡片还在、还是「申请加入」——文案里写了码不算数。
    expect(find.text('申请加入'), findsOneWidget);
    expect(find.text('附近的队伍 · 1 支在招募'), findsOneWidget);
  });

  testWidgets('队长:审批半屏拉申请列表,「拒绝(次)在左 / 同意(主)在右」', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(viewerStatus: 'LEADER', pendingCount: 2),
      ]
      ..applicants = <Map<String, dynamic>>[
        <String, dynamic>{
          'memberId': 5,
          'memberName': '阿杰',
          'appliedAt': '2026-09-17 10:00:00',
        },
        <String, dynamic>{'memberId': 6, 'memberName': 'Mia'},
      ];
    await _pump(tester, api: api);

    await _openCard(tester);
    expect(find.text('你是队长 · 已组 3/4 · 还能再加 1 人'), findsOneWidget);
    expect(find.text('待处理的申请 · 2'), findsOneWidget);
    expect(find.text('阿杰'), findsOneWidget);
    expect(
      tester.getCenter(find.text('拒绝').first).dx <
          tester.getCenter(find.text('同意').first).dx,
      isTrue,
    );

    await tester.tap(find.text('同意').first);
    await tester.pumpAndSettle();
    expect(api.handled, <({int teamId, int memberId, bool approved})>[
      (teamId: 7, memberId: 5, approved: true),
    ]);
    // 处理掉的那行不在列表里了。
    expect(find.text('阿杰'), findsNothing);
    expect(find.text('待处理的申请 · 1'), findsOneWidget);
  });

  testWidgets('队长同意到满员:队伍从列表消失,半屏跟着收起', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(viewerStatus: 'LEADER', joinedCount: 3, pendingCount: 1),
      ]
      ..applicants = <Map<String, dynamic>>[
        <String, dynamic>{'memberId': 5, 'memberName': '阿杰'},
      ];
    api.afterHandle = () => api.teams = <Map<String, dynamic>>[];
    await _pump(tester, api: api);

    await _openCard(tester);
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();

    expect(find.text('待处理的申请 · 1'), findsNothing);
    expect(find.text('附近的队伍 · 0 支在招募'), findsOneWidget);
  });

  testWidgets('队长处理失败 APPLY_NOT_PENDING:该行移除 + 说明「已经处理或失效」', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(viewerStatus: 'LEADER', pendingCount: 1),
      ]
      ..applicants = <Map<String, dynamic>>[
        <String, dynamic>{'memberId': 5, 'memberName': '阿杰'},
      ]
      ..handleError = const TeamMapApiException(
        '已处理',
        errorCode: 'APPLY_NOT_PENDING',
      );
    await _pump(tester, api: api);

    await _openCard(tester);
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();

    expect(find.text('这条申请已经处理或失效'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('阿杰'), findsNothing);
  });

  testWidgets('P6 我的队伍:三态行 + 角控件计数不算被拒 + 进队 / 撤回', (WidgetTester tester) async {
    final List<int> openedTeams = <int>[];
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..joined = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 7,
          'title': '外滩夜行',
          'joinedCount': 3,
          'maxMembers': 4,
          'status': 0,
        },
      ]
      ..applicationsRows = <Map<String, dynamic>>[
        <String, dynamic>{
          'teamId': 8,
          'title': '苏河湾探店日',
          'leaderName': '阿May',
          'applyStatus': 'PENDING',
        },
        <String, dynamic>{
          'teamId': 10,
          'title': '霓虹拾光',
          'applyStatus': 'REJECTED',
        },
      ];
    await _pump(tester, api: api, openedTeams: openedTeams);

    // 计数 = 已加入 + 申请中,不算被拒。
    expect(find.text('我的队伍 · 2'), findsOneWidget);
    await tester.tap(find.text('我的队伍 · 2'));
    await tester.pumpAndSettle();

    expect(find.text('已加入'), findsOneWidget);
    expect(find.text('申请中'), findsOneWidget);
    expect(find.text('队长未同意'), findsOneWidget);

    await tester.tap(find.text('外滩夜行'));
    await tester.pumpAndSettle();
    expect(openedTeams, <int>[7]);

    // 撤回申请:确认后发接口,列表重拉(半屏不重开)。
    final int callsBefore = api.myTeamsCalls;
    await tester.tap(find.text('苏河湾探店日'));
    await tester.pumpAndSettle();
    expect(find.text('撤回后可以重新申请;队长那边会少一条待处理。'), findsOneWidget);
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    expect(api.withdrawn, <int>[8]);
    expect(api.myTeamsCalls > callsBefore, isTrue);
  });

  testWidgets('私密字段不进 UI:inviteCode / leaderMemberId / ownerType 一个字都不出现', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(
          viewerHasTicket: true,
          extra: <String, dynamic>{
            'inviteCode': 'SECRET1',
            'leaderMemberId': 99,
            'ownerType': 2,
          },
        ),
      ];
    await _pump(tester, api: api);
    await _openCard(tester);

    expect(find.textContaining('SECRET1'), findsNothing);
    expect(find.textContaining('inviteCode'), findsNothing);
    expect(find.textContaining('leaderMemberId'), findsNothing);
    expect(find.textContaining('ownerType'), findsNothing);
  });

  testWidgets('定位不可用:说清是哪一类,并给重试', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int tries = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_SignedInAuth.new),
        ].cast(),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TeamNearbyPage(
            api: api,
            locate: () async {
              tries += 1;
              if (tries == 1) {
                throw const LocationUnavailable(LocationFailure.deniedForever);
              }
              return const MapCoordinate(
                latitude: 31.2304,
                longitude: 121.4737,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('附近的队伍没能读到'), findsOneWidget);
    expect(find.text('请在系统设置中开启位置权限，以便继续使用位置功能'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('附近的队伍 · 0 支在招募'), findsOneWidget);
  });

  testWidgets('★ 拉队伍失败:上屏的是人话,不是异常原文', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..nearbyError = _badResponse502('/api/team/nearby');
    await _pump(tester, api: api);

    expect(find.text('附近的队伍没能读到'), findsOneWidget);
    expect(find.text('网络异常，请稍后重试'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('游客:/team/nearby 给登录引导,不空转;登完就地重拉', (WidgetTester tester) async {
    // 生产实测(2026-09-18,无 token):
    //   GET /api/team/nearby 与 POST /api/team/my 都返
    //   `HTTP 401 {"msg":"登录状态已失效，请重新登录","code":401}`。
    // 游客落这一页,列表**永远**读不出来 —— 给转圈就是永远转圈。
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()]
      ..joined = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 7,
          'title': '外滩夜行',
          'joinedCount': 3,
          'maxMembers': 4,
          'status': 0,
        },
      ];
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_MutableAuth.new),
        teamMapApiProvider.overrideWithValue(api),
      ].cast(),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TeamNearbyPage(
            locate: () async =>
                const MapCoordinate(latitude: 31.2304, longitude: 121.4737),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ① 落的是登录引导,不是转不完的圈,也不是一句「没能读到」。
    expect(find.text('登录后查看附近的队伍'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.text('附近的队伍没能读到'), findsNothing);
    // #465/#295 修复回归锁:图标钉 Cupertino 系 —— Icons.lock_outline 是
    // Material 残留,曾从这里漏过(门禁只扫交互控件,不扫静态图标)。
    expect(find.byIcon(CupertinoIcons.lock), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    // 游客别去打注定 401 的接口(打了也只会把 401 的原文甩给用户)。
    expect(api.radii, isEmpty);
    expect(api.myTeamsCalls, 0);

    // ②「去登录」是真的出口:能把登录弹窗叫出来。
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
    expect(api.radii, isEmpty, reason: '开登录弹窗这个动作本身不碰队伍接口');

    // ③ 登完留在原页就地重拉,不用退出重进。
    (container.read(authControllerProvider.notifier) as _MutableAuth).signIn();
    Navigator.of(tester.element(find.text('登录城瘾'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('登录后查看附近的队伍'), findsNothing);
    expect(api.radii, <int>[1000]);
    expect(find.text('附近的队伍 · 1 支在招募'), findsOneWidget);
    expect(find.text('外滩夜行路线 · 周五 19:30 场'), findsOneWidget);
  });

  testWidgets('「我的队伍」半屏自带不透明底:下层文字不透上来', (WidgetTester tester) async {
    // 两次只改**下层页面**的内容(1 支队伍 / 空态),半屏自己的内容一模一样。
    // 半屏有不透明底 ⇒ 它盖住的那一带两次像素完全一致;
    // 半屏透明 ⇒ 下层队伍行 / 空态文字透上来,像素必不相同。
    final Uint8List overRow = await _myTeamsSheetBand(
      tester,
      teams: <Map<String, dynamic>>[_team()],
    );
    final Uint8List overEmpty = await _myTeamsSheetBand(
      tester,
      teams: <Map<String, dynamic>>[],
    );
    expect(overEmpty, equals(overRow), reason: '半屏那一带被下层页面改动了 = 半屏没画底,下层文字透上来');
  });

  // ── N-1(b1-sim-team-3):/team/nearby 各态的返回路径 ──────────────────
  // 截图只拍到登录门无返回箭头;登录态/深链进法要用真路由栈证(回执≠观测,
  // 这里以 widget 测试为证,模拟器无 tap 通道未观测渲染)。

  testWidgets('N-1 冷启动深链(登录态、列表非空):导航栏给「回首页」,点了真回首页', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    final GoRouter router = await _pumpRouter(
      tester,
      withStack: false,
      api: api,
    );

    // 落在列表态(不是自带「回首页」兜底的门/错误/空态)—— 此前零出口的一支。
    expect(find.text('附近的队伍 · 1 支在招募'), findsOneWidget);
    expect(
      find.byKey(const Key('team-nearby-home-exit')),
      findsOneWidget,
      reason: '栈底直达没有上一页,导航栏 leading 必须给得出出口',
    );
    await tester.tap(find.byKey(const Key('team-nearby-home-exit')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/feed');
  });

  testWidgets('N-1 带栈进入(登录态):只有系统返回钮,不重复给回首页', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    await _pumpRouter(tester, withStack: true, api: api);

    expect(find.text('附近的队伍 · 1 支在招募'), findsOneWidget);
    expect(find.byKey(const Key('team-nearby-home-exit')), findsNothing);
    expect(
      find.byType(CupertinoNavigationBarBackButton),
      findsOneWidget,
      reason: '有上一页 → 标准 back chevron(规则手册:所有页导航栏标准返回)',
    );
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(find.text('go-nearby'), findsOneWidget);
  });

  testWidgets('N-1 游客深链:登录门在,导航栏出口同在(双保险)', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi();
    await _pumpRouter(tester, withStack: false, api: api, signedIn: false);

    expect(find.text('登录后查看附近的队伍'), findsOneWidget);
    expect(find.byKey(const Key('team-nearby-home-exit')), findsOneWidget);
  });
}
