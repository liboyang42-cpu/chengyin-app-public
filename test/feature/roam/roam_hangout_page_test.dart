import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/roam.dart';
import 'package:chengyin_app/data/models/roam_social.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/roam/roam_hangout_page.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 附近的局那页的行为测试。
///
/// ★ 判据只认「用户点了以后真调了哪个接口」,不认界面文案好看 ——
///   加入 = 进群(拿到 conversationId 才算成)、关局/退出 = 危险动作先进确认、
///   举报成功不弹 toast(卡片上那枚「已举报」才是回执)。
class _FakeLocation implements RoamLocationSource {
  @override
  Future<RoamLivePosition> current() async =>
      const RoamLivePosition(latitude: 31.2304, longitude: 121.4737);

  @override
  Stream<RoamLivePosition> watch() => const Stream<RoamLivePosition>.empty();
}

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

AuthState _signedIn() => AuthState(
  initialized: true,
  user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
);

class _FakeRoamApi extends RoamApi {
  _FakeRoamApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<RoamHangoutItem> items = const <RoamHangoutItem>[];
  RoamHangoutItem? detail;
  List<RoamRunner> runners = const <RoamRunner>[];
  int suggestedRadius = 0;
  int suggestedCount = 0;
  int conversationId = 55;

  final List<int> joined = <int>[];
  final List<int> closed = <int>[];
  final List<int> left = <int>[];
  final List<({int id, String reason})> reported =
      <({int id, String reason})>[];
  RoamApiException? joinError;
  int nearbyCalls = 0;

