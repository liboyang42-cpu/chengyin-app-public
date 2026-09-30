// b1-sim-play-4 N2/§3.8:冷启动显式深链必须压过「会话恢复窗口」。
//
// 小程序真源里 onLaunch 的静默登录不拦页面:带 scene/query 冷启,目标页
// 首帧就在画面上,登录态到了再原地刷新数据。App 侧此前把**所有**冷启落点
// (含游客可直达的 /activities、/official-events)扣在 splash 后等
// token 恢复(有界 5s)+ userInfo 网络(15s 连接 + 20s 接收)——
// 真跑实测 ~40s、/official-events ~70s 才可达,即「恢复优先级压过深链」。
//
// 本文件钉三件事:
// ① 恢复在途期间,显式冷启深链首帧直接落地(不被 splash 吞);
// ② 恢复完成后不回跳、不漂到别的 tab;
// ③ 需登录深链的 fail-closed 一秒都不放松:恢复期内不许见到受保护页,
//    恢复完成是游客 → 仍兜底回首页。

import 'dart:async';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/feature/activity/activity_list_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/official/official_events_page.dart';
import 'package:chengyin_app/feature/points/points_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// userInfo 挂起不返回 = 会话恢复窗口拉满(真机钥匙串卡死 + 弱网时正是这样)。
class _PendingUserInfoAuthApi extends AuthApi {
  _PendingUserInfoAuthApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final Completer<Map<String, dynamic>> userInfoResponse =
      Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> userInfo() => userInfoResponse.future;
}

class _EmptyActivityApi implements ActivityApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<List<dynamic>>.value(<dynamic>[]);
}

class _EmptyOfficialApi implements OfficialApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<List<dynamic>>.value(<dynamic>[]);
}

Future<ProviderContainer> _pumpColdStart(
  WidgetTester tester, {
  required String route,
  required _PendingUserInfoAuthApi api,
}) async {
  // 有旧 token → bootstrap 会走 userInfo,恢复窗口挂起。
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'cy_jwt': 'stale-but-present-token',
  });
  tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authApiProvider.overrideWithValue(api),
      activityApiProvider.overrideWithValue(_EmptyActivityApi()),
      officialApiProvider.overrideWithValue(_EmptyOfficialApi()),
    ].cast(),
  );
  addTearDown(container.dispose);
  // main.dart 的启动序:先异步点火 bootstrap,再 runApp(不 await)。
  unawaited(container.read(authControllerProvider.notifier).bootstrap());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ChengyinApp()),
  );
  await tester.pump();
  return container;
}

void _completeRestore(_PendingUserInfoAuthApi api) {
  api.userInfoResponse.complete(<String, dynamic>{
    'code': 200,
    'appUser': <String, dynamic>{'id': 7, 'nickname': '复验账号'},
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('N2①: 恢复在途时冷启 --route=/activities 首帧直落活动列表', (
    WidgetTester tester,
  ) async {
    final api = _PendingUserInfoAuthApi();
    final container = await _pumpColdStart(
      tester,
      route: '/activities',
      api: api,
    );
    expect(container.read(authControllerProvider).initialized, isFalse);

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/activities',
      reason: '游客可直达的深链不该等会话恢复(splash)——恢复优先级不得压过深链',
    );
    expect(find.byType(ActivityListPage), findsOneWidget);

    // 恢复完成后不许回跳/漂移。
    _completeRestore(api);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/activities',
    );
    expect(find.byType(ActivityListPage), findsOneWidget);
  });

  testWidgets('N2①: 恢复在途时冷启 --route=/official-events 首帧直落官方活动页', (
    WidgetTester tester,
  ) async {
    final api = _PendingUserInfoAuthApi();
    final container = await _pumpColdStart(
      tester,
      route: '/official-events',
      api: api,
    );
    expect(container.read(authControllerProvider).initialized, isFalse);

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/official-events',
      reason: '真跑 §3.8/N2:/official-events 被恢复窗口扣了 ~70s 才可达',
    );
    expect(find.byType(OfficialEventsPage), findsOneWidget);

    _completeRestore(api);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/official-events',
    );
    expect(find.byType(OfficialEventsPage), findsOneWidget);
  });

  testWidgets('N2③: 需登录深链 fail-closed —— 恢复期内不许见受保护页,登完是游客仍回首页', (
    WidgetTester tester,
  ) async {
    // /points 在 _loginRequiredPrefixes:恢复未知期不得提前落地(A1 冻结面)。
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'cy_jwt': 'stale-but-present-token',
    });
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/points';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final api = _PendingUserInfoAuthApi();
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[authApiProvider.overrideWithValue(api)].cast(),
    );
    addTearDown(container.dispose);
    unawaited(container.read(authControllerProvider.notifier).bootstrap());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/splash',
      reason: '需登录路由必须继续等会话恢复,不得随深链优先一起放行',
    );
    expect(find.byType(PointsPage), findsNothing);

    // 恢复结果:token 已失效(非 200)→ 游客 → /points 兜底回首页,不落在 /points。
    api.userInfoResponse.complete(<String, dynamic>{'code': 401});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PointsPage), findsNothing);
    final settled = container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    expect(
      settled,
      anyOf('/feed', '/splash'),
      reason: '401 归一为游客后应兜底首页(允许还有一帧收敛)',
    );
    expect(settled == '/splash', isFalse, reason: '最终必须离开 splash');
    expect(settled, '/feed');
  });
}
