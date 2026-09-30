import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_gap_logic.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

class _ArrivalPlayApi extends PlayApi {
  _ArrivalPlayApi(this.validationMethod) : super(_client());

  final int? validationMethod;
  final List<({int nodeId, double longitude, double latitude})> arrivals =
      <({int nodeId, double longitude, double latitude})>[];

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async => PlayNodesResult(
    topicId: topicId,
    mode: 1,
    playable: true,
    total: 1,
    doneCount: 0,
    nodes: <PlayNode>[
      PlayNode(
        nodeId: 17,
        name: '到店即可',
        address: '测试点位',
        sortId: 1,
        done: false,
        validationMethod: validationMethod,
      ),
    ],
  );

  @override
  Future<CheckinReward> submitTopicArrive({
    required int topicId,
    required int nodeId,
    required double longitude,
    required double latitude,
    RouteAdvanceToken? routeAdvance,
  }) async {
    arrivals.add((nodeId: nodeId, longitude: longitude, latitude: latitude));
    return const CheckinReward(
      nodeId: 17,
      firstTime: true,
      doneCount: 1,
      total: 1,
      completed: true,
      newBadges: <PlayBadge>[],
    );
  }

  /// 开节点会顺带探测 R14 旅程检定(GET /api/play/encounter,失败静默)。
  /// 这里挡掉真请求,只测到店链本身。
  @override
  Future<Map<String, dynamic>> encounter({
    required int topicId,
    required int nodeId,
  }) async => throw PlayException('本用例不外发 encounter');
}

class _GrantedLocationPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    return Position(
      longitude: 121.4737,
      latitude: 31.2304,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1755518400000),
      accuracy: 4,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  late GeolocatorPlatform originalPlatform;

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _GrantedLocationPlatform();
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalPlatform;
  });

  for (final int? validationMethod in <int?>[null, 0]) {
    testWidgets('validationMethod=${validationMethod ?? 'null'} 到店节点走真实定位完成链', (
      WidgetTester tester,
    ) async {
      final api = _ArrivalPlayApi(validationMethod);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
          child: const MaterialApp(
            home: PlaySessionPage(activityId: 0, topicId: 23),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('到店即可'));
      await tester.pumpAndSettle();

      expect(api.arrivals, hasLength(1));
      expect(api.arrivals.single.nodeId, 17);
      expect(api.arrivals.single.longitude, isNot(121.4737));
      expect(api.arrivals.single.latitude, isNot(31.2304));
      expect(find.text('打卡成功'), findsOneWidget);
      expect(find.textContaining('暂未支持'), findsNothing);
    });
  }

  test('validationMethod 支持后端已定义的 0–7，未知值必须 fail-closed', () {
    for (final int method in <int>[0, 1, 2, 3, 4, 5, 6, 7]) {
      expect(
        playNodeInteractionFor(
          mode: 1,
          node: PlayNode(
            nodeId: 17,
            name: '已知方式',
            address: '',
            sortId: 1,
            done: false,
            validationMethod: method,
          ),
        ),
        isNot(PlayNodeInteraction.unsupported),
        reason: '后端合同已定义 validationMethod=$method',
      );
    }

    expect(
      playNodeInteractionFor(
        mode: 1,
        node: const PlayNode(
          nodeId: 17,
          name: '未知方式',
          address: '',
          sortId: 1,
          done: false,
          validationMethod: 99,
        ),
      ),
      PlayNodeInteraction.unsupported,
    );
  });

  testWidgets('未知打卡方式显示明确配置错误，不误调定位完成链', (WidgetTester tester) async {
    final api = _ArrivalPlayApi(99);
    final List<FlutterErrorDetails> diagnostics = <FlutterErrorDetails>[];
    final originalHandler = FlutterError.onError;
    FlutterError.onError = diagnostics.add;
    addTearDown(() => FlutterError.onError = originalHandler);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
        child: const MaterialApp(
          home: PlaySessionPage(activityId: 0, topicId: 23),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('配置异常'), findsOneWidget);
    await tester.tap(find.text('到店即可'));
    await tester.pump();
    FlutterError.onError = originalHandler;

    expect(api.arrivals, isEmpty);
    expect(find.text('节点验证配置异常（方式 99），请联系活动方'), findsOneWidget);
    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.exception,
      isA<UnsupportedPlayValidationMethod>(),
    );
  });
}
