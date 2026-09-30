// 店铺分身的人形舞台(屏④上半屏)。逐条照搬小程序 `utils/npc-figure.js`
// 与 `pages/play/index.js:1208-1276`。
//
// ★ 为什么不接 glb / Rive:那两条都要先有一个资产文件。而「一个能真的转起来、
//   有体积和明暗的人形」本身不需要资产 —— 几百个三角面 + 一次弱透视 + 画家算法就够。
//
// ★ 几何是**纯函数**(样机注释:「纯函数,可单测」),只吐坐标与亮度(0..1),
//   不碰颜色也不碰画布。上色留在 [NpcFigurePainter] 里。
//
// 结构自下而上:光晕 → 内圈地环(定位)→ 外圈地环(慢转)→ **人形压在环之上**。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/theme/cy_tokens.dart';

// ————————————————————— 纯几何 —————————————————————

/// 一个人形的顶点表与三角面表。
///
/// 顶点是 `[x, y, z]` 三元组(与样机同形,不另包类型):y 向上,原点在胸口附近,
/// 整体落在 y ∈ [-0.60, 0.925]、|x| ≤ 0.317。
class NpcFigureModel {
  const NpcFigureModel({required this.verts, required this.faces});

  final List<List<double>> verts;
  final List<List<int>> faces;
}

/// 投影结果。[p] 是屏幕坐标,[z] 是相机空间深度(**越大越远**)。
class NpcProjection {
  const NpcProjection({required this.p, required this.z});

  final List<Offset> p;
  final List<double> z;
}

/// 一个可见面:在 [NpcFigureModel.faces] 里的下标、深度、亮度。
class NpcShadedFace {
  const NpcShadedFace({required this.idx, required this.z, required this.shade});

  final int idx;
  final double z;

  /// 0..1。底下垫了 0.26 的环境光 —— 全黑的背光面会在暗底上消失,人形就缺一块。
  final double shade;
}

/// 绕 Y 轴一圈取 [n] 个点的单位圆(cos/sin 预算好,每帧重算是浪费)。
List<List<double>> _unitRing(int n) {
  return List<List<double>>.generate(n, (int i) {
    final double a = (i / n) * math.pi * 2;
    return <double>[math.cos(a), math.sin(a)];
  });
}

/// 一段锥台:从 [y0] 半径 [r0] 到 [y1] 半径 [r1],顶底可选封盖。
void _tube(
  List<List<double>> verts,
  List<List<int>> faces,
  double cx,
  double cz,
  double y0,
  double r0,
  double y1,
  double r1,
  int seg, {
  required bool capTop,
  required bool capBottom,
}) {
  final List<List<double>> c = _unitRing(seg);
  final int base = verts.length;
  for (int i = 0; i < seg; i++) {
    verts.add(<double>[cx + c[i][0] * r0, y0, cz + c[i][1] * r0]);
  }
  for (int i = 0; i < seg; i++) {
    verts.add(<double>[cx + c[i][0] * r1, y1, cz + c[i][1] * r1]);
  }
  for (int i = 0; i < seg; i++) {
    final int j = (i + 1) % seg;
    faces.add(<int>[base + i, base + j, base + seg + j]);
    faces.add(<int>[base + i, base + seg + j, base + seg + i]);
  }
  if (capTop) {
    final int t = verts.length;
    verts.add(<double>[cx, y1, cz]);
    for (int i = 0; i < seg; i++) {
      faces.add(<int>[base + seg + i, base + seg + (i + 1) % seg, t]);
    }
  }
  if (capBottom) {
    final int b = verts.length;
    verts.add(<double>[cx, y0, cz]);
    for (int i = 0; i < seg; i++) {
      faces.add(<int>[base + (i + 1) % seg, base + i, b]);
    }
  }
}

