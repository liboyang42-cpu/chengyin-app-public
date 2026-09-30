// 招牌主推卡接线(gap-spec-roam §4 #28):有展示没跳转 → 按源 actionable 门禁点。
// 真源 components/cy/scene-roam-poi-detail/index.js:181-186,427-430:
//   featuredType 1=店内活动(featuredId=活动ID)→ 活动详情;2=券 → 券包;
//   actionable = (1 且有 featuredId) || 2 —— 类型缺失时卡片**不可点**,
//   不能把券 id 当活动 id 猜着跳。
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/roam_merchant_info.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/roam/roam_poi_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixed_auth.dart';

class _FeaturedRoamApi extends RoamApi {
  _FeaturedRoamApi(this.featuredJson)
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final Map<String, dynamic>? featuredJson;

  @override
  Future<CityNodeDetail> nodeDetail(int poiId) async => CityNodeDetail(
    poiId: poiId,
    name: '武康大楼',
    status: 1,
    merchantId: 31,
    lat: 31.2,
    lng: 121.4,
  );

  @override
  Future<(RoamMerchantInfo, RoamFeatured?)> publicMerchantDetail(
    int merchantId,
  ) async => (
    const RoamMerchantInfo(id: 31, name: '梧桐咖啡'),
    featuredJson == null ? null : RoamFeatured.fromJson(featuredJson!),
  );
}

Future<GoRouter> _pump(
  WidgetTester tester,
  Map<String, dynamic>? featuredJson,
) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const RoamPoiDetailPage(poiId: 7)),
      GoRoute(
        path: '/activity/:id',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('活动详情-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/coupons',
        builder: (_, _) => const Scaffold(body: Text('券包')),
      ),
      GoRoute(
        path: '/roam/citystamp',
        builder: (_, GoRouterState state) => Scaffold(
          body: Text(
            '城市印章-${state.uri.queryParameters['kind']}-${state.uri.queryParameters['place']}',
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // main 侧 #208 口径给这页加了页内登录门(_LoadState.needLogin):
      // 游客不发 nodeDetail,主推卡永远不出现。用例要的是接线,先给登录态。
      overrides: <dynamic>[
        roamApiProvider.overrideWithValue(_FeaturedRoamApi(featuredJson)),
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
      ].cast(),
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(platform: TargetPlatform.iOS),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  test('模型:featuredType/featuredId 解析与 actionable 门禁逐条对齐源', () {
    expect(
      RoamFeatured.fromJson(<String, dynamic>{
        'name': '招牌手冲',
        'featuredType': 1,
        'featuredId': 42,
      }).actionable,
      isTrue,
    );
    expect(
      RoamFeatured.fromJson(<String, dynamic>{
        'name': '招牌手冲',
        'featuredType': 2,
      }).actionable,
      isTrue,
    );
    // type=1 但没带 id:跳过去只会 404,不可点。
    expect(
      RoamFeatured.fromJson(<String, dynamic>{
        'name': 'a',
        'featuredType': 1,
      }).actionable,
      isFalse,
    );
    // 源判据 typeof === 'number':字符串类型号按缺失处理。
    expect(
      RoamFeatured.fromJson(<String, dynamic>{
        'name': 'a',
        'featuredType': '1',
        'featuredId': 42,
      }).actionable,
      isFalse,
    );
    expect(
      RoamFeatured.fromJson(<String, dynamic>{'name': 'a'}).actionable,
      isFalse,
    );
  });

  testWidgets('★ 活动主推点进活动详情(带服务端给的 id)', (WidgetTester tester) async {
    await _pump(tester, <String, dynamic>{
      'name': '招牌手冲',
      'featuredType': 1,
      'featuredId': 42,
    });

    expect(find.text('招牌主推'), findsOneWidget);
    await tester.tap(find.byKey(const Key('roam-poi-featured')));
    await tester.pumpAndSettle();
    expect(find.text('活动详情-42'), findsOneWidget);
  });

  testWidgets('★ 券主推点进券包,不拿券 id 拼活动路由', (WidgetTester tester) async {
    await _pump(tester, <String, dynamic>{
      'name': '满减券',
      'featuredType': 2,
      'featuredId': 9,
    });

    await tester.tap(find.byKey(const Key('roam-poi-featured')));
    await tester.pumpAndSettle();
    expect(find.text('券包'), findsOneWidget);
    expect(find.textContaining('活动详情'), findsNothing);
  });

  testWidgets('类型缺失的旧数据仍是纯展示:不可点、不报错', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pump(tester, <String, dynamic>{'name': '招牌手冲'});

    final Finder card = find.byKey(const Key('roam-poi-featured'));
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('活动详情'), findsNothing);
    expect(find.text('券包'), findsNothing);
    semantics.dispose();
  });

  // 真源 pages/roam/index.js:480-484 openCityStamp:kind=sign、place=据点名。
  testWidgets('★ 据点动作行有「投一张」,带真名跳 citystamp(kind=sign)', (
    WidgetTester tester,
  ) async {
    await _pump(tester, null);

    await tester.tap(find.byKey(const Key('roam-poi-citystamp-entry')));
    await tester.pumpAndSettle();
    expect(find.text('城市印章-sign-武康大楼'), findsOneWidget);
  });
}
