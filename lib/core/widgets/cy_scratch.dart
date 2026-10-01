import '../../l10n/strings.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';

/// 采样网格边长。与真源 `pages/play/components/scratch/index.js` 的 `SAMPLE = 16` 同值:
/// 256 个点足以判「擦了多少」,不必逐像素。
const int kCyScratchSampleGrid = 16;

/// 刮开区域的下限 —— 够放下那颗「直接揭示」(44×32)。
///
/// 为什么要有下限:那颗出口是**绝对定位**的,内容比它窄/矮时会被挤出 Stack 的
/// 边界,clip 之后连点都点不到 —— 出口形同虚设,而那正是无障碍要保的那条路。
/// 产量里两处用法的内容都远大于这个尺寸,这条只在退化场景生效。
const double _kCyScratchMinWidth = 132;
const double _kCyScratchMinHeight = 88;

/// 已擦除占比(0–1)= 已擦点数 / 总点数。真源 `sampledAlphaProgress` 同口径。
double cyScratchProgress(
  int clearedCells, {
  int grid = kCyScratchSampleGrid,
}) {
  final int total = grid * grid;
  if (total <= 0) return 0;
  return clearedCells / total;
}

/// 到没到揭示阈值。
///
/// 阈值缺失/非法时退回 **0.45** —— 真源 `utils/scratch-progress.js#shouldReveal` 原文:
/// 「退回 0 会让『碰一下就揭示』,正是稿要避免的纯点击领奖」。
bool cyScratchShouldReveal(double progress, double threshold) {
  final double resolved = threshold > 0 && threshold <= 1 ? threshold : 0.45;
  return (progress > 0 ? progress : 0) >= resolved;
}

/// 笔刷停在 [center] 时,盖住了网格里哪些采样点(下标 = row * grid + col)。
///
/// 采样点取**每格中心** —— 与真源在 canvas 上铺的采样网格同一套几何。
/// 真源量的是 alpha(只读 256 次 `getImageData`);这里直接按几何记账,
/// 少一次 GPU 回读,判定结果一致。
Set<int> cyScratchCellsUnderBrush({
  required Offset center,
  required Size size,
  required double brush,
  int grid = kCyScratchSampleGrid,
}) {
  final Set<int> touched = <int>{};
  if (size.width <= 0 || size.height <= 0 || grid <= 0) return touched;
  final double cellW = size.width / grid;
  final double cellH = size.height / grid;
  // 只扫笔刷覆盖到的那几格,不做整网格 256 次距离计算
  final int minCol = ((center.dx - brush) / cellW - 0.5).floor().clamp(0, grid - 1);
  final int maxCol = ((center.dx + brush) / cellW - 0.5).ceil().clamp(0, grid - 1);
  final int minRow = ((center.dy - brush) / cellH - 0.5).floor().clamp(0, grid - 1);
  final int maxRow = ((center.dy + brush) / cellH - 0.5).ceil().clamp(0, grid - 1);
  for (int row = minRow; row <= maxRow; row++) {
    for (int col = minCol; col <= maxCol; col++) {
      final Offset sample = Offset(cellW * (col + 0.5), cellH * (row + 0.5));
      if ((sample - center).distance <= brush) touched.add(row * grid + col);
    }
  }
  return touched;
}

/// `cy-scratch` · 擦开 / 刮开。
///
/// 真源:`pages/play/components/scratch/`(Figma「玩法游戏UI·动效稿」UX 借鉴板)。
/// 用途在真源里有两处:`playkit-slowtask/index.wxml:25`(揭示今日进度)、
/// `playkit-dailysign/index.wxml:59`(揭示签文)。
///
/// ## 无障碍是硬边界,不是加分项
/// 「擦」是一个**运动能力要求**。所以:
/// * 开了「减少动态效果」→ 整层不挂,内容直接可见(不是「擦得快一点」,是**不要求擦**);
/// * 遮罩在的时候**始终**有一颗可见的「直接揭示」,不要求持续擦除或长按;
/// * 内容**从头到尾都在树里**(遮罩只是盖在上面的一层)—— 遮罩不是渲染开关,
///   读屏器任何时候都读得到下面那段字。
class CyScratch extends StatefulWidget {
  const CyScratch({
    super.key,
    required this.child,
    this.label = '',
    this.threshold = 0.55,
    this.brush = 16,
    this.revealed = false,
    this.onReveal,
  });

  /// 被盖住的内容。**始终在树里**,只有视觉被遮罩盖住。
  final Widget child;

