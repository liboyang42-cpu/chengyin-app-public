import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('漫游历史、核销码与集邮册辅助动作使用 Cupertino', () {
    for (final String path in <String>[
      'lib/feature/roam/roam_history_page.dart',
      'lib/feature/roam/city_node_voucher_page.dart',
      'lib/feature/roam/stamp_album_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('Cupertino'), reason: path);
      expect(source, isNot(contains('TextButton(')), reason: path);
      expect(source, isNot(contains('IconButton(')), reason: path);
      expect(
        source,
        isNot(contains('CircularProgressIndicator(')),
        reason: path,
      );
    }
  });
}
