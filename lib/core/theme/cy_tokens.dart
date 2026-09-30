import 'package:flutter/material.dart';

import 'cy_tokens.g.dart';

/// 城瘾设计系统 token —— 与小程序 `chengyinhub-xcx/style/tokens.wxss` 一一对应。
///
/// ★ 单一真源是小程序那份 wxss。值由 `tool/gen_tokens.py` 生成到
///   `cy_tokens.g.dart`;这里只保留决策注释、语义别名与 App 独有量。
///
/// ★ 单位换算:小程序按 750rpx 设计稿,iPhone 上 750rpx = 375pt ⇒ **1rpx = 0.5pt**。
///   下面每个尺寸都标了原始 rpx 值便于回查。
///
/// ★ 这套是**黑白系**:`brand` 等于 `textPrimary`(白),主按钮是**白底黑字**。
///   彩色只做强调,不做主色 —— 这与「深空星海」蓝紫方案是**语义级不同**,
///   不是调色差异。新增 UI 一律按黑白系来。
///
/// ⚠️ token 化要匹配**语义类别**,不能只匹配数值:间距 8 与字号 8 数值相同
///   但不可互借(小程序侧曾因此返工)。用 spacing 就取 spacing,别去拿 radius。
///
/// ★ **颜色常量只服务恒暗页**(玩家域)。`CyGeneratedTokens` 是暗色编译期快照,
///   在浅色主题(商家工作台 / 主题编辑器)下**不会变**;拿它画浅色页 = 白底黑卡、
///   白底白字,而且不抛错、单测全绿(2026-08-19 一天撞三次,见
///   `test/light_pages_no_static_colors_test.dart`)。
///   → 新代码一律 `CyPalette.of(context)`(随主题切换);存量恒暗页可继续用本层,
///     但按 P3/P4 批次逐步迁出(手册 C4)。
///   → 字号 / 间距 / 圆角不受主题影响,继续从这里取;iOS 排版阶梯见 [CyType]。
abstract final class CyTokens {
  // ── 背景(深色) ─────────────────────────────────────────
  /// `--cy-color-bg-page` 纯黑。注意不是深蓝黑。
  static const Color bgPage = CyGeneratedTokens.colorBgPage;

  /// `--cy-color-bg-surface` 卡片面
  static const Color bgSurface = CyGeneratedTokens.colorBgSurface;

  /// `--cy-color-bg-surface-subtle`
  static const Color bgSurfaceSubtle = CyGeneratedTokens.colorBgSurfaceSubtle;

  /// `--cy-color-bg-elevated` 浮起层 / 输入框空态
  static const Color bgElevated = CyGeneratedTokens.colorBgElevated;

  /// `--cy-color-bg-surface-strong` 输入框填充态
  static const Color bgSurfaceStrong = CyGeneratedTokens.colorBgSurfaceStrong;

  /// `--cy-color-bg-glass` 玻璃层(半屏弹窗底)
  static const Color bgGlass = CyGeneratedTokens.colorBgGlass;

  // ── 文本 ───────────────────────────────────────────────
  /// `--cy-color-text-primary`
  static const Color textPrimary = CyGeneratedTokens.colorTextPrimary;

  /// `--cy-color-text-secondary`
  static const Color textSecondary = CyGeneratedTokens.colorTextSecondary;

  /// `--cy-color-text-tertiary`
  static const Color textTertiary = CyGeneratedTokens.colorTextTertiary;

  /// `--cy-color-text-placeholder`
  static const Color textPlaceholder = CyGeneratedTokens.colorTextPlaceholder;

  /// `--cy-color-text-disabled` rgba(255,255,255,.40)
  static const Color textDisabled = CyGeneratedTokens.colorTextDisabled;

  /// `--cy-color-text-inverse` 用于白底之上
  static const Color textInverse = CyGeneratedTokens.colorTextInverse;

  // ── 描边 / 状态 ─────────────────────────────────────────
  /// `--cy-color-border-subtle` rgba(255,255,255,.08)
  static const Color borderSubtle = CyGeneratedTokens.colorBorderSubtle;

