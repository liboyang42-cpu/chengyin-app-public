import 'package:flutter/material.dart';

import 'cy_tokens.dart';
import 'cy_tokens.g.dart';

/// 语义色板。**为什么要有这层**:商家域在小程序里走浅色工作台
/// (`style/merchant-light.wxss`,36 个页面 @import),C 端走暗色。
/// App 这边此前所有页面都吃同一套 `CyTokens` 静态常量 ⇒ 商家页全渲成黑底,
/// 和小程序并排看是两个产品。静态常量表达不了「同一语义、两套取值」,
/// 所以把语义色收进 ThemeExtension,由 `Theme.of(context)` 决定拿哪一套。
///
/// 取值是小程序 `style/tokens.wxss` 的逐字镜像:
///   暗色 = 默认 `page{}` 块;浅色 = `.theme-light / .theme-merchant` 块(617-665 行)。
///
/// ★ 分工(手册 §3.6,依 HIG):**系统语义色不在这层** —— 导航栏 / Tab Bar /
///   工具栏 / sheet / alert 的背景与前景、分组列表底、分隔线、disclosure 箭头、
///   开关开启绿、系统危险红,一律交给 Cupertino 原生控件(不传色),它们自带
///   深浅自适应。本层只管**品牌语义色**:页面底 / 内容卡片底与描边 / 主 CTA /
///   业务状态色 / 选中态与未读角标。
///
/// ★ C4(即使只发一种外观也要双值):商家端恒浅、玩家端恒暗,但每个颜色在
///   两端都必须有值 —— 玻璃与材质要按背后内容取色,缺一端就会在玻璃上露馅。
///   本文件两个静态实例必须同时给全所有字段(编译器强制)。
///   取值只来自生成物 `cy_tokens.g.dart`,**不许写字面量**(真源是 tokens.wxss)。
///   ⚠️ 现存例外:暗色 status-warning/success 与浅色 bg-surface-strong /
///   input-idle / input-filled 的生成值尚未追平 master@90e66d70 的 09-02/09-03
///   变更,追平要同步重录 golden,单独处理(见 docs/design-tokens.md)。
/// ⚠️ 值只改小程序真源，再运行 `python3 tool/gen_tokens.py`；App 侧由
///   `token_codegen_test.dart` 锁住生成物，手写层只保留复合值与语义装配。
@immutable
class CyPalette extends ThemeExtension<CyPalette> {
  const CyPalette({
    required this.bgPage,
    required this.bgSurface,
    required this.bgSurfaceSubtle,
    required this.bgSurfaceStrong,
    required this.bgElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textPlaceholder,
    required this.textDisabled,
    required this.textInverse,
    required this.borderSubtle,
    required this.borderStrong,
    required this.overlay,
    required this.cardBorder,
    required this.cardShadow,
    required this.bgSubtle,
    required this.bgGlass,
    required this.actionPrimaryBg,
    required this.actionPrimaryFg,
    required this.actionSecondaryBg,
    required this.brand,
    required this.brandSoft,
    required this.inputBgEmpty,
    required this.inputBgFilled,
    required this.statePressed,
    required this.statusInfo,
    required this.statusWarning,
    required this.statusSuccess,
    required this.statusDanger,
    required this.inputPlaceholder,
    required this.onCoverFg,
  });

  final Color bgPage;
  final Color bgSurface;
  final Color bgSurfaceSubtle;
  final Color bgSurfaceStrong;
  final Color bgElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textPlaceholder;
  final Color textDisabled;
  final Color textInverse;
  final Color borderSubtle;
  final Color borderStrong;
  final Color overlay;

  /// ★ 卡片「描边 vs 投影」在两端是**互斥**的,不是可叠加的两个装饰:
  ///   暗色端没有投影(黑底上投影不可见),靠 1px 描边划出卡片边界;
  ///   浅色端 tokens.wxss:663-665 明确把 border 和顶缘高光都置 transparent,
  ///   只留投影 —— 白卡叠白底再加灰描边会显脏。两个都给 = 两端都不对。
  final Color cardBorder;
  final List<BoxShadow> cardShadow;

  /// ★ 半透明微亮底(标签/次级按钮/禁用态)。**两端不是同一种做法**:
  ///   暗色端 `rgba(255,255,255,.04)` —— 靠透明度在黑底上提亮;
  ///   浅色端 `#f8fafc` 实色 —— 因为 4% 白叠在白卡上**完全不可见**,
  ///   标签会渲成「没有底的一行灰字」(2026-08-19 商家台账基准图实拍到)。
  final Color bgSubtle;
  final Color bgGlass;

