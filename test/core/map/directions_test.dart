import 'package:chengyin_app/core/map/directions.dart';
import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MapCoordinate _a = MapCoordinate(latitude: 31.2300, longitude: 121.4700);
const MapCoordinate _b = MapCoordinate(latitude: 31.2320, longitude: 121.4720);
const MapCoordinate _c = MapCoordinate(latitude: 31.2340, longitude: 121.4740);

Map<String, Object?> _nativeRoute({
  required MapCoordinate from,
  required MapCoordinate to,
  double distance = 320,
  double eta = 240,
}) => <String, Object?>{
  'distance': distance,
  'expectedTravelTime': eta,
  'polyline': <double>[
    from.latitude,
    from.longitude,
    from.latitude,
    to.longitude,
    to.latitude,
    to.longitude,
  ],
  'steps': <Map<String, Object?>>[
    <String, Object?>{
      'instruction': '',
      'distance': 0.0,
      'latitude': from.latitude,
      'longitude': from.longitude,
    },
    <String, Object?>{
      'instruction': '左转进入南京东路',
      'distance': 180.0,
      'latitude': from.latitude,
      'longitude': to.longitude,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(DirectionsClient.channelName);
  final List<MethodCall> calls = <MethodCall>[];

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('解析原生路线:折线、距离、ETA、步骤(跳过空指令)', () async {
    mock((_) async => _nativeRoute(from: _a, to: _b));
    final DirectionsRoute route = await DirectionsClient().directions(
      _a,
      _b,
      mode: DirectionsMode.walking,
    );

    expect(calls.single.method, 'calculate');
    expect(calls.single.arguments, <String, Object?>{
      'fromLat': _a.latitude,
      'fromLng': _a.longitude,
      'toLat': _b.latitude,
      'toLng': _b.longitude,
      'mode': 'walking',
    });
    expect(route.polyline, hasLength(3));
    expect(route.polyline.last, _b);
    expect(route.distanceMeters, 320);
    expect(route.eta, const Duration(seconds: 240));
    expect(route.steps.map((RouteStep s) => s.instruction), <String>[
      '左转进入南京东路',
    ]);
    expect(route.steps.single.distanceMeters, 180);
    expect(route.isFallback, isFalse);
    expect(route.notice, isNull);
  });

  test('无路线(原生报错)→ 回退为直线并给出可见提示', () async {
    mock((_) async => throw PlatformException(code: 'no_route'));
    final DirectionsRoute route = await DirectionsClient().directions(_a, _b);

    expect(route.isFallback, isTrue);
    expect(route.polyline, <MapCoordinate>[_a, _b]);
    expect(route.distanceMeters, closeTo(293, 5));
    expect(route.eta, isNull);
    expect(route.steps, isEmpty);
    expect(route.notice, DirectionsClient.fallbackNotice);
  });

  test('没有原生桥(Android / 未注册)→ 同样回退直线', () async {
    // 不注册 mock:MethodChannel 抛 MissingPluginException。
    final DirectionsRoute route = await DirectionsClient().directions(_a, _b);
    expect(route.isFallback, isTrue);
    expect(route.notice, DirectionsClient.fallbackNotice);
  });

  test('公交只有 ETA 没有折线 → 直线折线 + 公交提示,距离/ETA 保留', () async {
    mock(
      (_) async => <String, Object?>{
        'distance': 2000.0,
        'expectedTravelTime': 900.0,
        'polyline': <double>[],
        'steps': <Object?>[],
      },
    );
    final DirectionsRoute route = await DirectionsClient().directions(
      _a,
      _b,
      mode: DirectionsMode.transit,
    );
    expect(calls.single.arguments['mode'], 'transit');
    expect(route.polyline, <MapCoordinate>[_a, _b]);
    expect(route.eta, const Duration(minutes: 15));
    expect(route.distanceMeters, 2000);
    expect(route.isFallback, isFalse);
    expect(route.notice, DirectionsClient.transitNotice);
  });

  test('同一段同模式命中缓存,并发请求串行发出', () async {
    int inFlight = 0;
    int maxInFlight = 0;
    mock((MethodCall call) async {
      inFlight++;
      maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
      final Map<Object?, Object?> a = call.arguments as Map<Object?, Object?>;
      return _nativeRoute(
        from: MapCoordinate(
          latitude: a['fromLat']! as double,
          longitude: a['fromLng']! as double,
        ),
        to: MapCoordinate(
          latitude: a['toLat']! as double,
          longitude: a['toLng']! as double,
        ),
      );
    });
    final DirectionsClient client = DirectionsClient();
    await Future.wait(<Future<DirectionsRoute>>[
      client.directions(_a, _b),
      client.directions(_b, _c),
      client.directions(_a, _b),
    ]);
    expect(maxInFlight, 1);
    expect(calls, hasLength(2));
    await client.directions(_a, _b, mode: DirectionsMode.driving);
    expect(calls, hasLength(3));
  });

  test('routeThrough 逐段请求并拼接;某段失败只让该段走直线', () async {
    mock((MethodCall call) async {
      final Map<Object?, Object?> a = call.arguments as Map<Object?, Object?>;
      if (a['toLat'] == _c.latitude) throw PlatformException(code: 'no_route');
      return _nativeRoute(from: _a, to: _b, distance: 300, eta: 200);
    });
    final DirectionsRoute route = await DirectionsClient().routeThrough(
      <MapCoordinate>[_a, _b, _c],
    );

    expect(calls, hasLength(2));
    // 第一段 3 点 + 第二段直线 2 点,接缝去重 → 4 点。
    expect(route.polyline, <MapCoordinate>[
      _a,
      const MapCoordinate(latitude: 31.2300, longitude: 121.4720),
      _b,
      _c,
    ]);
    expect(route.distanceMeters, closeTo(300 + 293, 5));
    expect(route.eta, isNull, reason: '有一段没有 ETA,总 ETA 不能假装准确');
    expect(route.steps, hasLength(1));
    expect(route.isFallback, isTrue);
    expect(route.notice, DirectionsClient.fallbackNotice);
  });

  test('openInMaps 把目的地与 directionsMode 交给原生', () async {
    mock((_) async => true);
    final bool ok = await DirectionsClient().openInMaps(
      _b,
      name: '外滩',
      mode: DirectionsMode.driving,
    );
    expect(ok, isTrue);
    expect(calls.single.method, 'openInMaps');
    expect(calls.single.arguments, <String, Object?>{
      'lat': _b.latitude,
      'lng': _b.longitude,
      'name': '外滩',
      'mode': 'driving',
    });
  });

  test('openInMaps 没有原生桥 → false(调用方走 map_launcher 兜底)', () async {
    expect(await DirectionsClient().openInMaps(_b, name: '外滩'), isFalse);
  });

  test('ETA/距离文案', () {
    expect(formatRouteDistance(850), '850 m');
    expect(formatRouteDistance(1234), '1.2 km');
    expect(formatRouteEta(const Duration(seconds: 50)), '1 分钟');
    expect(formatRouteEta(const Duration(minutes: 75)), '1 小时 15 分钟');
  });
}
