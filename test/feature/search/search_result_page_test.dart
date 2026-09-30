// 搜索结果独立页:四类 tabs 带计数、结果卡片、空态、商家不可打开提示。
// 对齐小程序 pages/search2/result。

import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/merchant.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:dio/dio.dart';
import 'package:chengyin_app/feature/search/search_result_page.dart';

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
      type: SearchResultType.activity,
      id: 3,
      title: '夜跑局',
      detail: '滨江',
    ),
    SearchResultRow(
      type: SearchResultType.merchant,
      id: 4,
      title: '老王咖啡',
      detail: '合作商家',
    ),
  ],
  counts: <SearchResultType, int>{
    SearchResultType.topic: 1,
    SearchResultType.activity: 2,
    SearchResultType.club: 0,
    SearchResultType.merchant: 1,
  },
);

Future<void> pumpResult(
  WidgetTester tester, {
  SearchResultBundle Function()? bundle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        searchResultsProvider.overrideWith(
          (ref, arg) async => bundle?.call() ?? _bundle(),
        ),
      ].cast(),
      child: const MaterialApp(home: SearchResultPage(keyword: '测试')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('四类 tabs 带计数(全部 + 主题/活动/俱乐部/商家)', (WidgetTester tester) async {
    await pumpResult(tester);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('主题 1'), findsOneWidget);
    expect(find.text('活动 2'), findsOneWidget);
    expect(find.text('俱乐部 0'), findsOneWidget);
    expect(find.text('商家 1'), findsOneWidget);
  });

  testWidgets('结果卡片渲染类型标签/标题/摘要', (WidgetTester tester) async {
    await pumpResult(tester);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('静安微旅行'), findsOneWidget);
    expect(find.text('城市主题'), findsOneWidget);
    expect(find.text('脱口秀之夜'), findsOneWidget);
    // 主题走海报卡(更高),商家卡要滚到才可见。
    await tester.scrollUntilVisible(
      find.text('老王咖啡'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('老王咖啡'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('主题 静安微旅行'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('点类型 tab 只留该类型结果', (WidgetTester tester) async {
    await pumpResult(tester);
    await tester.tap(find.text('活动 2'));
    await tester.pumpAndSettle();
    expect(find.text('脱口秀之夜'), findsOneWidget);
    expect(find.text('夜跑局'), findsOneWidget);
    expect(find.text('静安微旅行'), findsNothing);
    expect(find.text('老王咖啡'), findsNothing);
  });

  testWidgets('商家结果无主页 → 提示暂不可打开', (WidgetTester tester) async {
    await pumpResult(tester);
    await tester.scrollUntilVisible(
      find.text('老王咖啡'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('老王咖啡'));
    await tester.pump();
    expect(find.text('这条结果暂不可打开'), findsOneWidget);
  });

  testWidgets('空结果 → 空态文案', (WidgetTester tester) async {
    await pumpResult(
      tester,
      bundle: () =>
          const SearchResultBundle(rows: <SearchResultRow>[], counts: {}),
    );
    expect(find.text('没有找到匹配内容'), findsOneWidget);
    expect(find.text('换个关键词，或看看地图附近有什么'), findsOneWidget);
  });

  testWidgets('有源因未登录被跳过 → 顶部说明原因并给去登录', (WidgetTester tester) async {
    await pumpResult(
      tester,
      bundle: () => SearchResultBundle(
        rows: <SearchResultRow>[
          SearchResultRow(
            type: SearchResultType.topic,
            id: 1,
            title: '静安微旅行',
            detail: '城市主题',
          ),
        ],
        counts: <SearchResultType, int>{SearchResultType.topic: 1},
        loginGated: true,
      ),
    );

    expect(find.text('登录后能搜到更多结果'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('静安微旅行'), findsOneWidget);
  });

  testWidgets('没有源被跳过时不出现登录提示', (WidgetTester tester) async {
    await pumpResult(tester);
    expect(find.text('登录后能搜到更多结果'), findsNothing);
  });

  test('俱乐部源要登录(401)不哑掉整页:其余三源照常出结果', () async {
    final container = ProviderContainer(
      overrides: <dynamic>[
        topicApiProvider.overrideWithValue(_TopicsApi()),
        activityApiProvider.overrideWithValue(_ActivitiesApi()),
        clubApiProvider.overrideWithValue(_UnauthorizedClubApi()),
        merchantApiProvider.overrideWithValue(_MerchantsApi()),
      ].cast(),
    );
    addTearDown(container.dispose);

    final bundle = await _search(container);

    expect(bundle.loginGated, isTrue);
    expect(
      bundle.rows.map((SearchResultRow r) => r.type),
      containsAll(<SearchResultType>[
        SearchResultType.topic,
        SearchResultType.activity,
        SearchResultType.merchant,
      ]),
      reason: '游客搜「咖啡」不该整页失败 —— 坏的只是俱乐部这一源',
    );
    expect(
      bundle.rows.any((SearchResultRow r) => r.type == SearchResultType.club),
      isFalse,
    );
  });

  test('真故障(500)不被登录门槛吞掉', () async {
    final container = ProviderContainer(
      overrides: <dynamic>[
        topicApiProvider.overrideWithValue(_TopicsApi()),
        activityApiProvider.overrideWithValue(_ActivitiesApi()),
        clubApiProvider.overrideWithValue(_ServerErrorClubApi()),
        merchantApiProvider.overrideWithValue(_MerchantsApi()),
      ].cast(),
    );
    addTearDown(container.dispose);

    // 真故障不能被登录门槛吞掉:它进 failedTypes(页面按逐路失败报错/提示),
    // 而不是被软化成「要登录」的空结果。
    const SearchQuery query = SearchQuery(keyword: '咖啡');
    final subscription = container.listen(
      searchResultsProvider(query),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await pumpEventQueue();

    final bundle = await container.read(searchResultsProvider(query).future);
    expect(bundle.failedTypes, <SearchResultType>[SearchResultType.club]);
    expect(bundle.loginGated, isFalse);
    expect(bundle.hasFailure, isTrue);
  });
}

/// autoDispose 的 family 只 read 不 listen 会在 loading 期被回收,
/// 所以先挂一个订阅再取 future。
Future<SearchResultBundle> _search(ProviderContainer container) {
  const SearchQuery query = SearchQuery(keyword: '咖啡');
  final subscription = container.listen(
    searchResultsProvider(query),
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container.read(searchResultsProvider(query).future);
}

DioException _dioError(int statusCode) {
  final RequestOptions options = RequestOptions(path: '/api/club/list');
  return DioException(
    requestOptions: options,
    response: Response<Object?>(
      requestOptions: options,
      statusCode: statusCode,
    ),
    type: DioExceptionType.badResponse,
  );
}

class _TopicsApi implements TopicApi {
  @override
  Future<List<Topic>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    bool recommend = false,
    int pageNum = 1,
    int pageSize = 10,
  }) async => <Topic>[Topic(id: 1, name: '静安微旅行')];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ActivitiesApi implements ActivityApi {
  @override
  Future<List<Activity>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    String? sortType,
    String? longitude,
    String? latitude,
    double? minPrice,
    double? maxPrice,
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 10,
  }) async => <Activity>[Activity(id: 2, name: '脱口秀之夜')];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MerchantsApi implements MerchantApi {
  @override
  Future<List<Merchant>> searchByName(String name) async => <Merchant>[
    Merchant(id: 4, name: '老王咖啡'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnauthorizedClubApi implements ClubApi {
  @override
  Future<List<Club>> searchByName(String name) async => throw _dioError(401);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ServerErrorClubApi implements ClubApi {
  @override
  Future<List<Club>> searchByName(String name) async => throw _dioError(500);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
