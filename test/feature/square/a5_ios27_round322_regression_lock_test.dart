// #322 (a5-ios27-square-topic-2) 落 main 后 4 处外观修复的回归锁。
//
// 仿 round24 抓到 #435 门禁漏洞后补测试 (#437) 的先例:
//   修好的东西必须留一道闸,不然下个人 refactor 会顺手把 44pt 缩回 36、
//   把语义名删了、把调色板取色换回暗端常量 —— 全都在 CI 里静默通过。
//
// 判据走源码字面量而不是渲染回读:
//   这四个点在真实页里都要 provider + AsyncValue 数据流才渲染得出,
//   widget test 成本远高于收益;#322 报告自己承认「compose 页无金图基线,
//   其 44pt 修复靠代码走查+analyze,未出图」。源码锁就是走查的固化。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final File f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path 不见了');
  return f.readAsStringSync();
}

void main() {
  test('square 发布页 安全标签贴片钮 minimumSize ≥44pt (#322 418bc6b7)', () {
    final String src = _read('lib/feature/square/square_compose_page.dart');
    final int i = src.indexOf("key: Key('square-compose-safety-");
    expect(i, greaterThan(0), reason: '贴片钮 key 不见了');
    final String around = src.substring(i, i + 400);
    expect(
      around,
      contains('minimumSize: const Size(44, 44)'),
      reason:
          '#322 已把 36 修到 44,不许再退回去;'
          'L9 表单贴片钮触达区 ≥44pt',
    );
    expect(
      around,
      isNot(contains('Size(0, 36)')),
      reason: '旧的 Size(0, 36) 又回来了',
    );
  });

  test('square 详情页 作者行「编辑/编辑记录」补 44pt 热区 (#322 bef83f20)', () {
    final String src = _read('lib/feature/square/square_detail_page.dart');
    for (final String key in <String>[
      "Key('square-post-edit')",
      "Key('square-post-revisions')",
    ]) {
      final int i = src.indexOf('const $key');
      expect(i, greaterThan(0), reason: '$key 不见了');
      final String around = src.substring(i, i + 300);
      expect(
        around,
        contains('minimumSize: const Size(44, 44)'),
        reason: '$key 缺 44pt 触达锁,回到裸文本钮时代',
      );
    }
  });

  test('square 草稿页 修订裸图标钮 44pt + 语义名 (#322 575adf22)', () {
    final String src = _read('lib/feature/square/square_drafts_page.dart');
    final int i = src.indexOf('_showRevisions(post)');
    expect(i, greaterThan(0), reason: '草稿页修订入口不见了');
    final int btn = src.lastIndexOf('CupertinoButton(', i);
    expect(btn, greaterThan(0), reason: '修订钮前导 CupertinoButton 不见了');
    final String around = src.substring(btn, i + 400);
    expect(
      around,
      contains('minimumSize: const Size(44, 44)'),
      reason: 'L9:裸图标钮也要 44pt',
    );
    expect(
      around,
      contains("semanticLabel: '查看修订历史'"),
      reason: 'A2:图标钮必须有语义名,screen reader 才读得出「这是修订」',
    );
  });

  test('topic 定价页 _InlineError 走调色板双值 (#322 b9ff36b1)', () {
    final String src = _read('lib/feature/topic/topic_pricing_page.dart');
    final int i = src.indexOf('class _InlineError');
    expect(i, greaterThan(0), reason: '_InlineError 不见了');
    final int end = src.indexOf('\n}\n', i);
    final String body = src.substring(i, end < 0 ? src.length : end);
    expect(
      body,
      contains('CyPalette.of(context)'),
      reason: '恒浅页必须取 palette 双值,不能直读暗端常量',
    );
    expect(
      body,
      contains('palette.statusWarning'),
      reason: '标题色走 palette.statusWarning',
    );
    expect(
      body,
      contains('palette.textSecondary'),
      reason: '副文案色走 palette.textSecondary',
    );
    expect(
      body,
      isNot(contains('CyTokens.statusWarning')),
      reason: '暗端常量在白色恒浅页上对比度不足,已修过 (#322)',
    );
    expect(body, isNot(contains('CyTokens.textSecondary')), reason: '同上');
  });
}