/// 一颗球(UV 球,横 [seg] 纵 [rings])。
void _sphere(
  List<List<double>> verts,
  List<List<int>> faces,
  double cx,
  double cy,
  double cz,
  double r,
  int seg,
  int rings,
) {
  final int base = verts.length;
  for (int k = 0; k <= rings; k++) {
    final double phi = (k / rings) * math.pi;
    final double y = math.cos(phi) * r;
    final double rr = math.sin(phi) * r;
    for (int i = 0; i < seg; i++) {
      final double a = (i / seg) * math.pi * 2;
      verts.add(<double>[
        cx + math.cos(a) * rr,
        cy + y,
        cz + math.sin(a) * rr,
      ]);
    }
  }
  for (int k = 0; k < rings; k++) {
    for (int i = 0; i < seg; i++) {
      final int j = (i + 1) % seg;
      final int r0 = base + k * seg;
      final int r1 = base + (k + 1) * seg;
      faces.add(<int>[r0 + i, r0 + j, r1 + j]);
      faces.add(<int>[r0 + i, r1 + j, r1 + i]);
    }
  }
}

/// 建一个人形:头 + 躯干 + 肩 + 脖 + 两条手臂。数值逐字照搬样机 `buildFigure`。
NpcFigureModel buildNpcFigure() {
  final List<List<double>> verts = <List<double>>[];
  final List<List<int>> faces = <List<int>>[];
  _sphere(verts, faces, 0, 0.74, 0, 0.185, 14, 10); // 头
  // 躯干(几乎直筒,不是裙摆)
  _tube(verts, faces, 0, 0, -0.60, 0.235, 0.30, 0.255, 16,
      capTop: false, capBottom: true);
  // 肩:到顶再收一点
  _tube(verts, faces, 0, 0, 0.30, 0.255, 0.46, 0.215, 16,
      capTop: true, capBottom: false);
  // 脖子
  _tube(verts, faces, 0, 0, 0.46, 0.09, 0.58, 0.085, 10,
      capTop: true, capBottom: false);
  // 左臂(贴着身体,不是伸出去的板子)
  _tube(verts, faces, -0.255, 0, -0.22, 0.05, 0.34, 0.062, 10,
      capTop: true, capBottom: true);
  // 右臂
  _tube(verts, faces, 0.255, 0, -0.22, 0.05, 0.34, 0.062, 10,
      capTop: true, capBottom: true);
  return NpcFigureModel(verts: verts, faces: faces);
}

/// 相机距离。再近人形会被透视拉变形(样机 `DIST`)。
const double _kCameraDist = 4.2;

/// 人形占画布短边的比例。
///
/// ⚠️ 样机注释记着这里栽过一次:0.42 时人形只占画布高的 58%,
/// 台子尺寸明明是对的,人却缩在中间一小团。0.55 ⇒ 1.525 × 0.55 ≈ 84% 短边、
/// 76% 画布高,与 `.npc__ph`(196px / 260px)同档。
const double _kFigureScale = 0.55;

/// 绕 Y 轴转 [ry] 度后做弱透视投影。
///
/// ⚠️ 样机的 `scale` 形参**没有调用方传过**,这里直接删掉了 —— 它在 JS 里是
/// `scale || min(w,h)*0.55`,照抄成 Dart 的 `??` 就会在传 0 时算出 s=0
/// (整个人形塌成一个点)。既然没人用,不留这个坑。
NpcProjection projectNpcFigure(List<List<double>> verts, double ry, Size size) {
  final double rad = ry * math.pi / 180;
  final double cs = math.cos(rad);
  final double sn = math.sin(rad);
  final double s = math.min(size.width, size.height) * _kFigureScale;
  final double cx = size.width / 2;
  final double cy = size.height / 2;
  final List<Offset> p = <Offset>[];
  final List<double> z = <double>[];
  for (final List<double> v in verts) {
    final double x = v[0] * cs + v[2] * sn;
    final double zz = -v[0] * sn + v[2] * cs;
    final double k = _kCameraDist / (_kCameraDist - zz);
    p.add(Offset(cx + x * s * k, cy - v[1] * s * k));
    z.add(-zz);
  }
  return NpcProjection(p: p, z: z);
}

