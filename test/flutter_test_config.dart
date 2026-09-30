// golden 测试的全局配置:加载真实中文字体。
//
// ★ 不做这一步,golden 快照里所有中文都是 Ahem 字体的**方框(豆腐块)**,
//   看不出字号/行高/截断是否正确 —— 而那正是要靠快照检查的东西。
//
// 只影响测试渲染,不打进 App 包。字体取自 macOS 系统目录,
// 若在没有该字体的机器上跑(如 CI),静默跳过、退回方框,不让测试失败。

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _candidates = <String>[
  '/System/Library/Fonts/STHeiti Medium.ttc',
  '/System/Library/Fonts/STHeiti Light.ttc',
  '/System/Library/Fonts/Supplemental/Songti.ttc',
];

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final String path in _candidates) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    final Uint8List bytes = await f.readAsBytes();
    // 覆盖默认字族,让未指定 fontFamily 的文本也能拿到中文字形。
    // 覆盖各路默认族:主题里显式构造的 TextStyle 会丢掉 family,
    // 落到 Flutter 的默认族上,只覆盖 Roboto 不够。
    for (final String family in <String>[
      'Roboto',
      '.SF UI Text',
      '.SF UI Display',
      // ★ 现代 Flutter 的 iOS Typography 用的是这两个族名(旧的 .SF UI * 已不再命中)。
      //   不加载它们,任何用 debugDefaultTargetPlatformOverride 拍 iOS 态的基线里,
      //   页面正文都会变成方框 —— 而按钮反而是好的(它们走 goldenTheme 补的族名),
      //   一眼看去像「只有正文坏了」,很难想到是平台切换导致换了字族。
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.AppleSystemUIFont',
      'PingFang SC',
      'packages/flutter/Roboto',
    ]) {
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    break;
  }
  // 等宽字体:核销码回落态用 monospace 展示(商家要照着手输,等宽能分清 0/O、1/l)。
  // 不加载它,那段码在快照里是方框 —— 而这条正是最需要用快照盯住的应急路径。
  for (final String path in <String>[
    '/System/Library/Fonts/Menlo.ttc',
    '/System/Library/Fonts/Monaco.ttf',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    final Uint8List bytes = await f.readAsBytes();
    for (final String family in <String>['monospace', 'Menlo', 'Courier New']) {
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    break;
  }
  // 图标字体:不加载的话所有 Icon 在快照里都是空心方框,
  // 看不出图标本身是否选对、尺寸是否协调。
  final String inferredFlutterRoot = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent.parent.path;
  for (final String p in <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final String root)
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '$inferredFlutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]) {
    final File f = File(p);
    if (!f.existsSync()) continue;
    final Uint8List bytes = await f.readAsBytes();
    final FontLoader loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
    break;
  }
  // CupertinoIcons 来自 pub 包，不在 Flutter 的 Material 图标字体里。
  // 登录/手机 Sheet 已换用 CupertinoTextField 后，若不单独加载，
  // golden 会把清除、手机等 SF-style glyph 拍成方框，造成假的视觉回归。
  final String? home = Platform.environment['HOME'];
  if (home != null) {
    for (final String version in <String>['1.0.9', '1.0.8']) {
      final File f = File(
        '$home/.pub-cache/hosted/pub.dev/cupertino_icons-$version/assets/CupertinoIcons.ttf',
      );
      if (!f.existsSync()) continue;
      final Uint8List bytes = await f.readAsBytes();
      for (final String family in <String>[
        'CupertinoIcons',
        'packages/cupertino_icons/CupertinoIcons',
      ]) {
        final FontLoader loader = FontLoader(family)
          ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
      break;
    }
  }
  await testMain();
}
