// 搜索结果页整页快照:四类 tabs + 卡片列表。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_search_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/city_node_search_page.dart';
import 'package:chengyin_app/feature/search/search_result_page.dart';
import 'golden_theme.dart';

SearchResultBundle _bundle() => SearchResultBundle(
  rows: <SearchResultRow>[
    SearchResultRow(
      type: SearchResultType.topic,
      id: 1,
      title: '静安微旅行',
      detail: '城市主题',
    ),
    SearchResultRow(
      type: SearchResultType.activity,
      id: 2,
      title: '脱口秀之夜',
      detail: '某剧场',
    ),
    SearchResultRow(
      type: SearchResultType.club,
      id: 3,
      title: '城市夜骑俱乐部',
      detail: '城市俱乐部',
    ),
    SearchResultRow(
      type: SearchResultType.merchant,
      id: 4,
      title: '老王咖啡',
      detail: '合作商家',
      tags: const <String>['咖啡', '静安'],
    ),
  ],
  counts: <SearchResultType, int>{
    SearchResultType.topic: 1,
    SearchResultType.activity: 1,
    SearchResultType.club: 1,
    SearchResultType.merchant: 1,
  },
);

void main() {
  testWidgets('搜索结果页', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 820));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          searchResultsProvider.overrideWith((ref, arg) async => _bundle()),
        ].cast(),
        child: MaterialApp(
          theme: goldenTheme(),
          debugShowCheckedModeBanner: false,
          home: const SearchResultPage(keyword: '咖啡'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('商家 1'), findsOneWidget);
    expect(find.text('老王咖啡'), findsOneWidget);
    expect(find.text('咖啡'), findsNWidgets(2)); // 输入框 + 卡片标签
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_search_result.png'),
    );
  });

  testWidgets('城市节点地图筛选', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: goldenTheme(),
          debugShowCheckedModeBanner: false,
          // 半屏弹层在测试环境没有 Material 祖先:裸 `TextStyle`(family 为 null)
          // 会落到 flutter_test 的默认测试字族,中文渲染成方框 —— 与
          // golden_theme.dart 里 `withGoldenFont` 记的是同一个坑,那边修的是
          // Material 按钮的文字样式,这里补的是「默认字族」这一层。
          // 包一层**透明** Material(不改任何像素),让真实中文字形落地。
          builder: (BuildContext context, Widget? child) =>
              Material(color: Colors.transparent, child: child!),
          home: const CityNodeSearchPage(initialKeyword: '咖啡'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('search-map-filter')));
    await tester.pumpAndSettle();

    expect(find.text('商家发现'), findsNWidgets(2));
    expect(find.byKey(const Key('search-filter-merchant-tag')), findsOneWidget);
    expect(
      find.byKey(const Key('search-filter-merchant-city-role')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_city_node_search_filter.png'),
    );
  });
}
