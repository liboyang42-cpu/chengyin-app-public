// 门禁:纯文本确认框不许再直接用 `AlertDialog`,一律走 `cyConfirm`。
//
// 迁移前 27 处各写一套:按钮 24 处 `TextButton` / 7 处 `FilledButton`,
// 「确定要退出账号吗?」的取消和退出是**两颗完全相同的文字按钮** —— 主次不分。
// 还有一处标题干脆叫「提示」,等于什么都没说。
//
// **带自定义内容的弹窗不在管辖内**(表单、列表、输入框那些) ——
// cyConfirm 只接标题 + 一段文字,硬塞进去反而要给它加一堆 slot,得不偿失。
// 判据是 `content:` 后面跟的是不是 `Text` / `const Text` / 字符串插值。
//
// 负控:把任意一处 cyConfirm 改回 `AlertDialog(title: Text(..), content: Text(..))`,
// 本测试必须红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 允许继续用 AlertDialog 的文件:content 是表单/列表/输入框,不是一段话。
/// ⚠️ 往这里加豁免前先想清楚:是真的需要自定义内容,还是只是懒得迁?
///    每一条都写明 content 是什么。
const Map<String, String> _kAllowed = <String, String>{};

const String _kCustomAlertMarker =
    'no-plain-alert-dialog: custom-interactive-content';

List<int> _plainTextAlertDialogLines(String src) {
  final List<int> offenders = <int>[];
  final List<String> lines = src.split('\n');
  final RegExp alertDialog = RegExp(r'(^|[^A-Za-z0-9_])AlertDialog\(');
  for (int i = 0; i < lines.length; i++) {
    if (!alertDialog.hasMatch(lines[i])) continue;
    final String seg = lines
        .sublist(i, (i + 12).clamp(0, lines.length))
        .join('\n');
    if (seg.contains(_kCustomAlertMarker)) continue;
    if (RegExp(r"content:\s*(const\s+)?Text\(").hasMatch(seg)) {
      offenders.add(i + 1);
    }
  }
  return offenders;
}

void main() {
  test('纯文本确认框一律走 cyConfirm,不许直接用 AlertDialog', () {
    final List<String> offenders = <String>[];
    int scanned = 0;
    final Set<String> usedAllowances = <String>{};

    for (final FileSystemEntity e in Directory(
      'lib/feature',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final String src = e.readAsStringSync();
      if (!src.contains('AlertDialog(')) continue;

      if (_kAllowed.containsKey(e.path)) {
        usedAllowances.add(e.path);
        continue;
      }

      // content 跟的是不是一段文字 —— 是就说明本可以用 cyConfirm。
      // 同文件的交互式内容只能按弹窗加精确标记，不得整文件豁免。
      offenders.addAll(
        _plainTextAlertDialogLines(src).map((int line) => '${e.path}:$line'),
      );
    }

    expect(
      scanned,
      greaterThanOrEqualTo(60),
      reason: '只扫到 $scanned 个 feature 文件,太少了 —— 目录变了?',
    );

    // ★ 豁免名单会腐烂:文件删了/改名了,豁免还留着,下次有人在同名新文件里
    //   写 AlertDialog 就被白白放过。所以名单里每一条都必须仍然命中。
    final Set<String> stale = _kAllowed.keys.toSet().difference(usedAllowances);
    expect(
      stale,
      isEmpty,
      reason:
          '这些豁免已经失效(文件不存在或里面已经没有 AlertDialog 了),'
          '请从 _kAllowed 删掉:\n${stale.join('\n')}',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          '这些是纯文本确认框,应该用 cyConfirm'
          '(lib/core/widgets/cy_confirm.dart)——\n'
          '直接用 AlertDialog 会退回「取消和确认长得一模一样」的老样子:\n'
          '${offenders.join('\n')}',
    );
  });

  test('★ 负控：自定义弹窗标记不能掩盖同文件纯文本确认', () {
    const String source = '''
AlertDialog(
  // no-plain-alert-dialog: custom-interactive-content
  content: Text('dynamic'),
);
AlertDialog(
  title: const Text('开启导航'),
  content: const Text('仅前台使用定位'),
);
''';

    expect(_plainTextAlertDialogLines(source), <int>[5]);
  });
}
