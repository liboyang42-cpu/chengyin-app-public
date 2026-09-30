import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_projection.dart';

/// 图标步骤行 —— 真源 `utils/playkit-steps.js`(纯函数 + 一张表)。
///
/// 真源原话(Figma「ADA 借鉴卡」E 条 ← Sago Mini):「任务步骤全部图形化,
/// 不读字也能开始玩;**文字只做氛围不做说明书**」。
/// 所以图标承担说明职责,原来那句整句说明降级成这一行的 aria-label ——
/// 图标 + 一行长说明并排等于没改,读者仍然会去读那行字。
///
/// 真源里这张表有 8 种玩法,但**真正渲染它的只有两个组件**
/// (`playkit-steps/index.wxml:5` 与 `playkit-blindtaste/index.wxml:11`)。
/// 这里只登记这两个 —— 表里多出来的条目在 App 侧没有渲染位,就是死数据。
///
/// 标签保留 2–4 个字而不是纯图标:Cupertino 那套是通用字形,
/// 没有「闭眼尝一口」这种专用图标,纯图标 + 猜谜对玩家更不友好
/// (真源同口径:`cy-icon` 也没有,所以它自己也留了标签)。
const Map<PlayKitKind, List<(IconData, String)>> _kPlayKitSteps =
    <PlayKitKind, List<(IconData, String)>>{
      // 真源 `playkit-steps.js#STEPS.blindtaste`
      PlayKitKind.blindTaste: <(IconData, String)>[
        (CupertinoIcons.gift_fill, '领小样'),
        (CupertinoIcons.heart_fill, '闭眼尝'),
        (CupertinoIcons.checkmark_circle_fill, '作答'),
      ],
      // 真源 `playkit-steps.js#STEPS.steps`
      PlayKitKind.steps: <(IconData, String)>[
        (CupertinoIcons.location_fill, '走起来'),
        (CupertinoIcons.clock_fill, '刷新'),
        (CupertinoIcons.star_fill, '落章'),
      ],
    };

/// 某种玩法的步骤序列。没登记的 kind 给空表(真源 `stepIcons` 同口径)。
List<(IconData, String)> playKitStepIcons(PlayKitKind kind) =>
    _kPlayKitSteps[kind] ?? const <(IconData, String)>[];

/// 图标行的读屏文案。服务端给了整句说明就用它,否则用标签拼一句。
/// (真源 `stepsA11yLabel(type, fallbackText)`)
String playKitStepsA11y(PlayKitKind kind, [String fallbackText = '']) {
  final String text = fallbackText.trim();
  if (text.isNotEmpty) return text;
  final List<(IconData, String)> steps = playKitStepIcons(kind);
  if (steps.isEmpty) return '';
  return '玩法步骤:${<String>[
    for (int i = 0; i < steps.length; i++) '${i + 1} ${steps[i].$2}',
  ].join(',')}';
}

/// 图标 + 序号 + 标签,中间用一条细线串起来。
class PlayKitStepRow extends StatelessWidget {
  const PlayKitStepRow({
    super.key,
    required this.kind,
    required this.a11yLabel,
    this.color,
  });

  final PlayKitKind kind;

  /// 整行作为**一个**语义节点被念出来(子项的序号/标签不再逐个念)。
  final String a11yLabel;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final List<(IconData, String)> steps = playKitStepIcons(kind);
    if (steps.isEmpty) return const SizedBox.shrink();
    final Color tone = color ?? CyTokens.textPrimary;
    return Semantics(
      container: true,
      label: a11yLabel,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            for (int index = 0; index < steps.length; index++) ...<Widget>[
              if (index > 0)
                // 不用 material 的 Divider:这一个文件里只有这一条线
                Expanded(
                  child: Container(height: 1, color: CyTokens.borderStrong),
                ),
              _StepBadge(
                index: index + 1,
                icon: steps[index].$1,
                label: steps[index].$2,
                color: tone,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.index,
    required this.icon,
    required this.label,
    required this.color,
  });

  final int index;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SizedBox(
        width: 38,
        height: 30,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            Icon(icon, size: 24, color: color),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: CyTokens.bgPage, width: 1),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: CyTokens.bgPage,
                    // 原型 18rpx=9pt 低于字级下限(T1:最小走 micro),提到 micro。
                    fontSize: CyTokens.typeMicro,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: CyTokens.space1),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: CyTokens.typeCaption,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}
