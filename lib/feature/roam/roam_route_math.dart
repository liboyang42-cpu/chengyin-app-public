import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/roam_session.dart';

/// 漫游路线图(轨迹 + 点亮 POI)的画布归一化。
///
/// 对齐小程序 `subpackageRoam/session` 的 `_route`:轨迹与 POI 一起做 bbox
/// 归一化居中(lat/lng → 卡内像素),输出待画的线段与圆点。
/// 全部纯函数,页面/画笔只负责画。

/// 路线颜色表(与小程序 utils/play-visual-tokens.js ROUTE_COLORS 一致,
/// canvas 读不到 WXSS token,必须留字面量)。
const List<Color> roamRouteColors = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFFD9D9D9),
  Color(0xFFA6A6A6),
  Color(0xFF737373),
  Color(0xFF404040),
];

/// 一条轨迹线段:起点 + 长度 + 方向角(度)。
class RoamRouteSegment {
  const RoamRouteSegment({
    required this.x,
    required this.y,
    required this.len,
    required this.deg,
  });

  final int x;
  final int y;
  final int len;
  final int deg;
}

/// 一个 POI 圆点:圆心 + 颜色。
class RoamRouteDot {
  const RoamRouteDot({required this.x, required this.y, required this.color});

  final int x;
  final int y;
  final Color color;
}

/// 归一化结果。
class RoamRouteLayout {
  const RoamRouteLayout({this.segs = const <RoamRouteSegment>[], this.dots = const <RoamRouteDot>[]});

  final List<RoamRouteSegment> segs;
  final List<RoamRouteDot> dots;

  bool get isEmpty => segs.isEmpty;
}

/// 把 [session] 的轨迹与 POI 归一化到 [size] 内(留 [pad] 边距)。
/// 轨迹点不足两个时不画线(与小程序一致:track.length < 2 → 空)。
RoamRouteLayout layoutRoamRoute(
  RoamSession session, {
  required Size size,
  required double pad,
}) {
  final List<RoamPoint> track = session.track;
  if (track.length < 2) return const RoamRouteLayout();

  final double lat0 = track.first.lat;
  final double kx = math.cos(lat0 * math.pi / 180);
  Offset m(RoamPoint p) => Offset(p.lng * kx, -p.lat);

  final List<Offset> tp = track.map(m).toList();
  final List<Offset> pp = session.pois
      .where((RoamPoi p) => p.lat != null && p.lng != null)
      .map((RoamPoi p) => Offset(p.lng! * kx, -p.lat!))
      .toList();
  final List<Offset> all = <Offset>[...tp, ...pp];

  double x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (final Offset p in all) {
    x0 = math.min(x0, p.dx);
    y0 = math.min(y0, p.dy);
    x1 = math.max(x1, p.dx);
    y1 = math.max(y1, p.dy);
  }
  final double sc = math.min(
    (size.width - pad * 2) / math.max(1e-9, x1 - x0),
    (size.height - pad * 2) / math.max(1e-9, y1 - y0),
  );
  final double ox = (size.width - (x1 - x0) * sc) / 2 - x0 * sc;
  final double oy = (size.height - (y1 - y0) * sc) / 2 - y0 * sc;
  double X(Offset p) => p.dx * sc + ox;
  double Y(Offset p) => p.dy * sc + oy;

  final List<RoamRouteSegment> segs = <RoamRouteSegment>[];
  for (int i = 1; i < tp.length; i++) {
    final double ax = X(tp[i - 1]), ay = Y(tp[i - 1]);
    final double bx = X(tp[i]), by = Y(tp[i]);
    final double len = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2)).toDouble();
    if (len < 2) continue;
    segs.add(RoamRouteSegment(
      x: ax.round(),
      y: ay.round(),
      len: len.round() + 2,
      deg: (math.atan2(by - ay, bx - ax) * 180 / math.pi).round(),
    ));
  }
  final List<RoamRouteDot> dots = <RoamRouteDot>[];
  for (int i = 0; i < pp.length; i++) {
    dots.add(RoamRouteDot(
      x: X(pp[i]).round(),
      y: Y(pp[i]).round(),
      color: roamRouteColors[i % roamRouteColors.length],
    ));
  }
  return RoamRouteLayout(segs: segs, dots: dots);
}