  /// 主 CTA 底/字。★ **两端正好相反**:暗色端近白底黑字,浅色端纯黑底白字
  /// (tokens.wxss `.theme-light`:679 「2026-08-07 用户拍板:主 CTA 纯黑」)。
  /// 用静态常量会在浅色页上渲出「白底白丸」—— 选中态和未选中态完全看不出差别。
  final Color actionPrimaryBg;
  final Color actionPrimaryFg;
  final Color actionSecondaryBg;

  /// 强调色。★ 城瘾是**黑白系**:暗色端 brand 就是 text-primary(近白),
  /// 浅色端是商家中性灰 #33363C(tokens.wxss:36 明确「商家配色禁墨蓝,
  /// CTA/选中改灰,不带蓝色相」)。两端不是同一个颜色,更不是品牌紫。
  final Color brand;

  /// 强调软底。暗色端是 12% 透明白,浅色端是实色 #EAEBEE ——
  /// 透明白叠在白卡上会完全消失,同 bgSubtle 那条坑。
  final Color brandSoft;

  /// 输入框空态 / 有内容态底色。
  /// ★ **两端是「空亮填暗」的镜像**(真源 2026-09-03 用户当面纠正的方向):
  ///   暗端空态比页底亮(#3B3B3D)、填写后回落 #1C1C1E;浅端空态纯白、
  ///   填写后压一档灰(#EFEFEF)。判据是「看一眼就知道这栏填没填」。
  /// ⚠️ 本仓生成物尚未追平该次变更(现为暗 #1C1C1E→#3B3B3D、浅 #E8E8E8→#FFFFFF),
  ///   追平要同步重录 golden,单独一批做(见 docs/design-tokens.md)。
  final Color inputBgEmpty;
  final Color inputBgFilled;

  /// 按压蒙层。两端都是「在现有底上压一层」的半透明色,**不是**实色:
  ///   暗色端 rgba(255,255,255,.10) 提亮;浅色端 rgba(15,23,43,.06) 压暗。
  /// 只用于自绘的行/卡按压反馈(HIG 无系统控件接管时的最小反馈)。
  final Color statePressed;

  /// 业务状态色(成功/警告/危险/信息)。★ **两端不是同一组值**:
  /// 浅端是 R1 调过对比度的深色原语(green-700 / amber-700 / red-700 / blue-600),
  /// 直接拿暗端值压在商家白底上会不达 AA。语义色,不做主题装饰(C1)。
  /// 状态色的**前景**另有 onCoverFg 口径(见 CyTokens):暗端状态色偏亮配深字。
  final Color statusInfo;
  final Color statusWarning;
  final Color statusSuccess;
  final Color statusDanger;

  /// 输入框占位文字。暗端 #A3A3A5 / 浅端 #6F6F6F(浅端 2026-08-25 为过
  /// 4.5:1 从 #737373 调深)。正文色不在这层:浅端真源把它归到
  /// input-filled-fg(见 docs/design-tokens.md「已知缺口」)。
  final Color inputPlaceholder;

  /// 状态色底上的前景。★ **两端相反,别凭直觉配**:
  ///   暗端状态色是调亮的,黑字对比 5.06–7.76:1,白字只有 2.55–3.91:1(不达标);
  ///   浅端状态色是压深的 R1 原语,白字 5.00–5.34:1,黑字反而 3.71–3.96:1。
  /// 即「彩色底配白字」这条常理在这套色板上**两端都不成立**,配错不抛错。
  /// 对比度由 test/theme/contrast_test.dart 锁住。
  final Color onCoverFg;