/// 面的可见性、深度与亮度,已按**远→近**排好(画家算法)。
///
/// ★ 背面剔除用**投影后**的有向面积:面朝观察者时为负(样机的绕序)。
///   这一步同时干掉了内表面,不然转到侧面会看见躯干内壁,像塌了一块。
List<NpcShadedFace> shadeNpcFaces(
  NpcFigureModel model,
  double ry,
  NpcProjection proj,
) {
  final double rad = ry * math.pi / 180;
  final double cs = math.cos(rad);
  final double sn = math.sin(rad);
  // 光从左上前方来;转的是模型不是光,所以法线要转到同一坐标系里再点乘。
  const double lx = -0.45;
  const double ly = 0.78;
  const double lz = 0.44;
  final List<NpcShadedFace> out = <NpcShadedFace>[];
  for (int f = 0; f < model.faces.length; f++) {
    final List<int> t = model.faces[f];
    final Offset a = proj.p[t[0]];
    final Offset b = proj.p[t[1]];
    final Offset c = proj.p[t[2]];
    final double area =
        (b.dx - a.dx) * (c.dy - a.dy) - (c.dx - a.dx) * (b.dy - a.dy);
    if (area >= 0) continue; // 背面:剔掉
    final List<double> va = model.verts[t[0]];
    final List<double> vb = model.verts[t[1]];
    final List<double> vc = model.verts[t[2]];
    final double ux = vb[0] - va[0];
    final double uy = vb[1] - va[1];
    final double uz = vb[2] - va[2];
    final double vx = vc[0] - va[0];
    final double vy = vc[1] - va[1];
    final double vz = vc[2] - va[2];
    final double nx = uy * vz - uz * vy;
    final double ny = uz * vx - ux * vz;
    final double nz = ux * vy - uy * vx;
    // 绕 Y 轴的旋转不动 y 分量,所以下面归一化用的是没转过的 ny —— 对的。
    final double rx = nx * cs + nz * sn;
    final double rz = -nx * sn + nz * cs;
    final double raw = math.sqrt(rx * rx + ny * ny + rz * rz);
    final double len = raw == 0 ? 1 : raw;
    final double d = (rx * lx + ny * ly + rz * lz) / len;
    out.add(
      NpcShadedFace(
        idx: f,
        z: (proj.z[t[0]] + proj.z[t[1]] + proj.z[t[2]]) / 3,
        // 环境光垫底:全黑的背光面会在暗底上消失,人形就缺一块
        shade: (0.26 + math.max(0, d) * 0.74).clamp(0.0, 1.0),
      ),
    );
  }
  out.sort((NpcShadedFace m, NpcShadedFace n) => n.z.compareTo(m.z));
  return out;
}

/// 转角上下界。再大就看见后脑勺,分身「在跟你说话」的感觉就没了(样机 ±38°)。
const double kNpcRyLimit = 38;

/// 跟手转:横向位移 × 0.35,夹在 ±[kNpcRyLimit]。
double npcDragRy(double startRy, double dx) =>
    (startRy + dx * 0.35).clamp(-kNpcRyLimit, kNpcRyLimit);

/// 呼吸式浮动(样机 `Math.sin((Date.now()-t0)/1400) * 5`):±5px。
double npcFigureBob(Duration elapsed) =>
    math.sin(elapsed.inMilliseconds / 1400) * 5;

/// 外圈地环转了几圈(样机 `npcRingSpin 14s linear infinite`)。
double npcRingTurns(Duration elapsed) => elapsed.inMilliseconds / 14000;

// ————————————————————— 舞台 —————————————————————

/// `.fx-npc__fig` 400rpx × 440rpx。
const Size kNpcFigureBox = Size(200, 220);

/// 名牌下面那行。
const String kNpcRoleLabel = '店铺替身 · 在店里';

