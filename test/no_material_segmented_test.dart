// 门禁:不许用 Material 自带的分段/选择控件。
//
// `SegmentedButton` / `ChoiceChip` / `FilterChip` 都自带 Material 3 的默认外观 ——
// 选中对勾、边框分隔、主题色填充。城瘾是黑白系,小程序那套 `cy-tabs` 长得完全不同。
//
// 实证(2026-08-19):商家台账用 `ChoiceChip`,渲出来是一颗**青绿色带对勾的胶囊**,
// 而它上下左右的页面用的是黑白药丸。同一个 App 里两种设计语言,基准图一眼就看出来。
// 当时 10 个页面各写了一套同样的东西:3 处 Material 控件、4 处 Material TabBar、
// 2 处自绘 CyChip Row、1 处 ChoiceChip。
//
// 正确做法:用 `CyTabs`(underline / segmented / chip 三个变体)。
// Material `TabBar` 可以继续用 —— 它配合 `TabBarView` 是合理的结构选择,
// 外观已在 `AppTheme` 的 tabBarTheme 里统一成 cy-tabs 的样子。
//
// 负控:往任意 feature 文件里塞一个 `SegmentedButton(`,本测试必须红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _kBanned = <String>[
  'SegmentedButton',
  'ChoiceChip',
  'FilterChip',
];

void main() {
  test('feature 层不许出现 Material 分段/选择控件', () {
    final List<String> offenders = <String>[];
    int scanned = 0;

    for (final FileSystemEntity e
        in Directory('lib/feature').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        // 注释里提到它们是正常的(解释为什么不用),只查代码
        final String code = lines[i].split('//').first;
        for (final String w in _kBanned) {
          // 带左括号才算真的在用 —— 只提名字的(如 import 或类型注解)不算
          if (code.contains('$w(') || code.contains('$w<')) {
            offenders.add('${e.path}:${i + 1}  $w');
          }
        }
      }
    }

    // ★ 目录搬家后这道闸会扫 0 个文件然后报绿 —— 必须有下限。
    expect(scanned, greaterThanOrEqualTo(60),
        reason: '只扫到 $scanned 个 feature 文件,太少了 —— 目录是不是变了?');

    expect(offenders, isEmpty,
        reason: 'Material 默认外观(选中对勾/边框分隔/主题色填充)与城瘾黑白系不搭。\n'
            '改用 CyTabs(lib/core/widgets/cy_tabs.dart):\n'
            '${offenders.join('\n')}');
  });

  test('搜索框一律走 CySearchField,不许各页自己拼 TextField', () {
    // 6 个页面各写过一套:只有 1 处有清除钮、0 处做空/满态底色区分。
    // 判据是「带搜索图标的 TextField」—— 普通表单输入框不在管辖内。
    final List<String> offenders = <String>[];
    int scanned = 0;

    for (final FileSystemEntity e
        in Directory('lib/feature').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final String src = e.readAsStringSync();
      if (!src.contains('TextField(')) continue;
      // 搜索框的特征:装饰里带放大镜
      if (RegExp(r'prefixIcon:\s*(const\s+)?Icon\(\s*Icons\.search')
          .hasMatch(src)) {
        offenders.add(e.path);
      }
    }

    expect(scanned, greaterThanOrEqualTo(60),
        reason: '只扫到 $scanned 个 feature 文件,太少了');
    expect(offenders, isEmpty,
        reason: '这些页面自己拼了搜索框,会漏掉清除钮和空/满态底色。\n'
            '改用 CySearchField(lib/core/widgets/cy_search_field.dart):\n'
            '${offenders.join('\n')}');
  });
}