  @override
  Future<RoamHangoutNearby> hangoutNearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    nearbyCalls += 1;
    return RoamHangoutNearby(
      items: items,
      radius: radiusM,
      suggestedRadius: suggestedRadius == 0 ? null : suggestedRadius,
      suggestedCount: suggestedCount == 0 ? null : suggestedCount,
    );
  }

  @override
  Future<RoamHangoutItem> hangoutDetail(int id) async {
    final RoamHangoutItem? row = detail;
    if (row == null) throw RoamApiException('这个局看不了');
    return row;
  }

  @override
  Future<int> hangoutJoin(int id) async {
    if (joinError != null) throw joinError!;
    joined.add(id);
    return conversationId;
  }

  @override
  Future<void> hangoutClose(int id) async => closed.add(id);

  @override
  Future<void> hangoutLeave(int id) async => left.add(id);

  @override
  Future<int> hangoutReport({required int id, required String reason}) async {
    reported.add((id: id, reason: reason));
    return 1;
  }

  @override
  Future<List<RoamRunner>> nearbyRunners({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async => runners;

  @override
  Future<List<RoamPoi>> pois({
    required double lat,
    required double lng,
    int? radiusM,
  }) async => const <RoamPoi>[];

  @override
  Future<List<RoamShopVisitors>> shopVisitors({
    required int sourceType,
    required List<int> sourceIds,
  }) async => const <RoamShopVisitors>[];
}

RoamHangoutItem _hangout({
  int id = 7,
  bool isMember = false,
  bool isOwner = false,
  bool full = false,
  bool reported = false,
}) => RoamHangoutItem(
  kind: 'hangout',
  id: id,
  title: '打 UNO 找搭子',
  addressName: '云锦路地铁站 2 号口',
  startAt: '2026-09-15 20:00',
  memberCount: 3,
  distance: 350,
  isMember: isMember,
  isOwner: isOwner,
  full: full,
  reported: reported,
  members: const <RoamHangoutMember>[
    RoamHangoutMember(memberId: 9, nickname: '阿岚', avatar: 'a.png'),
  ],
);

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRoamApi api,
  int? hangoutId,
  bool signedIn = true,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/roam/nearby',
    routes: <RouteBase>[
      GoRoute(
        path: '/roam/nearby',
        builder: (_, _) => RoamHangoutPage(hangoutId: hangoutId),
      ),
      GoRoute(
        path: '/im/chat/:id',
        builder: (_, GoRouterState state) =>
            Text('chat-${state.pathParameters['id']}'),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(path: '/topic/:id', builder: (_, _) => const Text('topic')),
      GoRoute(path: '/activity/:id', builder: (_, _) => const Text('activity')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            signedIn ? _signedIn() : const AuthState(initialized: true),
          ),
        ),
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(_FakeLocation()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('工具抽屉照小程序五行:筛选 / 我的局 / 附近的人 / 我的队伍 / 设置', (
    WidgetTester tester,
  ) async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..items = <RoamHangoutItem>[_hangout()];
    await _pumpPage(tester, api: api);

    await tester.tap(find.byKey(const Key('hangout-tools-grab')));
    await tester.pumpAndSettle();

    expect(find.text('筛选'), findsOneWidget);
    expect(find.text('我的局'), findsOneWidget);
    expect(find.text('附近的人'), findsOneWidget);
    expect(find.text('我的队伍'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // 副标题里的数字现算,不写死
    expect(find.text('1 个 · 3.0km内'), findsOneWidget);
  });

  testWidgets('空态:后端给了拉远建议就主推「看远一点」', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..suggestedRadius = 20000
      ..suggestedCount = 7;
    await _pumpPage(tester, api: api);

    await tester.tap(find.byKey(const Key('hangout-tools-grab')));
    await tester.pumpAndSettle();

    expect(find.text('雾再远一点,20km 内有 7 个局在约。'), findsOneWidget);
    expect(find.text('看远一点'), findsOneWidget);
    expect(find.text('在这里开一局'), findsWidgets);
  });

  testWidgets('空态:没有建议就引导「在这里开一局」', (WidgetTester tester) async {
    await _pumpPage(tester, api: _FakeRoamApi());

    await tester.tap(find.byKey(const Key('hangout-tools-grab')));
    await tester.pumpAndSettle();

    expect(find.text('开一个,让附近的人找到你。'), findsOneWidget);
    expect(find.text('在这里开一局'), findsWidgets);
  });

  testWidgets('附近的人只出列表:昵称 / 在走时长 / 提醒文案', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..runners = <RoamRunner>[
        const RoamRunner(
          memberId: 9,
          nickname: '阿岚',
          avatar: 'a.png',
          lat: 31.2304,
          lng: 121.4737,
          explorePct: 42,
          shops: 3,
          elapsedSec: 2300,
        ),
      ];
    await _pumpPage(tester, api: api);

    await tester.tap(find.byKey(const Key('hangout-tools-grab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('附近的人'));
    await tester.pumpAndSettle();

    expect(find.text('阿岚'), findsOneWidget);
    expect(find.text('走了半小时上下'), findsOneWidget);
    expect(find.text('38:20'), findsOneWidget);
    expect(find.text('只显示这会儿正在走的人,走远了就不在这儿了'), findsOneWidget);
  });

  testWidgets('加入 = 进群:拿到 conversationId 才跳群聊', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()..detail = _hangout();
    await _pumpPage(tester, api: api, hangoutId: 7);

    expect(find.text('打 UNO 找搭子'), findsOneWidget);
    await tester.tap(find.text('加入这个局'));
    await tester.pumpAndSettle();

    expect(api.joined, <int>[7]);
    expect(find.text('chat-55'), findsOneWidget);
  });

  testWidgets('局满了:加入键是灰的,点了不发请求', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()..detail = _hangout(full: true);
    await _pumpPage(tester, api: api, hangoutId: 7);

    expect(find.text('这局满了'), findsOneWidget);
    await tester.tap(find.text('这局满了'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(api.joined, isEmpty);
  });

  testWidgets('局主:详情里的「关局」先过原生确认,确认后才发请求', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..detail = _hangout(isOwner: true);
    await _pumpPage(tester, api: api, hangoutId: 7);

    await tester.tap(find.text('看详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关局'));
    await tester.pumpAndSettle();

    // 确认真弹出来了(危险动作不许直接发)
    expect(find.text('关掉「打 UNO 找搭子」?'), findsOneWidget);
    expect(api.closed, isEmpty);

    await tester.tap(find.text('关局').last);
    await tester.pumpAndSettle();

    expect(api.closed, <int>[7]);
  });

  testWidgets('队员:退出也要先确认,取消就不发请求', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..detail = _hangout(isMember: true);
    await _pumpPage(tester, api: api, hangoutId: 7);

    await tester.tap(find.text('看详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();

    expect(find.text('退出「打 UNO 找搭子」?'), findsOneWidget);
    await tester.tap(find.text('继续待着'));
    await tester.pumpAndSettle();
    expect(api.left, isEmpty);
  });

  testWidgets('举报成功不弹 toast:卡片上的「已举报」就是回执', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()..detail = _hangout();
    await _pumpPage(tester, api: api, hangoutId: 7);

    await tester.tap(find.text('看详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('举报'));
    await tester.pumpAndSettle();

    expect(find.text('举报会进人工审核,不会通知对方'), findsOneWidget);
    await tester.tap(find.text('骚扰 / 引流'));
    await tester.pumpAndSettle();

    expect(api.reported, hasLength(1));
    expect(api.reported.single.id, 7);
    expect(api.reported.single.reason, '骚扰 / 引流');
    // 回到卡片,链接变成「已举报」状态
    await tester.tap(find.text('看详情'));
    await tester.pumpAndSettle();
    expect(find.text('已举报'), findsOneWidget);
  });

  testWidgets('进群的失败提示用后端原话,不自己编', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..detail = _hangout()
      ..joinError = RoamApiException('这个局已经关了');
    await _pumpPage(tester, api: api, hangoutId: 7);

    await tester.tap(find.text('加入这个局'));
    await tester.pumpAndSettle();

    expect(find.text('这个局已经关了'), findsOneWidget);
    expect(find.text('chat-55'), findsNothing);
  });

  // B1 模拟器报告 P1:游客撞 401 时被说成「列表这次没读到,重试」——
  // 重试按多少次都还是 401,是条死路。游客态直接给登录门,连请求都不发。
  testWidgets('游客:列表位置给登录门(去登录),不发注定 401 的请求', (WidgetTester tester) async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..items = <RoamHangoutItem>[_hangout()];
    await _pumpPage(tester, api: api, signedIn: false);

    expect(find.textContaining('登录后查看附近的局'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(api.nearbyCalls, 0, reason: '游客态不该发注定 401 的请求');
  });
}
