import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/city_node_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/city_node_poi.dart';
import 'package:chengyin_app/feature/map/map_controller.dart';
import 'package:chengyin_app/feature/search/city_node_search_page.dart';
import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:dio/dio.dart';

class _FakeCityNodeApi implements CityNodeApi {
  double? lat;
  double? lng;
  int? radius;
  String? keyword;
  int? categoryId;
  String? tag;
  String? cityRole;

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
    this.lat = lat;
    this.lng = lng;
    this.radius = radius;
    this.keyword = keyword;
    this.categoryId = categoryId;
    this.tag = tag;
    this.cityRole = cityRole;
    return const <CityNodePoi>[
      CityNodePoi(
        poiId: 7,
        name: '远处节点',
        lat: 31.23,
        lng: 121.47,
        distance: 1200,
      ),
      CityNodePoi(
        poiId: 8,
        name: '附近节点',
        lat: 31.24,
        lng: 121.48,
        distance: 280,
      ),
      CityNodePoi(poiId: 9, name: '距离未知节点', lat: 31.25, lng: 121.49),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeActivityApi implements ActivityApi {
  _FakeActivityApi([this.returned]);

  // 允许注入带日期/票价的活动行,验证客户端兜底过滤。
  List<Activity>? returned;
  String? keyword;
  String? categoryId;
  String? sortType;
  String? longitude;
  String? latitude;
  double? minPrice;
  double? maxPrice;
  String? startDate;
  String? endDate;

  @override
  Future<List<Activity>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    String? sortType,
    String? longitude,
    String? latitude,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    this.keyword = keyword;
    this.categoryId = categoryId;
    this.sortType = sortType;
    this.longitude = longitude;
    this.latitude = latitude;
    return returned ??
        <Activity>[
          Activity(
            id: 21,
            name: '有坐标活动',
            latitude: 31.235,
            longitude: 121.475,
            topicId: 31,
          ),
          Activity(id: 22, name: '无坐标活动'),
        ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('城市节点搜索用当次中心点与筛选项拉节点', () async {
    final api = _FakeCityNodeApi();
    final activityApi = _FakeActivityApi();
    final range = DateTimeRange(
      start: DateTime(2026, 8, 23),
      end: DateTime(2026, 8, 24),
    );
    final container = ProviderContainer(
      overrides: <dynamic>[
        cityNodeApiProvider.overrideWithValue(api),
        activityApiProvider.overrideWithValue(activityApi),
        currentMapLocationProvider.overrideWith(
          (ref) async =>
              const MapCoordinate(latitude: 31.23, longitude: 121.47),
        ),
      ].cast(),
    );
    addTearDown(container.dispose);

    final result = await container.read(
      cityNodeSearchProvider(
        CityNodeSearchQuery(
          keyword: '咖啡',
          categoryId: 6,
          tag: '宠物友好',
          cityRole: '街区客厅',
          sortType: 2,
          minPrice: 50,
          maxPrice: 300,
          dateRange: range,
        ),
      ).future,
    );

    expect(
      result.nodes.map((CityNodePoi node) => node.name),
      <String>['附近节点', '远处节点', '距离未知节点'],
      reason: '只用服务端基于当次坐标返回的真实 distance；未知距离放末尾',
    );
    expect(
      (api.lat, api.lng, api.radius),
      (31.23, 121.47, 20000),
      reason: '中心点必须来自当次定位，范围对齐地图搜索上限',
    );
    expect((api.keyword, api.categoryId), ('咖啡', 6));
    expect((api.tag, api.cityRole), ('宠物友好', '街区客厅'));
    expect(
      (
        activityApi.keyword,
        activityApi.categoryId,
        activityApi.sortType,
        activityApi.longitude,
        activityApi.latitude,
      ),
      ('咖啡', '6', '2', '121.47', '31.23'),
      reason: '活动与商家节点必须使用同一次地图中心与关键词',
    );
    // 后端 activityList 不收日期/价格(见 ApiActivityController 签名):
    // 请求侧绝不能再塞 min_price/start_date 这种死参数,改由客户端兜底过滤。
    expect(
      (activityApi.minPrice, activityApi.maxPrice),
      (null, null),
      reason: '日期/价格不下发后端 —— 后端不收,发了是死参数',
    );
    expect(
      (activityApi.startDate, activityApi.endDate),
      (null, null),
      reason: '日期不下发后端',
    );
    expect(
      result.activities.map((Activity activity) => activity.name),
      <String>['有坐标活动', '无坐标活动'],
      reason: '返回行无日期/票价 → 客户端过滤原样放行,无坐标活动仍可达',
    );
    expect(
      result.scene.points.map((MapPoint point) => point.id),
      containsAll(<String>['activity-21', 'city-node-8']),
      reason: '地图同时呈现真坐标活动和商家节点',
    );
    expect(
      result.scene.points.map((MapPoint point) => point.id),
      isNot(contains('activity-22')),
      reason: '活动缺坐标时 fail closed，不伪造 marker',
    );

    await container.read(
      cityNodeSearchProvider(
        const CityNodeSearchQuery(
          keyword: '咖啡',
          center: MapCoordinate(latitude: 31.25, longitude: 121.49),
        ),
      ).future,
    );
    expect(
      (api.lat, api.lng),
      (31.25, 121.49),
      reason: '拖动地图后必须改用新中心点重查，不能继续锁在定位坐标',
    );
  });

  test('地图搜索客户端兜底过滤:日期区间 + 价格区间同时命中', () async {
    final activityApi = _FakeActivityApi(<Activity>[
      Activity(id: 1, name: '早于区间', startDate: '2026-08-20', minAmount: 80),
      Activity(id: 2, name: '区间内', startDate: '2026-08-23', minAmount: 100),
      Activity(id: 3, name: '超价格', startDate: '2026-08-23', minAmount: 999),
      Activity(id: 4, name: '无价无期'),
    ]);
    final container = ProviderContainer(
      overrides: <dynamic>[
        cityNodeApiProvider.overrideWithValue(_FakeCityNodeApi()),
        activityApiProvider.overrideWithValue(activityApi),
        currentMapLocationProvider.overrideWith(
          (ref) async =>
              const MapCoordinate(latitude: 31.23, longitude: 121.47),
        ),
      ].cast(),
    );
    addTearDown(container.dispose);

    final result = await container.read(
      cityNodeSearchProvider(
        CityNodeSearchQuery(
          keyword: '咖啡',
          dateRange: DateTimeRange(
            start: DateTime(2026, 8, 23),
            end: DateTime(2026, 8, 24),
          ),
          minPrice: 50,
          maxPrice: 300,
        ),
      ).future,
    );

    expect(
      result.activities.map((Activity a) => a.name),
      containsAll(<String>['区间内', '无价无期']),
      reason: '区间内 + 无日期/票价(不可判)放行',
    );
    expect(
      result.activities.map((Activity a) => a.name),
      isNot(contains('早于区间')),
      reason: '开始日期早于筛选区间下界 → 客户端剔除',
    );
    expect(
      result.activities.map((Activity a) => a.name),
      isNot(contains('超价格')),
      reason: '票价高于筛选上界 → 客户端剔除',
    );
  });

  testWidgets('地图搜索补齐主题路线、商家、节点、图层、标签与空态文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          cityNodeSearchProvider.overrideWith((ref, query) async {
            return const CityNodeSearchResult(
              center: MapCoordinate(latitude: 31.23, longitude: 121.47),
              activities: <Activity>[],
              nodes: <CityNodePoi>[],
            );
          }),
        ].cast(),
        child: const MaterialApp(
          home: CityNodeSearchPage(initialKeyword: '咖啡'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    expect(find.text('关联主题路线'), findsOneWidget);
    expect(find.text('商家发现'), findsOneWidget);
    expect(find.text('商家节点'), findsWidgets);
    expect(find.text('地图图层说明'), findsOneWidget);
    expect(find.text('探索标签'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('换个关键词，或拖动地图看看别处'), findsOneWidget);
  });

  // 定位被永久拒绝时「重试」是死循环 —— 系统不会再弹第二次授权,
  // 出口只能是去设置(口径对齐 route_preview_sheet 的「去设置」)。
  testWidgets('★ 定位权限不可用:错误态给「去设置」而不是重试死循环', (WidgetTester tester) async {
    // 本文件既有用例的口径:地图常驻后默认 800x600 测试面会把错误态挤溢出,
    // 手机口径按 main 的 390x844 量。
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          cityNodeSearchProvider.overrideWith((ref, query) async {
            throw const MapLocationException(
              '定位权限已被永久关闭，请到系统设置中开启',
              canOpenSettings: true,
            );
          }),
        ].cast(),
        child: const MaterialApp(home: CityNodeSearchPage()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    expect(find.text('定位权限已被永久关闭，请到系统设置中开启'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('普通加载失败仍是「地图结果没加载出来 + 重试」', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          cityNodeSearchProvider.overrideWith((ref, query) async {
            throw Exception('网络开小差了');
          }),
        ].cast(),
        child: const MaterialApp(home: CityNodeSearchPage()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    expect(find.text('地图结果没加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('去设置'), findsNothing);
  });

  testWidgets('地图和列表同时呈现活动与商家节点，无坐标活动不丢失', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          cityNodeSearchProvider.overrideWith((ref, query) async {
            return CityNodeSearchResult(
              center: const MapCoordinate(latitude: 31.23, longitude: 121.47),
              activities: <Activity>[
                Activity(
                  id: 21,
                  name: '外滩城市寻宝',
                  latitude: 31.235,
                  longitude: 121.475,
                  topicId: 31,
                ),
                Activity(id: 22, name: '无坐标工坊'),
              ],
              nodes: const <CityNodePoi>[CityNodePoi(poiId: 8, name: '街角咖啡')],
            );
          }),
        ].cast(),
        child: const MaterialApp(home: CityNodeSearchPage()),
      ),
    );
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    expect(find.text('活动'), findsWidgets);
    expect(find.text('商家节点'), findsWidgets);
    expect(find.text('查看全部 3 个结果'), findsOneWidget);
    // 地图固定在列表上方(P1-5 地图常驻),无坐标提示紧跟结果数头部,列表顶部即可见。
    expect(find.text('1 个活动暂未提供位置，仅在列表中显示'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('外滩城市寻宝'), findsOneWidget);
    expect(find.text('无坐标工坊'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('街角咖啡'), findsOneWidget);
    expect(find.byKey(const Key('search-map-filter')), findsOneWidget);
  });

  testWidgets('地图筛选应用探索标签与城市角色后重查同一个节点接口', (WidgetTester tester) async {
    CityNodeSearchQuery? requestedQuery;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          cityNodeSearchProvider.overrideWith((ref, query) async {
            requestedQuery = query;
            return const CityNodeSearchResult(
              center: MapCoordinate(latitude: 31.23, longitude: 121.47),
              activities: <Activity>[],
              nodes: <CityNodePoi>[],
            );
          }),
        ].cast(),
        child: const MaterialApp(home: CityNodeSearchPage()),
      ),
    );

    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-map-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('search-filter-merchant-tag')),
      '宠物友好',
    );
    await tester.enterText(
      find.byKey(const Key('search-filter-merchant-city-role')),
      '街区客厅',
    );
    await tester.ensureVisible(find.byKey(const Key('search-filter-apply')));
    await tester.tap(find.byKey(const Key('search-filter-apply')));
    await tester.pumpAndSettle();

    expect(requestedQuery?.tag, '宠物友好');
    expect(requestedQuery?.cityRole, '街区客厅');
  });

