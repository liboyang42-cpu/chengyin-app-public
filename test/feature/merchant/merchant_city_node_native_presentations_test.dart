import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('据点认领和打卡码使用 Cupertino 富内容 Sheet', () {
    final String source = File(
      'lib/feature/merchant/merchant_city_node_page.dart',
    ).readAsStringSync();

    expect(source, contains('showCupertinoSheet'));
    expect(source, contains('CupertinoPageScaffold'));
    expect(
      source,
      isNot(contains('CupertinoSearchTextField')),
      reason: '小程序认领 Sheet 只有候选列表，不能借原生化多加搜索框',
    );
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, isNot(contains('AlertDialog(')));
  });

  test('核销候选的 Flutter 回退是 CupertinoActionSheet', () {
    final String source = File(
      'lib/feature/merchant/scan_choice.dart',
    ).readAsStringSync();

    expect(source, contains('AppleLiquidSheet.showSheet'));
    expect(source, contains('CupertinoActionSheet'));
    expect(source, isNot(contains('showModalBottomSheet')));
  });

  test('成为节点页保留小程序标题、入口与顺序', () {
    final String source = File(
      'lib/feature/merchant/merchant_city_node_page.dart',
    ).readAsStringSync();
    expect(source, contains("middle: const Text('成为节点')"));
    expect(source, contains('把门店变成漫游地图上的互动据点'));
    expect(source, contains("child: const Text('认领节点')"));
    expect(source, contains("child: const Text('+ 投放据点')"));
    expect(source, contains("middle: Text('认领平台节点')"));
    expect(
      source.indexOf('...home.applications.map'),
      lessThan(source.indexOf('...home.nodes.map')),
    );
  });
}
