// 主 CTA token 明暗归属钉死门禁。
//
// 2026-09-21 b1-sim-roam-4 N7 曾报「暗表 #F8F8F8 / 浅表 #000000 疑似互串」，
// 对账真源 style/tokens.wxss 判定为**真源如此、未互串**：
//   page{}（玩家暗）:147  --cy-color-action-primary-bg: #F8F8F8  /* 主 CTA:星白底 */
//   page{}（玩家暗）:148  --cy-color-action-primary-fg: #0A0A0A  /* 深墨字 */
//   .theme-light（商家浅）:1012  #000000  /* 2026-08-07 用户拍板:主 CTA 纯黑 */
//   .theme-light（商家浅）:1013  #FFFFFF
// 暗端 CTA 本就是「星白底 + 深墨字」的亮岛（pages/roam/index.wxss:749 有 ds-ok 注释），
// 防止未来有人按「暗=深、浅=亮」的直觉把两值"修"回去，这里逐字钉死。

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/theme/cy_tokens.g.dart';

double _luminance(Color c) {
  double ch(double v) {
    v = v / 255.0;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = c.toARGB32();
  return 0.2126 * ch(((argb >> 16) & 0xFF).toDouble()) +
      0.7152 * ch(((argb >> 8) & 0xFF).toDouble()) +
      0.0722 * ch((argb & 0xFF).toDouble());
}

double _contrast(Color fg, Color bg) {
  final a = _luminance(fg), b = _luminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  test('暗表主 CTA = 星白底 #F8F8F8 + 深墨字 #0A0A0A（真源 page{} 逐字）', () {
    expect(CyGeneratedTokens.colorActionPrimaryBg, const Color(0xFFF8F8F8));
    expect(CyGeneratedTokens.colorActionPrimaryFg, const Color(0xFF0A0A0A));
    expect(CyTokens.actionPrimaryBg, const Color(0xFFF8F8F8));
    expect(CyTokens.actionPrimaryFg, const Color(0xFF0A0A0A));
  });

  test(
    '浅表主 CTA = 纯黑底 #000000 + 白字 #FFFFFF（真源 .theme-light 逐字，2026-08-07 拍板）',
    () {
      expect(
        CyGeneratedLightTokens.colorActionPrimaryBg,
        const Color(0xFF000000),
      );
      expect(
        CyGeneratedLightTokens.colorActionPrimaryFg,
        const Color(0xFFFFFFFF),
      );
    },
  );

  test('两值不互串：暗端亮、浅端深，配对前景对比度均达 AA', () {
    expect(
      CyGeneratedTokens.colorActionPrimaryBg,
      isNot(equals(CyGeneratedLightTokens.colorActionPrimaryBg)),
      reason: '暗/浅主 CTA 底相同 = 生成映射疑似再次互串',
    );
    expect(
      _luminance(CyTokens.actionPrimaryBg),
      greaterThan(_luminance(CyPalette.light.actionPrimaryBg)),
      reason: '玩家暗端 CTA 必须是亮岛、商家浅端必须是深色',
    );
    expect(
      _contrast(CyPalette.dark.actionPrimaryFg, CyPalette.dark.actionPrimaryBg),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(
        CyPalette.light.actionPrimaryFg,
        CyPalette.light.actionPrimaryBg,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });
}
