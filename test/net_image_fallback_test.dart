// 网络图必须有兜底 —— 与地图 Key 那次是同一个病。
//
// ★★ 2026-08-19 扫出来:全仓 58 处 `Image.network`,其中 13 处**没有
//   errorBuilder**。URL 挂了、图被删了、或者后端下发空串时,
//   Flutter 会画一个系统碎图标 —— 在深色底上是个刺眼的灰白方块,
//   而且它**长得像 bug 而不像"这张图没了"**。
//
//   靠"每个调用方记得写 errorBuilder"的约定必然漏掉一批
//   (地图那次是 4 个调用方漏了 2 个)。收口成 CyNetImage,
//   新代码天然有兜底。
//
// ⚠️ 已有 errorBuilder 的那些**没动** —— 它们的兜底往往是有意设计的
//   (比如俱乐部 logo 兜成首字母方块)。这条门禁只拦"一个兜底都没有"。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/cy_net_image.dart';
import 'support/source_text.dart';

void main() {
  testWidgets('★★ 空 URL 走兜底,不抛 —— 后端很多字段是 String?',
      (WidgetTester tester) async {
    // 传空串给 Image.network 会抛 "No host specified in URI"。
    for (final String? u in <String?>[null, '', '   ']) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CyNetImage(u, width: 40, height: 40)),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '「$u」不该抛');
    }
  });

  testWidgets('★ 兜底不画错误图标 —— 一张加载不出来的图最好安静地不在那里',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CyNetImage(null, width: 40, height: 40)),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(find.byIcon(Icons.error), findsNothing);
  });

  test('★★ 每一处网络图都要有兜底(自带 errorBuilder 或走 CyNetImage)', () {
    final List<String> offenders = <String>[];
    int scanned = 0;

    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      // 组件本身自带兜底,豁免。
      if (e.path.endsWith('cy_net_image.dart')) continue;
      // ⚠️ npc/ 是用户在改的目录,不纳入(改了会撞车)。
      if (e.path.contains('/npc/')) continue;

      final String code = codeOf(e.path);
      final int n = RegExp(r'Image\.network\(').allMatches(code).length;
      if (n == 0) continue;
      scanned++;
      final int guarded = RegExp(r'errorBuilder').allMatches(code).length;
      if (guarded < n) {
        offenders.add('${e.path}  ${n} 处图 / ${guarded} 个兜底');
      }
    }

    expect(scanned, greaterThan(5),
        reason: '只扫到 $scanned 个含网络图的文件 —— 断言写法失效了');
    expect(offenders, isEmpty,
        reason: '这些网络图没有兜底 —— URL 挂了会显示系统碎图标,'
            '看着像 bug 而不像"这张图没了"。改用 CyNetImage:\n'
            '${offenders.join('\n')}');
  });

  test('★ 兜底色跟着主题走 —— 商家域是浅色页', () {
    // 写死深色 token 会在白底上变成一个黑方块。
    // (门禁 light_pages_no_static_colors 抓到过我这一处。)
    final String code = codeOf('lib/core/widgets/cy_net_image.dart');
    expect(code.contains('CyPalette.of(context)'), isTrue);
    expect(code.contains('CyTokens.bg'), isFalse);
  });
}
