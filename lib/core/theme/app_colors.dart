import 'package:flutter/material.dart';
import 'cy_tokens.dart';

/// 语义色别名 —— 所有 feature 层引用这里,**禁止硬编码**。
///
/// ★ 2026-08-18:值已全部改为引用 [CyTokens],与小程序
///   `style/tokens.wxss` 对齐。字段名保持不变,故既有页面无需改动即换肤。
///
/// ★ 这是一次**语义级**换底,不是调色:
///   原方案是「深空星海」蓝紫系(bgDeep 深蓝黑 / primary 星蓝),
///   小程序是**黑白系**——`brand = textPrimary`,主按钮**白底黑字**,
///   彩色只做强调。新增 UI 一律按黑白系,别再把彩色当主色用。
abstract final class AppColors {
  // ── 背景三层 ───────────────────────────────────────────
  /// 页面底。★纯黑,不是深蓝黑。
  static const Color bgDeep = CyTokens.bgPage;
  static const Color bgSurface = CyTokens.bgSurface;
  static const Color bgElevated = CyTokens.bgElevated;

  // ── 动作 ───────────────────────────────────────────────
  /// ★语义已变:不再是「星蓝主色」,而是**主按钮底色(白)**。
  /// 用它做强调色时注意——它现在是白的,与 textPrimary 同色。
  static const Color primary = CyTokens.actionPrimaryBg;

  /// ★语义已变:主色之上的前景,现在是**黑**(白底黑字)。
  static const Color onPrimary = CyTokens.actionPrimaryFg;

  /// 强调色。⚠️ 黑白系里彩色只做点缀,不要拿来做按钮底或主色。
  /// 小程序侧已做过「去紫相」整改,新增 UI 慎用。
  static const Color nodeGlow = Color(0xFF00E5D4);
  static const Color accentViolet = Color(0xFFB47CFF);

  // ── App 滤镜相机 ──────────────────────────────────────
  /// 夜视观测层专用荧光色，仅用于扫描线、准星与状态读数。
  static const Color filterNightVision = Color(0xFF7CFF8A);
  static const Color filterNightVisionDim = Color(0x667CFF8A);

  /// 宠物 POV 的低机位提示色，不承担主按钮语义。
  static const Color filterPetPov = Color(0xFFFFB6D2);

  // ── 文本 ───────────────────────────────────────────────
  static const Color textPrimary = CyTokens.textPrimary;
  static const Color textSecondary = CyTokens.textSecondary;
  static const Color textDisabled = CyTokens.textDisabled;

  // ── 功能色 ─────────────────────────────────────────────
  /// 已对齐 `--cy-color-status-*` 深色块取值(2026-08-18 从 tokens.wxss 取)。
  static const Color success = CyTokens.statusSuccess;
  static const Color warning = CyTokens.statusWarning;
  static const Color danger = CyTokens.statusDanger;

  /// 分隔线 = `--cy-color-border-subtle`
  static const Color divider = CyTokens.borderSubtle;
}
