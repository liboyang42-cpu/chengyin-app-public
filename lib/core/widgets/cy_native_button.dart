import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';
import '../theme/cy_tokens.g.dart';

Color _destructiveColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? CyGeneratedLightTokens.colorStatusDanger
    : CyTokens.statusDanger;

/// Apple 原生按钮的行为角色。
///
/// 这里只表达动作层级，不决定业务页的位置、宽高或文案。
enum CyNativeButtonRole { primary, secondary, destructive }

/// 按钮所在的视觉层。
///
/// Liquid Glass 只适合浮动功能层；内容区的主 CTA 使用系统实色
/// Cupertino 按钮，避免整页每个主行动都变成 prominent glass。
enum CyNativeButtonPresentation { contentSolid, floatingGlass }

/// 同时提供 SF Symbol 和 Cupertino 降级图标。
///
/// SF Symbols 不能在 Flutter 测试与旧系统中渲染，所以不使用上游的
/// 通用圆形占位图标；调用方必须给出语义一致的 Cupertino 图标。
@immutable
class CyNativeButtonIcon {
  const CyNativeButtonIcon({required this.sfSymbol, required this.fallback})
    : assert(sfSymbol.length > 0, 'sfSymbol must not be empty.');

  final String sfSymbol;
  final IconData fallback;
}

/// Apple 原生纯图标动作。
///
/// iOS 26+ 使用系统 Liquid Glass 图标按钮；其余环境使用
/// [CupertinoButton]。无论图标视觉尺寸如何，命中区都不小于 44pt，
/// [label] 同时作为 VoiceOver 名称与系统 tooltip。
class CyNativeIconButton extends StatelessWidget {
  const CyNativeIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.role = CyNativeButtonRole.secondary,
    this.size = 44,
    this.iconSize = 20,
    this.disc = true,
    this.liquidGlassSupported,
  }) : assert(label.length > 0, 'label must not be empty.'),
       assert(size >= 44, 'size must be at least 44pt.'),
       assert(iconSize > 0, 'iconSize must be > 0.');

  final String label;
  final CyNativeButtonIcon icon;
  final VoidCallback? onPressed;
  final CyNativeButtonRole role;
  final double size;
  final double iconSize;

  /// 是否给图标衬一个圆形底盘。
  ///
  /// 默认 true(功能层浮动钮的既有形态:26+ 玻璃圆盘 / 回退实色圆盘)。
  /// **内容卡里的图标动作**(列表行尾「…」、卡内关闭)Apple 的画法是
  /// **裸字形**(plain/无底)—— 灰底盘是 Material tonal icon button 的
  /// 味道(a5-ios27-club-2 R3 critic 点名、§四.9 登记的共用件缺口)。
  /// `disc: false` 走系统 plain 通道,命中区仍 ≥44pt。
  final bool disc;
  final bool? liquidGlassSupported;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Color destructive = _destructiveColor(context);
    final bool useNative =
        liquidGlassSupported ?? NativeLiquidGlassUtils.supportsLiquidGlass;
    final Color foreground = role == CyNativeButtonRole.destructive
        ? destructive
        : role == CyNativeButtonRole.primary
        ? palette.actionPrimaryFg
        : palette.textPrimary;
    final Color background = role == CyNativeButtonRole.primary
        ? palette.actionPrimaryBg
        : palette.actionSecondaryBg;

    final Widget child = useNative
        ? LiquidGlassButton.icon(
            onPressed: onPressed,
            icon: NativeLiquidGlassIcon.sfSymbol(icon.sfSymbol),
            size: size,
            iconSize: iconSize,
            tooltip: label,
            iconColor: foreground,
            tint: role == CyNativeButtonRole.destructive
                ? destructive
                : background,
            style: !disc
                ? LiquidGlassButtonStyle.plain
                : role == CyNativeButtonRole.primary
                ? LiquidGlassButtonStyle.prominentGlass
                : LiquidGlassButtonStyle.glass,
          )
        : Semantics(
            container: true,
            button: true,
            enabled: onPressed != null,
            label: label,
            onTap: onPressed,
            child: ExcludeSemantics(
              child: CupertinoButton(
                onPressed: onPressed,
                minimumSize: Size.square(size),
                padding: EdgeInsets.zero,
                color: disc ? background : CupertinoColors.transparent,
                disabledColor: disc ? background : CupertinoColors.transparent,
                borderRadius: BorderRadius.circular(size / 2),
                child: Icon(icon.fallback, size: iconSize, color: foreground),
              ),
            ),
          );
    return SizedBox.square(dimension: size, child: child);
  }
}