  /// 暗色(C 端)。镜像 tokens.wxss 默认 `page{}` 块。
  static const CyPalette dark = CyPalette(
    bgPage: CyTokens.bgPage,
    bgSurface: CyTokens.bgSurface,
    bgSurfaceSubtle: CyTokens.bgSurfaceSubtle,
    bgSurfaceStrong: CyTokens.bgSurfaceStrong,
    bgElevated: CyTokens.bgElevated,
    textPrimary: CyTokens.textPrimary,
    textSecondary: CyTokens.textSecondary,
    textTertiary: CyTokens.textTertiary,
    textPlaceholder: CyTokens.textPlaceholder,
    textDisabled: CyTokens.textDisabled,
    textInverse: CyTokens.textInverse,
    borderSubtle: CyTokens.borderSubtle,
    borderStrong: CyTokens.borderStrong,
    overlay: CyTokens.overlay,
    cardBorder: CyTokens.borderSubtle,
    cardShadow: <BoxShadow>[],
    bgSubtle: CyTokens.bgSubtle,
    bgGlass: CyTokens.bgGlass,
    actionPrimaryBg: CyTokens.actionPrimaryBg,
    actionPrimaryFg: CyTokens.actionPrimaryFg,
    actionSecondaryBg: CyTokens.actionSecondaryBg,
    brand: CyTokens.brand,
    brandSoft: CyTokens.brandSoft,
    inputBgEmpty: CyTokens.inputBgEmpty,
    inputBgFilled: CyTokens.inputBgFilled,
    statePressed: CyTokens.statePressed,
    statusInfo: CyTokens.statusInfo,
    statusWarning: CyTokens.statusWarning,
    statusSuccess: CyTokens.statusSuccess,
    statusDanger: CyTokens.statusDanger,
    inputPlaceholder: CyTokens.inputPlaceholder,
    onCoverFg: CyTokens.onCoverFg,
  );

  /// 浅色(商家工作台)。镜像 tokens.wxss `.theme-light / .theme-merchant`(617-665)。
  static const CyPalette light = CyPalette(
    bgPage: CyGeneratedLightTokens.colorBgPage,
    bgSurface: CyGeneratedLightTokens.colorBgSurface,
    bgSurfaceSubtle: CyGeneratedLightTokens.colorBgSurfaceSubtle,
    // ⚠️ 暂接 compCellFillBg(#EAEAEA),**不是** colorBgSurfaceStrong:
    //   生成物里浅色 colorBgSurfaceStrong 仍是玩家档 #3B3B3D(真源 09-02 起
    //   浅色块已重声明为 #E4E4E4)。追平生成物后应改回语义 token。
    bgSurfaceStrong: CyGeneratedLightTokens.compCellFillBg,
    bgElevated: CyGeneratedLightTokens.colorBgElevated,
    // 2026-08-07 用户拍板:商家版黑 = 纯黑,不是 #111 那种「柔和黑」。
    textPrimary: CyGeneratedLightTokens.colorTextPrimary,
    // ⚠️ 小程序 merchant-light.wxss:74 把 --cy-text-secondary 指到
    //   **text-tertiary**(#6B6B6B),不是 text-secondary(#404040)。
    //   照名字对齐会比小程序深一档,这里跟真源走。
    textSecondary: CyGeneratedLightTokens.textSecondary,
    textTertiary: CyGeneratedLightTokens.colorTextTertiary,
    textPlaceholder: CyGeneratedLightTokens.colorTextPlaceholder,
    textDisabled: CyGeneratedLightTokens.colorTextDisabled,
    textInverse: CyGeneratedLightTokens.colorTextInverse,
    borderSubtle: CyGeneratedLightTokens.colorBorderSubtle,
    borderStrong: CyGeneratedLightTokens.colorBorderStrong,
    overlay: CyGeneratedLightTokens.colorOverlay,
    cardBorder: Colors.transparent,
    cardShadow: <BoxShadow>[
      // --cy-comp-card-shadow-day: 0 2rpx 8rpx rgba(15,23,43,.48)
      // 2rpx/8rpx 在 750 设计宽下 ≈ 1px/4px。
      BoxShadow(color: Color(0x7A0F172B), offset: Offset(0, 1), blurRadius: 4),
    ],
    // tokens.wxss:704 `.theme-light` —— 实色,不是透明叠加
    bgSubtle: CyGeneratedLightTokens.bgSubtle,
    bgGlass: CyGeneratedLightTokens.colorBgGlass,
    actionPrimaryBg: CyGeneratedLightTokens.colorActionPrimaryBg,
    actionPrimaryFg: CyGeneratedLightTokens.colorActionPrimaryFg,
    actionSecondaryBg: CyGeneratedLightTokens.colorActionSecondaryBg,
    brand: CyGeneratedLightTokens.colorBrand,
    brandSoft: CyGeneratedLightTokens.colorBrandSoft,
    inputBgEmpty: CyGeneratedLightTokens.colorInputIdleBg,
    inputBgFilled: CyGeneratedLightTokens.colorInputFilledBg,
    statePressed: CyGeneratedLightTokens.colorStatePressed,
    statusInfo: CyGeneratedLightTokens.colorStatusInfo,
    statusWarning: CyGeneratedLightTokens.colorStatusWarning,
    statusSuccess: CyGeneratedLightTokens.colorStatusSuccess,
    statusDanger: CyGeneratedLightTokens.colorStatusDanger,
    inputPlaceholder: CyGeneratedLightTokens.colorInputPlaceholder,
    onCoverFg: CyGeneratedLightTokens.colorActionPrimaryFg,
  );

