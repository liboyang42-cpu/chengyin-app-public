import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('发布、据点和商家项目页使用 iOS 原生导航壳', () {
    const List<String> paths = <String>[
      'lib/feature/publish/publish_activity_page.dart',
      'lib/feature/roam/city_node_voucher_page.dart',
      'lib/feature/merchant/city_node_redeem_page.dart',
      'lib/feature/merchant/merchant_recruit_page.dart',
      'lib/feature/merchant/merchant_redemption_detail_page.dart',
      'lib/feature/merchant/merchant_subscription_page.dart',
      'lib/feature/merchant/project_home_page.dart',
      'lib/feature/merchant/project_players_page.dart',
      'lib/feature/merchant/node_template_edit_page.dart',
    ];

    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('appBar: AppBar(')), reason: path);
    }
  });

  test('据点核销保留手动输码的 VoiceOver 名称与 44pt 热区', () {
    final String source = File(
      'lib/feature/merchant/city_node_redeem_page.dart',
    ).readAsStringSync();

    expect(source, contains("label: '手动输入'"));
    expect(source, contains('minimumSize: const Size(44, 44)'));
    expect(source, contains("key: const Key('citynode-manual')"));
  });
}