/// 地环的倾角与后推(样机 `rotateX(74deg) translateZ(-92rpx)`,
/// 父级 `perspective:1600rpx`)。rpx→px 折半。
const double _kRingTiltDeg = 74;
const double _kRingPushZ = -46;
const double _kStagePerspective = 800;

/// 脚下的一圈地环。倾成地面椭圆,不是画面里的同心圆。
///
/// ⚠️ 颜色只能中性:样机原本是金色 `rgba(232,194,122,…)`,而玩家端整页单色。
class NpcGroundRing extends StatelessWidget {
  const NpcGroundRing({
    super.key,
    required this.diameter,
    required this.alpha,
    required this.turns,
  });

  final double diameter;
  final double alpha;

  /// 已经自转了几圈。内圈恒 0(它只负责定位)。
  final double turns;

  @override
  Widget build(BuildContext context) {
    // CSS 的 `rotateX(74deg) translateZ(-92rpx) rotateZ(θ)` 是左乘序,
    // Matrix4 的级联写法正好同序。
    final Matrix4 m = Matrix4.identity()
      ..setEntry(3, 2, 1 / _kStagePerspective)
      ..rotateX(_kRingTiltDeg * math.pi / 180)
      ..translateByDouble(0.0, 0.0, _kRingPushZ, 1.0)
      ..rotateZ(turns * math.pi * 2);
    return Transform(
      transform: m,
      alignment: Alignment.center,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            // ds-ok 地环描边,中性白透明度不是色板色
            color: const Color(0xFFFFFFFF).withValues(alpha: alpha),
            width: 1, // 2rpx
          ),
        ),
      ),
    );
  }
}

/// 人形舞台:可拖转的低模人形 + 名字 + 角色行(样机 `.fx-npc__stage`)。
///
/// ★ 降低动态时**停的是动效不是功能**:外圈不转、呼吸不动,
///   但人形、名字、角色行都还在,而且照样拖得动。
class NpcFigure extends StatefulWidget {
  const NpcFigure({
    super.key,
    required this.npcName,
    this.roleLabel = kNpcRoleLabel,
  });

  final String npcName;
  final String roleLabel;

  @override
  State<NpcFigure> createState() => _NpcFigureState();
}

