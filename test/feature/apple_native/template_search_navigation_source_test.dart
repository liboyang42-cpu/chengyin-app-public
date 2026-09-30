import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

bool _hasMaterialScaffold(String source) =>
    source.replaceAll('CupertinoPageScaffold', '').contains('Scaffold(');

void main() {
  test('负控：页面级 Material Scaffold 不能通过原生导航检查', () {
    expect(_hasMaterialScaffold('return Scaffold(appBar: AppBar());'), isTrue);
  });

  test('模板与城市节点搜索页的页面级根壳全部使用 Cupertino 导航', () {
    const Map<String, int> expectedNativeRoots = <String, int>{
      'lib/feature/template/template_detail_page.dart': 1,
      'lib/feature/template/template_edit_page.dart': 2,
      'lib/feature/template/template_intro_page.dart': 1,
      // 页面根壳 + 节点详情 Cupertino sheet，两者都应保留。
      'lib/feature/search/city_node_search_page.dart': 2,
    };

    for (final MapEntry<String, int> contract in expectedNativeRoots.entries) {
      final String source = _source(contract.key);
      expect(
        'CupertinoPageScaffold('.allMatches(source).length,
        greaterThanOrEqualTo(contract.value),
        reason: '${contract.key} 缺少页面级原生导航根壳',
      );
      expect(
        source,
        contains('CupertinoNavigationBar('),
        reason: '${contract.key} 缺少 iOS 原生导航栏',
      );
      expect(
        _hasMaterialScaffold(source),
        isFalse,
        reason: '${contract.key} 仍有页面级 Material Scaffold',
      );
    }
  });

  test('编辑、跳过、搜索与 sheet 入口不因导航迁移丢失', () {
    final String edit = _source('lib/feature/template/template_edit_page.dart');
    for (final String key in <String>[
      'template-preview',
      'template-save-draft',
      'template-publish',
    ]) {
      expect(edit, contains(key));
    }

    expect(
      _source('lib/feature/template/template_intro_page.dart'),
      contains('template-intro-skip'),
    );

    final String search = _source(
      'lib/feature/search/city_node_search_page.dart',
    );
    expect(search, contains('search-map-filter'));
    expect(search, contains('showCupertinoSheet<void>'));
  });
}
