// 文案叫用户重试,就必须给得了重试。
//
// ★ 起因(2026-08-18):`map_page.dart` 的隐私设置读取失败态写着「隐私设置读取失败,
//   请重试」,却**没有传 onRetry** —— 那是 App 的**第一屏**(initialLocation='/map'),
//   用户会永久卡在一个叫他重试、又无处可点的界面上,只能杀进程重开。
//
// 这类错**看图看不出来**:截图里那句「请重试」本身长得完全正常,
// 缺的是"没有按钮"这件事,而空白不会在图上喊出来。
//
// 只管「文案承诺了动作」的那一类;空态(还没买过票 / 还没领过券)本来就不需要出路,
// 不在管辖范围。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

/// 出现这些词 = 文案向用户承诺了一个可执行动作。
const List<String> _promisesAction = <String>['重试', '再试', '刷新一下', '点击重新'];

void main() {
  test('凡文案里承诺了「重试」的 StatusView,都必须带 onRetry', () {
    final List<String> offenders = <String>[];

    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      // ★ 剥掉注释再扫。注释里几乎必然出现「重试」二字 ——
      //   它正在解释"这里为什么**不**给重试"。照全文扫会把那句说明
      //   当成界面文案,判成"承诺了重试却没给"。理由见 support/source_text.dart。
      final String src = codeOf(e.path);

      for (final RegExpMatch m in RegExp(r'StatusView\(').allMatches(src)) {
        // 括号配平,取出整个 StatusView(...) 块。
        int depth = 0;
        int j = m.end - 1;
        while (j < src.length) {
          if (src[j] == '(') depth++;
          if (src[j] == ')') {
            depth--;
            if (depth == 0) break;
          }
          j++;
        }
        final String block = src.substring(m.start, j + 1);
        final bool promises =
            _promisesAction.any((String w) => block.contains(w));
        if (promises && !block.contains('onRetry')) {
          final int line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些状态态的文案让用户重试,却没给可点的重试:\n${offenders.join('\n')}',
    );
  });
}