/// 保留小程序几何结构的 Apple 按钮基础件。
///
/// iOS 26+ 非 loading 状态使用已锁定版本的 [LiquidGlassButton]；
/// 旧系统、非 iOS、测试与 loading 状态使用完整的 [CupertinoButton]
/// 降级。调用方可以显式传入 [width] / [height]，组件不会重排业务页。
///
/// 上游原生按钮当前无进度内容槽，Flutter overlay 又会被 UiKitView
/// 压在下面。因此 loading 时转为 Cupertino 进度按钮，避免伪造原生动画。
class CyNativeButton extends StatelessWidget {
  const CyNativeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.role = CyNativeButtonRole.primary,
    this.icon,
    this.width,
    this.height = CyTokens.btnH,
    this.loading = false,
    this.borderRadius,
    this.liquidGlassSupported,
    this.presentation = CyNativeButtonPresentation.contentSolid,
  }) : assert(label.length > 0, 'label must not be empty.'),
       assert(height >= 44, 'height must be at least 44pt.'),
       assert(width == null || width >= 44, 'width must be at least 44pt.');

  final String label;
  final VoidCallback? onPressed;
  final CyNativeButtonRole role;
  final CyNativeButtonIcon? icon;

  /// 显式宽度。留空时按内容宽度布局。
  final double? width;

  /// 普通字号下的目标高度。Dynamic Type 放大时只增加必要高度。
  final double height;
  final bool loading;
  final double? borderRadius;
  final CyNativeButtonPresentation presentation;

  /// 仅供 widget 合同测试覆盖能力探测。
  final bool? liquidGlassSupported;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Color destructive = _destructiveColor(context);
    final double effectiveHeight = _effectiveHeight(context);
    final bool enabled = onPressed != null && !loading;
    final bool useNative =
        !loading &&
        presentation == CyNativeButtonPresentation.floatingGlass &&
        (liquidGlassSupported ?? NativeLiquidGlassUtils.supportsLiquidGlass);

    final _ButtonColors colors = switch (role) {
      CyNativeButtonRole.primary => _ButtonColors(
        background: palette.actionPrimaryBg,
        foreground: palette.actionPrimaryFg,
      ),
      CyNativeButtonRole.secondary => _ButtonColors(
        background: palette.actionSecondaryBg,
        foreground: palette.textPrimary,
      ),
      CyNativeButtonRole.destructive => _ButtonColors(
        background: palette.actionSecondaryBg,
        foreground: destructive,
        tint: destructive,
      ),
    };

    final Widget child = useNative
        ? _nativeButton(
            colors: colors,
            effectiveHeight: effectiveHeight,
            enabled: enabled,
          )
        : _cupertinoButton(
            colors: colors,
            effectiveHeight: effectiveHeight,
            enabled: enabled,
          );

    return SizedBox(width: width, height: effectiveHeight, child: child);
  }

  Widget _nativeButton({
    required _ButtonColors colors,
    required double effectiveHeight,
    required bool enabled,
  }) {
    return LiquidGlassButton(
      label: label,
      onPressed: enabled ? onPressed : null,
      icon: icon == null
          ? null
          : NativeLiquidGlassIcon.sfSymbol(icon!.sfSymbol),
      width: width,
      height: effectiveHeight,
      foregroundColor: colors.foreground,
      tint: colors.tint ?? colors.background,
      style: role == CyNativeButtonRole.primary
          ? LiquidGlassButtonStyle.prominentGlass
          : LiquidGlassButtonStyle.glass,
      borderRadius: borderRadius,
      maxLines: 1,
    );
  }

  Widget _cupertinoButton({
    required _ButtonColors colors,
    required double effectiveHeight,
    required bool enabled,
  }) {
    final Widget content = loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CupertinoActivityIndicator(color: colors.foreground),
              const SizedBox(width: CyTokens.space2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon!.fallback, size: 18),
                const SizedBox(width: CyTokens.space2),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      value: loading ? '正在处理' : null,
      liveRegion: loading,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: enabled ? onPressed : null,
          color: colors.background,
          disabledColor: colors.background,
          foregroundColor: colors.foreground,
          borderRadius: BorderRadius.circular(
            borderRadius ?? effectiveHeight / 2,
          ),
          minimumSize: Size(44, effectiveHeight),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.btnPadX),
          child: content,
        ),
      ),
    );
  }

  double _effectiveHeight(BuildContext context) {
    final double baseFontSize =
        CupertinoTheme.of(context).textTheme.actionTextStyle.fontSize ?? 17;
    final double scaledFontSize = MediaQuery.textScalerOf(
      context,
    ).scale(baseFontSize);
    return math.max(44, height + math.max(0, scaledFontSize - baseFontSize));
  }
}

@immutable
class _ButtonColors {
  const _ButtonColors({
    required this.background,
    required this.foreground,
    this.tint,
  });

  final Color background;
  final Color foreground;
  final Color? tint;
}
