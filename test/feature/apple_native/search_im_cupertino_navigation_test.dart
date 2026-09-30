import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_controller.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/search_page.dart';
import 'package:chengyin_app/feature/search/search_result_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('搜索、搜索结果与消息使用 Cupertino 原生导航容器', (WidgetTester tester) async {
    for (final Widget page in <Widget>[
      const SearchPage(),
      const SearchResultPage(keyword: '咖啡'),
      const ImListPage(),
    ]) {
      await _pump(tester, page);

      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    }
  });

  testWidgets('Cupertino 返回按钮恢复上一页，不改页面默认落点', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides().cast(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (BuildContext context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SearchResultPage(keyword: '咖啡'),
                    ),
                  ),
                  child: const Text('打开搜索结果'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开搜索结果'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);
    expect(find.text('搜索主题、活动、俱乐部、商家'), findsOneWidget);

    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(find.text('打开搜索结果'), findsOneWidget);

    await tester.tap(find.text('打开搜索结果'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(1, 420), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('打开搜索结果'), findsOneWidget);
  });

  testWidgets('200% Dynamic Type 下三页主内容可读且无溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final ({Widget page, String anchor}) testCase
        in <({Widget page, String anchor})>[
          (page: const SearchPage(), anchor: '搜索'),
          (
            page: const SearchResultPage(keyword: '咖啡'),
            anchor: '搜索主题、活动、俱乐部、商家',
          ),
          (page: const ImListPage(), anchor: '消息'),
        ]) {
      await _pump(
        tester,
        testCase.page,
        textScaler: const TextScaler.linear(2),
      );
      expect(
        tester.getTopLeft(find.text(testCase.anchor).first).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(CupertinoNavigationBar)).dy,
        ),
        reason: '${testCase.anchor} 不能被原生导航栏遮住',
      );
      expect(tester.takeException(), isNull, reason: testCase.anchor);
    }
  });

  testWidgets('搜索页发现商家入口保留 44pt 热区与 VoiceOver 名称', (WidgetTester tester) async {
    await _pump(tester, const SearchPage());
    final SemanticsHandle semantics = tester.ensureSemantics();

    final Finder action = find.byKey(const Key('search-discover-merchants'));
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('发现商家'), findsOneWidget);
    semantics.dispose();
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: _overrides().cast(),
      child: MaterialApp(
        home: page,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<dynamic> _overrides() => <dynamic>[
  searchCategoriesProvider.overrideWith((ref) async => <Category>[]),
  searchResultsProvider.overrideWith(
    (ref, query) async => const SearchResultBundle(
      rows: <SearchResultRow>[],
      counts: <SearchResultType, int>{},
    ),
  ),
  imConversationsProvider.overrideWith((ref) async => <Conversation>[]),
];
