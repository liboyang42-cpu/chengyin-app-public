import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('游玩结算、带队与广场主链使用 iOS 导航壳', () {
    const List<String> paths = <String>[
      'lib/feature/play/play_ending_page.dart',
      'lib/feature/play/filter_shot_camera_page.dart',
      'lib/feature/play/team_lead_page.dart',
      'lib/feature/square/square_list_page.dart',
      'lib/feature/square/square_detail_page.dart',
    ];
    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('appBar: AppBar(')), reason: path);
    }
  });

  test('广场保留地图搜索、发布、删除和举报入口', () {
    final String list = File(
      'lib/feature/square/square_list_page.dart',
    ).readAsStringSync();
    final String detail = File(
      'lib/feature/square/square_detail_page.dart',
    ).readAsStringSync();

    expect(list, contains("label: '在地图上搜索'"));
    expect(list, contains("label: '发布'"));
    expect(detail, contains("label: '删除'"));
    expect(detail, contains("label: '举报'"));
  });
}
