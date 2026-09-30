// B1 二轮报告 N5:#315 外观清扫后,漫游出发页/护照瓷贴仍残留 Material
// 线性图标(Android 观感混进 iOS 页面,roam2-02 实拍)。全部换成
// Cupertino 系统字形后,这里钉住不再回潮。
//
// 口径见 docs/ios27-design-language.md「实现选型② Flutter Cupertino」。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roam_live_page 不留 Material Icons.* 调用点', () {
    final String src = File(
      'lib/feature/roam/roam_live_page.dart',
    ).readAsStringSync();
    final Iterable<RegExpMatch> hits = RegExp(r'\bIcons\.').allMatches(src);
    expect(
      hits.map((RegExpMatch m) => src.substring(0, m.start).split('\n').length),
      isEmpty,
      reason: 'Material 图标残留(行号见上);用 CupertinoIcons.* 系统字形',
    );
  });
}
