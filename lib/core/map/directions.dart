// 真实道路路线规划(决策 D7)—— Dart 侧模型 + `com.chengyin.app/directions` 通道。
//
// 原生侧:ios/Runner/DirectionsBridge.swift(MKDirections / MKMapItem.openMaps)。
// Android(决策 D1)没有注册通道 → MissingPluginException → 走直线回退,不维护双实现。
//
// ★ 坐标:本文件进出一律 GCJ-02(与后端节点坐标同系)。国行 MapKit 的道路数据
//   就是 GCJ-02,节点坐标可以原样喂;设备 GPS(WGS84)要先经 core/util/coord.dart
//   换算,见 device_location.dart。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'map_scene.dart';

enum DirectionsMode { walking, driving, transit }

extension DirectionsModeLabel on DirectionsMode {
  String get label => switch (this) {
    DirectionsMode.walking => '步行',
    DirectionsMode.driving => '驾车',
    DirectionsMode.transit => '公交',
  };
}

class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.coordinate,
  });

  final String instruction;
  final double distanceMeters;

  /// 该步开始(即转弯动作发生)的位置。
  final MapCoordinate coordinate;
}

class DirectionsRoute {
  const DirectionsRoute({
    required this.polyline,
    required this.distanceMeters,
    required this.eta,
    required this.steps,
    this.isFallback = false,
    this.notice,
  });

  final List<MapCoordinate> polyline;
  final double distanceMeters;

  /// null = 不知道(直线回退时不编一个时间出来)。
  final Duration? eta;
  final List<RouteStep> steps;

  /// 至少有一段没拿到道路路线,按直线画的。
  final bool isFallback;

  /// 需要让用户看见的说明(回退 / 公交无分步)。
  final String? notice;
}

/// 两点球面距离(米)。
double routeDistanceMeters(MapCoordinate a, MapCoordinate b) {
  const double r = 6371000;
  final double dLat = _rad(b.latitude - a.latitude);
  final double dLng = _rad(b.longitude - a.longitude);
  final double h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

double _rad(double deg) => deg * math.pi / 180;

String formatRouteDistance(double meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(1)} km'
    : '${meters.round()} m';

String formatRouteEta(Duration eta) {
  final int minutes = math.max(1, (eta.inSeconds / 60).round());
  if (minutes < 60) return '$minutes 分钟';
  final int rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} 小时' : '${minutes ~/ 60} 小时 $rest 分钟';
}

class DirectionsClient {
  DirectionsClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.chengyin.app/directions';
  static const String fallbackNotice = '暂时无法规划道路路线，已按直线显示';
  static const String transitNotice = '公交暂无分步路线，可在「地图」中查看换乘';

  final MethodChannel _channel;

  // MKDirections 有频率限制(约 50 次/分钟,超了直接报 throttled):
  // 串行发 + 同段同模式缓存。ponytail: 缓存不过期、不限大小,一次导航会话量级够用。
  final Map<String, DirectionsRoute> _cache = <String, DirectionsRoute>{};
  Future<void> _tail = Future<void>.value();

