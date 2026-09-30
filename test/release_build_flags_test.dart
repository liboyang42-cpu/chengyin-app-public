// 打包时必须注入的编译期常量,以及「高德已彻底拆干净」这道闸。
//
// ★★ 这类错的形态是**构建成功、包也正常、装上去某块功能是空的**:
//   `flutter build apk --release` 不传 --dart-define 一样出包,
//   常量是空串,对应功能静默降级 —— 构建日志不会警告,测试也不会红
//   (测试跑在 debug、也不走那条分支)。所以只能靠一份**打包清单**钉住,
//   并在这里核对清单本身没被改坏。
//
// ★ 2026-09-15(Task 1.4):地图换成 Apple Maps 后 AMAP_*_KEY 整组消失。
//   原来那条「缺 Key 时的降级文案不许写构建命令」改成两条:
//     ① map_page 的界面文案里仍不许出现构建命令/内部名(祸根还在:
//        任何 dart-define 降级都可能再犯);
//     ② pubspec 里不许再出现 amap —— 依赖只要回来,替身 plugin、
//        Podfile 分支、arm64 模拟器障碍就会一起回来。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('★★ 第一屏的降级文案不能把构建命令写给用户看', () {
    final String raw = File('lib/feature/map/map_page.dart').readAsStringSync();

    // ⚠️ 判据不是"文件里有没有 dart-define" —— assert/debugPrint 里有它是
    //   **对的**(release 会整段剥掉,只有开发者在 debug 下看得到)。
    //   要拦的是它出现在 **StatusView 的文案**里。所以只扫界面文案那几个参数。
    final Iterable<RegExpMatch> uiTexts = RegExp(
            r"(?:message|sub|title|retryLabel):\s*'([^']*)'")
        .allMatches(raw);
    expect(uiTexts, isNotEmpty, reason: '没解析到界面文案 —— 断言写法失效了');
    for (final RegExpMatch t in uiTexts) {
      final String text = t.group(1)!;
      for (final String jargon in <String>['dart-define', 'Key 未配置', 'API_BASE_URL']) {
        expect(text.contains(jargon), isFalse,
            reason: '界面文案「$text」里有构建命令/内部名 —— '
                '审核员打开第一屏就是它,等同于宣告"这 App 没做完"');
      }
    }
  });

  test('★★ pubspec 里不许再出现 amap —— 依赖回来,整条障碍链就一起回来', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.toLowerCase().contains('amap'), isFalse,
        reason: '高德依赖回到 pubspec —— AMapFoundation 没有 arm64 模拟器切片,'
            '模拟器又会起不来,视觉裁判随之瞎掉');
    final String podfile = File('ios/Podfile').readAsStringSync();
    expect(podfile.contains('CY_ARM64_SIMULATOR'), isFalse,
        reason: '替身 plugin 的 pod 切换分支回来了 —— 那是为高德开的后门');
  });

  test('★★ 打包清单必须存在,且列全了所有 dart-define', () {
    final File doc = File('docs/release-build-flags.md');
    expect(doc.existsSync(), isTrue,
        reason: '缺打包清单 —— 忘了传 --dart-define 会打出一个地图空白的包');
    final String s = doc.readAsStringSync();

    // 从 Env 里解析出全部 String.fromEnvironment 的键,逐个要求清单里写到。
    final String env = File('lib/core/config/env.dart').readAsStringSync();
    final Set<String> keys = RegExp(r"String\.fromEnvironment\(\s*'(\w+)'")
        .allMatches(env)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();
    expect(keys, isNotEmpty, reason: '没解析到 Env 里的编译期常量 —— 断言写法失效了');

    for (final String k in keys) {
      expect(s.contains(k), isTrue,
          reason: '打包清单里漏了 $k —— 漏一个就是一块功能静默失效');
    }
  });

  test('★ API 基址默认值指向生产,不是占位或内网', () {
    // 读原文而不是 codeOf:这条只看常量值,注释在不在都不影响,
    // 而剥注释会让下面按 indexOf 定位的偏移对不上。
    final String env = File('lib/core/config/env.dart').readAsStringSync();
    // ⚠️ 只取 apiBaseUrl 那一处 —— 其它 fromEnvironment 常量可能没有
    //   defaultValue(**本来就该是空**,由 --dart-define 注入),会误匹配。
    final int at = env.indexOf('apiBaseUrl');
    expect(at, greaterThan(0));
    final RegExpMatch? m =
        RegExp(r"defaultValue: '([^']+)'").firstMatch(env.substring(at));
    expect(m, isNotNull, reason: 'apiBaseUrl 的 defaultValue 不见了');
    final String url = m!.group(1)!;
    expect(url.startsWith('https://'), isTrue,
        reason: '生产基址必须是 HTTPS(ICP 备案与 ATS 都要求)');
    // 内网/占位地址混进 release 包 = 装上去什么都加载不出来。
    for (final String bad in <String>['localhost', '127.0.0.1', '10.0.2.2', 'example.com']) {
      expect(url.contains(bad), isFalse, reason: '基址里有 $bad');
    }
  });
}
