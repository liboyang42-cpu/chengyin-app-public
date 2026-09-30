import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('排行榜使用系统分段控件，不再自绘点击与选中态', () {
    final String source = File(
      'lib/feature/p3/growth/leaderboard_page.dart',
    ).readAsStringSync();

    expect(source, contains('CyTabsVariant.segmented'));
    expect(source, isNot(contains('class _Segmented')));
    expect(source, isNot(contains('GestureDetector(')));
    expect(source, isNot(contains('AnimatedContainer(')));
  });
}
