// b1-sim-search P0-1 回归锁:结果页四路请求逐路计数,某一路失败(游客态
// 俱乐部 401 生产实测)不许把其余三路的成功结果整包丢掉。
// 1:1 对齐小程序 pages/search2/result/index.js finish():
//   部分失败有结果 → 照常出结果 + toast「部分搜索没有完成，结果可能不全」;
//   全失败         → 「搜索服务暂时不可用，请重试」;
//   部分失败且零结果 → 「部分搜索没有完成，请重试后再确认结果」。
// 同根因的地图页(P1-5)也在这里锁:节点一路 401 时地图与活动列表照出。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/map/apple_scene_view.dart';
import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/city_node_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/city_node_poi.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/merchant.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/map/map_controller.dart';
import 'package:chengyin_app/feature/search/city_node_search_page.dart';
import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/search_result_page.dart';

/// 游客实测 401:`{"msg":"登录状态已失效，请重新登录","code":401}`。
DioException _unauthorized() => DioException(
  type: DioExceptionType.badResponse,
  response: Response(
    statusCode: 401,
    data: <String, dynamic>{'msg': '登录状态已失效，请重新登录', 'code': 401},
    requestOptions: RequestOptions(path: '/api/club/list'),
  ),
  requestOptions: RequestOptions(path: '/api/club/list'),
);

DioException _networkDown() => DioException(
  type: DioExceptionType.connectionError,
  requestOptions: RequestOptions(path: '/api/topic/list'),
);

class _TopicApiFake implements TopicApi {
  _TopicApiFake({this.failure});
  final Object? failure;

  @override
  Future<List<Topic>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    bool recommend = false,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    if (failure != null) throw failure!;
    return <Topic>[Topic(id: 1, name: '静安微旅行')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ActivityApiFake implements ActivityApi {
  _ActivityApiFake({this.failure});
  final Object? failure;

  @override
  Future<List<Activity>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    String? sortType,
    String? longitude,
    String? latitude,
    double? minPrice,
    double? maxPrice,
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    if (failure != null) throw failure!;
    return <Activity>[
      Activity(id: 21, name: '外滩城市寻宝', latitude: 31.235, longitude: 121.475),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClubApiFake implements ClubApi {
  _ClubApiFake({this.failure});
  final Object? failure;

  @override
  Future<List<Club>> searchByName(String name) async {
    if (failure != null) throw failure!;
    return <Club>[Club(id: 5, name: '夜跑俱乐部')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MerchantApiFake implements MerchantApi {
  _MerchantApiFake({this.failure});
  final Object? failure;

  @override
  Future<List<Merchant>> searchByName(String name) async {
    if (failure != null) throw failure!;
    return <Merchant>[Merchant(id: 7, memberId: 70, name: '老王咖啡')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CityNodeApiFake implements CityNodeApi {
  _CityNodeApiFake({this.failure});
  final Object? failure;

  @override
  Future<List<CityNodePoi>> nearby({
    required double lat,
    required double lng,
    int radius = 3000,
    String? keyword,
    int? categoryId,
    String? tag,
    String? cityRole,
  }) async {
    if (failure != null) throw failure!;
    return const <CityNodePoi>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<dynamic> _apiOverrides({
  Object? topicFailure,
  Object? activityFailure,
  Object? clubFailure,
  Object? merchantFailure,
}) => <dynamic>[
  topicApiProvider.overrideWithValue(_TopicApiFake(failure: topicFailure)),
  activityApiProvider.overrideWithValue(
    _ActivityApiFake(failure: activityFailure),
  ),
  clubApiProvider.overrideWithValue(_ClubApiFake(failure: clubFailure)),
  merchantApiProvider.overrideWithValue(
    _MerchantApiFake(failure: merchantFailure),
  ),
];

void main() {
  test('俱乐部 401:其余三路结果照常返回,登录门槛单记 loginGated 不算失败', () async {
    final container = ProviderContainer(
      overrides: <dynamic>[
        ..._apiOverrides(clubFailure: _unauthorized()),
      ].cast(),
    );
    addTearDown(container.dispose);

    final bundle = await container.read(
      searchResultsProvider(const SearchQuery(keyword: '交友')).future,
    );

    expect(
      bundle.rows.map((SearchResultRow r) => r.title),
      containsAll(<String>['静安微旅行', '外滩城市寻宝', '老王咖啡']),
      reason: '一路 401 不许把三路成功结果整包丢掉(P0-1)',
    );
    // 401 是真故障还是登录门槛要分开:重试救不了游客,给「去登录」提示。
    expect(bundle.failedTypes, isEmpty);
    expect(bundle.loginGated, isTrue);
    expect(bundle.hasFailure, isFalse);
    expect(bundle.allFailed, isFalse);
  });

  testWidgets('游客结果页:俱乐部 401 仍出卡片 + 「登录后能搜到更多结果」引导', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          ..._apiOverrides(clubFailure: _unauthorized()),
        ].cast(),
        child: const MaterialApp(home: SearchResultPage(keyword: '交友')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('静安微旅行'), findsOneWidget);
    expect(find.text('老王咖啡'), findsOneWidget);
    expect(find.text('没能完成搜索'), findsNothing);
    expect(find.text('登录后能搜到更多结果'), findsOneWidget);
    expect(find.text('部分搜索没有完成，结果可能不全'), findsNothing);
    // tabs 逐路计数与小程序一致:失败那路记 0,不吞别的组。
    expect(find.text('主题 1'), findsOneWidget);
    expect(find.text('俱乐部 0'), findsOneWidget);
  });

  testWidgets('结果页全失败:整页错误文案对齐小程序 allFailed 一档', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          ..._apiOverrides(
            topicFailure: _networkDown(),
            activityFailure: _networkDown(),
            clubFailure: _networkDown(),
            merchantFailure: _networkDown(),
          ),
        ].cast(),
        child: const MaterialApp(home: SearchResultPage(keyword: 'zzz')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索服务暂时不可用，请重试'), findsOneWidget);
    expect(find.text('DioException'), findsNothing);
  });

  testWidgets('地图页:节点一路 401,地图与活动列表照常呈现,图例标「未更新」', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          ..._apiOverrides(),
          cityNodeApiProvider.overrideWithValue(
            _CityNodeApiFake(failure: _unauthorized()),
          ),
          currentMapLocationProvider.overrideWith(
            (ref) async =>
                const MapCoordinate(latitude: 31.23, longitude: 121.47),
          ),
        ].cast(),
        child: const MaterialApp(home: CityNodeSearchPage()),
      ),
    );
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    // P1-5:地图块不再长在 data 分支里 —— 有一路失败也必须看得到地图。
    expect(find.byType(AppleSceneView), findsOneWidget);
    expect(find.text('外滩城市寻宝'), findsOneWidget);
    expect(find.text('商家节点 · 未更新'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('地图页定位永久拒绝:副文案是人话,按钮给「去设置」', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          ..._apiOverrides(),
          currentMapLocationProvider.overrideWith(
            (ref) => throw const MapLocationException(
              '定位权限已被永久关闭，请到系统设置中开启',
              canOpenSettings: true,
            ),
          ),
        ].cast(),
        child: const MaterialApp(home: CityNodeSearchPage()),
      ),
    );
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    expect(find.text('定位权限已被永久关闭，请到系统设置中开启'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });
}
