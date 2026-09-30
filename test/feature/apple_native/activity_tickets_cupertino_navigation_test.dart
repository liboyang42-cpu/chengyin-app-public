import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('活动与票夹主链使用 iOS 原生导航壳', () {
    const List<String> paths = <String>[
      'lib/feature/activity/activity_list_page.dart',
      'lib/feature/activity/activity_detail_page.dart',
      'lib/feature/tickets/tickets_page.dart',
      'lib/feature/tickets/ticket_detail_page.dart',
      'lib/feature/tickets/pass_page.dart',
    ];

    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('appBar: AppBar(')), reason: path);
      expect(source, contains('CyPageTitle('), reason: '保留小程序页内大标题: $path');
    }
  });

  test('活动列表保留官方活动入口和 44pt 点击区', () {
    final String source = File(
      'lib/feature/activity/activity_list_page.dart',
    ).readAsStringSync();
    expect(source, contains("key: const Key('activities-official-entry')"));
    expect(source, contains("context.push('/official-events')"));
    // 44pt 点击区经 `CyTokens.btnH` 表达(真源 --cy-btn-h),不写字面量;
    // btnH == 44 由 test/theme/contrast_test.dart:130 钉死。
    expect(source, contains('minimumSize: const Size.square(CyTokens.btnH)'));
  });
}