  testWidgets('游客 401 → 登录引导，不把原始 DioException 画到屏幕上', (
    WidgetTester tester,
  ) async {
    // 生产实测:`/api/city/nodes` 不在后端匿名放行名单里,游客必撞 401。
    // 此前这一屏是整段英文异常 + MDN 链接(REPORT-sim-square 问题 2)。
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          activityApiProvider.overrideWithValue(_FakeActivityApi()),
          cityNodeApiProvider.overrideWithValue(_UnauthorizedCityNodeApi()),
          currentMapLocationProvider.overrideWith(
            (ref) async =>
                const MapCoordinate(latitude: 31.23, longitude: 121.47),
          ),
        ].cast(),
        child: const MaterialApp(
          home: CityNodeSearchPage(initialKeyword: '咖啡'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    expect(find.text('登录后搜索附近的城市节点'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('地图结果没加载出来'), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('developer.mozilla.org'), findsNothing);
  });

  testWidgets('非登录故障淡化成「商家节点 · 未更新」，不会误报成要登录', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          activityApiProvider.overrideWithValue(_FakeActivityApi()),
          cityNodeApiProvider.overrideWithValue(_ServerErrorCityNodeApi()),
          currentMapLocationProvider.overrideWith(
            (ref) async =>
                const MapCoordinate(latitude: 31.23, longitude: 121.47),
          ),
        ].cast(),
        child: const MaterialApp(
          home: CityNodeSearchPage(initialKeyword: '咖啡'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用当前位置搜索'));
    await tester.pumpAndSettle();

    expect(find.text('商家节点 · 未更新'), findsOneWidget);
    expect(find.text('登录后搜索附近的城市节点'), findsNothing);
  });
}

DioException _dioError(int statusCode) {
  final RequestOptions options = RequestOptions(path: '/api/city/nodes');
  return DioException(
    requestOptions: options,
    response: Response<Object?>(
      requestOptions: options,
      statusCode: statusCode,
    ),
    type: DioExceptionType.badResponse,
  );
}

class _UnauthorizedCityNodeApi implements CityNodeApi {
  @override
  Future<List<CityNodePoi>> nearby({
    required double lat,
    required double lng,
    int radius = 3000,
    String? keyword,
    int? categoryId,
    String? tag,
    String? cityRole,
  }) async => throw _dioError(401);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ServerErrorCityNodeApi implements CityNodeApi {
  @override
  Future<List<CityNodePoi>> nearby({
    required double lat,
    required double lng,
    int radius = 3000,
    String? keyword,
    int? categoryId,
    String? tag,
    String? cityRole,
  }) async => throw _dioError(500);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
