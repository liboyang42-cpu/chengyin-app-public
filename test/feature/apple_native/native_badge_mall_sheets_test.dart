import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('勋章详情使用 Cupertino Sheet 和系统操作按钮', () {
    final String source = File(
      'lib/feature/p3/badges/badge_wall_page.dart',
    ).readAsStringSync();

    expect(source, contains('showCupertinoSheet<void>'));
    expect(source, contains('CupertinoPageScaffold('));
    expect(source, contains('CupertinoButton('));
    expect(source, isNot(contains('showModalBottomSheet')));
  });

  test('商品加购使用 Cupertino Sheet、系统步进按钮和确认操作', () {
    final String source = File(
      'lib/feature/mall/product_detail_page.dart',
    ).readAsStringSync();

    expect(source, contains('showCupertinoSheet<void>'));
    expect(source, contains('CupertinoPageScaffold('));
    expect(
      RegExp(r'\bCupertinoButton\(').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
    expect(source, isNot(contains('showModalBottomSheet')));
  });
}
