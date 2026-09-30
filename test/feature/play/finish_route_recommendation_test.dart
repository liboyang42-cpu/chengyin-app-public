// 完赛推荐「附近下一程」—— 真源 pages/play/finish-route-recommendation.js +
// pages/play/index.js :5541 loadFinishRouteRecommendation。
import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/finish_route_recommendation.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

class _FakeActivityApi extends ActivityApi {
  _FakeActivityApi({this.rows = const <Activity>[], this.fails = false})
    : super(_client());

  final List<Activity> rows;
  final bool fails;
  final List<Map<String, String?>> requests = <Map<String, String?>>[];

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
    requests.add(<String, String?>{
      'sortType': sortType,
      'longitude': longitude,
      'latitude': latitude,
      'pageNum': '$pageNum',
      'pageSize': '$pageSize',
    });
    if (fails) throw Exception('offline');
    return rows;
  }
}

class _LocationSource implements PlayNavigationLocationSource {
  _LocationSource({this.position, this.fails = false});

  final PlayNavigationPosition? position;
  final bool fails;
  int calls = 0;

  @override
  Future<PlayNavigationPosition> current() async {
    calls += 1;
    if (fails) throw PlayException('需要定位权限才能开始前往');
    return position!;
  }

  @override
  Stream<PlayNavigationPosition> watch() =>
      const Stream<PlayNavigationPosition>.empty();
}

const PlayNode _doneWithCoords = PlayNode(
  nodeId: 2,
  name: '已到达点',
  address: '',
  sortId: 2,
  done: true,
  latitude: 31.23,
  longitude: 121.48,
);

const PlayNode _laterDone = PlayNode(
  nodeId: 3,
  name: '最后到达点',
  address: '',
  sortId: 5,
  done: true,
  latitude: 31.24,
  longitude: 121.49,
);

Activity _row({
  required int id,
  String name = '周末城市漫游',
  int? topicId,
  double? distance,
  String? addressName,
  String? address,
  String? imgUrl,
  double? minAmount,
}) => Activity(
  id: id,
  name: name,
  topicId: topicId,
  distance: distance,
  addressName: addressName,
  address: address,
  imgUrl: imgUrl,
  minAmount: minAmount,
);

