// 配色对比度守卫。
//
// 2026-08-18 把主题从「深空星海」蓝紫系换成与小程序一致的黑白系,
// primary 从星蓝变成**白**(主按钮白底黑字)。这类换底最容易踩的坑是
// 「token 名对了、颜色不对」——尤其是**同色系软底吃掉自己文字的对比度**:
// 角标常写成 `色.withValues(alpha:.15)` 当底 + 同一个色当字,主色一变白就糊。
//
// 故这里按 WCAG 相对亮度算真实对比度,且**半透明底先与父层合成再比**。

import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/theme/app_colors.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/main.dart';

double _luminance(Color c) {
  double ch(double v) {
    v = v / 255.0;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = c.toARGB32();
  final r = ch(((argb >> 16) & 0xFF).toDouble());
  final g = ch(((argb >> 8) & 0xFF).toDouble());
  final b = ch((argb & 0xFF).toDouble());
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrast(Color fg, Color bg) {
  final a = _luminance(fg), b = _luminance(bg);
  final hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// 把半透明色合成到不透明父层上,得到**实际显示**的颜色。
/// ★ 不做这一步就比对比度,等于比了一个屏幕上不存在的颜色。
Color composite(Color fg, Color opaqueBg) {
  final f = fg.toARGB32(), b = opaqueBg.toARGB32();
  final a = ((f >> 24) & 0xFF) / 255.0;
  int mix(int fc, int bc) => (fc * a + bc * (1 - a)).round();
  return Color.fromARGB(
    0xFF,
    mix((f >> 16) & 0xFF, (b >> 16) & 0xFF),
    mix((f >> 8) & 0xFF, (b >> 8) & 0xFF),
    mix(f & 0xFF, b & 0xFF),
  );
}

void main() {
  group('黑白系换底后的对比度', () {
    test('主按钮:白底黑字必须达 AA(≥4.5)', () {
      expect(
        contrast(AppColors.onPrimary, AppColors.primary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('正文 / 次要文字在页面底与卡片面上均达 AA', () {
      expect(
        contrast(AppColors.textPrimary, AppColors.bgDeep),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppColors.textPrimary, AppColors.bgSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppColors.textSecondary, AppColors.bgSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('★ 半透明角标必须合成后再比,不能比"屏幕上不存在的颜色"', () {
      final badgeBg = composite(
        AppColors.primary.withValues(alpha: 0.15),
        AppColors.bgSurface,
      );
      expect(
        contrast(AppColors.primary, badgeBg),
        greaterThanOrEqualTo(3.0),
        reason: '角标是小字号非正文，按 AA Large 的 3:1 下限',
      );
    });

    test('次要按钮前景在页面底上达 AA', () {
      expect(
        contrast(CyTokens.actionSecondaryFg, CyTokens.bgPage),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('禁用态文字合成后仍可辨(≥2.5,低于正文但不至于隐形)', () {
      final disabled = composite(AppColors.textDisabled, AppColors.bgSurface);
      expect(contrast(disabled, AppColors.bgSurface), greaterThanOrEqualTo(2.5));
    });

    test('描边不是"看不见"——合成后与卡片面有可辨差异', () {
      final line = composite(AppColors.divider, AppColors.bgSurface);
      expect(contrast(line, AppColors.bgSurface), greaterThan(1.05));
    });
  });

  group('按钮规格与禁用态(对齐 .cy-btn)', () {
    test('★ 禁用态是"换色"不是"降透明度"', () {
      // 小程序 components.wxss 原注释:opacity:.4 会把已调过对比度的文字
      // 整体压暗到 4.5:1 以下,且全站出现两套禁用视觉。
      // 正解是 text-placeholder 字 + bg-subtle 底。
      final bg = composite(CyTokens.bgSubtle, CyTokens.bgPage);
      final c = contrast(CyTokens.textPlaceholder, bg);
      expect(c, greaterThanOrEqualTo(3.0),
          reason: '禁用态要"看得出不可用"但仍可辨认，不能糊成一团');

      // 对照:若改回 opacity .4 压暗文字,对比度会显著更差。
      final faded = composite(
        CyTokens.textPrimary.withValues(alpha: 0.4),
        CyTokens.bgPage,
      );
      expect(contrast(faded, CyTokens.bgPage), lessThan(c),
          reason: 'opacity 方案确实更差，这就是不用它的原因');
    });

    test('按钮尺寸/圆角来自 token,不是 Flutter 默认值', () {
      // .cy-btn 高 88rpx→44(Flutter 常见写法是 52,比小程序高一截)
      expect(CyTokens.btnH, 44);
      expect(CyTokens.btnHSm, 32);
      expect(CyTokens.btnPadX, 20);
      // ★ 按钮圆角是 radius-lg 不是 md —— 卡片才用 md。
      expect(CyTokens.radiusLg, 16);
      expect(CyTokens.radiusMd, 12);
    });

    test('次级按钮底色可辨(填充式,无描边)', () {
      // 用户定「只有填充没有描边」,那么填充本身必须能与页面底分开。
      final fill = composite(CyTokens.actionSecondaryBg, CyTokens.bgPage);
      expect(contrast(fill, CyTokens.bgPage), greaterThan(1.03),
          reason: '没有描边时，填充是唯一的边界线索');
      expect(contrast(CyTokens.actionSecondaryFg, fill),
          greaterThanOrEqualTo(4.5));
    });
  });

  group('禁用按钮在纯黑页面上必须看得见(golden 抓到的盲区)', () {
    test('★ 只断言禁用「文字」不够 —— 按钮「底」与页面底也要可辨', () {
      // 实测教训:bg-subtle 是 rgba(255,255,255,.04),叠在纯黑页面底上
      // ≈ #0A0A0A,与背景几乎无差,整个按钮在快照里看不见。
      // 小程序那个值能用是因为它的按钮多在 #0A0A0B 卡片内。
      final fill = composite(CyTokens.bgSubtle, CyTokens.bgPage);
      final selfContrast = contrast(fill, CyTokens.bgPage);
      // 这条**故意断言它不可辨**,把「底色本身救不回来」这个事实固定下来 ——
      // 所以必须靠描边给边界,而不是把 bgSubtle 调亮(那会偏离 token)。
      expect(selfContrast, lessThan(1.2),
          reason: '若某天它变得可辨了，说明有人动了 bgSubtle 或 bgPage，届时该重估描边方案');
      // 描边是实际的边界线索,它必须能被看见。
      final line = composite(CyTokens.borderSubtle, CyTokens.bgPage);
      expect(contrast(line, fill), greaterThan(1.05),
          reason: '描边要能从按钮填充里分出来，否则等于没加');
    });
  });

  group('彩色底上的前景(onCoverFg)', () {
    test('★ 状态色底 + onCoverFg 必须达 AA(3:1 大字下限)', () {
      for (final bg in <Color>[
        CyTokens.statusDanger,
        CyTokens.statusSuccess,
        CyTokens.statusWarning,
        CyTokens.statusInfo,
      ]) {
        expect(contrast(CyTokens.onCoverFg, bg), greaterThanOrEqualTo(3.0),
            reason: '角标/勾选这类小图形按 AA Large 下限');
      }
    });

    test('★ 状态色上深字优于白字 —— 别凭"彩色底配白字"的常理改回白', () {
      // 本套状态色为深色主题调亮,四个色上黑字对比度都显著更高。
      // success 上白字只有 2.55,连 AA Large 都不到。
      for (final bg in <Color>[
        CyTokens.statusDanger,
        CyTokens.statusSuccess,
        CyTokens.statusWarning,
        CyTokens.statusInfo,
      ]) {
        expect(
          contrast(CyTokens.onCoverFg, bg),
          greaterThan(contrast(const Color(0xFFFFFFFF), bg)),
          reason: '若某天状态色被调暗到白字更优，这条会红，届时才该改 onCoverFg',
        );
      }
    });
  });

  group('与小程序 token 的一致性(防止只改 AppColors 不改 token)', () {
    test('AppColors 的底色/文字必须直接来自 CyTokens', () {
      expect(AppColors.bgDeep, CyTokens.bgPage);
      expect(AppColors.bgSurface, CyTokens.bgSurface);
      expect(AppColors.textPrimary, CyTokens.textPrimary);
      expect(AppColors.divider, CyTokens.borderSubtle);
    });

    test('★ 主按钮是白底黑字,不是彩色底 —— 黑白系的核心约束', () {
      expect(AppColors.primary, CyTokens.actionPrimaryBg);
      expect(AppColors.onPrimary, CyTokens.actionPrimaryFg);
      expect(CyTokens.brand, CyTokens.textPrimary);
    });
  });

  // 状态色是 C4 双值的样板:两端取值不同,而且**前景也要跟着换**。
  // 「彩色底配白字」这条常理在这套色板上两端都不成立 —— 配错不抛错,
  // 只有真盯着那一屏才看得出来,所以把对比度锁进测试。
  group('状态色双值(CyPalette)的 ADA 对比度', () {
    final List<(String, Color)> darkFills = <(String, Color)>[
      ('info', CyPalette.dark.statusInfo),
      ('warning', CyPalette.dark.statusWarning),
      ('success', CyPalette.dark.statusSuccess),
      ('danger', CyPalette.dark.statusDanger),
    ];
    final List<(String, Color)> lightFills = <(String, Color)>[
      ('info', CyPalette.light.statusInfo),
      ('warning', CyPalette.light.statusWarning),
      ('success', CyPalette.light.statusSuccess),
      ('danger', CyPalette.light.statusDanger),
    ];

    test('暗端状态底配 onCoverFg(深字)≥ 4.5', () {
      for (final (String name, Color fill) in darkFills) {
        expect(
          contrast(CyPalette.dark.onCoverFg, fill),
          greaterThanOrEqualTo(4.5),
          reason: '$name 状态底上 onCoverFg 不达标 —— 白字在这套亮色状态块上只有 2.5-3.9:1',
        );
      }
    });

    test('浅端状态底配 onCoverFg(白字)≥ 4.5', () {
      for (final (String name, Color fill) in lightFills) {
        expect(
          contrast(CyPalette.light.onCoverFg, fill),
          greaterThanOrEqualTo(4.5),
          reason: '$name 状态底上白字不达标 —— 浅端是压深的 R1 原语,黑字反而更差',
        );
      }
    });

    test('状态色当文字:浅端白卡/页底、暗端黑底都 ≥ 4.5', () {
      for (final (String name, Color fill) in lightFills) {
        expect(contrast(fill, CyPalette.light.bgSurface),
            greaterThanOrEqualTo(4.5), reason: '$name 在白卡上');
        expect(contrast(fill, CyPalette.light.bgPage),
            greaterThanOrEqualTo(4.5), reason: '$name 在页底上');
      }
      for (final (String name, Color fill) in darkFills) {
        expect(contrast(fill, CyPalette.dark.bgPage),
            greaterThanOrEqualTo(4.5), reason: '$name 在黑页底上');
      }
    });
  });

  // ★ 上面全是 **token 级**断言,而 2026-09-18 出的这个坑在**接线**上:
  //   `CupertinoButton.filled` 的文字色读的是 `CupertinoTheme.primaryContrastingColor`
  //   (cupertino/button.dart),SDK 默认值恒为**白**;而 App 根主题只给了 primaryColor
  //   (= 主按钮底色 #F8F8F8)→ 白底白字 ≈1.1:1。b1-sim-topic 模拟器实拍 tp-05:
  //   `/topic/pricing/partner` 错误态的「重试」整枚按钮看不出字。
  //   所以这里起**真 App 根主题**读一遍,而不是再算一遍 token。
  group('App 根 Cupertino 主题的按钮配色', () {
    testWidgets('filled 按钮的文字色与 primaryColor 是配对的(不是白字)', (
      WidgetTester tester,
    ) async {
      // bootstrap 会经 flutter_secure_storage 读 token(测试环境无原生 channel,
      // 不注册内存 mock 会永久挂起)—— 与 test/widget_test.dart 同款。
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await tester.pumpWidget(const ProviderScope(child: ChengyinApp()));
      await tester.pump();

      final CupertinoThemeData theme = CupertinoTheme.of(
        tester.element(find.text('城瘾')),
      );
      expect(theme.primaryColor, AppColors.primary, reason: '主按钮底色仍是白');
      expect(
        theme.primaryContrastingColor,
        AppColors.onPrimary,
        reason: '少了这一项就退回 SDK 默认的白色 —— 白底白字',
      );
      expect(
        contrast(theme.primaryContrastingColor, theme.primaryColor),
        greaterThanOrEqualTo(3),
        reason: 'filled 按钮实测曾 ≈1.1:1,连 WCAG 3:1 都不到',
      );
    });
  });
}
