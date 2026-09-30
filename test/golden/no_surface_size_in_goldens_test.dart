// 快照测试不许用 `setSurfaceSize` 定视口,一律走 [setGoldenViewport]。
//
// ★ 为什么值得一道闸:`tester.binding.setSurfaceSize` **只改渲染画布,不改
//   `MediaQuery`**。设了 390×844,页面读到的 `MediaQuery.of(context).size`
//   仍然是 flutter_test 的默认 800×600 —— 而且 800×600 是**横屏**。
//   两者不一致这件事在快照里**没有任何报错**:图照样出得来,尺寸也对,
//   只有按视口比例排的那部分是错的。于是错误被烤进基线,变成「期望」。
//   ⚠️ **错的基线比没有基线更糟**,它长得跟证据一模一样。
//
//   实证一(2026-09-09,屏③ 章节故事流):上留白 22vh 照 600 算成 132pt,
//   正确值 844 × 0.22 = 185.7pt。第一版基线就是错的,差点入库。
//
//   实证二(同日,迁移这一批时才炸出来):**页面自己没读 MediaQuery 也会中招**
//   —— Flutter SDK 的 `showCupertinoSheet` 把调用方给的 `topGap` 乘上视口高度
//   来定半屏顶部留白(`packages/flutter/lib/src/cupertino/sheet.dart:551`:
//   `top: MediaQuery.heightOf(context) * <topGap>`)。于是:
//
//     badge_wall_page.dart:119     topGap 0.28,画布 800 → 烤成 0.28×600=168pt,应为 224pt
//     search_filter_sheet.dart:23  topGap 0.12,画布 844 → 烤成 0.12×600=72pt,应为 101.3pt
//
//   后者那张基线里,半屏**盖住了用户刚输入的搜索框**,「筛选」按钮也压掉了 ——
//   而它一直是绿的。「本页没读 MediaQuery」不是安全理由,只能从源头堵。
//
// 负控(改门禁后必跑):把任意一处 `setGoldenViewport` 改回 `setSurfaceSize`,
// 下面第二条必须红并指出文件:行;把第一条探针里的 `setGoldenViewport` 换成
// `setSurfaceSize`,它必须红在 `Expected Size(390,844) / Actual Size(800,600)`。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

/// 扫描范围:`test/golden/` 下的一切,加上仓库任何角落里出快照的文件。
/// ★ 不按目录写死:哪天有人在别处写 `matchesGoldenFile`,也要被管到。
/// ⚠️ `Directory('test').listSync` 给的是相对路径(`test/golden/x.dart`),
///   所以这里不能写成 `/test/golden/` —— 带头斜杠永远匹配不上,下面那条
///   `scanned` 兜底断言就是这么把它抓出来的。
bool _isGoldenSource(File f) =>
    f.path.endsWith('.dart') &&
    (f.path.contains('/golden/') ||
        f.readAsStringSync().contains('matchesGoldenFile'));

void main() {
  testWidgets('setGoldenViewport 同时改到 MediaQuery,不只是画布',
      (WidgetTester tester) async {
    const Size viewport = Size(390, 844);
    setGoldenViewport(tester, viewport);

    late Size seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(seen, viewport, reason: '页面读到的视口必须就是快照画布');
    // ★ 钉死这一条:800×600 正是 flutter_test 的默认值,也正是
    //   `setSurfaceSize` 留下的那个错值。它一旦回来,上面那条也会红,
    //   但这条能一眼说清红在哪。
    expect(seen, isNot(const Size(800, 600)));
    expect(
      tester.binding.renderViews.first.size,
      viewport,
      reason: '渲染画布也要跟着走 —— 只设 tester.view,不再需要 setSurfaceSize',
    );
  });

  test('出快照的文件里不许出现 setSurfaceSize', () {
    final List<String> offenders = <String>[];
    int scanned = 0;

    for (final FileSystemEntity e
        in Directory('test').listSync(recursive: true)) {
      if (e is! File || !_isGoldenSource(e)) continue;
      // 本文件的 reason 字符串里要带上这个名字才说得清,豁免自己。
      if (e.path.endsWith('no_surface_size_in_goldens_test.dart')) continue;
      scanned++;

      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('setSurfaceSize')) {
          offenders.add('${e.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    // ★ 兜住断言本身:改了目录名 / 换了 cwd / `_isGoldenSource` 写窄了,
    //   offenders 会空着绿过去,而它一个文件都没扫 —— 正是本文件开头
    //   骂的那种假绿。跟兄弟门禁(`no_material_action_controls_test.dart:67`、
    //   `no_clock_dependent_goldens_test.dart:61`)同款处置。
    expect(scanned, greaterThanOrEqualTo(40),
        reason: '只扫到 $scanned 个出快照的文件,断言写法失效了');

    expect(
      offenders,
      isEmpty,
      reason: '这些地方用 setSurfaceSize 定视口,MediaQuery 会停在 800×600,\n'
          '按视口比例排版的部分会被烤错并固化成「期望」:\n'
          '${offenders.join('\n')}\n'
          '改成 setGoldenViewport(tester, const Size(w, h))(golden_theme.dart)。',
    );
  });
}
