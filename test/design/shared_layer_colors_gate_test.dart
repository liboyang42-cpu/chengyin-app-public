// 共用层色值门禁:色值字面量只许活在主题定义文件里(手册 C3/C4)。
//
// ★ 为什么需要:手册 §3.6 的分工写得很清楚 ——
//   页面给 `CyPalette.of(context)`(随外观切换),`CyTokens.*` 只给确定恒暗的页,
//   但**没有一条门禁守它**。四条 UI 线同时在写共用组件(2026-09-17),
//   谁在新组件里写一个 `Color(0xFF1C1C1E)`,就会重演
//   `light_pages_no_static_colors_test.dart` 记的那三次事故:
//   黑卡戳在白页上、状态标签底色消失、白底白字 —— 全都不报错、单测全绿。
//
// ★ 范围:`lib/core/**`,但 `lib/core/theme/**` 除外。
//   主题定义文件(`cy_palette.dart` / `app_colors.dart` / `cy_tokens.g.dart`)
//   是字面量**唯一正确的住处**;widgets / map / network 里出现字面量,就是绕过语义 token。
//
// ★ 允许清单是**双向**的(与 no_fake_glass 同规矩):登记项不再出现也红,
//   逼着人回来删行 —— 否则清单会慢慢变成一张过期的免死金牌。
//   登记项必须逐条写理由;没有理由的字面量应该改成 token,而不是加到表里。
//
// ★ 负控:`Color(0x…)` 与 `Colors.white` 的合成源码必须都被扫到(见文末用例)。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scan_support.dart';

/// `相对路径|字面量` → 允许出现的次数。每条都必须有理由。
const Map<String, int> kAllowedLiterals = <String, int>{
  'lib/core/widgets/cy_widgets.dart|0xFF6B6B6B': 1, // 选中+禁用态的中灰,待 P2 收编成 token
  'lib/core/widgets/cy_cupertino_range_slider.dart|CupertinoColors.black':
      1, // canvas.drawShadow 的投影色,不是 UI 语义色
  'lib/core/widgets/cy_cupertino_range_slider.dart|CupertinoColors.white':
      1, // 仿原生 CupertinoSlider 拇指:恒白靠阴影起层(源码注释在案),暗色下 systemBackground 会翻黑隐形
  'lib/core/widgets/cy_swipe_actions.dart|CupertinoColors.white':
      1, // 真机 UIContextualAction 图标深浅两种外观都是白,不随主题翻
};

/// 命中:`相对路径|字面量` → 次数。返回 (逐项计数, 允许清单总数)。
Map<String, int> scanSource(String path, String source) {
  final String code = stripComments(source);
  final Map<String, int> hits = <String, int>{};
  void count(String token, RegExp re) {
    final int n = re.allMatches(code).length;
    if (n > 0) hits['$path|$token'] = n;
  }

  // `Color(0x…)` 与 `Color.fromARGB(0x…)` 都是「直接写死数值」,一起拦。
  for (final RegExpMatch m in RegExp(
    r'Color\(\s*(0x[0-9A-Fa-f]+)|Color\.fromARGB\(\s*(0x[0-9A-Fa-f]+)',
  ).allMatches(code)) {
    final String token = m.group(1) ?? 'fromARGB:${m.group(2)}';
    hits['$path|$token'] = (hits['$path|$token'] ?? 0) + 1;
  }
  // 固定黑白 —— 不随外观变的色。`\b` 保证不会把 `CupertinoColors.black`
  // 同时算成 `Colors.black`(前者是另一条、单独登记)。
  count('Colors.white', RegExp(r'\bColors\.white\b'));
  count('Colors.black', RegExp(r'\bColors\.black\b'));
  count('Colors.white24', RegExp(r'\bColors\.white24\b'));
  count('Colors.black54', RegExp(r'\bColors\.black54\b'));
  count('Colors.black87', RegExp(r'\bColors\.black87\b'));
  count('CupertinoColors.white', RegExp(r'\bCupertinoColors\.white\b'));
  count('CupertinoColors.black', RegExp(r'\bCupertinoColors\.black\b'));
  return hits;
}

void main() {
  test('★ lib/core(除 theme)不许出现色值字面量', () {
    final Directory core = Directory('lib/core');
    expect(
      core.existsSync(),
      isTrue,
      reason: '找不到 lib/core,扫描退化为空会把「查不了」伪装成通过',
    );

    final Map<String, int> actual = <String, int>{};
    int scanned = 0;
    for (final FileSystemEntity e in core.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      // 主题定义文件是字面量的合法住处(且 cy_tokens.g.dart 是生成物)。
      if (e.path.startsWith('lib/core/theme/')) continue;
      scanned++;
      scanSource(e.path, e.readAsStringSync()).forEach((String k, int v) {
        actual[k] = (actual[k] ?? 0) + v;
      });
    }
    expect(
      scanned,
      greaterThanOrEqualTo(20),
      reason: '只扫到 $scanned 个共用层文件,目录结构变了就把这条闸修好,别静默失效',
    );

    // 新增/超量:字面量出现了但没人登记,或比登记的多。
    final List<String> offenders = <String>[];
    actual.forEach((String key, int n) {
      final int allowed = kAllowedLiterals[key] ?? 0;
      if (n > allowed) {
        offenders.add('$key 出现 $n 次(允许 $allowed)');
      }
    });
    // 反向:登记的条目消失了,逼人来删行。
    final List<String> stale = <String>[];
    kAllowedLiterals.forEach((String key, int allowed) {
      final int n = actual[key] ?? 0;
      if (n < allowed) {
        stale.add('$key 只剩 $n 次(登记 $allowed)');
      }
    });

    expect(
      offenders,
      isEmpty,
      reason:
          '共用层里出现了未登记的色值字面量 —— 改用 CyPalette/CyTokens 语义色;'
          '确属例外就登记进 kAllowedLiterals 并写理由:\n${offenders.join('\n')}',
    );
    expect(
      stale,
      isEmpty,
      reason:
          '这些登记项已经不存在/变少了,请从 kAllowedLiterals 删掉或改低(这是好事):\n${stale.join('\n')}',
    );
  });

  test('负控:硬编码色值必须被扫到,注释里的不算', () {
    const String mutation = '''
      final bg = Color(0xFF1C1C1E);
      final fg = Colors.white;
      Icon(CupertinoIcons.add, color: CupertinoColors.black);
      // Color(0xFF000000) 写在注释里是解释,不是违规
''';
    final Map<String, int> hits = scanSource('lib/core/example.dart', mutation);
    expect(hits['lib/core/example.dart|0xFF1C1C1E'], 1);
    expect(hits['lib/core/example.dart|Colors.white'], 1);
    expect(hits['lib/core/example.dart|CupertinoColors.black'], 1);
    expect(hits.length, 3, reason: '注释里的字面量不该被算进来');
  });
}
