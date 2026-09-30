// App 内分步导航状态机(决策 D7)。纯 Dart:输入位置(GCJ-02),输出当前指令、
// 剩余距离/时间、到达、偏航;偏航确认后由 [RouteGuidance.run] 调调用方给的重算函数。

import 'dart:math' as math;

import 'directions.dart';
import 'map_scene.dart';

class GuidanceState {
  const GuidanceState({
    required this.route,
    required this.nextStep,
    required this.distanceToNextStepMeters,
    required this.remainingMeters,
    required this.remainingTime,
    required this.offsetMeters,
    required this.offRoute,
    required this.arrived,
    this.rerouting = false,
    this.rerouted = false,
  });

  final DirectionsRoute route;

  /// 前方下一个动作;null = 前方没有转弯了,直奔终点。
  final RouteStep? nextStep;
  final double distanceToNextStepMeters;
  final double remainingMeters;
  final Duration? remainingTime;

  /// 离路线的垂直距离。
  final double offsetMeters;
  final bool offRoute;
  final bool arrived;

  /// 已确认偏航,正在重算。
  final bool rerouting;

  /// 本次状态刚换上重算后的路线(只在换线那一刻为 true)。
  final bool rerouted;

  String get instruction => arrived
      ? RouteGuidance.arrivedInstruction
      : nextStep?.instruction ?? RouteGuidance.finalInstruction;

  GuidanceState _copy({bool? rerouting, bool? rerouted}) => GuidanceState(
    route: route,
    nextStep: nextStep,
    distanceToNextStepMeters: distanceToNextStepMeters,
    remainingMeters: remainingMeters,
    remainingTime: remainingTime,
    offsetMeters: offsetMeters,
    offRoute: offRoute,
    arrived: arrived,
    rerouting: rerouting ?? this.rerouting,
    rerouted: rerouted ?? this.rerouted,
  );
}

class RouteGuidance {
  RouteGuidance(
    DirectionsRoute route, {
    this.arrivalRadiusMeters = 30,
    this.offRouteThresholdMeters = 40,
    this.offRouteConfirmations = 2,
  }) {
    _setRoute(route);
  }

  static const String finalInstruction = '沿路线前往目的地';
  static const String arrivedInstruction = '已到达目的地';

  /// 进入终点多少米内算到达。
  final double arrivalRadiusMeters;

  /// 离路线超过多少米算疑似偏航。
  final double offRouteThresholdMeters;

  /// 连续多少次超阈值才确认偏航 —— 防 GPS 单点漂移触发重算。
  final int offRouteConfirmations;

  late DirectionsRoute _route;
  late List<double> _cumulative;
  late List<double> _stepAlong;
  int _offCount = 0;
  bool _arrived = false;

  DirectionsRoute get route => _route;

  void replaceRoute(DirectionsRoute route) {
    _setRoute(route);
    _offCount = 0;
  }

  GuidanceState update(MapCoordinate position) {
    final _Projection p = _project(position);
    final double total = _cumulative.last;
    final double remaining = math.max(0, total - p.along);
    _arrived =
        _arrived ||
        routeDistanceMeters(position, _route.polyline.last) <=
            arrivalRadiusMeters;
    _offCount = !_arrived && p.offset > offRouteThresholdMeters
        ? _offCount + 1
        : 0;

    int next = -1;
    for (int i = 0; i < _stepAlong.length; i++) {
      if (_stepAlong[i] > p.along + 1) {
        next = i;
        break;
      }
    }
    final Duration? eta = _route.eta;
    return GuidanceState(
      route: _route,
      nextStep: next < 0 ? null : _route.steps[next],
      distanceToNextStepMeters: next < 0
          ? remaining
          : _stepAlong[next] - p.along,
      remainingMeters: remaining,
      remainingTime: eta == null
          ? null
          : total <= 0
          ? Duration.zero
          : Duration(seconds: (eta.inSeconds * remaining / total).round()),
      offsetMeters: p.offset,
      offRoute: _offCount >= offRouteConfirmations,
      arrived: _arrived,
    );
  }

  /// 驱动一次导航:每个位置出一个状态;偏航确认后从当前位置重算并换线;到达即结束。
  Stream<GuidanceState> run(
    Stream<MapCoordinate> positions, {
    required Future<DirectionsRoute> Function(MapCoordinate from) reroute,
  }) async* {
    await for (final MapCoordinate position in positions) {
      final GuidanceState state = update(position);
      if (state.offRoute && !state.arrived) {
        yield state._copy(rerouting: true);
        replaceRoute(await reroute(position));
        yield update(position)._copy(rerouted: true);
        continue;
      }
      yield state;
      if (state.arrived) return;
    }
  }

  void _setRoute(DirectionsRoute route) {
    _route = route;
    final List<MapCoordinate> line = route.polyline;
    _cumulative = <double>[0];
    for (int i = 0; i + 1 < line.length; i++) {
      _cumulative.add(_cumulative.last + _Segment(line[i], line[i + 1]).length);
    }
    _stepAlong = <double>[
      for (final RouteStep s in route.steps) _project(s.coordinate).along,
    ];
  }

  _Projection _project(MapCoordinate point) {
    final List<MapCoordinate> line = _route.polyline;
    if (line.length < 2) {
      return _Projection(
        along: 0,
        offset: line.isEmpty ? 0 : routeDistanceMeters(point, line.first),
      );
    }
    _Projection best = const _Projection(along: 0, offset: double.infinity);
    for (int i = 0; i + 1 < line.length; i++) {
      final _Segment seg = _Segment(line[i], line[i + 1]);
      final (double t, double offset) = seg.project(point);
      if (offset < best.offset) {
        best = _Projection(
          along: _cumulative[i] + t * seg.length,
          offset: offset,
        );
      }
    }
    return best;
  }
}

class _Projection {
  const _Projection({required this.along, required this.offset});
  final double along;
  final double offset;
}

/// 以线段起点为原点的局部平面近似。ponytail: 等距圆柱近似,单段几公里内误差 <1%,
/// 跨城长段才需要换大地线投影。
class _Segment {
  _Segment(this.a, MapCoordinate b)
    : _kx = math.cos(a.latitude * math.pi / 180) * _metersPerDegree,
      _by = (b.latitude - a.latitude) * _metersPerDegree,
      _bx =
          (b.longitude - a.longitude) *
          math.cos(a.latitude * math.pi / 180) *
          _metersPerDegree;

  static const double _metersPerDegree = 6371000 * math.pi / 180;

  final MapCoordinate a;
  final double _kx;
  final double _bx;
  final double _by;

  double get length => math.sqrt(_bx * _bx + _by * _by);

  (double, double) project(MapCoordinate p) {
    final double px = (p.longitude - a.longitude) * _kx;
    final double py = (p.latitude - a.latitude) * _metersPerDegree;
    final double len2 = _bx * _bx + _by * _by;
    final double t = len2 == 0
        ? 0
        : ((px * _bx + py * _by) / len2).clamp(0.0, 1.0);
    final double dx = px - t * _bx;
    final double dy = py - t * _by;
    return (t, math.sqrt(dx * dx + dy * dy));
  }
}
