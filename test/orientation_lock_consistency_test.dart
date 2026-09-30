// 锁竖屏这件事写在**四个地方**,必须同一个口径。
//
// ★★★ 2026-08-20 实测:原本**三个样** ——
//   · AndroidManifest      `screenOrientation="portrait"`  → 只正竖屏
//   · ios Info.plist(iPhone)  Portrait                     → 只正竖屏
//   · ios Info.plist(~ipad)   Portrait + **UpsideDown**    → 多允许倒竖屏
//   · lib/main.dart           portraitUp + **portraitDown** → 多允许倒竖屏
//
//   倒竖屏在真机上会把**底部固定 CTA 甩到顶上**,而全站页面都是
//   「底部固定主按钮」的版式。iPad 那条是 Flutter 模板残留。
//
// ⚠️ 只在 Dart 里锁是不够的:**启动到首帧之间那段仍按系统方向渲染**
//   (main.dart 原注释已写明)。所以三处都要,而且要一致。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★★★ 四处锁向一致:只允许正竖屏', () {
    // ① Android
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('android:screenOrientation="portrait"'), isTrue,
        reason: 'Android 侧没锁竖屏');

    // ② / ③ iOS 两个 orientations 键。剥掉 XML 注释再判 ——
    //   本文件和 plist 的注释里都写着 UpsideDown 这个词(在解释为什么不要它)。
    final String plist =
        File('ios/Runner/Info.plist').readAsStringSync().replaceAll(
              RegExp(r'<!--.*?-->', dotAll: true),
              '',
            );
    expect(plist.contains('UIInterfaceOrientationLandscape'), isFalse,
        reason: 'iOS 侧允许了横屏 —— 全站没有横屏版设计');
    expect(plist.contains('UIInterfaceOrientationPortraitUpsideDown'), isFalse,
        reason: '倒竖屏会把底部固定 CTA 甩到顶上;'
            'iPad 那条曾经有(Flutter 模板残留)');

    // ④ Dart。codeOf 剥注释,免得抓到解释它自己的那段话。
    final String dart = codeOf('lib/main.dart');
    expect(dart.contains('DeviceOrientation.portraitUp'), isTrue);
    expect(dart.contains('DeviceOrientation.portraitDown'), isFalse,
        reason: 'Dart 侧比原生侧多允许了一个方向 —— 四处口径就不一致了');
    expect(dart.contains('DeviceOrientation.landscape'), isFalse);
  });
}
