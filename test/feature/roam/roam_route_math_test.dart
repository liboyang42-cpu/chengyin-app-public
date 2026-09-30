import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_route_math.dart';

void main() {
  RoamSession sessionWith(List<RoamPoint> track, [List<RoamPoi> pois = const []]) {
    return RoamSession(
      ts: 1,
      track: track,
      pois: pois,
    );
  }

  group('路线归一化(box fit)', () {
    const Size canvas = Size(335, 260);
    const double pad = 30;

    test('轨迹点不足两个 → 空布局,不画线也不报错', () {
      expect(layoutRoamRoute(sessionWith(const <RoamPoint>[]), size: canvas, pad: pad).isEmpty, isTrue);
      expect(
        layoutRoamRoute(
          sessionWith(const <RoamPoint>[RoamPoint(lat: 30, lng: 120)]),
          size: canvas,
          pad: pad,
        ).isEmpty,
        isTrue,
      );
    });

    test('两点轨迹 → 一段线;画布内、长度≥2', () {
      final layout = layoutRoamRoute(
        sessionWith(const <RoamPoint>[
          RoamPoint(lat: 30.1, lng: 120.1),
          RoamPoint(lat: 30.2, lng: 120.2),
        ]),
        size: canvas,
        pad: pad,
      );
      expect(layout.segs, hasLength(1));
      final seg = layout.segs.single;
      expect(seg.x, inInclusiveRange(0, canvas.width.round()));
      expect(seg.y, inInclusiveRange(0, canvas.height.round()));
      expect(seg.len, greaterThanOrEqualTo(2));
    });

    test('轨迹点全部落在画布内(bbox 归一化居中)', () {
      final track = <RoamPoint>[
        for (int i = 0; i < 20; i++)
          RoamPoint(lat: 30.0 + i * 0.001, lng: 120.0 + i * 0.002),
      ];
      final layout = layoutRoamRoute(sessionWith(track), size: canvas, pad: pad);
      expect(layout.segs, hasLength(19));
      for (final seg in layout.segs) {
        expect(seg.x, inInclusiveRange(0, canvas.width.round()),
            reason: '线段起点 x 越界');
        expect(seg.y, inInclusiveRange(0, canvas.height.round()),
            reason: '线段起点 y 越界');
      }
    });

    test('POI 圆点:有坐标的才画,数量与颜色轮转', () {
      final layout = layoutRoamRoute(
        sessionWith(const <RoamPoint>[
          RoamPoint(lat: 30.1, lng: 120.1),
          RoamPoint(lat: 30.2, lng: 120.2),
        ], const <RoamPoi>[
          RoamPoi(name: 'a', lat: 30.15, lng: 120.15),
          RoamPoi(name: 'b', lat: null, lng: 120.15),
          RoamPoi(name: 'c', lat: 30.15, lng: 120.16),
        ]),
        size: canvas,
        pad: pad,
      );
      // 没坐标的 POI 不画(与小程序 filter(p => p.lat) 一致)。
      expect(layout.dots, hasLength(2));
      for (final dot in layout.dots) {
        expect(dot.x, inInclusiveRange(0, canvas.width.round()));
        expect(dot.y, inInclusiveRange(0, canvas.height.round()));
      }
      expect(layout.dots[0].color, roamRouteColors[0]);
      expect(layout.dots[1].color, roamRouteColors[1]);
    });
  });
}