  /// `--cy-color-border-strong` rgba(255,255,255,.16)
  static const Color borderStrong = CyGeneratedTokens.colorBorderStrong;

  /// `--cy-color-state-pressed` rgba(255,255,255,.10)
  static const Color statePressed = CyGeneratedTokens.colorStatePressed;

  /// `--cy-color-overlay` rgba(0,0,0,.56)
  static const Color overlay = CyGeneratedTokens.colorOverlay;

  // ── 动作(★黑白系的核心) ────────────────────────────────
  /// `--cy-color-action-primary-bg` 主按钮底 = **白**
  static const Color actionPrimaryBg = CyGeneratedTokens.colorActionPrimaryBg;

  /// `--cy-color-action-primary-fg` 主按钮字 = **黑**
  static const Color actionPrimaryFg = CyGeneratedTokens.colorActionPrimaryFg;

  /// `--cy-color-action-secondary-bg` rgba(255,255,255,.08)
  static const Color actionSecondaryBg =
      CyGeneratedTokens.colorActionSecondaryBg;

  /// `--cy-color-action-secondary-fg-on-dark`
  static const Color actionSecondaryFg =
      CyGeneratedTokens.colorActionSecondaryFgOnDark;

  /// 状态色底(danger/success/warning/info)之上的前景色 —— **深色**。
  ///
  /// ★ 反直觉但实测如此:本套状态色是为**深色主题**调亮的,
  ///   四个色上黑字对比度都显著高于白字(见 test/theme/contrast_test.dart):
  ///     danger  白 3.91 / 黑 5.06
  ///     success 白 2.55(**不达标**)/ 黑 7.76
  ///     warning 白 3.38 / 黑 5.86
  ///     info    白 3.41 / 黑 5.81
  ///   所以「彩色底配白字」这条常理在这套色板上是错的,不要凭直觉改成白。
  static const Color onCoverFg = CyGeneratedTokens.colorActionPrimaryFg;

  /// `--cy-color-brand` —— 就是 textPrimary。品牌色不是彩色。
  static const Color brand = CyGeneratedTokens.colorBrand;

  /// `--cy-color-brand-soft` rgba(248,248,248,.12)
  static const Color brandSoft = CyGeneratedTokens.colorBrandSoft;

  // ── 输入框 ─────────────────────────────────────────────
  static const Color inputBgEmpty = CyGeneratedTokens.colorInputIdleBg;
  static const Color inputBgFilled = CyGeneratedTokens.colorInputFilledBg;
  static const Color inputPlaceholder = CyGeneratedTokens.colorInputPlaceholder;
  static const Color inputText = CyGeneratedTokens.colorInputText;

  // ── 状态色(深色块) ─────────────────────────────────────
  /// `--cy-color-status-info`。⚠️ wxss 注释记录:原 #2F74FF 在 elevated 上
  /// 对比度不足已上调为 ref-blue-400,别改回去。
  static const Color statusInfo = CyGeneratedTokens.colorStatusInfo;
  static const Color statusWarning = CyGeneratedTokens.colorStatusWarning;
  static const Color statusSuccess = CyGeneratedTokens.colorStatusSuccess;
  static const Color statusDanger = CyGeneratedTokens.colorStatusDanger;

  // ── 节点玩法语义色（与小程序同源）──────────────────────────
  static const Color playKitTaste =
      CyGeneratedTokens.colorPlaykitTaste;
  static const Color playKitMusic =
      CyGeneratedTokens.colorPlaykitMusic;
  static const Color playKitSlow = CyGeneratedTokens.colorPlaykitSlow;

  // ── 字号(rpx → pt,÷2) ────────────────────────────────
  static const double typeMicro = CyGeneratedTokens.typeMicro;
  static const double typeCaption = CyGeneratedTokens.typeCaption;
  static const double typeLabel = CyGeneratedTokens.typeLabel;
  static const double typeBody = CyGeneratedTokens.typeBody;
  static const double typeButton = CyGeneratedTokens.typeButton;
  static const double typeCardTitle = CyGeneratedTokens.typeCardTitle;
  static const double typeSectionTitle = CyGeneratedTokens.typeSectionTitle;
  static const double typeDisplay = CyGeneratedTokens.typeDisplay;
  static const double typePageTitle = CyGeneratedTokens.typePageTitle;