  static CyPalette of(BuildContext context) =>
      Theme.of(context).extension<CyPalette>() ?? dark;

  @override
  CyPalette copyWith({
    Color? bgPage,
    Color? bgSurface,
    Color? bgSurfaceSubtle,
    Color? bgSurfaceStrong,
    Color? bgElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textPlaceholder,
    Color? textDisabled,
    Color? textInverse,
    Color? borderSubtle,
    Color? borderStrong,
    Color? overlay,
    Color? cardBorder,
    List<BoxShadow>? cardShadow,
    Color? bgSubtle,
    Color? bgGlass,
    Color? actionPrimaryBg,
    Color? actionPrimaryFg,
    Color? actionSecondaryBg,
    Color? brand,
    Color? brandSoft,
    Color? inputBgEmpty,
    Color? inputBgFilled,
    Color? statePressed,
    Color? statusInfo,
    Color? statusWarning,
    Color? statusSuccess,
    Color? statusDanger,
    Color? inputPlaceholder,
    Color? onCoverFg,
  }) {
    return CyPalette(
      bgPage: bgPage ?? this.bgPage,
      bgSurface: bgSurface ?? this.bgSurface,
      bgSurfaceSubtle: bgSurfaceSubtle ?? this.bgSurfaceSubtle,
      bgSurfaceStrong: bgSurfaceStrong ?? this.bgSurfaceStrong,
      bgElevated: bgElevated ?? this.bgElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textPlaceholder: textPlaceholder ?? this.textPlaceholder,
      textDisabled: textDisabled ?? this.textDisabled,
      textInverse: textInverse ?? this.textInverse,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      overlay: overlay ?? this.overlay,
      cardBorder: cardBorder ?? this.cardBorder,
      cardShadow: cardShadow ?? this.cardShadow,
      bgSubtle: bgSubtle ?? this.bgSubtle,
      bgGlass: bgGlass ?? this.bgGlass,
      actionPrimaryBg: actionPrimaryBg ?? this.actionPrimaryBg,
      actionPrimaryFg: actionPrimaryFg ?? this.actionPrimaryFg,
      actionSecondaryBg: actionSecondaryBg ?? this.actionSecondaryBg,
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      inputBgEmpty: inputBgEmpty ?? this.inputBgEmpty,
      inputBgFilled: inputBgFilled ?? this.inputBgFilled,
      statePressed: statePressed ?? this.statePressed,
      statusInfo: statusInfo ?? this.statusInfo,
      statusWarning: statusWarning ?? this.statusWarning,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusDanger: statusDanger ?? this.statusDanger,
      inputPlaceholder: inputPlaceholder ?? this.inputPlaceholder,
      onCoverFg: onCoverFg ?? this.onCoverFg,
    );
  }

  @override
  CyPalette lerp(ThemeExtension<CyPalette>? other, double t) {
    if (other is! CyPalette) return this;
    return CyPalette(
      bgPage: Color.lerp(bgPage, other.bgPage, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgSurfaceSubtle: Color.lerp(bgSurfaceSubtle, other.bgSurfaceSubtle, t)!,
      bgSurfaceStrong: Color.lerp(bgSurfaceStrong, other.bgSurfaceStrong, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      bgSubtle: Color.lerp(bgSubtle, other.bgSubtle, t)!,
      bgGlass: Color.lerp(bgGlass, other.bgGlass, t)!,
      actionPrimaryBg: Color.lerp(actionPrimaryBg, other.actionPrimaryBg, t)!,
      actionPrimaryFg: Color.lerp(actionPrimaryFg, other.actionPrimaryFg, t)!,
      actionSecondaryBg: Color.lerp(
        actionSecondaryBg,
        other.actionSecondaryBg,
        t,
      )!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      inputBgEmpty: Color.lerp(inputBgEmpty, other.inputBgEmpty, t)!,
      inputBgFilled: Color.lerp(inputBgFilled, other.inputBgFilled, t)!,
      statePressed: Color.lerp(statePressed, other.statePressed, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t)!,
      inputPlaceholder: Color.lerp(
        inputPlaceholder,
        other.inputPlaceholder,
        t,
      )!,
      onCoverFg: Color.lerp(onCoverFg, other.onCoverFg, t)!,
    );
  }
}