  Future<DirectionsRoute> directions(
    MapCoordinate from,
    MapCoordinate to, {
    DirectionsMode mode = DirectionsMode.walking,
  }) {
    final String key =
        '${mode.name}|${from.latitude.toStringAsFixed(5)},'
        '${from.longitude.toStringAsFixed(5)}|'
        '${to.latitude.toStringAsFixed(5)},${to.longitude.toStringAsFixed(5)}';
    final Future<DirectionsRoute> result = _tail.then((_) async {
      final DirectionsRoute? hit = _cache[key];
      if (hit != null) return hit;
      final DirectionsRoute route = await _request(from, to, mode);
      // 回退结果不缓存:下次(比如网络恢复)还该再试道路路线。
      if (!route.isFallback) _cache[key] = route;
      return route;
    });
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// 多节点顺序路线:逐段请求再拼接。
  Future<DirectionsRoute> routeThrough(
    List<MapCoordinate> points, {
    DirectionsMode mode = DirectionsMode.walking,
  }) async {
    final List<DirectionsRoute> legs = <DirectionsRoute>[
      for (int i = 0; i + 1 < points.length; i++)
        await directions(points[i], points[i + 1], mode: mode),
    ];
    if (legs.isEmpty) {
      return DirectionsRoute(
        polyline: List<MapCoordinate>.of(points),
        distanceMeters: 0,
        eta: Duration.zero,
        steps: const <RouteStep>[],
      );
    }
    final List<MapCoordinate> polyline = <MapCoordinate>[];
    for (final DirectionsRoute leg in legs) {
      polyline.addAll(
        polyline.isNotEmpty && leg.polyline.first == polyline.last
            ? leg.polyline.skip(1)
            : leg.polyline,
      );
    }
    final bool fallback = legs.any((DirectionsRoute l) => l.isFallback);
    return DirectionsRoute(
      polyline: polyline,
      distanceMeters: legs.fold(0, (double s, l) => s + l.distanceMeters),
      eta: legs.any((DirectionsRoute l) => l.eta == null)
          ? null
          : legs.fold<Duration>(Duration.zero, (Duration s, l) => s + l.eta!),
      steps: <RouteStep>[for (final DirectionsRoute l in legs) ...l.steps],
      isFallback: fallback,
      notice: fallback
          ? fallbackNotice
          : legs
                .map((DirectionsRoute l) => l.notice)
                .whereType<String>()
                .firstOrNull,
    );
  }

  /// 交给 Apple 地图导航。false = 没打开(无原生桥 / 系统拒绝),调用方自己兜底。
  Future<bool> openInMaps(
    MapCoordinate to, {
    required String name,
    DirectionsMode mode = DirectionsMode.walking,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('openInMaps', <String, Object?>{
            'lat': to.latitude,
            'lng': to.longitude,
            'name': name,
            'mode': mode.name,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Apple 地图底图 + 折线的静态预览 PNG。null = 不可用(Android / 快照失败),界面不画图。
  Future<Uint8List?> snapshot(
    DirectionsRoute route, {
    required double width,
    required double height,
    MapCoordinate? user,
    bool dark = true,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>(
        'snapshot',
        <String, Object?>{
          'polyline': <double>[
            for (final MapCoordinate c in route.polyline) ...<double>[
              c.latitude,
              c.longitude,
            ],
          ],
          'width': width,
          'height': height,
          'userLat': user?.latitude,
          'userLng': user?.longitude,
          'dark': dark,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<DirectionsRoute> _request(
    MapCoordinate from,
    MapCoordinate to,
    DirectionsMode mode,
  ) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel
          .invokeMapMethod<Object?, Object?>('calculate', <String, Object?>{
            'fromLat': from.latitude,
            'fromLng': from.longitude,
            'toLat': to.latitude,
            'toLng': to.longitude,
            'mode': mode.name,
          });
    } on MissingPluginException {
      return _straight(from, to);
    } on PlatformException {
      return _straight(from, to);
    }
    if (raw == null) return _straight(from, to);
    return _parse(raw, from, to, mode) ?? _straight(from, to);
  }

  static DirectionsRoute? _parse(
    Map<Object?, Object?> raw,
    MapCoordinate from,
    MapCoordinate to,
    DirectionsMode mode,
  ) {
    final Object? distance = raw['distance'];
    final Object? eta = raw['expectedTravelTime'];
    if (distance is! num || eta is! num) return null;
    final List<double> flat = <double>[
      for (final Object? v in (raw['polyline'] as List<Object?>?) ?? const [])
        if (v is num) v.toDouble(),
    ];
    final List<MapCoordinate> polyline = <MapCoordinate>[
      for (int i = 0; i + 1 < flat.length; i += 2)
        MapCoordinate(latitude: flat[i], longitude: flat[i + 1]),
    ];
    final List<RouteStep> steps = <RouteStep>[];
    for (final Object? s in (raw['steps'] as List<Object?>?) ?? const []) {
      if (s is! Map) continue;
      final Object? text = s['instruction'];
      final Object? d = s['distance'];
      final Object? lat = s['latitude'];
      final Object? lng = s['longitude'];
      if (text is! String || text.trim().isEmpty) continue;
      if (d is! num || lat is! num || lng is! num) continue;
      steps.add(
        RouteStep(
          instruction: text.trim(),
          distanceMeters: d.toDouble(),
          coordinate: MapCoordinate(
            latitude: lat.toDouble(),
            longitude: lng.toDouble(),
          ),
        ),
      );
    }
    // 公交:MKDirections 只给 ETA,不给折线与分步。
    final bool etaOnly = polyline.length < 2;
    if (etaOnly && mode != DirectionsMode.transit) return null;
    return DirectionsRoute(
      polyline: etaOnly ? <MapCoordinate>[from, to] : polyline,
      distanceMeters: distance.toDouble(),
      eta: Duration(seconds: eta.round()),
      steps: steps,
      notice: etaOnly ? transitNotice : null,
    );
  }

  static DirectionsRoute _straight(MapCoordinate from, MapCoordinate to) =>
      DirectionsRoute(
        polyline: <MapCoordinate>[from, to],
        distanceMeters: routeDistanceMeters(from, to),
        eta: null,
        steps: const <RouteStep>[],
        isFallback: true,
        notice: fallbackNotice,
      );
}
