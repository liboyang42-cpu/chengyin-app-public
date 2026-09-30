import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';

/// Cupertino 没有导出 material 的 `kMinInteractiveDimension`,这里按 HIG 写死 44
/// (与 `CyTokens.btnH` 同值,但用途不同:那个是主按钮高度,这个是命中区下限)。
const double kPlayKitMinTapTarget = 44;

/// 计时/传感器族五件共用的**形状**,不放任何玩法规则。
///
/// 为什么值得抽:倒计时、秒表、计步三屏是同一个台面语言(眉标 + 一个大数字 +
/// 一颗实心 CTA),限时快答与贴纸图鉴是同一个 sheet 语言。各写一份的话,
/// 五屏的眉标字距、数字基线、CTA 高度会各飘各的 —— 那种漂移 golden 抓不住,
/// 玩家一眼能看出「这不是一个产品」。

/// 大数字(倒计时读数 / 秒表读数 / 计步 LCD)。
///
/// 字号是**页面私有**的:原型里这几个数在 58–126px 之间,不在 iOS 梯级上
/// (梯级最大档 34)。同类先例:回仓内 `CyTokens.stillnessTimerType = 80` ——
/// 整屏计时器的数字是道具,不是排版层级。字重按 T3 收到 w700(原型是
/// Black/900;中文大字号堆到 900 会糊成一团黑块)。
class PlayKitBigFigure extends StatelessWidget {
  const PlayKitBigFigure({
    super.key,
    required this.text,
    required this.size,
    required this.color,
    this.letterSpacing = 0,
    this.semanticsLabel,
  });

  final String text;
  final double size;
  final Color color;
  final double letterSpacing;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final Widget figure = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1,
        letterSpacing: letterSpacing,
        // 等宽数字:读数每拍换一位时,整行不会左右抖
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    final String? label = semanticsLabel;
    return label == null
        ? figure
        : Semantics(
            container: true,
            label: label,
            child: ExcludeSemantics(child: figure),
          );
  }
}

/// 眉标:一行字距拉开的小字,压在台面最上面。
class PlayKitEyebrow extends StatelessWidget {
  const PlayKitEyebrow(
    this.text, {
    super.key,
    required this.color,
    this.letterSpacing = 3.4,
  });

  final String text;
  final Color color;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: CyTokens.typeCaption,
        fontWeight: FontWeight.w600,
        letterSpacing: letterSpacing,
      ),
    );
  }
}

/// 胶囊小标(「目标 10.00 秒 · 容差 ±0.30」「第 3 局」…)。
class PlayKitPill extends StatelessWidget {
  const PlayKitPill(
    this.label, {
    super.key,
    required this.foreground,
    required this.background,
    this.border,
    this.semanticsLabel,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color? border;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space2,
          vertical: CyTokens.space1,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: CyTokens.typeCaption,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 实心动作按钮(原型那颗黑/白胶囊)。
///
/// 不复用 `CyNativeButton`:它跟 `CyPalette` 走 —— 玩家域恒暗,主按钮是**白底黑字**,
/// 而倒计时/秒表这两屏是原型里唯一两块**浅色**台面,白底按钮压在白底上等于消失。
/// 所以这里由调用方给两面颜色,几何与命中区(≥44pt)与共用层一致。
class PlayKitSolidAction extends StatelessWidget {
  const PlayKitSolidAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    this.busy = false,
    this.width,
    this.border,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;

  /// 上一次动作还没回来 / 正在跑:压暗但仍占位,不让布局跳一下。
  final bool busy;
  final double? width;

  /// 描边。倒计时那颗钮是**白底 + 黑描边**:油漫上来之后白底会糊掉,
  /// 靠这圈描边把它托住(小程序 `.oc__b` 原文)。
  final Color? border;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final Widget button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space6,
          vertical: CyTokens.space3,
        ),
        minimumSize: const Size.square(CyTokens.btnH),
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        color: background,
        disabledColor: background,
        pressedOpacity: 0.88,
        onPressed: busy ? null : onPressed,
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: CyTokens.typeButton,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    final Widget sized = width == null
        ? button
        : SizedBox(width: width, child: button);
    final Widget faded = busy ? Opacity(opacity: 0.55, child: sized) : sized;
    final String? semantic = semanticsLabel;
    return semantic == null
        ? faded
        : Semantics(button: true, label: semantic, child: faded);
  }
}

/// 整屏台面的底:铺满、SafeArea、可选内边距。三屏(倒计时/秒表/计步)共用,
/// 保证退出与安全区口径一致 —— 那个位置出错在真机上才看得见。
class PlayKitStageSurface extends StatelessWidget {
  const PlayKitStageSurface({
    super.key,
    required this.background,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: CyTokens.space4,
      vertical: CyTokens.space4,
    ),
  });

  final Color background;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: SafeArea(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
