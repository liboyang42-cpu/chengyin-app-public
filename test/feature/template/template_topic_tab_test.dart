// `pages/template/index` 「主题」tab(主题模板货架)对齐测试。
//
// ★ 口径来源 = 小程序 master@90e66d70 `pages/template/index.js`:
//   · tab 状态机 `switchTab` :444-468 / `getGameRows` :520-560 /
//     `getTopicTemplates` :601-650 —— success / fail / complete 三处都是
//     **seq + tab 双闸**。那边的契约测试 `tests/unit/template-tab-failure-state-contract
//     .test.js` 把这条钉死了,本文件的 1-3 组是同一批语义的 App 版。
//   · 文案与置顶排序 `rebuildLists` :407-431;
//   · 装饰 `decorateTopic` :355-372 / `hitCategory` :395。
// ★ 负控纪律:每条「迟到响应不许画到别的 tab 上」的断言,都在**同一个用例**里
//   配一条「tab 对得上时它确实画出来了」——否则断言可能只是恒真。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/api/template_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/data/models/topic_template.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/template/template_list_page.dart';

const TopicTemplate topicA = TopicTemplate(
  id: 31,
  name: '生活不掉线',
  subtitle: '30 天找回节奏',
  chapterCount: 4,
  locationCount: 9,
  totalTime: '120分钟',
  categoryIds: '7',
  templateStatus: 'VERIFIED',
);
const TopicTemplate topicB = TopicTemplate(
  id: 32,
  name: '城市夜行',
  chapterCount: 2,
  categoryIds: '8',
  templateStatus: 'VERIFIED',
);
const TopicTemplate topicPreview = TopicTemplate(
  id: 33,
  name: '实验整包',
  previewOnly: true,
);

final List<Category> categories = <Category>[
  Category(id: 7, name: '生活备份'),
  Category(id: 8, name: '夜间路线'),
];

/// 主题货架接口的假实现。`gate` 用来把响应**卡在途中**(迟到场景)。
class _FakeTemplateApi implements TemplateApi {
  _FakeTemplateApi({this.topicRows = const <TopicTemplate>[]});

  List<TopicTemplate> topicRows;
  Completer<List<TopicTemplate>>? gate;
  Object? failure;
  int topicCalls = 0;

  @override
  Future<List<TopicTemplate>> topicTemplateList() {
    topicCalls += 1;
    if (failure case final Object error) return Future<List<TopicTemplate>>.error(error);
    return gate?.future ?? Future<List<TopicTemplate>>.value(topicRows);
  }

