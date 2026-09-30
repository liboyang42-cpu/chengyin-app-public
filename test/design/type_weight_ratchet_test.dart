// T3 字重棘轮:lib 里 `FontWeight.w800/w900` 不许**新增**。
//
// ★ 判据来源:手册 T3(强调用 bold trait,不用 w800/w900 堆重)。
//   2026-09-17 建账实测:28 个文件 61 处存量,全是重做前的老写法;
//   四条 UI 线正在逐页重写,重写时会自然消掉 —— 但**没有门禁拦新增**,
//   新写的页里再堆一个 w800 谁都不会发现。
//
// ★ 本表是**上限式**(只拦新增,不拦减少),这是对本仓棘轮先例(双向)的
//   有理由偏离:28 个文件横跨四条 UI 线的写集,双向棘轮会让他们每改对一次
//   (w800 → w600)就点红一次本文件并回来改表,冲突成本大于收益。
//   上限只拦「变多」;减少不用改表,顺手改低更好。偏高的上限只放松到
//   「建账那天」的存量,不会放行任何新增。
//
// ★ 顺带硬禁 w100/w200/w300(Ultralight/Thin/Light,T3 明令不用):
//   全仓 0 处,直接归零,没有 allowlist。
//
// ★ 负控:往任意 lib 文件加一处 `FontWeight.w800`(或 w300)→ 本测试必须红;
//   文末另有用例在临时目录里走同一条扫描路径复现这件事。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scan_support.dart';

/// 文件 → w800/w900 允许出现的**上限**。数值 = 2026-09-17 建账实测值。
const Map<String, int> kWeightCap = <String, int>{
  'lib/core/widgets/cy_widgets.dart': 2,
  'lib/feature/auth/login_page.dart': 1,
  'lib/feature/auth/splash_page.dart': 1,
  'lib/feature/club/club_list_page.dart': 1,
  'lib/feature/mall/cart_checkout_sheet.dart': 3,
  'lib/feature/mall/cart_page.dart': 2,
  'lib/feature/mall/product_detail_page.dart': 2,
  'lib/feature/mall/product_list_page.dart': 1,
  'lib/feature/merchant/batch_detail_page.dart': 1,
  'lib/feature/merchant/merchant_settlement_view.dart': 1,
  'lib/feature/play/stillness_challenge_page.dart': 1,
  'lib/feature/profile/profile_page.dart': 7,
  'lib/feature/publish/publish_chooser_sheet.dart': 3,
  'lib/feature/publish/publish_page.dart': 2,
  'lib/feature/publish/publish_pro_sheets.dart': 3,
  'lib/feature/roam/roam_hangout_page.dart': 2,
  'lib/feature/roam/roam_live_page.dart': 2,
  'lib/feature/roam/roam_poi_detail_page.dart': 4,
  'lib/feature/roam/roam_session_page.dart': 2,
  'lib/feature/settings/about_page.dart': 2,
  // template 域四条(edit 5 / intro 1 / list 6 / name 1)在 A5 外观复核里
  // 全部改成 Semibold/Bold,已归零 —— 删行 = 上限 0,锁住不再回流。
};

final RegExp _heavy = RegExp(r'FontWeight\.w[89]00');
final RegExp _light = RegExp(r'FontWeight\.w[123]00');

/// 扫一个根目录,返回 (超量项, 硬禁项, 扫描文件数)。
(List<String>, List<String>, int) scanTree(String root) {
  final List<String> over = <String>[];
  final List<String> banned = <String>[];
  int scanned = 0;
  for (final FileSystemEntity e in Directory(root).listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    scanned++;
    final String code = codeOfFile(e.path);
    final int heavy = _heavy.allMatches(code).length;
    final int cap = kWeightCap[e.path] ?? 0;
    if (heavy > cap) over.add('${e.path}: $heavy 处(上限 $cap)');
    final int light = _light.allMatches(code).length;
    if (light > 0) banned.add('${e.path}: $light 处');
  }
  return (over, banned, scanned);
}

void main() {
  test('★ lib 里 w800/w900 不许超过建账上限;w100/w200/w300 归零', () {
    final (List<String> over, List<String> banned, int scanned) = scanTree('lib');
    expect(
      scanned,
      greaterThanOrEqualTo(300),
      reason: '只扫到 $scanned 个文件,目录结构变了就把这条闸修好,别静默失效',
    );
    expect(
      over,
      isEmpty,
      reason:
          '这些文件的 w800/w900 超过了建账上限 —— T3 要求强调用 Semibold/Bold,'
          '改 w600/w700 即可;确属设计决定的话,先与标准线对齐再抬高上限:\n${over.join('\n')}',
    );
    expect(
      banned,
      isEmpty,
      reason: 'T3 明令不用 Ultralight/Thin/Light(w100/w200/w300):\n${banned.join('\n')}',
    );
  });

  test('负控:未登记文件里的 w800/w300 必须被拦下', () {
    final Directory temp = Directory.systemTemp.createTempSync('cy-weight-scan-');
    addTearDown(() => temp.deleteSync(recursive: true));
    File('${temp.path}/new_page.dart').writeAsStringSync('''
      const TextStyle a = TextStyle(fontWeight: FontWeight.w800);
      const TextStyle b = TextStyle(fontWeight: FontWeight.w900);
      const TextStyle c = TextStyle(fontWeight: FontWeight.w300);
      // FontWeight.w800 写在注释里不算
''');
    final (List<String> over, List<String> banned, int scanned) = scanTree(temp.path);
    expect(scanned, 1);
    expect(over, hasLength(1), reason: '新文件里的 w800/w900 没被拦下');
    expect(banned, hasLength(1), reason: 'w300 没被拦下');
  });
}
