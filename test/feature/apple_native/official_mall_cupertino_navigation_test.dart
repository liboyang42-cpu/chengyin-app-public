import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('官方活动与商城页使用 iOS 原生导航壳', () {
    const List<String> paths = <String>[
      'lib/feature/official/official_events_page.dart',
      'lib/feature/official/official_event_detail_page.dart',
      'lib/feature/mall/product_list_page.dart',
      'lib/feature/mall/product_detail_page.dart',
      'lib/feature/mall/cart_page.dart',
    ];
    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('appBar: AppBar(')), reason: path);
    }
  });

  test('商城两个购物车入口保留 VoiceOver 名称与 44pt 点击区', () {
    for (final String path in <String>[
      'lib/feature/mall/product_list_page.dart',
      'lib/feature/mall/product_detail_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains("label: '购物车'"), reason: path);
      expect(source, contains('minimumSize: const Size(44, 44)'), reason: path);
      expect(source, contains("context.push('/cart')"), reason: path);
    }
  });
}