  @override
  Future<List<PlayTemplate>> list({
    String? keyword,
    int? categoryId,
    int? packType,
  }) async => const <PlayTemplate>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryApi implements CategoryApi {
  @override
  Future<List<Category>> list({String? type}) async => categories;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePublishApi implements PublishApi {
  @override
  Future<PublishTemplateHomeData> templateHomeSections() async =>
      PublishTemplateHomeData(
        total: 0,
        categories: categories,
        banner: <PublishTemplate>[],
        latest: <PublishTemplate>[],
        recommended: <PublishTemplate>[],
        mustPlay: <PublishTemplate>[],
        hot: <PublishTemplate>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSquareApi implements SquareApi {
  final List<int> used = <int>[];
  Completer<int>? gate;
  Object? failure;

  @override
  Future<int> remixTopicTemplate(int topicId) {
    used.add(topicId);
    if (failure case final Object error) return Future<int>.error(error);
    return gate?.future ?? Future<int>.value(9302);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedAuth extends AuthController {
  _FixedAuth(this.value);

  final AuthState value;

  @override
  AuthState build() => value;
}

/// 「游戏」tab 的假数据(页面走 templateSquareProvider)。
TemplateSquareData _gameData(String title) => TemplateSquareData(
  categories: categories,
  banner: <PlayTemplate>[PlayTemplate(id: 41, title: title)],
  recommended: const <PlayTemplate>[],
  latest: const <PlayTemplate>[],
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakeTemplateApi templateApi,
  _FakeSquareApi? squareApi,
  List<TemplateSquareQuery>? gameQueries,
  Completer<TemplateSquareData>? gameGate,
  Object? gameFailure,
  String gameTitle = '街角密码',
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/template-square',
    routes: <RouteBase>[
      GoRoute(
        path: '/template-square',
        builder: (_, _) => const TemplateListPage(),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('我的')),
      ),
      GoRoute(path: '/im', builder: (_, _) => const Scaffold(body: Text('消息'))),
      GoRoute(
        path: '/search',
        builder: (_, _) => const Scaffold(body: Text('搜索')),
      ),
      GoRoute(
        path: '/template/:id',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('详情 ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/publish/pro',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('发布器 ${state.uri.queryParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // ★ 关掉 Riverpod 3 的自动重试:默认策略会给失败的元素排 10 次指数退避,
      //   本文件要观测的正是「失败发生了几次」与「失败有没有进缓存」——
      //   留着默认重试,一次失败会变成 11 次请求,判据不再可观测。
      //   (仓内既有约定:test/core/router 下的失败态用例同样写
      //   `retry: (int _, Object _) => null`。)
      retry: (int _, Object _) => null,
      overrides: [
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              initialized: true,
              user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
            ),
          ),
        ),
        templateApiProvider.overrideWithValue(templateApi),
        categoryApiProvider.overrideWithValue(_FakeCategoryApi()),
        publishApiProvider.overrideWithValue(_FakePublishApi()),
        squareApiProvider.overrideWithValue(squareApi ?? _FakeSquareApi()),
        templateSquareProvider.overrideWith((
          Ref ref,
          TemplateSquareQuery query,
        ) {
          gameQueries?.add(query);
          if (gameFailure case final Object error) {
            return Future<TemplateSquareData>.error(error);
          }
          return gameGate?.future ?? Future<TemplateSquareData>.value(_gameData(gameTitle));
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

Future<void> _switchTo(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byKey(const Key('template-tabs')),
    matching: find.text(label),
  ));
  await tester.pump();
}

void main() {
  group('tab 状态口径(seq + tab 双闸)', () {
    testWidgets('主题 tab 成功后切游戏 tab 请求失败:错误态可见,主题内容不得冒充游戏列表', (
      WidgetTester tester,
    ) async {
      final _FakeTemplateApi api = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      );
      await _pump(tester, templateApi: api, gameFailure: Exception('网络断开'));
      await tester.pumpAndSettle();
      expect(find.text('生活不掉线'), findsOneWidget, reason: '主题 tab 是首屏');

      await _switchTo(tester, '游戏');
      await tester.pumpAndSettle();

      expect(find.text('网络断开'), findsOneWidget, reason: '错误文案与重试必须可见');
      expect(find.text('重试'), findsOneWidget);
      expect(
        find.text('生活不掉线'),
        findsNothing,
        reason: '主题列表不得留在屏上冒充游戏 tab',
      );
    });

    testWidgets('失败后切回主题 tab:缓存内容即刻恢复,错误清空,且不再发请求', (
      WidgetTester tester,
    ) async {
      final _FakeTemplateApi api = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      );
      await _pump(tester, templateApi: api, gameFailure: Exception('网络断开'));
      await tester.pumpAndSettle();
      await _switchTo(tester, '游戏');
      await tester.pumpAndSettle();
      expect(find.text('网络断开'), findsOneWidget);

      await _switchTo(tester, '主题');
      await tester.pumpAndSettle();

      expect(find.text('生活不掉线'), findsOneWidget, reason: '已加载 tab 的缓存必须原样回来');
      expect(find.text('网络断开'), findsNothing, reason: '错误必须清空');
      expect(api.topicCalls, 1, reason: '回到已加载的 tab 不许重新拉一遍');
    });

    testWidgets('迟到的游戏响应落在主题 tab 上:只进缓存,不得把未加载的主题 tab 标成已加载', (
      WidgetTester tester,
    ) async {
      final _FakeTemplateApi topicApi = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      )..gate = Completer<List<TopicTemplate>>();
      final Completer<TemplateSquareData> gameGate =
          Completer<TemplateSquareData>();
      await _pump(tester, templateApi: topicApi, gameGate: gameGate);

      // 用户先切到游戏(请求在途),又切回主题(主题请求也在途)
      await _switchTo(tester, '游戏');
      await _switchTo(tester, '主题');
      expect(find.byType(CySkeleton), findsWidgets, reason: '主题还没回来:骨架屏');

      gameGate.complete(_gameData('街角密码'));
      await tester.pump();

      expect(
        find.text('街角密码'),
        findsNothing,
        reason: '游戏响应不得画到主题 tab 上',
      );
      expect(find.byType(CySkeleton), findsWidgets, reason: '主题仍在途,骨架屏不许被掐掉');
      expect(
        find.byKey(const Key('topic-empty')),
        findsNothing,
        reason: '游戏响应把主题标成已加载 → 空缓存会渲染成假空态',
      );

      topicApi.gate!.complete(<TopicTemplate>[topicA, topicB]);
      await tester.pumpAndSettle();
      expect(find.text('生活不掉线'), findsOneWidget);

      // 负控:同一个游戏响应,在 tab 对得上时必须真的画出来。
      await _switchTo(tester, '游戏');
      await tester.pumpAndSettle();
      expect(
        find.text('街角密码'),
        findsOneWidget,
        reason: '响应本身是好的 —— 上面找不到它只可能是被 tab 闸挡了',
      );
    });

    testWidgets('迟到的游戏失败落在主题 tab 上:错误不得画到主题的错误卡', (
      WidgetTester tester,
    ) async {
      final _FakeTemplateApi topicApi = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      )..gate = Completer<List<TopicTemplate>>();
      final Completer<TemplateSquareData> gameGate =
          Completer<TemplateSquareData>();
      await _pump(tester, templateApi: topicApi, gameGate: gameGate);

      await _switchTo(tester, '游戏');
      await _switchTo(tester, '主题');
      gameGate.completeError(Exception('玩法模板挂在了路上'));
      await tester.pump();

      expect(
        find.text('玩法模板挂在了路上'),
        findsNothing,
        reason: '游戏的失败文案不许画在主题的错误卡上',
      );
      expect(find.byType(CySkeleton), findsWidgets, reason: '主题在途的骨架屏不许被掐掉');

      topicApi.gate!.complete(<TopicTemplate>[topicA]);
      await tester.pumpAndSettle();
      expect(find.text('生活不掉线'), findsOneWidget);

      // 负控:同样的失败,在游戏 tab 上必须画出来(否则上面的 findsNothing 是恒真)。
      await _switchTo(tester, '游戏');
      await tester.pumpAndSettle();
      expect(find.text('玩法模板挂在了路上'), findsOneWidget);
    });

    testWidgets('游戏 tab 失败后切回:失败不进缓存,必须重新发一次请求', (WidgetTester tester) async {
      final List<TemplateSquareQuery> queries = <TemplateSquareQuery>[];
      final _FakeTemplateApi topicApi = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      );
      await _pump(
        tester,
        templateApi: topicApi,
        gameQueries: queries,
        gameFailure: Exception('网络断开'),
      );
      await tester.pumpAndSettle();
      await _switchTo(tester, '游戏');
      await tester.pumpAndSettle();
      expect(find.text('网络断开'), findsOneWidget);
      expect(queries, hasLength(1));

      await _switchTo(tester, '主题');
      await tester.pumpAndSettle();
      await _switchTo(tester, '游戏');
      await tester.pumpAndSettle();

      expect(
        queries,
        hasLength(2),
        reason: '真源失败时 _gameLoaded 保持 false —— 切回游戏 tab 要重新加载,不是回放旧错误',
      );
    });

    testWidgets('请求在途时切去已加载 tab:loading 由 switchTab 显式清掉', (WidgetTester tester) async {
      final _FakeTemplateApi api = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      );
      await _pump(tester, templateApi: api, gameGate: Completer<TemplateSquareData>());
      await tester.pumpAndSettle();

      await _switchTo(tester, '游戏');
      await _switchTo(tester, '主题');
      await tester.pump();

      expect(find.text('生活不掉线'), findsOneWidget);
      expect(
        find.byType(CySkeleton),
        findsNothing,
        reason: '游戏在途的 complete 只归游戏 tab 管,主题这边不许留着游离的 loading',
      );
    });
  });

  group('货架(rebuildLists 的排序、文案与四态)', () {
    testWidgets('无品类:第一条做 banner,标题是「推荐」「全部主题」', (WidgetTester tester) async {
      final _FakeTemplateApi api = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      );
      await _pump(tester, templateApi: api);
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(CySectionTitle, '推荐'),
        findsOneWidget,
        reason: '★ bannerTitle 叫「推荐」不叫「全部」(chips 行首项也叫「推荐」)',
      );
      expect(find.widgetWithText(CySectionTitle, '全部主题'), findsOneWidget);
      expect(find.byKey(const Key('topic-banner-card')), findsOneWidget);
      expect(find.text('生活不掉线'), findsOneWidget);
      expect(find.text('30 天找回节奏'), findsOneWidget);
      expect(find.text('4 章 · 9 个点 · 120分钟'), findsWidgets, reason: 'metaText 去重单位');
      expect(find.text('城市夜行'), findsOneWidget, reason: 'banner 之后进置顶列表');
      expect(find.text('实验模板'), findsNothing, reason: 'VERIFIED 不打实验标');
    });

    testWidgets('选中品类:纯前端重排,不发请求,标题带品类名与个数', (WidgetTester tester) async {
      final _FakeTemplateApi api = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA, topicB],
      );
      await _pump(tester, templateApi: api);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('topic-category-7')));
      await tester.pumpAndSettle();

