import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void _expectAppleActions(String source) {
  expect(source, isNot(contains('FilledButton(')));
  expect(source, isNot(contains('OutlinedButton(')));
  expect(source, isNot(contains('TextButton(')));
  expect(source, isNot(contains('IconButton(')));
  expect(source, isNot(contains('CircularProgressIndicator(')));
}

void main() {
  final Map<String, String> sources = <String, String>{
    for (final String path in <String>[
      'lib/feature/mall/cart_page.dart',
      'lib/feature/mall/product_detail_page.dart',
      'lib/feature/mall/product_list_page.dart',
      'lib/feature/orders/orders_page.dart',
      'lib/feature/orders/order_detail_sheet.dart',
    ])
      path: File(path).readAsStringSync(),
  };

  test('商城、购物车和订单高频操作使用 Apple 按钮与加载件', () {
    for (final MapEntry<String, String> entry in sources.entries) {
      _expectAppleActions(entry.value);
    }

    expect(
      sources['lib/feature/mall/cart_page.dart'],
      contains('CyNativeButton('),
    );
    expect(
      sources['lib/feature/mall/product_detail_page.dart'],
      contains('CyNativeButton('),
    );
    expect(
      sources['lib/feature/orders/orders_page.dart'],
      contains('CyNativeButton('),
    );
    expect(
      sources['lib/feature/orders/order_detail_sheet.dart'],
      contains('CyNativeButton('),
    );
    expect(
      sources['lib/feature/orders/order_detail_sheet.dart'],
      contains('CupertinoPageScaffold('),
    );
  });

  test('高频动作保留 44pt 触控下限与 VoiceOver 语义', () {
    final String combined = sources.values.join('\n');
    expect(combined, contains('minimumSize: const Size(44, 44)'));
    expect(combined, contains("label: '购物车'"));
    expect(combined, isNot(contains("Text('下单待接')")));
  });

  test('负控：主支付动作退回 Material FilledButton 必须判红', () {
    final String valid = sources['lib/feature/orders/order_detail_sheet.dart']!;
    final String broken =
        '$valid\nFilledButton(onPressed: null, child: Text("pay"));';

    expect(() => _expectAppleActions(broken), throwsA(isA<TestFailure>()));
  });
}
