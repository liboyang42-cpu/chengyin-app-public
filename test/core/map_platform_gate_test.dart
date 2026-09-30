// 地图的平台闸必须在**共用组件**里,不能靠每个调用方各挡一次。
//
// ★★ 2026-08-19 一天之内撞了两次同一个疏漏(高德时代):
//   · `poi_pick_page` 直接渲地图控件,缺原生实现时**整页崩**
//     (BoxConstraints forces an infinite width);
//   · `publish_pro_page` 没挡,渲出一块空白地图,用户看不出为什么。
//   「每个调用方记得挡」这种约定**必然漏掉一个** —— 闸放错层。
//
// ⇒ 闸下沉到 AppleSceneView 里(决策 D1:非 iOS 直接降级)。新的消费方天然被保护。
//
// ⚠️ 各页自己那层**不是重复**,保留:
//   · map_page 是 App 第一屏,做的是整页降级(文案不同、还给了替代去处);
//   · play_session_page 那层还叠着**隐私协议同意**判断,不只是平台。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_text.dart';

const String _view = 'lib/core/map/apple_scene_view.dart';

void main() {
  test('★★ 地图组件自己挡平台 —— 不靠调用方', () {
    final String view = codeOf(_view);
    expect(view.contains('if (defaultTargetPlatform != TargetPlatform.iOS)'),
        isTrue,
        reason: '共用组件没挡的话,新消费方在非 iOS 上会静默崩');
    expect(view.contains('_MapUnavailable'), isTrue);
  });

  test('★ 占位不自己设尺寸,也不带构建命令/调试输出', () {
    final String raw = File(_view).readAsStringSync();
    final String body = raw.substring(raw.indexOf('class _MapUnavailable'));
    expect(body.contains('SizedBox(width:'), isFalse,
        reason: '占位设了固定宽度 —— 嵌进小卡片会溢出');
    expect(body.contains('ColoredBox'), isTrue);
    expect(body.contains('dart-define'), isFalse);
    expect(body.contains('debugPrint'), isFalse);
  });

  test('★ 业务代码不再直接引用高德', () {
    for (final String path in <String>[
      'lib/feature/map/map_page.dart',
      'lib/feature/play/play_session_page.dart',
      'lib/feature/roam/roam_live_page.dart',
      'lib/feature/search/city_node_search_page.dart',
      'lib/feature/topic/topic_detail_page.dart',
      'lib/feature/publish/publish_pro_page.dart',
    ]) {
      // 只认词首的 amap。高德留下的标识符都长这样:`AmapSceneView`、
      // `amap_scene_view.dart`、`com.amap.api`、`AMapWidget` —— 它们前面要么是
      // 行首,要么是非字母。不做这个限制的话,`roamApi`(roam + Api)这类
      // camelCase 会把自家符号判成高德引用:2026-09-17 实测就是这样误伤了
      // `play_session_page.dart`,让整条 analyze-and-test 门禁对**所有** PR 变红。
      final RegExp amap = RegExp(r'(?<![a-z])amap');
      expect(amap.hasMatch(codeOf(path).toLowerCase()), isFalse, reason: path);
    }
  });

  test('★★ 只有 AppleSceneView 直接渲 AppleMap —— 绕开它就绕开了平台闸', () {
    final List<String> direct = <String>[
      for (final FileSystemEntity e in Directory('lib').listSync(recursive: true))
        if (e is File &&
            e.path.endsWith('.dart') &&
            e.path != _view &&
            codeOf(e.path).contains('AppleMap('))
          e.path,
    ];
    expect(direct, isEmpty, reason: direct.join('\n'));
  });
}
