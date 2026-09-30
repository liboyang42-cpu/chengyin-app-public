// App 不许给「微信胶囊」让位。
//
// ★★★ 2026-08-19 用户明确指出:
//   「小程序的会被微信导航栏遮挡,所以右上角都被让开了;**app 不需要**」。
//
//   小程序里右上角那块留白是给微信胶囊按钮(右上角那个「···⊙」)让位的,
//   几何来自 `wx.getMenuButtonBoundingClientRect()`:
//     · actionRight = 屏宽 − 胶囊左边 + 12   → 整条右侧都空出来
//     · contentTop  = 胶囊底 + 12            → 内容不许钻到胶囊底下
//     · sheetTop    = 胶囊底 + 5             → 弹窗顶停在胶囊下面
//   (真源:小程序 utils/nav-safe-area.js;消费方只有 roam / play / publish-fabu 三页)
//
//   **原生 App 里没有胶囊**。照抄这套几何 = 右上角白空一块、内容整体下压,
//   而且没有任何东西会出现在那里 —— 是纯粹的视觉损失。
//
// ⚠️ 这条门禁只拦「按胶囊坐标算出来的常量/命名」。
//   正常的 SafeArea / AppBar / 状态栏高度不在此列 —— 那是真的要避的东西。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★★★ lib/ 里不许出现给微信胶囊让位的几何', () {
    // 命名或注释里直指胶囊的写法。
    final RegExp banned = RegExp(
      r'menuButton|getMenuButtonBoundingClientRect|resolveMenuChrome|'
      r'actionRight|contentTop|sheetTop|capsuleGap|CAPSULE_GAP',
    );
    final List<String> hits = <String>[];
    int scanned = 0;

    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      // 用户正在改的目录不纳入(改了会撞车)。
      if (e.path.contains('/npc/')) continue;
      scanned++;
      // ★ 用 codeOf 剥注释:本文件自己就在注释里写了这些词,
      //   扫全文会让门禁抓到解释它自己的那段话(本项目栽过四次的"注释自伤")。
      final String code = codeOf(e.path);
      for (final RegExpMatch m in banned.allMatches(code)) {
        hits.add('${e.path}  「${m.group(0)}」');
      }
    }

    expect(scanned, greaterThan(100),
        reason: '只扫到 $scanned 个文件 —— 断言写法失效了');
    expect(hits, isEmpty,
        reason: 'App 里没有微信胶囊,给它让位只会白空一块右上角:\n'
            '${hits.join('\n')}');
  });

  test('★★ 负控:门禁真能红', () {
    // 把小程序那套命名塞进一段假代码,确认正则认得出来。
    final RegExp banned = RegExp(
      r'menuButton|getMenuButtonBoundingClientRect|resolveMenuChrome|'
      r'actionRight|contentTop|sheetTop|capsuleGap|CAPSULE_GAP',
    );
    for (final String sample in <String>[
      'final double actionRight = width - menuButton.left + 12;',
      'top: chrome.contentTop,',
      'const double capsuleGap = 12;',
    ]) {
      expect(banned.hasMatch(sample), isTrue, reason: '「$sample」该被拦下');
    }
    // 正常的安全区写法不该被误伤。
    for (final String ok in <String>[
      'SafeArea(top: false, child: x)',
      'MediaQuery.of(context).padding.top',
      'appBar: AppBar(title: Text("发布主题"))',
    ]) {
      expect(banned.hasMatch(ok), isFalse, reason: '「$ok」是正常写法,不该被拦');
    }
  });
}
