// 不许有「没人引用的基线图」。
//
// ★ 为什么值得一道闸:孤儿基线**永远不会被重出**,于是它定格在生成它的那一刻,
//   随后代码怎么改都与它无关 —— 它不再是证据,而是**过期证据**,还长得跟证据一模一样。
//
//   实证(2026-08-18):`goldens/skeleton.png` 无人引用,停在 `2aeb960` 那一刻,
//   底部带着一条 RenderFlex 溢出的黄黑斜纹;而那个溢出早在 `ba0c3ce` 就按根因修掉了
//   (骨架容器 Column → ListView)。复核时我看图判「标了 ✅ 的修复没生效」,
//   查下去才发现是图陈旧。**过期证据比没有证据贵**,它会带着后续所有推理跑偏。
//
// 反向那半(测试引用了不存在的基线)不用这里管:那种情况测试自己就会红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每张 goldens/*.png 都至少被一个测试引用', () {
    final Directory dir = Directory('test/golden/goldens');
    final List<String> pngs = dir
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String n) => n.endsWith('.png'))
        .toList()
      ..sort();

    // 把 test/ 下所有 dart 源码连成一片,逐个文件名去里面找。
    final StringBuffer sources = StringBuffer();
    for (final FileSystemEntity e in Directory('test').listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) {
        sources.write(e.readAsStringSync());
      }
    }
    final String all = sources.toString();

    final List<String> orphans =
        pngs.where((String n) => !all.contains(n)).toList();

    expect(
      orphans,
      isEmpty,
      reason: '这些基线图没有任何测试引用,不会随代码重出,迟早变成过期证据:\n'
          '${orphans.join('\n')}\n'
          '要么给它补一个真正会跑的测试,要么删掉它。',
    );
  });
}
