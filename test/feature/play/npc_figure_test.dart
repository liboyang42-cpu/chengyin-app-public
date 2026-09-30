import 'dart:math' as math;

import 'package:chengyin_app/feature/play/free_explore/widgets/npc_figure.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, {bool reduceMotion = false}) {
  return t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(child: NpcFigure(npcName: '阿旧')),
      ),
    ),
  );
}

/// 当前那一帧的转角。直接读 painter,不猜 Transform 里的矩阵。
double _ry(WidgetTester t) =>
    (t
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(NpcFigure),
                    matching: find.byKey(const Key('npc-fig-canvas')),
                  ),
                )
                .painter!
            as NpcFigurePainter)
        .ry;

NpcFigurePainter _painter(WidgetTester t) =>
    t
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(NpcFigure),
                matching: find.byKey(const Key('npc-fig-canvas')),
              ),
            )
            .painter!
        as NpcFigurePainter;

/// 投影后的有向面积。背面剔除的判据就是它 —— 测试自己算一遍,
/// 不复用实现里的中间值(否则是拿实现证明实现)。
double _signedArea(NpcProjection proj, List<int> f) {
  final Offset a = proj.p[f[0]];
  final Offset b = proj.p[f[1]];
  final Offset c = proj.p[f[2]];
  return (b.dx - a.dx) * (c.dy - a.dy) - (c.dx - a.dx) * (b.dy - a.dy);
}

