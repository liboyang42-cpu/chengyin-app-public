// 搜索索引页:八大热搜词、搜索历史(本地)、零类别隐藏、地图入口。
// 对齐小程序 pages/search2/index。

import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/search_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  Future<void> pumpSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          // 无类别:验证「类别没有就不显示」的隐藏分支。
          searchCategoriesProvider.overrideWith((ref) async => <Category>[]),
        ].cast(),
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('八大热搜词逐字对齐小程序 hotkeys', (WidgetTester tester) async {
    await pumpSearch(tester);
    expect(find.text('猜你想搜'), findsOneWidget);
    for (final String word in <String>[
      '交友',
      '盗墓笔记',
      '旅游',
      '美食',
      '运动',
      '读书',
      '电影',
      '音乐',
    ]) {
      expect(find.text(word), findsOneWidget, reason: '热搜词 $word 缺失');
    }
  });

  testWidgets('输入框占位符对齐小程序', (WidgetTester tester) async {
    await pumpSearch(tester);
    expect(find.text('搜索主题、活动、俱乐部、商家'), findsOneWidget);
  });

  testWidgets('零类别时整个类别块隐藏(不显示空态占位)', (WidgetTester tester) async {
    await pumpSearch(tester);
    expect(find.text('类别'), findsNothing, reason: '零类别不该出现类别标题');
  });

  testWidgets('类别加载失败时「类别」标题常驻,错误挂在标题下方', (WidgetTester tester) async {
    // 小程序 .type-list wx:if 包住整块:加载/错误时标题在,只有零类别才隐藏。
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          searchCategoriesProvider.overrideWith(
            (ref) async => throw Exception('boom'),
          ),
        ].cast(),
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('类别'), findsOneWidget);
    expect(find.text('类别没能加载出来'), findsOneWidget);
  });

  testWidgets('本地历史渲染 + 清空', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'search2_history': '["读书","盗墓笔记"]',
    });
    await pumpSearch(tester);
    expect(find.text('搜索历史'), findsOneWidget);
    // 读书/盗墓笔记 同时出现在热搜词里,历史存在时应各有两份。
    expect(find.text('读书'), findsNWidgets(2));
    expect(find.text('盗墓笔记'), findsNWidgets(2));
    expect(find.text('清空'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('搜索历史'), findsNothing);
    expect(find.text('读书'), findsOneWidget, reason: '清空后只剩热搜词');
  });

  testWidgets('无历史时历史区块不渲染', (WidgetTester tester) async {
    await pumpSearch(tester);
    expect(find.text('搜索历史'), findsNothing);
    expect(find.text('清空'), findsNothing);
  });

  testWidgets('地图入口按钮进入城市节点搜索', (WidgetTester tester) async {
    await pumpSearch(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('在地图上搜城市节点'), findsOneWidget);
  });

  testWidgets('筛选按钮存在', (WidgetTester tester) async {
    await pumpSearch(tester);
    expect(find.text('筛选'), findsOneWidget);
  });

  testWidgets('类别 VoiceOver 节点可真正激活', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          searchCategoriesProvider.overrideWith(
            (ref) async => <Category>[Category(id: 7, name: '城市漫游', type: 1)],
          ),
        ].cast(),
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.text('城市漫游'));
    expect(node.label, '城市漫游');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('★★ 本地历史读不出来:说得出发生了什么 + 重试可恢复', (WidgetTester tester) async {
    final _FlakyHistoryStore store = _FlakyHistoryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          searchCategoriesProvider.overrideWith((ref) async => <Category>[]),
          searchHistoryStoreProvider.overrideWithValue(store),
        ].cast(),
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 历史读失败 ≠ 没有历史:原先这里裸抛,历史区直接消失。
    expect(find.text('历史没能读出来'), findsOneWidget);
    expect(find.byKey(const Key('search-history-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-history-retry')));
    await tester.pumpAndSettle();

    expect(store.reads, 2);
    expect(find.text('历史没能读出来'), findsNothing);
    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('读书'), findsNWidgets(2), reason: '历史回来了:热搜 + 历史各一份');
  });
}

/// 第一次读失败、之后成功:验证页面对本地读取失败也有出路。
class _FlakyHistoryStore extends SearchHistoryStore {
  _FlakyHistoryStore() : super(const FlutterSecureStorage());

  int reads = 0;

  @override
  Future<List<String>> read() async {
    reads += 1;
    if (reads == 1) throw Exception('存储暂时读不出来');
    return <String>['读书'];
  }
}
