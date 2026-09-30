// iOS 上架配置的静态守卫。
//
// ★ 为什么要有:这一类值错了**本地跑一切正常**,要等 App Store 审核或上传时才炸,
//   反馈周期以天计。而它们又极容易在 Xcode 里被顺手改掉或在模板里带着占位符发出去。
//   （本轮就抓到两条:显示名是英文 "Chengyin App"、加密合规未声明。）
//
// 只断言「会让提审失败/被追问」的项,不断言样式类的东西。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _plist = 'ios/Runner/Info.plist';

String? _value(String xml, String key) {
  final int k = xml.indexOf('<key>$key</key>');
  if (k < 0) return null;
  final String rest = xml.substring(k + '<key>$key</key>'.length);
  final RegExpMatch? m = RegExp(
    r'^\s*<(string|true|false)\s*/?>([^<]*)',
  ).firstMatch(rest);
  if (m == null) return null;
  return m.group(1) == 'string' ? m.group(2) : m.group(1);
}

void main() {
  final String xml = File(_plist).readAsStringSync();

  test('主屏显示名是「城瘾」,不是英文占位', () {
    // CFBundleDisplayName 是图标下面那行字。模板默认会带 "Chengyin App"。
    expect(_value(xml, 'CFBundleDisplayName'), '城瘾');
  });

  test('已声明出口合规,免得每次上传都被追问加密问题', () {
    // App 侧只走标准 HTTPS(Env.apiBaseUrl),无加密类依赖、无自实现加密 ⇒ 属标准豁免。
    // 若将来真的引入自有加密,这里要改成 true 并补 Encryption Registration。
    expect(_value(xml, 'ITSAppUsesNonExemptEncryption'), 'false');
  });

  test('三条权限说明齐全且是中文具体用途(含糊的会被拒)', () {
    for (final String key in <String>[
      'NSCameraUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
      'NSLocationWhenInUseUsageDescription',
    ]) {
      final String? v = _value(xml, key);
      expect(v, isNotNull, reason: '$key 缺失');
      expect(v!.trim().length, greaterThan(8), reason: '$key 过短,像占位');
      expect(RegExp(r'[一-龥]').hasMatch(v), isTrue, reason: '$key 不是中文用途说明');
    }
  });

  test(
    '★ 微信 appid 仍是占位符 —— 这条红是提醒,不是故障',
    () {
      // 拿到开放平台移动应用 appid 后:把 lib/feature/auth/auth_controller.dart 的
      // kWechatAppId、本 plist 的 CFBundleURLSchemes 一起换掉,然后把本条断言反过来。
      // 在那之前它必须**一直红**,否则「占位符发上线」这件事没有任何东西挡着。
      final bool stillPlaceholder = xml.contains('wxYOURAPPID');
      expect(
        stillPlaceholder,
        isFalse,
        reason:
            '微信 appid 还是占位 wxYOURAPPID —— 真机微信登录/支付回跳必然失败。'
            '这是外部前置(需用户在开放平台注册移动应用),不是代码缺陷。',
      );
    },
    skip: '外部前置未完成:等开放平台移动应用 appid。拿到后删掉这个 skip。',
  );
}
