// 票夹「我的队伍 ›」行(A3 收尾入口)。真源
// `subpackageMember/signup/index.js` loadMyTeams()/teamOf()/goMyTeam() +
// `index.wxml:110-121` 的 .team-entry。钉三件事:
//   ① 有队伍的票,票卡下面出这一行(队名/人数按真源口径取舍);
//   ② 点它开**这支队伍**的详情 —— 落点与 /team/nearby「我的队伍」同一条路由;
//   ③ 拉不到 / 已结束 / 已解散:整行不出,不弹全局 toast、不写空态。
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/team/team_nearby_page.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeTeamApi extends TeamMapApi {
  _FakeTeamApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  Object? error;
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> myTeams() async {
    calls++;
    if (error != null) throw error!;
    return rows;
  }
}

/// 票夹的队伍行是**已登录**用户看到的东西。游客另有登录门
/// (见 tickets_guest_gate_test.dart),这里必须先把登录态摆好。
class _SignedIn extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

void main() {
  final tickets = <MyRegistration>[
    MyRegistration(
      id: 11,
      ownerType: 1,
      ownerId: 101,
      title: '外滩路线',
      registrationStatus: 2,
    ),
    MyRegistration(
      id: 22,
      ownerType: 2,
      ownerId: 202,
      title: '周末场次',
      registrationStatus: 2,
    ),
  ];

  Future<_FakeTeamApi> pumpWallet(
    WidgetTester tester, {
    required List<Map<String, dynamic>> teams,
    Object? teamError,
  }) async {
    final api = _FakeTeamApi()
      ..rows = teams
      ..error = teamError;
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (context, state) => const TicketsPage()),
        GoRoute(
          path: '/team/:teamId',
          builder: (context, state) =>
              Text('team-detail-${state.pathParameters['teamId']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedIn.new),
          myTicketsProvider.overrideWith(
            (ref) async => WalletSnapshot(tickets: tickets),
          ),
          teamMapApiProvider.overrideWithValue(api),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('票夹一次拉全量,队伍行落到 ownerType:ownerId 匹配的那张票下', (
    WidgetTester tester,
  ) async {
    final api = await pumpWallet(
      tester,
      teams: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 555,
          'ownerType': 1,
          'ownerId': 101,
          'title': ' 外滩小队 ',
          'joinedCount': 3,
          'maxMembers': 5,
          'status': 2,
        },
      ],
    );
    // 全页只发一次 /api/team/my,不每张票各拉一遍。
    expect(api.calls, 1);
    expect(find.text('我的队伍'), findsOneWidget);
    // 队名按真源 trim 后展示,人数 N/M 两个都有才写。
    expect(find.text('外滩小队'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
  });

  testWidgets('点队伍行开这支队伍的详情(/team/:teamId)', (WidgetTester tester) async {
    await pumpWallet(
      tester,
      teams: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 555,
          'ownerType': 1,
          'ownerId': 101,
          'title': '外滩小队',
          'status': 2,
        },
      ],
    );
    await tester.tap(find.text('我的队伍'));
    await tester.pumpAndSettle();
    expect(find.text('team-detail-555'), findsOneWidget);
  });

  testWidgets('拉不到队伍:整行不出,票夹照常,无 toast 无空态', (WidgetTester tester) async {
    await pumpWallet(
      tester,
      teams: const <Map<String, dynamic>>[],
      teamError: const TeamMapApiException('我的队伍没读到'),
    );
    expect(find.text('我的队伍'), findsNothing);
    expect(find.text('出错了'), findsNothing);
    // 票夹本体照常渲染 —— 队伍失败不污染票列表。
    expect(find.text('外滩路线'), findsOneWidget);
  });

  testWidgets('已结束(3)/已解散(4)的队不给入口;对不上号的票不出行', (WidgetTester tester) async {
    await pumpWallet(
      tester,
      teams: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 777,
          'ownerType': 1,
          'ownerId': 101,
          'title': '散伙队',
          'status': 4,
        },
        <String, dynamic>{
          'id': 888,
          'ownerType': 1,
          'ownerId': 999,
          'title': '别人的票',
          'status': 2,
        },
      ],
    );
    expect(find.text('我的队伍'), findsNothing);
  });
}