class _NpcFigureState extends State<NpcFigure>
    with SingleTickerProviderStateMixin {
  static final NpcFigureModel _model = buildNpcFigure();

  /// 已经跑了多久。用 notifier 直接驱动重绘 —— 每帧 setState 会把整棵子树重建一遍,
  /// 而这里每帧变的只有画布和外圈。
  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );
  Ticker? _ticker;

  double _ry = 0;
  double _dragStartRy = 0;
  double _dragDx = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 样机 reducedMotion 时 `_startNpcFigure` 画一帧就 return,不进 rAF。
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker?.stop();
      _elapsed.value = Duration.zero;
      return;
    }
    final Ticker ticker = _ticker ??= createTicker((Duration d) {
      _elapsed.value = d;
    });
    if (!ticker.isActive) ticker.start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartRy = _ry;
    _dragDx = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragDx += details.delta.dx;
    setState(() => _ry = npcDragRy(_dragStartRy, _dragDx));
  }

  @override
  Widget build(BuildContext context) {
    final double w = kNpcFigureBox.width;
    final double h = kNpcFigureBox.height;
    const double halo = 230; // 460rpx
    const double ringIn = 190; // 380rpx
    const double ringOut = 230; // 460rpx

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none, // 光晕与外圈都比 fig 盒子大,不许剪掉
            children: <Widget>[
              // 光晕:`left:50%; top:46%`,自身居中
              Positioned(
                left: w / 2 - halo / 2,
                top: h * 0.46 - halo / 2,
                child: Container(
                  width: halo,
                  height: halo,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    // ds-ok 形象后的体积光,不是色板色
                    gradient: RadialGradient(
                      colors: <Color>[
                        Color(0x1AFFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: <double>[0, 0.62, 1],
                    ),
                  ),
                ),
              ),
              // 内圈:定位用,不转
              Positioned(
                left: w / 2 - ringIn / 2,
                top: h / 2 - ringIn / 2,
                child: const NpcGroundRing(
                  diameter: ringIn,
                  alpha: 0.22,
                  turns: 0,
                ),
              ),
              Positioned(
                left: w / 2 - ringOut / 2,
                top: h / 2 - ringOut / 2,
                child: ValueListenableBuilder<Duration>(
                  valueListenable: _elapsed,
                  builder: (BuildContext context, Duration v, Widget? _) =>
                      NpcGroundRing(
                        key: const Key('npc-fig-ring-outer'),
                        diameter: ringOut,
                        alpha: 0.12,
                        turns: npcRingTurns(v),
                      ),
                ),
              ),
              // ★人形压在环之上
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  child: CustomPaint(
                    key: const Key('npc-fig-canvas'),
                    painter: NpcFigurePainter(
                      model: _model,
                      ry: _ry,
                      elapsed: _elapsed,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        Text(
          widget.npcName,
          style: const TextStyle(
            // ds-ok 形象名牌,比正文大一档(32rpx)
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: CyTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 3), // 6rpx
        Text(
          widget.roleLabel,
          style: const TextStyle(
            fontSize: CyTokens.typeCaption,
            color: CyTokens.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// 只负责上色与绘制;几何全在上面那些纯函数里。
class NpcFigurePainter extends CustomPainter {
  NpcFigurePainter({
    required this.model,
    required this.ry,
    required this.elapsed,
  }) : super(repaint: elapsed);

  final NpcFigureModel model;
  final double ry;
  final ValueListenable<Duration> elapsed;

  /// 这一帧的呼吸偏移。降低动态时 [elapsed] 恒为 0 ⇒ 它也恒为 0。
  double get bob => npcFigureBob(elapsed.value);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.translate(0, bob);
    final NpcProjection proj = projectNpcFigure(model.verts, ry, size);
    final List<NpcShadedFace> faces = shadeNpcFaces(model, ry, proj);
    final Paint paint = Paint()..style = PaintingStyle.fill;
    for (final NpcShadedFace f in faces) {
      final List<int> t = model.faces[f.idx];
      final Offset a = proj.p[t[0]];
      final Offset b = proj.p[t[1]];
      final Offset c = proj.p[t[2]];
      // ⚠️ 必须用**不透明**灰阶。半透明填充下,补缝用的重叠区会把 alpha 叠一倍 ——
      //    样机实拍两轮都栽在这:先是描边描出线框人,再是微膨胀涨出亮网格。
      //    28..114:再暗就比下面的名字还弱,形象反而成了背景。
      final int g = (28 + f.shade * 86).round();
      paint.color = Color.fromARGB(255, g, g, g); // ds-ok 人形体积明暗,中性灰阶
      // 沿质心把三角微微涨 0.4px,盖住抗锯齿留下的发丝缝
      final double mx = (a.dx + b.dx + c.dx) / 3;
      final double my = (a.dy + b.dy + c.dy) / 3;
      final Path path = Path();
      for (int i = 0; i < 3; i++) {
        final Offset q = i == 0 ? a : (i == 1 ? b : c);
        final double dx = q.dx - mx;
        final double dy = q.dy - my;
        final double raw = math.sqrt(dx * dx + dy * dy);
        final double len = raw == 0 ? 1 : raw;
        final Offset e = Offset(
          q.dx + dx / len * 0.4,
          q.dy + dy / len * 0.4,
        );
        if (i == 0) {
          path.moveTo(e.dx, e.dy);
        } else {
          path.lineTo(e.dx, e.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  /// ⚠️ [elapsed] 已经是 `repaint` 监听源,呼吸不走这里;
  /// 这里只管**重建时**该不该重画 —— 转角变了必须重画。
  @override
  bool shouldRepaint(NpcFigurePainter oldDelegate) =>
      oldDelegate.ry != ry || !identical(oldDelegate.model, model);
}