  // ── 圆角(rpx → pt,÷2) ────────────────────────────────
  static const double radiusSm = CyGeneratedTokens.radiusSm;
  static const double radiusMd = CyGeneratedTokens.radiusMd;
  static const double radiusLg = CyGeneratedTokens.radiusLg;
  static const double radiusXl = CyGeneratedTokens.radiusXl;
  static const double radiusPill = CyGeneratedTokens.radiusPill;

  // ── 间距(rpx → pt,÷2) ────────────────────────────────
  static const double space1 = CyGeneratedTokens.space1;
  static const double space1_5 = CyGeneratedTokens.space1_5;
  static const double space2 = CyGeneratedTokens.space2;
  static const double space2_5 = CyGeneratedTokens.space2_5;
  static const double space3 = CyGeneratedTokens.space3;
  static const double space3_5 = CyGeneratedTokens.space3_5;
  static const double space4 = CyGeneratedTokens.space4;
  static const double space5 = CyGeneratedTokens.space5;
  static const double space6 = CyGeneratedTokens.space6;
  static const double space7 = CyGeneratedTokens.space7;
  static const double space8 = CyGeneratedTokens.space8;

  // ── 按钮尺寸(rpx → pt,÷2) ──────────────────────────────
  /// `--cy-btn-h` 88rpx。⚠️ 不是 52 —— Flutter 默认的 52 比小程序高一截。
  static const double btnH = CyGeneratedTokens.btnH;

  /// `--cy-btn-h-sm` 64rpx
  static const double btnHSm = CyGeneratedTokens.btnHSm;

  /// `--cy-btn-pad-x` 40rpx
  static const double btnPadX = CyGeneratedTokens.btnPadX;

  /// `--cy-bg-subtle` rgba(255,255,255,0.04)。次级按钮底与禁用底都用它。
  static const Color bgSubtle = CyGeneratedTokens.bgSubtle;

  /// `--cy-page-x` 页面横向安全边距。
  static const double pageX = CyGeneratedTokens.pageX;

  // ── 行高 ───────────────────────────────────────────────
  static const double leadingTight = CyGeneratedTokens.leadingTight;
  static const double leadingNormal = CyGeneratedTokens.leadingNormal;
  static const double leadingLoose = CyGeneratedTokens.leadingLoose;

  /// `--cy-shadow-card: none` —— ★深色下卡片**没有阴影**。
  /// Flutter 的 Card 默认带 elevation,必须显式置 0,否则与小程序观感不同。
  static const double cardElevation = 0;

  // ── App 静止挑战专属量(Figma component 49:270) ───────────
  static const double stillnessRingSize = 260;
  static const double stillnessRingStroke = 16;
  static const double stillnessTimerType = 80;
  static const double stillnessStabilityWidth = 220;
  static const double stillnessStabilityHeight = 8;
  static const double stillnessGuideSize = 72;
  static const double stillnessGuideIconSize = 34;
  static const double stillnessTitleTracking = 7;
  static const double stillnessCaptionTracking = 0.8;
  // ── iOS 系统控件尺寸(App 独有) ─────────────────────────
  /// 旧系统 `CupertinoTabBar` 的标准内容高度。
  static const double iosLegacyTabBarHeight = 50;

  /// `native_liquid_glass` 的最小可点击 Tab 高度与系统玻璃溢出区。
  static const double iosLiquidTabBarHeight = 56;
  static const double iosLiquidTabBarOverflow = 20;

  /// iOS 原生半屏 Sheet 的两个停靠高度与背景缩放。
  static const double iosSheetInitialHeight = 420;
  static const double iosSheetExpandedHeight = 640;
  static const double iosSheetHeightFraction = 0.7;
  static const double iosSheetBackgroundZoomScale = 0.96;
}

