// T5 字距棘轮:lib 里**任何**负 `letterSpacing` 一律红(存量已归零,无 allowlist)。
//
// ★ 判据来源:手册 T5「中文大字不加负字距(`letterSpacing: 0`)」,AGENTS.md 排版条
//   写成「中文不加负字距」。`test/theme/type_scale_test.dart` 的 T5 只管**梯级 token**
//   (`CyType.*`),管不到页内自造的 `TextStyle(letterSpacing: -2)` —— 这类点位一直是
//   裸奔状态。
// ★ 触发建账的是 `b8d12a90`(#435 / a5-ios27-negative-letterspacing):它人工 grep
//   清掉了 play 域两处(`pack_opening_intro.dart` 的 -2、`stopwatch_game_page.dart`
//   的 -1),报告 §4 自证「lib 面零命中」,但**没有留下任何门禁** —— 下一条线再加一处
//   负字距不会有任何东西变红。同型的漏收口本轮链上刚疼过一次(#332 的 CyTabs 源码钉测)。
// ★ 纯数字装饰也在禁区内:A5 报告 §1-2 已按「不自裁」把它归零(手册只有禁止侧条款),
//   本闸沿用同一口径。想放行必须先往手册 T5 增补条款,不在本线自裁。
// ★ 已知残余(本闸**扫不到**,登记给 #430/#353 面):`lib/core/theme/app_theme.dart`
//   未给 `cupertinoOverrideTheme` 接 `textTheme`,全局 `CupertinoButton` 仍继承
//   Flutter 自带 `-0.41` 负字距。那是**共用层未设值**,不是源码里的负字距点位。
//
// ★ 负控:文末在临时目录里走同一条扫描路径写入负字距点位,必须红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scan_support.dart';

final RegExp _negative = RegExp(r'letterSpacing:\s*-\s*[0-9]');

/// 扫一个根目录,返回 (违规点位, 扫描文件数)。
(List<String>, int) scanTree(String root) {
  final List<String> hits = <String>[];
  int scanned = 0;
  for (final FileSystemEntity e in Directory(root).listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    scanned++;
    final List<String> lines = codeOfFile(e.path).split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (_negative.hasMatch(lines[i])) {
        hits.add('${e.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
  }
  return (hits, scanned);
}

void main() {
  test('★ lib 里不许有负 letterSpacing 点位(T5:中文不加负字距)', () {
    final (List<String> hits, int scanned) = scanTree('lib');
    expect(
      scanned,
      greaterThanOrEqualTo(300),
      reason: '只扫到 $scanned 个文件,目录结构变了就把这条闸修好,别静默失效',
    );
    expect(
      hits,
      isEmpty,
      reason:
          'T5 要求中文不加负字距(强调用 Semibold/Bold)。删掉该属性回落 '
          '`DefaultTextStyle`/`CyType` 即可;确需非负值就用 `letterSpacing: 0`。'
          '\n${hits.join('\n')}',
    );
  });

  test('负控:未登记的负字距点位必须被拦下', () {
    final Directory temp = Directory.systemTemp.createTempSync(
      'cy-letterspacing-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    File('${temp.path}/new_page.dart').writeAsStringSync('''
      const TextStyle a = TextStyle(fontSize: 35, letterSpacing: -2);
      const TextStyle b = TextStyle(letterSpacing: -0.41);
      const TextStyle c = TextStyle(letterSpacing: 0);
      const TextStyle d = TextStyle(letterSpacing: 2);
      // letterSpacing: -1 写在注释里不算
''');
    final (List<String> hits, int scanned) = scanTree(temp.path);
    expect(scanned, 1);
    expect(hits, hasLength(2), reason: '负字距点位没被拦下(或把非负值误判成违规)');
  });
}
