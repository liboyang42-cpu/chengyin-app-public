import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 全仓门禁:**可点击的控件不许写成「即将开放」**。
///
/// ★ 靶子是「一个写着功能名的按钮,点下去弹『即将开放』」——
///   它比没有这个按钮更糟:用户会反复去点,还以为是自己操作错了。
///   我在写附近商家页时就顺手写了一个「邀约 → 即将开放」,当场删掉,于是有了这条。
///
/// ⚠️ **不拦陈述事实的文案**。第一版门禁一刀切,把三处存量全报了,逐个核完发现:
///   - `official_event.dart` 的「报名即将开放」是**状态文案**:活动尚未开始报名,
///     按钮已经是禁用的,这句在陈述事实 —— 拦它是错的;
///   - `play_session_page` 的「打卡方式暂未支持」也没有假按钮。
///   真正该拦的是**可点控件上的**占位。所以判据收窄成:同一行(或紧邻行)里
///   同时出现 onPressed/onTap 与这些词。
void main() {
  test('可点击控件的文案里没有「即将开放」这类占位', () {
    // ⚠️ 词表**漏一个词,门禁就是假的**。我第一版只写了「即将开放」,
    //    设置页里那句「我的喜欢**即将上线**」就这么溜了过去,
    //    直到我人肉读到那一行才发现。词表是这类门禁的唯一防线,宁可宽一点。
    final banned = <String>[
      '即将开放',
      '即将上线',
      '即将推出',
      '敬请期待',
      '功能开发中',
      '开发中',
      '暂未开放',
      '暂未支持',
      '尚未开放',
      '正在开发',
      '待接通',
    ];

    final offenders = <String>[];

    for (final FileSystemEntity f in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

        if (!RegExp(r'on(Pressed|Tap|Selected)\s*:').hasMatch(lines[i])) {
          continue;
        }

        // ★ 作用域 = **这个控件构造调用的完整括号范围**,靠括号配对求,
        //   既不按行数、也不按缩进。三种写法都试过,前两种都是错的:
        //     · 行数窗口(6 行):`child:` 落在窗口外 → 漏检,而且绿的原因是「没看到」
        //     · 行数窗口(12 行):扫进按钮**后面的兄弟组件** → 把登录表单下方那句
        //       独立提示误报成按钮文案
        //     · 按缩进收敛:`child:` 与 `onPressed:` **同级**(都是构造参数),
        //       会在 `style:` 那行就 break 掉 → 照样漏检
        //   括号配对才对得上「一个控件」这个语义单位。
        //   先往回找到这个控件的构造起点(`XxxWidget(` 那行),再配对到闭合。
        int start = i;
        for (int k = i; k >= 0 && k > i - 6; k--) {
          if (RegExp(r'[A-Z]\w*\s*\($').hasMatch(lines[k].trimRight()) ||
              RegExp(r'[A-Z]\w*\(').hasMatch(lines[k])) {
            start = k;
            break;
          }
        }
        int depth = 0;
        final List<String> scope = <String>[];
        for (int j = start; j < lines.length; j++) {
          scope.add(lines[j]);
          for (final int c in lines[j].codeUnits) {
            if (c == 0x28) depth++; // (
            if (c == 0x29) depth--; // )
          }
          if (j > start && depth <= 0) break;
        }
        final String window = scope.join('\n');

        for (final String bad in banned) {
          if (RegExp("'[^']*$bad[^']*'").hasMatch(window)) {
            final bool permanentlyDisabled = RegExp(
              r'on(Pressed|Tap|Selected)\s*:\s*null\s*,',
            ).hasMatch(lines[i]);
            offenders.add(
              '${f.path}:${i + 1}  '
              '${permanentlyDisabled ? '永久禁用' : '可点'}控件里出现「$bad」',
            );
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '写着功能名、点下去说「即将开放」的按钮,比没有这个按钮更糟。'
          '要么把功能做出来,要么把入口去掉:\n${offenders.join('\n')}',
    );
  });
}