/// 动效档位 —— 与小程序 `--cy-motion-*` / `--cy-ease-*` 同源，由
/// `tool/gen_tokens.py` 从 tokens.wxss 生成。
///
/// ⚠️ 时长一律从这里取，不要写 `Duration(milliseconds: 180)`。
///   档位之间的空隙是**有意留的**：180ms 这种「看着差不多」的中间值不会被
///   任何测试抓住（golden 拍的是稳定态，动画中间帧根本不进基线），于是两端
///   手感会一路悄悄漂移。本轮收编前 App 侧就同时存在 160/180/200/220/250
///   五种值在做同一类态切换。
///
/// ⚠️ 归档看**语义类别**，不看数值远近：Tab / Chip / 圆点这类态切换一律
///   `fast`，键盘避让 / 滚动 / 浮层出入一律 `standard`。
///
/// 时长五档一次铺齐，是为了下次写动效时有现成的格子可进，而不是再发明
/// 一个 180ms。缓动曲线等真正有调用点再进 allowlist，现在调用处仍是
/// `Curves.easeOutCubic`，提前封装只会变死代码。
///
/// 特定动画的时间轴常量（骨架呼吸、卡包开启、逐字落定）不属于这套档位，
/// 它们是逐帧编排，留在各自模块里具名即可。
abstract final class CyMotion {
  /// `--cy-motion-press` 按压回弹，触觉级，勿加长
  static const Duration press = CyGeneratedTokens.motionPress;

  /// `--cy-motion-fast` Chip / Tab / 按钮态切换 / 进度环跟手
  static const Duration fast = CyGeneratedTokens.motionFast;

  /// `--cy-motion-standard` 局部状态 / 浮层弹出 / 键盘避让
  static const Duration standard = CyGeneratedTokens.motionStandard;

  /// `--cy-motion-slow` sheet 上滑 / 页面级过场
  static const Duration slow = CyGeneratedTokens.motionSlow;

  /// `--cy-motion-celebrate` 完成 / 徽章 / 稀有时刻
  static const Duration celebrate = CyGeneratedTokens.motionCelebrate;

  /// `--cy-motion-fade-swap` 内容淡切
  static const Duration fadeSwap = CyGeneratedTokens.motionFadeSwap;
}

/// iOS 排版阶梯(手册 §3.5 T2)—— 新代码的字号/字重来源。
///
/// **为什么要单独一层**:仓内字阶是 rpx÷2 的页面私有值(`typeBody` 14 /
/// `typeLabel` 12 …),不在 iOS text styles 的梯级上(梯上没有 14)。结构对齐
/// 小程序时,字号必须落在梯级上,否则 Dynamic Type 缩放、粗细层次与无障碍
/// 观感都会悄悄漂移(T4)—— 而 golden 拍的是静态截图,漂移不会被抓住。
///
/// 梯级(HIG Type styles,pt):
///   Large Title 34 / Title1 28 / Title2 22 / Title3 20 / Headline 17 Semibold /
///   Body 17 / Callout 16 / Subhead 15 / Footnote 13 / Caption1 12 / Caption2 11。
///
/// ⚠️ 三条硬规则:
/// - T3:强调用 Semibold/Bold,**不出现 w800/w900**(堆重手法);
/// - T5:中文字距一律 0,不加负字距;
/// - C4:颜色**不写在这层** —— 前景色由 `CyPalette.of(context)` 决定,
///   本层只表达字号与字重,两端主题共用同一套阶梯。
///
/// ⚠️ 不要在这里加 `height`:中文行高由页面按 leading* 档位显式给,
///   写死进阶梯会在多行正文里把两端行高锁成同一个值。
abstract final class CyType {
  /// Large Title 34 —— 沉浸页/卡册的大字标题(一级页导航栏不用大标题,N1)
  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  /// Title1 28
  static const TextStyle title1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Title2 22
  static const TextStyle title2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Title3 20
  static const TextStyle title3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Headline 17 Semibold —— 列表行标题、强调行的值
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// Body 17 —— iOS 正文默认档
  static const TextStyle body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Callout 16
  static const TextStyle callout = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Subhead 15 —— 次要行、表单 label
  static const TextStyle subhead = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Footnote 13 —— 辅助说明
  static const TextStyle footnote = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Caption1 12 —— 时间戳、角标文字
  static const TextStyle caption1 = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Caption2 11 —— 最小可用档(HIG 下限)
  static const TextStyle caption2 = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );
}
