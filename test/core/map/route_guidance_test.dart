import 'dart:async';

import 'package:chengyin_app/core/map/directions.dart';
import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/map/route_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

// 纬度 31.23 附近:经度 0.001° ≈ 95 m,纬度 0.001° ≈ 111 m。
const MapCoordinate _p0 = MapCoordinate(latitude: 31.230, longitude: 121.470);
const MapCoordinate _p1 = MapCoordinate(latitude: 31.230, longitude: 121.472);
const MapCoordinate _p2 = MapCoordinate(latitude: 31.232, longitude: 121.472);

DirectionsRoute _route() => const DirectionsRoute(
  polyline: <MapCoordinate>[_p0, _p1, _p2],
  distanceMeters: 412,
  eta: Duration(seconds: 412),
  steps: <RouteStep>[
    RouteStep(instruction: '沿人民路向东', distanceMeters: 190, coordinate: _p0),
    RouteStep(instruction: '左转进入北京路', distanceMeters: 222, coordinate: _p1),
  ],
);

void main() {
  test('起点:下一步是前方的转弯,剩余距离/时间按折线算', () {
    final GuidanceState s = RouteGuidance(_route()).update(_p0);
    expect(s.nextStep?.instruction, '左转进入北京路');
    expect(s.distanceToNextStepMeters, closeTo(190, 3));
    expect(s.remainingMeters, closeTo(412, 5));
    expect(s.remainingTime!.inSeconds, closeTo(412, 6));
    expect(s.arrived, isFalse);
    expect(s.offRoute, isFalse);
  });

  test('指令随位置推进:过了转弯点后没有下一步,提示前往目的地', () {
    final RouteGuidance g = RouteGuidance(_route());
    expect(g.update(_p0).instruction, '左转进入北京路');
    final GuidanceState mid = g.update(
      const MapCoordinate(latitude: 31.231, longitude: 121.4721),
    );
    expect(mid.nextStep, isNull);
    expect(mid.instruction, RouteGuidance.finalInstruction);
    expect(mid.remainingMeters, closeTo(111, 5));
    expect(mid.offRoute, isFalse);
  });

  test('到达判定:进入半径即到达,且保持到达(半径可调)', () {
    final RouteGuidance g = RouteGuidance(_route(), arrivalRadiusMeters: 30);
    const MapCoordinate near = MapCoordinate(
      latitude: 31.2318,
      longitude: 121.472,
    ); // 距终点 ~22 m
    expect(g.update(near).arrived, isTrue);
    expect(g.update(_p1).arrived, isTrue, reason: '到达后不因抖动回退');

    const MapCoordinate far = MapCoordinate(
      latitude: 31.2310,
      longitude: 121.472,
    ); // 距终点 ~111 m
    expect(RouteGuidance(_route()).update(far).arrived, isFalse);
    expect(
      RouteGuidance(_route(), arrivalRadiusMeters: 150).update(far).arrived,
      isTrue,
    );
  });

  test('偏航:超过阈值连续 N 次才判偏航(阈值与次数可调)', () {
    const MapCoordinate south = MapCoordinate(
      latitude: 31.2290,
      longitude: 121.471,
    ); // 离线 ~111 m
    final RouteGuidance g = RouteGuidance(
      _route(),
      offRouteThresholdMeters: 50,
      offRouteConfirmations: 2,
    );
    final GuidanceState first = g.update(south);
    expect(first.offsetMeters, closeTo(111, 5));
    expect(first.offRoute, isFalse);
    expect(g.update(south).offRoute, isTrue);

    expect(
      RouteGuidance(
        _route(),
        offRouteThresholdMeters: 150,
        offRouteConfirmations: 1,
      ).update(south).offRoute,
      isFalse,
    );
  });

  test('run:偏航后以当前位置重算并换上新路线', () async {
    const MapCoordinate south = MapCoordinate(
      latitude: 31.2290,
      longitude: 121.471,
    );
    final List<MapCoordinate> rerouteFrom = <MapCoordinate>[];
    final DirectionsRoute rerouted = const DirectionsRoute(
      polyline: <MapCoordinate>[south, _p2],
      distanceMeters: 330,
      eta: Duration(seconds: 330),
      steps: <RouteStep>[],
    );
    final StreamController<MapCoordinate> positions =
        StreamController<MapCoordinate>();
    final Future<List<GuidanceState>> states =
        RouteGuidance(_route(), offRouteConfirmations: 2)
            .run(
              positions.stream,
              reroute: (MapCoordinate from) async {
                rerouteFrom.add(from);
                return rerouted;
              },
            )
            .toList();

    positions
      ..add(_p0)
      ..add(south)
      ..add(south)
      ..add(south);
    await positions.close();
    final List<GuidanceState> out = await states;

    expect(rerouteFrom, <MapCoordinate>[south]);
    expect(out.map((GuidanceState s) => s.rerouting), <bool>[
      false,
      false,
      true,
      false,
      false,
    ]);
    expect(out[3].route, same(rerouted));
    expect(out[3].rerouted, isTrue);
    expect(out.last.offRoute, isFalse);
    expect(
      out.last.remainingMeters,
      closeTo(routeDistanceMeters(south, _p2), 2),
    );
  });

  test('run:到达后结束流,不再重算', () async {
    int reroutes = 0;
    final List<GuidanceState> out = await RouteGuidance(_route())
        .run(
          Stream<MapCoordinate>.fromIterable(<MapCoordinate>[_p0, _p2, _p0]),
          reroute: (_) async {
            reroutes++;
            return _route();
          },
        )
        .toList();
    expect(out, hasLength(2));
    expect(out.last.arrived, isTrue);
    expect(reroutes, 0);
  });
}
