// iOS 排版阶梯守卫(手册 §3.5 T2 / §3.6 C4)。
//
// ★ 为什么需要:字号是**没有失败信号**的一类漂移 —— 写 14 还是 17、字重 700 还是
//   800,编译过、单测绿、golden 也只是跟着截图走一遍(基线一重录就"合法化"了)。
//   而 Dynamic Type 缩放、粗细层次和无障碍观感全靠这条梯级。所以把梯级本身锁死:
//   改阶梯必须先来改这张表,并且改的人会看到这段理由。
//
// ★ 值真源:HIG Type styles(Large Title 34 / Title1 28 / Title2 22 / Title3 20 /
//   Headline 17 Semibold / Body 17 / Callout 16 / Subhead 15 / Footnote 13 /
//   Caption1 12 / Caption2 11)。**不来自 tokens.wxss**(小程序没有 iOS 梯级)。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';

/// 期望梯级:名称 → (字号, 字重)。
const Map<String, (double, FontWeight)> kExpectedLadder =
    <String, (double, FontWeight)>{
      'largeTitle': (34, FontWeight.w700),
      'title1': (28, FontWeight.w400),
      'title2': (22, FontWeight.w400),
      'title3': (20, FontWeight.w400),
      'headline': (17, FontWeight.w600),
      'body': (17, FontWeight.w400),
      'callout': (16, FontWeight.w400),
      'subhead': (15, FontWeight.w400),
      'footnote': (13, FontWeight.w400),
      'caption1': (12, FontWeight.w400),
      'caption2': (11, FontWeight.w400),
    };

void main() {
  test('★ CyType 必须等于 iOS text styles 梯级,不许改名/加档/挪值', () {
    final Map<String, (double, FontWeight)> actual =
        <String, (double, FontWeight)>{
          'largeTitle': (
            CyType.largeTitle.fontSize!,
            CyType.largeTitle.fontWeight!,
          ),
          'title1': (CyType.title1.fontSize!, CyType.title1.fontWeight!),
          'title2': (CyType.title2.fontSize!, CyType.title2.fontWeight!),
          'title3': (CyType.title3.fontSize!, CyType.title3.fontWeight!),
          'headline': (CyType.headline.fontSize!, CyType.headline.fontWeight!),
          'body': (CyType.body.fontSize!, CyType.body.fontWeight!),
          'callout': (CyType.callout.fontSize!, CyType.callout.fontWeight!),
          'subhead': (CyType.subhead.fontSize!, CyType.subhead.fontWeight!),
          'footnote': (CyType.footnote.fontSize!, CyType.footnote.fontWeight!),
          'caption1': (CyType.caption1.fontSize!, CyType.caption1.fontWeight!),
          'caption2': (CyType.caption2.fontSize!, CyType.caption2.fontWeight!),
        };
    expect(
      actual,
      kExpectedLadder,
      reason: '阶梯变了就必须先 amend 本表(并说明为什么 Apple 的梯级不够用)',
    );
  });

  test('T3:不许 w800/w900 堆重', () {
    for (final MapEntry<String, (double, FontWeight)> entry
        in kExpectedLadder.entries) {
      expect(
        entry.value.$2.value,
        lessThanOrEqualTo(FontWeight.w700.value),
        reason:
            '${entry.key} 用了 ${entry.value.$2} —— 手册 T3 明确强调用 bold trait,'
            '不许靠 w800/w900 堆重',
      );
    }
  });

  test('T5:中文字距 0,不加负字距', () {
    final Map<String, TextStyle> all = <String, TextStyle>{
      'largeTitle': CyType.largeTitle,
      'title1': CyType.title1,
      'title2': CyType.title2,
      'title3': CyType.title3,
      'headline': CyType.headline,
      'body': CyType.body,
      'callout': CyType.callout,
      'subhead': CyType.subhead,
      'footnote': CyType.footnote,
      'caption1': CyType.caption1,
      'caption2': CyType.caption2,
    };
    for (final MapEntry<String, TextStyle> entry in all.entries) {
      expect(
        entry.value.letterSpacing,
        0,
        reason: '${entry.key} 的 letterSpacing 不是 0',
      );
    }
  });

  test('C4:阶梯只表达字号/字重,颜色不许写进来', () {
    for (final TextStyle style in <TextStyle>[
      CyType.largeTitle,
      CyType.title1,
      CyType.title2,
      CyType.title3,
      CyType.headline,
      CyType.body,
      CyType.callout,
      CyType.subhead,
      CyType.footnote,
      CyType.caption1,
      CyType.caption2,
    ]) {
      expect(style.color, isNull, reason: '字号层写死颜色 = 浅色页拿到暗色字,而且没有编译期信号');
    }
  });

  test('HIG 下限:最小 11pt', () {
    final double smallest = kExpectedLadder.values
        .map((v) => v.$1)
        .reduce((a, b) => a < b ? a : b);
    expect(
      smallest,
      greaterThanOrEqualTo(11),
      reason: 'HIG 明确最小 11pt,再小就是拿可读性换密度',
    );
  });
}