      expect(api.topicCalls, 1, reason: '品类切换是前端重排,不许再打一次接口');
      expect(find.text('生活备份 · 精选'), findsOneWidget);
      expect(find.text('生活备份 · 1 个'), findsOneWidget);
      expect(
        find.text('城市夜行'),
        findsNothing,
        reason: '选中品类后只列命中项(真源 rebuildLists 的 topList=top, tailList=[])',
      );

      await tester.tap(find.byKey(const Key('topic-category-recommend')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CySectionTitle, '推荐'), findsOneWidget);
      expect(find.text('城市夜行'), findsOneWidget);
    });

    testWidgets('实验模板:非 VERIFIED 与预览分别打标', (WidgetTester tester) async {
      final _FakeTemplateApi api = _FakeTemplateApi(
        topicRows: const <TopicTemplate>[
          topicA,
          TopicTemplate(id: 51, name: '未验证整包'),
          topicPreview,
        ],
      );
      await _pump(tester, templateApi: api);
      await tester.pumpAndSettle();

      expect(find.text('实验模板'), findsOneWidget);
      expect(find.text('实验预览'), findsOneWidget);
    });

    testWidgets('单条数据:banner 吃掉唯一一条,不许同屏出现空态', (WidgetTester tester) async {
      final _FakeTemplateApi api = _FakeTemplateApi(
        topicRows: <TopicTemplate>[topicA],
      );
      await _pump(tester, templateApi: api);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('topic-banner-card')), findsOneWidget);
      expect(
        find.byKey(const Key('topic-empty')),
        findsNothing,
        reason: '★ 空态判定必须把 banner 计入(真源契约:单条时 banner 有值、两列表全空)',
      );
    });

    testWidgets('空货架:空态文案照真源,且给得了重试', (WidgetTester tester) async {
      final _FakeTemplateApi api = _FakeTemplateApi();
      await _pump(tester, templateApi: api);
      await tester.pumpAndSettle();

      expect(find.text('还没有可复用的主题模板'), findsOneWidget);
      expect(
        find.text('新的整包主题开放后会出现在这里,也可以先去「游戏」里挑单个玩法'),
        findsOneWidget,
      );
      expect(find.text('刷新试试'), findsOneWidget);
      expect(api.topicCalls, 1);
    });

    testWidgets('加载失败:后端原话 + 重试真的重新发请求', (WidgetTester tester) async {
      final _FakeTemplateApi api = _FakeTemplateApi()
        ..failure = Exception('主题模板加载失败');
      await _pump(tester, templateApi: api);
      await tester.pumpAndSettle();

      expect(find.text('主题模板加载失败'), findsOneWidget);
      expect(api.topicCalls, 1);

      api
        ..failure = null
        ..topicRows = <TopicTemplate>[topicA, topicB];
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(api.topicCalls, 2);
      expect(find.text('生活不掉线'), findsOneWidget);
    });
  });

  group('用模板(topic-template/use)', () {
    testWidgets('点主题卡:整包复制成功后进专业编辑器', (WidgetTester tester) async {
      final _FakeSquareApi square = _FakeSquareApi();
      await _pump(
        tester,
        templateApi: _FakeTemplateApi(topicRows: <TopicTemplate>[topicA, topicB]),
        squareApi: square,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('topic-row-32')));
      await tester.pumpAndSettle();

      expect(square.used, <int>[32], reason: '用模板走既有的 /use 写入链路');
      expect(find.text('发布器 9302'), findsOneWidget);
    });

    testWidgets('预览模板:直说不能配置,不打 /use', (WidgetTester tester) async {
      final _FakeSquareApi square = _FakeSquareApi();
      await _pump(
        tester,
        templateApi: _FakeTemplateApi(
          topicRows: const <TopicTemplate>[topicPreview, topicA],
        ),
        squareApi: square,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('topic-banner-card')));
      await tester.pump();

      expect(find.text('这是预览模板，落库后才能配置'), findsOneWidget);
      expect(square.used, isEmpty);
    });

    testWidgets('复制失败:后端原话提示,页面不跳走', (WidgetTester tester) async {
      final _FakeSquareApi square = _FakeSquareApi()
        ..failure = Exception('模板已停用');
      await _pump(
        tester,
        templateApi: _FakeTemplateApi(topicRows: <TopicTemplate>[topicA, topicB]),
        squareApi: square,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('topic-row-32')));
      await tester.pump();

      expect(find.text('模板已停用'), findsOneWidget);
      expect(find.text('发布器 9302'), findsNothing);
    });
  });
}