void main() {
  const Size kBox = Size(200, 220); // .fx-npc__fig 400rpx × 440rpx

  group('几何:建模', () {
    test('★面数顶点数逐段对得上(头 + 躯干 + 肩 + 脖 + 两臂)', () {
      final NpcFigureModel m = buildNpcFigure();
      // 头 sphere(seg14,rings10): (10+1)*14=154 顶点 / 10*14*2=280 面
      // 躯干 tube(seg16,capBottom): 32+1=33 / 32+16=48
      // 肩   tube(seg16,capTop)   : 32+1=33 / 32+16=48
      // 脖   tube(seg10,capTop)   : 20+1=21 / 20+10=30
      // 左右臂 tube(seg10,双封盖) : (20+2)*2=44 / (20+10+10)*2=80
      expect(m.verts.length, 154 + 33 + 33 + 21 + 22 + 22);
      expect(m.faces.length, 280 + 48 + 48 + 30 + 40 + 40);
    });

    test('★第一个顶点是头顶极点 (0, 0.925, 0) —— UV 球 phi=0 那一圈', () {
      final NpcFigureModel m = buildNpcFigure();
      expect(m.verts.first[0], closeTo(0, 1e-12));
      expect(m.verts.first[1], closeTo(0.925, 1e-12), reason: '头心 0.74 + 半径 0.185');
      expect(m.verts.first[2], closeTo(0, 1e-12));
    });

    test('★人形高 1.525 个单位 —— 投影那句 0.55 的注释就是按它算的 76%', () {
      final NpcFigureModel m = buildNpcFigure();
      double lo = double.infinity;
      double hi = double.negativeInfinity;
      for (final List<double> v in m.verts) {
        lo = math.min(lo, v[1]);
        hi = math.max(hi, v[1]);
      }
      expect(lo, closeTo(-0.60, 1e-12), reason: '躯干底');
      expect(hi, closeTo(0.925, 1e-12), reason: '头顶');
      expect(hi - lo, closeTo(1.525, 1e-12));
      // 0.55 × 1.525 = 0.839 ⇒ 占 min(W,H) 的 84%?不,占画布高:
      // 1.525 × (min(200,220) × 0.55) = 167.75px,220 的 76%。
      expect((hi - lo) * (200 * 0.55) / 220, closeTo(0.7625, 1e-4));
    });

    test('★两条手臂贴着身体:|x| 最大 0.317,不是伸出去的板子', () {
      final NpcFigureModel m = buildNpcFigure();
      double mx = 0;
      for (final List<double> v in m.verts) {
        mx = math.max(mx, v[0].abs());
      }
      expect(mx, closeTo(0.317, 1e-9), reason: '臂心 0.255 + 臂顶半径 0.062');
      expect(mx, lessThan(0.5));
    });

    test('★所有面的三个下标都在顶点表内(封盖那两圈最容易越界)', () {
      final NpcFigureModel m = buildNpcFigure();
      for (final List<int> f in m.faces) {
        expect(f.length, 3);
        for (final int i in f) {
          expect(i, inInclusiveRange(0, m.verts.length - 1));
        }
      }
    });
  });

  group('几何:投影', () {
    test('★ry=0 时头顶极点落在画布正中偏上 (100, 8.25)', () {
      final NpcFigureModel m = buildNpcFigure();
      final NpcProjection proj = projectNpcFigure(m.verts, 0, kBox);
      // s = min(200,220)*0.55 = 110;cx=100, cy=110;z=0 ⇒ k=1
      expect(proj.p.first.dx, closeTo(100, 1e-9));
      expect(proj.p.first.dy, closeTo(110 - 0.925 * 110, 1e-9));
    });

    test('★绕 Y 轴是真的转:侧面那颗顶点 x 从 120.35 转到画布中线', () {
      final NpcFigureModel m = buildNpcFigure();
      // 头 UV 球 phi=90°、a=0 的那颗:模型坐标 (0.185, 0.74, 0)
      const int side = 5 * 14;
      expect(m.verts[side][0], closeTo(0.185, 1e-12));
      expect(m.verts[side][2], closeTo(0, 1e-12));

      final NpcProjection at0 = projectNpcFigure(m.verts, 0, kBox);
      expect(at0.p[side].dx, closeTo(100 + 0.185 * 110, 1e-9));
      expect(at0.z[side], closeTo(0, 1e-12));

      final NpcProjection at90 = projectNpcFigure(m.verts, 90, kBox);
      expect(at90.p[side].dx, closeTo(100, 1e-9), reason: '转 90° 后它正对镜头,横向落回中线');
      expect(at90.z[side], closeTo(0.185, 1e-9), reason: 'z 是相机空间深度,越大越远');
      // 弱透视:退远了就该缩。DIST=4.2 ⇒ k=4.2/(4.2+0.185)
      final double k = 4.2 / (4.2 + 0.185);
      expect(at90.p[side].dy, closeTo(110 - 0.74 * 110 * k, 1e-9));
    });

    test('★弱透视不是正交投影:同一个 y、不同 z 的两点画出来高度不同', () {
      final NpcFigureModel m = buildNpcFigure();
      final NpcProjection at90 = projectNpcFigure(m.verts, 90, kBox);
      const int near = 5 * 14; // 转 90° 后 z=+0.185(远)
      const int far = 5 * 14 + 7; // 同一圈对侧,z=-0.185(近)
      expect(m.verts[far][1], closeTo(m.verts[near][1], 1e-9), reason: '同一纬圈,y 相同');
      expect(
        at90.p[far].dy,
        isNot(closeTo(at90.p[near].dy, 0.5)),
        reason: 'DIST=4.2 的弱透视被拆掉的话这条会变成恒等',
      );
    });
  });

  group('几何:明暗与画家算法', () {
    test('★背面全剔干净:留下的面在投影里有向面积必须为负', () {
      final NpcFigureModel m = buildNpcFigure();
      for (final double ry in <double>[-38, 0, 17, 38]) {
        final NpcProjection proj = projectNpcFigure(m.verts, ry, kBox);
        final List<NpcShadedFace> vis = shadeNpcFaces(m, ry, proj);
        expect(vis.length, lessThan(m.faces.length), reason: 'ry=$ry 一个面都没剔 = 没做背面剔除');
        expect(vis, isNotEmpty);
        for (final NpcShadedFace f in vis) {
          expect(
            _signedArea(proj, m.faces[f.idx]),
            lessThan(0),
            reason: 'ry=$ry 漏了一个背面 ⇒ 转到侧面会看见躯干内壁',
          );
        }
      }
    });

    test('★环境光垫底 0.26:背光面不许全黑,否则暗底上人形缺一块', () {
      final NpcFigureModel m = buildNpcFigure();
      final NpcProjection proj = projectNpcFigure(m.verts, 0, kBox);
      final List<NpcShadedFace> vis = shadeNpcFaces(m, 0, proj);
      double lo = double.infinity;
      double hi = double.negativeInfinity;
      for (final NpcShadedFace f in vis) {
        lo = math.min(lo, f.shade);
        hi = math.max(hi, f.shade);
      }
      expect(lo, greaterThanOrEqualTo(0.26 - 1e-12));
      expect(lo, closeTo(0.26, 1e-9), reason: '确实有面完全背光,垫底值不是碰巧没被用上');
      expect(hi, greaterThan(0.6), reason: '迎光面要亮起来,不能整片都是垫底值');
      expect(hi, lessThanOrEqualTo(1));
    });

    test('★画家算法:远的排前面,z 单调不增', () {
      final NpcFigureModel m = buildNpcFigure();
      final NpcProjection proj = projectNpcFigure(m.verts, 12, kBox);
      final List<NpcShadedFace> vis = shadeNpcFaces(m, 12, proj);
      for (int i = 1; i < vis.length; i++) {
        expect(vis[i].z, lessThanOrEqualTo(vis[i - 1].z + 1e-12));
      }
      expect(vis.first.z, greaterThan(vis.last.z), reason: '首尾同深 = 根本没排序');
    });

    test('★光是跟着模型转的:同一个面在不同转角上亮度不同', () {
      final NpcFigureModel m = buildNpcFigure();
      Map<int, double> shadeAt(double ry) {
        final NpcProjection proj = projectNpcFigure(m.verts, ry, kBox);
        return <int, double>{
          for (final NpcShadedFace f in shadeNpcFaces(m, ry, proj))
            f.idx: f.shade,
        };
      }

      // 拖转的整个行程:-38° 到 +38°。
      final Map<int, double> at0 = shadeAt(-38);
      final Map<int, double> at38 = shadeAt(38);
      // -38° 时最亮的那个面 —— 它必然是迎着光的,转 38° 后法线也跟着转走,
      // 亮度必须掉下来。⚠️ 不用「有多少面变了」这种统计量:背光面被 0.26 的
      // 环境光垫底钳住,两个角度都是 0.26,会把统计量稀释成一个只能靠调阈值过的数。
      final int brightest = at0.keys.reduce(
        (int x, int y) => at0[x]! >= at0[y]! ? x : y,
      );
      expect(at38.containsKey(brightest), isTrue, reason: '它在 +38° 上仍然朝前,没被剔掉');
      expect(at0[brightest]!, greaterThan(0.9));
      expect(
        (at0[brightest]! - at38[brightest]!).abs(),
        greaterThan(0.15),
        reason: '法线没跟着模型一起转的话,同一个面在任何转角上都是同一个亮度 —— 这个差会是 0',
      );
    });
  });

  group('跟手转', () {
    test('★系数 0.35、上下界 ±38(再大就看见后脑勺)', () {
      expect(npcDragRy(0, 100), closeTo(35, 1e-9));
      expect(npcDragRy(10, -20), closeTo(3, 1e-9));
      expect(npcDragRy(0, 1000), closeTo(38, 1e-9));
      expect(npcDragRy(0, -1000), closeTo(-38, 1e-9));
      expect(kNpcRyLimit, 38);
    });

    testWidgets('★横拖真的改变转角,且拖到头停在 38°', (WidgetTester t) async {
      await _pump(t, reduceMotion: true);
      expect(_ry(t), 0);

      await t.drag(find.byKey(const Key('npc-fig-canvas')), const Offset(60, 0));
      await t.pump();
      expect(_ry(t), closeTo(21, 1e-9), reason: '60 × 0.35');

      await t.drag(
        find.byKey(const Key('npc-fig-canvas')),
        const Offset(600, 0),
      );
      await t.pump();
      expect(_ry(t), closeTo(38, 1e-9));
    });
  });

  group('待机动效', () {
    test('★呼吸浮动 ±5px,周期 2π×1400ms', () {
      expect(npcFigureBob(Duration.zero), closeTo(0, 1e-12));
      expect(
        npcFigureBob(const Duration(milliseconds: 2199)),
        closeTo(5, 0.01),
        reason: 'sin 峰值在 700π ≈ 2199ms',
      );
      expect(npcFigureBob(const Duration(milliseconds: 6597)), closeTo(-5, 0.01));
    });

    test('★外圈地环 14s 转一圈', () {
      expect(npcRingTurns(const Duration(seconds: 14)), closeTo(1, 1e-12));
      expect(npcRingTurns(const Duration(seconds: 7)), closeTo(0.5, 1e-12));
    });
  });

  group('降低动态:停的是动效,不是功能', () {
    testWidgets('★不起 ticker、不排帧;人形与名字照样在', (WidgetTester t) async {
      await _pump(t, reduceMotion: true);
      await t.pump(const Duration(milliseconds: 400));

      expect(
        t.binding.hasScheduledFrame,
        isFalse,
        reason: '样机 reducedMotion 时 _startNpcFigure 画一帧就 return,不进 rAF',
      );
      expect(_painter(t).bob, 0, reason: '呼吸停');
      expect(_painter(t).model.faces.length, 486, reason: '★人形还在,不许连人一起藏了');
      expect(find.text('阿旧'), findsOneWidget, reason: '★名字还在');
      expect(find.text('店铺替身 · 在店里'), findsOneWidget);
      expect(find.byKey(const Key('npc-fig-ring-outer')), findsOneWidget);
      expect(
        _ringTurns(t),
        0,
        reason: '外圈停转',
      );
    });

    testWidgets('★负控:常态下确实在动(上面那条不是恒真)', (WidgetTester t) async {
      await _pump(t);
      await t.pump(const Duration(milliseconds: 700));
      expect(t.binding.hasScheduledFrame, isTrue);
      expect(_painter(t).bob, isNot(0));
      expect(_ringTurns(t), greaterThan(0));
      // 收尾:ticker 是无限的,不停掉 tester 会抱怨 pending timer
      await _pump(t, reduceMotion: true);
    });
  });
}

/// 外圈地环这一帧转了几圈。
double _ringTurns(WidgetTester t) => t
    .widget<NpcGroundRing>(find.byKey(const Key('npc-fig-ring-outer')))
    .turns;
