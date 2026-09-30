// 发布主题 / 选择地点两页的整页快照。
//
// 这两页都是**纯表单**、没有外部依赖 —— 之所以还是要拍,
// 是因为前三轮看图抓到的三个 bug 全是"缺席被当成一个确定值"这一类,
// 而表单页的空态正是那类问题最容易藏的地方
// (占位文字看着像已填内容、必填项没标、按钮恒可点)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/publish/poi_pick_page.dart';
import 'package:chengyin_app/feature/publish/publish_page.dart';
import 'golden_theme.dart';

Future<void> _shot(
  WidgetTester t,
  Widget home,
  String path, {
  ThemeData? theme,
}) async {
  setGoldenViewport(t, const Size(390, 1000));
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: theme ?? goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  ));
  await t.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

void main() {
  testWidgets('发布主题:空表单', (WidgetTester tester) async {
    // ★ 这一页在真机上恒浅(app_router.dart:_topicEditorLight)→ 基准图也必须浅色。
    await _shot(
      tester,
      const PublishPage(),
      'goldens/page_publish.png',
      theme: topicEditorGoldenTheme(),
    );
  });

  testWidgets('★★ 选择地点:没配高德 Key 时的降级(原来会整页崩)',
      (WidgetTester tester) async {
    // 2026-08-19 补 golden 时撞出来的:这页原来**没有** Key 降级,
    // 直接渲原生地图控件 —— 没有原生实现时它返回无界尺寸,
    // 整页布局崩(BoxConstraints forces an infinite width)。
    // map_page 有这道降级,这页漏了。
    await _shot(tester, const PoiPickPage(), 'goldens/page_poi_pick.png');

    expect(find.text('地图暂时不可用'), findsOneWidget);
    // ★ 说清**替代做法** —— 这一步是发布流程里的一环,
    //   只说不可用会让人卡在这里不知道能不能继续。
    expect(find.textContaining('可以先跳过选点'), findsOneWidget);
    // 界面上不许出现构建命令(与 map_page 同一条纪律)。
    expect(find.textContaining('dart-define'), findsNothing);
  });
}