  /// 无障碍名字:读屏用户听到的是「擦开看看:<label>」,不是「一块灰色」。
  final String label;

  /// 擦到多少比例算完成。真源默认 0.55(刮刮卡的通行值);
  /// `slowtask` 用 0.4(那一屏的内容更短,要求擦满一半是折磨)。
  final double threshold;

  /// 笔刷半径(逻辑像素)。
  final double brush;

  /// 已经揭开过的内容不该再盖一层雾(真源:昨天擦过的今天重开还要再擦一遍是折磨)。
  final bool revealed;

  final VoidCallback? onReveal;

  @override
  State<CyScratch> createState() => _CyScratchState();
}

class _CyScratchState extends State<CyScratch> {
  /// 擦过的笔迹(局部坐标)。遮罩就靠它重画。
  final List<Offset> _strokes = <Offset>[];
  final Set<int> _touched = <int>{};

  /// 「已擦完」记在实例上而不是 widget 参数里:它是**这一次**擦除的进度,
  /// 不该由外部传入(真源同口径:不进 `data`,免得变成一条没人渲染的死字段)。
  bool _done = false;

  bool get _masked => !widget.revealed && !_done;

  void _erase(Offset position, Size size) {
    if (_done) return;
    _touched.addAll(
      cyScratchCellsUnderBrush(
        center: position,
        size: size,
        brush: widget.brush,
        grid: kCyScratchSampleGrid,
      ),
    );
    setState(() => _strokes.add(position));
    // 每擦几下轻震(节流):每一次都震会变成持续嗡鸣(真源 HAPTIC_EVERY = 5)
    if (_strokes.length % 5 == 0) unawaited(HapticFeedback.selectionClick());
    if (cyScratchShouldReveal(
      cyScratchProgress(_touched.length),
      widget.threshold,
    )) {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    // 揭示是这一屏唯一一次「拿到了」的时刻,给 medium(真源 _finish 同档)
    unawaited(HapticFeedback.mediumImpact());
    widget.onReveal?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final CyPalette palette = CyPalette.of(context);
    return Stack(
      // 遮罩与出口都不该被无声裁掉:真出了问题要看得见
      clipBehavior: Clip.none,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _kCyScratchMinWidth,
            minHeight: _kCyScratchMinHeight,
          ),
          child: widget.child,
        ),
        if (_masked && !reduceMotion)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size size = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                if (size.width <= 0 || size.height <= 0) {
                  return const SizedBox.shrink();
                }
                return Semantics(
                  button: true,
                  label: widget.label.isEmpty
                      ? stringsOf(context).sharedScratchReveal
                      : stringsOf(context).sharedScratchRevealLabel(widget.label),
                  // 读屏用户双击 = 直接揭示,不必做「擦」这个动作
                  onTap: _finish,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (DragStartDetails d) =>
                          _erase(d.localPosition, size),
                      onPanUpdate: (DragUpdateDetails d) =>
                          _erase(d.localPosition, size),
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CyScratchMaskPainter(
                                strokes: _strokes,
                                brush: widget.brush,
                                cover: palette.bgSurfaceStrong,
                              ),
                            ),
                          ),
                          Positioned(
                            right: CyTokens.space2,
                            bottom: CyTokens.space2,
                            child: CupertinoButton(
                              minimumSize: const Size(44, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: CyTokens.space2,
                              ),
                              onPressed: _finish,
                              child: Text(
                                stringsOf(context).sharedRevealDirectly,
                                style: TextStyle(
                                  color: palette.onCoverFg,
                                  fontSize: CyTokens.typeCaption,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 遮罩层:一整块实色,笔刷扫过的地方以 `BlendMode.clear` 擦掉,
/// 露出下面真正的 slot 内容。
class _CyScratchMaskPainter extends CustomPainter {
  _CyScratchMaskPainter({
    required this.strokes,
    required this.brush,
    required this.cover,
  });

  final List<Offset> strokes;
  final double brush;
  final Color cover;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect area = Offset.zero & size;
    // saveLayer:擦除只作用在这一层里,不会把下面的内容一起擦掉
    canvas.saveLayer(area, Paint());
    canvas.drawRect(area, Paint()..color = cover);
    final Paint eraser = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;
    for (final Offset stroke in strokes) {
      canvas.drawCircle(stroke, brush, eraser);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CyScratchMaskPainter oldDelegate) =>
      oldDelegate.strokes.length != strokes.length ||
      oldDelegate.brush != brush ||
      oldDelegate.cover != cover;
}