Future<void> _pumpSlot(
  WidgetTester tester, {
  required bool flagOn,
  required _FakeActivityApi api,
  required _LocationSource location,
  int? activityId,
  int? topicId,
  List<PlayNode> nodes = const <PlayNode>[],
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/finish',
    routes: <RouteBase>[
      GoRoute(
        path: '/finish',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: FinishRouteRecommendationSlot(
              activityId: activityId,
              topicId: topicId,
              nodes: nodes,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/activity/:id',
        builder: (_, state) => Text('activity:${state.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        featureFlagProvider.overrideWith((_, _) => flagOn),
        activityApiProvider.overrideWithValue(api),
        playNavigationLocationSourceProvider.overrideWithValue(location),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

void main() {
  group('纯逻辑', () {
    test('distanceText:>=1km 走公里一位小数,否则四舍五入米', () {
      expect(cyDistanceText(null), '');
      expect(cyDistanceText(305), '305 米');
      expect(cyDistanceText(1000), '1.0 公里');
      expect(cyDistanceText(1234), '1.2 公里');
    });

    test('resolveOrigin:有效坐标优先,否则回退最后打卡节点,都没有为 null', () {
      expect(resolveFinishOrigin(latitude: 31.1, longitude: 121.4), (
        latitude: 31.1,
        longitude: 121.4,
      ));
      expect(
        resolveFinishOrigin(
          latitude: double.nan,
          longitude: 121.4,
          nodes: const <PlayNode>[_doneWithCoords, _laterDone],
        ),
        (latitude: 31.24, longitude: 121.49),
      );
      expect(resolveFinishOrigin(nodes: const <PlayNode>[_doneWithCoords]), (
        latitude: 31.23,
        longitude: 121.48,
      ));
      expect(
        resolveFinishOrigin(
          nodes: const <PlayNode>[
            PlayNode(
              nodeId: 9,
              name: '没坐标',
              address: '',
              sortId: 9,
              done: true,
            ),
          ],
        ),
        isNull,
      );
    });

    test('pickCandidate:标题/距离/地址/价格的显示口径', () {
      final FinishRouteRecommendation? card =
          pickFinishRouteCandidate(<Activity>[
            _row(
              id: 3,
              distance: 305,
              addressName: '外滩源',
              imgUrl: 'a.jpg,b.jpg',
              minAmount: 12.5,
            ),
          ]);
      expect(card!.id, 3);
      expect(card.cover, 'a.jpg');
      expect(card.meta, '305 米 · 外滩源');
      expect(card.priceText, '¥12.5 起');

      expect(
        pickFinishRouteCandidate(<Activity>[
          _row(id: 4, minAmount: 0),
        ])!.priceText,
        '免费',
      );
      expect(
        pickFinishRouteCandidate(<Activity>[_row(id: 4, name: '')])!.title,
        '附近路线',
      );
      expect(pickFinishRouteCandidate(<Activity>[_row(id: 4)])!.priceText, '');
      expect(
        pickFinishRouteCandidate(<Activity>[
          _row(id: 4, address: '四川中路'),
        ])!.meta,
        '四川中路',
      );
      expect(pickFinishRouteCandidate(const <Activity>[]), isNull);
    });

    test('pickCandidate:本次活动与本主题各自独立排除,缺一个不连带', () {
      final List<Activity> rows = <Activity>[
        _row(id: 3, topicId: 9),
        _row(id: 5, topicId: 9),
        _row(id: 7, topicId: 11),
      ];
      expect(
        pickFinishRouteCandidate(
          rows,
          currentActivityId: 3,
          currentTopicId: 9,
        )!.id,
        7,
      );
      expect(
        pickFinishRouteCandidate(rows, currentActivityId: 3)!.id,
        5,
        reason: '没报主题时只按活动排除,同主题的其它场次仍可推',
      );
      expect(
        pickFinishRouteCandidate(rows, currentTopicId: 9)!.id,
        7,
        reason: '没报活动时同主题整片排除(3、5 都挂主题 9)',
      );
    });
  });

  group('弹层槽位', () {
    testWidgets('flag 关闭:不打接口也不渲染', (tester) async {
      final api = _FakeActivityApi();
      final location = _LocationSource(
        position: const PlayNavigationPosition(latitude: 31, longitude: 121),
      );
      await _pumpSlot(tester, flagOn: false, api: api, location: location);
      expect(
        find.byKey(const Key('finish-route-recommendation')),
        findsNothing,
      );
      expect(api.requests, isEmpty);
      expect(location.calls, 0);
    });

    testWidgets('flag 开:按距离排序取最近候选,点击进活动详情', (tester) async {
      final api = _FakeActivityApi(
        rows: <Activity>[
          _row(
            id: 8,
            distance: 900,
            addressName: '南京路',
            imgUrl: 'x.jpg',
            minAmount: 12,
          ),
        ],
      );
      final location = _LocationSource(
        position: const PlayNavigationPosition(
          latitude: 31.23,
          longitude: 121.47,
        ),
      );
      await _pumpSlot(
        tester,
        flagOn: true,
        api: api,
        location: location,
        activityId: 77,
        topicId: 9,
      );
      expect(find.text('附近下一程'), findsOneWidget);
      expect(find.text('¥12 起'), findsOneWidget);
      expect(find.text('900 米 · 南京路'), findsOneWidget);
      expect(api.requests.single['sortType'], '1');
      expect(api.requests.single['pageSize'], '5');
      expect(api.requests.single['latitude'], '31.23');

      await tester.tap(find.byKey(const Key('finish-route-recommendation')));
      await tester.pumpAndSettle();
      expect(find.text('activity:8'), findsOneWidget);
    });

    testWidgets('定位不可用回退最后打卡节点坐标;拿不到原点则不打接口', (tester) async {
      final api = _FakeActivityApi(rows: <Activity>[_row(id: 8, name: '续程')]);
      await _pumpSlot(
        tester,
        flagOn: true,
        api: api,
        location: _LocationSource(fails: true),
        nodes: const <PlayNode>[_doneWithCoords],
      );
      expect(api.requests.single['latitude'], '31.23');
      expect(find.text('续程'), findsOneWidget);

      final offline = _FakeActivityApi(fails: true);
      await _pumpSlot(
        tester,
        flagOn: true,
        api: offline,
        location: _LocationSource(fails: true),
      );
      expect(offline.requests, isEmpty);
      expect(
        find.byKey(const Key('finish-route-recommendation')),
        findsNothing,
      );
    });
  });
}
