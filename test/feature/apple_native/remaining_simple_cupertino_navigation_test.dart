import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const paths = <String>[
    'lib/feature/coop/complaint_page.dart',
    'lib/feature/coop/coop_pool_page.dart',
    'lib/feature/coop/coop_mybiz_page.dart',
    'lib/feature/coop/coop_perk_template_page.dart',
    'lib/feature/coop/coop_settlement_detail_page.dart',
    'lib/feature/merchant/merchant_city_node_create_page.dart',
    'lib/feature/play/play_session_page.dart',
    'lib/feature/publish/publish_pro_page.dart',
    'lib/feature/roam/roam_session_page.dart',
  ];

  test('普通二三级页统一使用 Cupertino 原生导航容器', () {
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, isNot(contains('appBar: AppBar(')), reason: path);
    }
  });
}
