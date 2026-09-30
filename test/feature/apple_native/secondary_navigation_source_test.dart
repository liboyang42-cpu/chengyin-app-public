import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _compact(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

bool _hasNativeNavigationRoot(String source) {
  final String compact = _compact(source);
  return compact.contains('return CupertinoPageScaffold(') &&
      compact.contains('navigationBar:') &&
      compact.contains('CupertinoNavigationBar(') &&
      compact.contains('child: Material(') &&
      compact.contains('child: SafeArea(') &&
      !compact.contains('return Scaffold( appBar: AppBar(');
}

void main() {
  test('负控：Material Scaffold/AppBar 不能通过原生导航根检查', () {
    expect(
      _hasNativeNavigationRoot(
        'return Scaffold(appBar: AppBar(), body: const Text("body"));',
      ),
      isFalse,
    );
  });

  test('资讯、券码、定价、创作者与成长中心使用 iOS 原生导航根壳', () {
    const Map<String, String?> contracts = <String, String?>{
      'lib/feature/account/infomation_detail_page.dart': null,
      'lib/feature/coupon/coupon_code_page.dart': null,
      'lib/feature/topic/topic_pricing_page.dart': '确认终价',
      'lib/feature/creator/creator_center_page.dart': '创作者中心',
      'lib/feature/p3/growth/growth_center_page.dart': '成长中心',
    };

    for (final MapEntry<String, String?> contract in contracts.entries) {
      final String source = File(contract.key).readAsStringSync();
      expect(
        _hasNativeNavigationRoot(source),
        isTrue,
        reason: '${contract.key} 仍在使用 Material 根导航',
      );
      if (contract.value case final String title) {
        expect(
          _compact(source),
          contains("CupertinoNavigationBar(middle: Text('$title'))"),
          reason: '${contract.key} 不能丢失原有页面标题',
        );
      }
    }
  });
}
