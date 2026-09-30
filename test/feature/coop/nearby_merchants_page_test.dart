// 附近商家(coop/nearby)的两头接线 —— 断点清单里的「孤岛链」:
//   · 入口侧:吃 topicId/topicName(真源 onLoad:有效→标题「找商家承接」,
//     参数在但解析不出正整数→missing-param 终态,不兜 0 也不静默丢);
//   · 出口侧:点整行进商家主页(openMerchant js:367-381),
//     未入驻 lead 没有 memberId,也就没有主页主体 —— 只提示,不导航。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/models/nearby_merchant.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coop/nearby_merchants_page.dart';

class _Auth extends AuthController {
  _Auth(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

final AuthState _loggedIn = AuthState(
  user: User(id: 7, nickname: '我', avatar: '', role: 'club'),
  initialized: true,
);

NearbyMerchant _merchant({
  required int id,
  int? memberId,
  String name = '静安咖啡',
}) => NearbyMerchant(id: id, name: name, memberId: memberId);

Widget _app(
  List<NearbyMerchant> rows, {
  String? topicIdRaw,
  String? topicName,
}) {
  final GoRouter router = GoRouter(
    initialLocation: '/coop/nearby',
    routes: <RouteBase>[
      GoRoute(
        path: '/coop/nearby',
        builder: (_, _) =>
            NearbyMerchantsPage(topicIdRaw: topicIdRaw, topicName: topicName),
      ),
      GoRoute(
        path: '/merchant/public-home/member/:memberId',
        builder: (_, GoRouterState state) =>
            Text('home/${state.pathParameters['memberId']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(() => _Auth(_loggedIn)),
      nearbyMerchantsProvider.overrideWith((ref) async => rows),
    ].cast(),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('不带主题:标题就是「附近商家」', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<NearbyMerchant>[_merchant(id: 1, memberId: 77)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('附近商家'), findsWidgets);
    expect(find.text('找商家承接'), findsNothing);
    expect(find.text('静安咖啡'), findsOneWidget);
  });

  testWidgets('带 topicId 进来:换标题「找商家承接」,主题名挂成副句', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        <NearbyMerchant>[_merchant(id: 1, memberId: 77)],
        topicIdRaw: '9',
        topicName: '夜游苏河',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('找商家承接'), findsOneWidget);
    expect(find.text('夜游苏河'), findsOneWidget);
  });

  testWidgets('topicId 在但解析不出正整数:「主题参数无效」终态,一个请求都不发', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/coop/nearby',
      routes: <RouteBase>[
        GoRoute(
          path: '/coop/nearby',
          builder: (_, _) => const NearbyMerchantsPage(topicIdRaw: 'abc'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(() => _Auth(_loggedIn)),
          nearbyMerchantsProvider.overrideWith(
            (ref) async => throw StateError('坏参数不该去取数'),
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('主题参数无效'), findsOneWidget);
    expect(find.text('主题参数无效，无法查询可承接商家'), findsOneWidget);
    // 真源这个终态给的是「返回上一页」,不是重试 —— 参数坏了重试也一样。
    expect(find.text('返回上一页'), findsOneWidget);
  });

  testWidgets('点已入驻行 → 商家主页(memberId 作主体)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<NearbyMerchant>[_merchant(id: 1, memberId: 77)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nearby-merchant-1')));
    await tester.pumpAndSettle();
    expect(find.text('home/77'), findsOneWidget);
  });

  testWidgets('未入驻 lead 没有主页主体:只提示先电话联系,不导航', (WidgetTester tester) async {
    await tester.pumpWidget(_app(<NearbyMerchant>[_merchant(id: 2)]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nearby-merchant-2')));
    await tester.pumpAndSettle();
    expect(find.text('这家还没在平台建档，先电话联系'), findsOneWidget);
    expect(find.textContaining('home/'), findsNothing);
  });
}
