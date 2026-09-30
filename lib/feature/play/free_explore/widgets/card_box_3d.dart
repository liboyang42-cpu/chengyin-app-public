import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../card_box_geometry.dart';

/// 厚度(小程序 `--T:12rpx` = 6px)。够看出「这是一张有厚度的卡」即可 ——
/// 侧脊上不写字,所以不用留更厚。
const double _kThickness = 6.0;

/// 相机距离(小程序 `perspective:1100rpx` = 550px)。再近卡片会被透视拉变形。
const double _kPerspective = 550.0;

/// 有厚度的 3D 卡盒:跟手横向拖转,松手吸附到正/背面,侧脊只在转起来时画。
///
/// ⚠️ Flutter 没有 CSS 的 `backface-visibility: hidden`:正反两面若同时放进
/// widget 树,背对观察者的那面会**镜像着画出来**。所以每一帧只放
/// [showsBack] 判定出的那一面,背面自己还要再 `rotateY(π)` 一次抵消镜像。
///
/// 每张卡都是单独 push 一个详情页,[CardBox3d] 随页面新建,[_ry] 天然从 0 开始,
/// 所以不需要「换卡归零」的处理。将来若出现**同一个实例切换不同卡**的用法,
/// 要同时:给它传随 nodeId 变化的 `key`、加回归零逻辑、并补一条能变红的测试——三件缺一不可。
class CardBox3d extends StatefulWidget {
  const CardBox3d({
    super.key,
    required this.front,
    required this.back,
    required this.width,
    required this.height,
    this.dimmed = false,
  });

  /// 正面(封面图)。
  final Widget front;

  /// 背面(章节名 + 章节介绍)。
  final Widget back;

  final double width;
  final double height;

  /// 已核销:整张灰掉。
  final bool dimmed;

  @override
  State<CardBox3d> createState() => _CardBox3dState();
}

class _CardBox3dState extends State<CardBox3d> {
  double _ry = 0;
  double _dragStartRy = 0;
  double _dragDx = 0;

  void _onDragStart(DragStartDetails details) {
    _dragStartRy = _ry;
    _dragDx = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragDx += details.delta.dx;
    setState(() => _ry = dragRy(_dragStartRy, _dragDx));
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() => _ry = snapRy(_ry));
  }

  @override
  Widget build(BuildContext context) {
    final double rad = _ry * math.pi / 180;
    final Matrix4 transform = Matrix4.identity()
      ..setEntry(3, 2, 1 / _kPerspective)
      ..rotateY(rad);

    final bool back = showsBack(_ry);
    // 面与侧脊要能拼成一个厚度为 T 的盒子：真源 .fx-card3d__front/__back 都有
    // translateZ(T/2)（front 直接推、back 转 180° 后再推，落点相同），
    // 侧脊转起来时才不会露在盒子外面 3px。
    final Widget face = Transform(
      transform: Matrix4.identity()
        ..translateByDouble(0.0, 0.0, _kThickness / 2, 1.0),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: back
              // 背面自己再翻 180°,否则内容是镜像的。
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: widget.back,
                )
              : widget.front,
        ),
      ),
    );

    final Widget content = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        face,
        // 侧脊只在转起来时画:正对时画它会在边缘糊出一条硬线。
        if (edgeOn(_ry)) ..._spines(),
      ],
    );

    final Widget box = GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      behavior: HitTestBehavior.opaque,
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: content,
      ),
    );

    if (!widget.dimmed) return box;
    // 已核销:整张灰掉(小程序 filter:grayscale(1) brightness(.72))。
    return ColorFiltered(
      key: const ValueKey<String>('card-box-dimmed'),
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126 * 0.72, 0.7152 * 0.72, 0.0722 * 0.72, 0, 0,
        0.2126 * 0.72, 0.7152 * 0.72, 0.0722 * 0.72, 0, 0,
        0.2126 * 0.72, 0.7152 * 0.72, 0.0722 * 0.72, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: box,
    );
  }

  List<Widget> _spines() {
    final Widget bar = Container(
      width: _kThickness,
      height: widget.height - CyTokens.radiusLg * 2,
      color: AppColors.bgSurface, /* 真源 var(--cy-color-bg-surface) */
    );
    return <Widget>[
      Transform(
        alignment: Alignment.centerLeft,
        // 真源 left:T/2 把转轴内收半个厚度,否则侧脊落在卡片边缘外侧。
        origin: const Offset(_kThickness / 2, 0),
        transform: Matrix4.identity()
          ..rotateY(-math.pi / 2)
          ..translateByDouble(0.0, 0.0, _kThickness / 2, 1.0),
        child: Align(alignment: Alignment.centerLeft, child: bar),
      ),
      Transform(
        alignment: Alignment.centerRight,
        origin: const Offset(-_kThickness / 2, 0),
        transform: Matrix4.identity()
          ..rotateY(math.pi / 2)
          ..translateByDouble(0.0, 0.0, _kThickness / 2, 1.0),
        child: Align(alignment: Alignment.centerRight, child: bar),
      ),
    ];
  }
}
