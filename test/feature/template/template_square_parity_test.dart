import 'dart:ui' as ui;

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/api/template_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/data/models/topic_template.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/publish/publish_capability.dart';
import 'package:chengyin_app/feature/template/template_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePublishApi implements PublishApi {
  _FakePublishApi(this.rows, {this.home});

  final List<PublishTemplate> rows;
  final PublishTemplateHomeData? home;

  @override
  Future<List<PublishTemplate>> templateHomeData() async => rows;

  @override
  Future<PublishTemplateHomeData> templateHomeSections() async =>
      home ??
      PublishTemplateHomeData(
        total: rows.length,
        categories: const <Category>[],
        banner: rows,
        latest: const <PublishTemplate>[],
        recommended: const <PublishTemplate>[],
        mustPlay: const <PublishTemplate>[],
        hot: const <PublishTemplate>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTemplateApi implements TemplateApi {
  _FakeTemplateApi(this.rows);

  final List<PlayTemplate> rows;
  int? lastCategoryId;
  int? lastPackType;

  @override
  Future<List<PlayTemplate>> list({
    String? keyword,
    int? categoryId,
    int? packType,
  }) async {
    lastCategoryId = categoryId;
    lastPackType = packType;
    return rows;
  }

  /// 「主题」tab 的货架接口。页面首屏落在主题 tab(真源 `data.tab='topic'`),
  /// 凡 pump TemplateListPage 的用例都要喂它一口:不喂就会打真网络,骨架屏不落。
  @override
  Future<List<TopicTemplate>> topicTemplateList() async =>
      const <TopicTemplate>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryApi implements CategoryApi {
  _FakeCategoryApi(this.rows);

  final List<Category> rows;

  @override
  Future<List<Category>> list({String? type}) async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedAuth extends AuthController {
  _FixedAuth(this.value);

  final AuthState value;

  @override
  AuthState build() => value;
}

/// 把页面从首屏的「主题」tab 切到「游戏」tab(广场五段在这后面)。
Future<void> _switchToGameTab(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('template-tabs')),
      matching: find.text('游戏'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('通知图标在 VoiceOver 中是唯一、有名称且可点的按钮', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    var inboxTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateSquareView(
          avatarUrl: '',
          total: 0,
          banner: const <PlayTemplate>[],
          latest: const <PlayTemplate>[],
          recommended: const <PlayTemplate>[],
          mustPlay: const <PlayTemplate>[],
          hot: const <PlayTemplate>[],
          categories: const <Category>[],
          selectedCategoryId: null,
          selectedPackType: null,  // 形态筛选:null = 全部形态
          onProfileTap: () {},
          onInboxTap: () => inboxTaps += 1,
          onSearchTap: () {},
          onCategorySelected: (_) {},
          onPackTypeSelected: (int? _) {},
          onTemplateTap: (_) {},
          onPublish: () {},
        ),
      ),
    );

    final Finder action = find.bySemanticsLabel('通知');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    await tester.tap(action);
    expect(inboxTaps, 1);
    semantics.dispose();
  });

  final List<PlayTemplate> rows = <PlayTemplate>[
    const PlayTemplate(
      id: 1,
      title: '街角密码',
      description: '玩家沿街寻找旧招牌、门牌与公共艺术',
      players: '2-6',
      duration: 45,
      categoryId: 11,
    ),
    const PlayTemplate(
      id: 2,
      title: '城市暗号',
      players: '3-8',
      duration: 55,
      categoryId: 12,
    ),
  ];
  final List<Category> categories = <Category>[
    Category(id: 11, name: '城市探索', type: 4),
    Category(id: 12, name: '解谜互动', type: 4),
  ];

  test('homeData 保留五段独立列表，不合并冒充推荐段', () {
    final PublishTemplateHomeData data = PublishTemplateHomeData.fromJson(
      <String, dynamic>{
        'total': 5,
        'categoryList': <Map<String, dynamic>>[
          <String, dynamic>{'id': 11, 'categoryName': '城市探索'},
        ],
        'bannerList': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'title': '主题推荐'},
        ],
        'latestList': <Map<String, dynamic>>[
          <String, dynamic>{'id': 2, 'title': '最新主题'},
        ],
        'recommendList': <Map<String, dynamic>>[
          <String, dynamic>{'id': 3, 'title': '推荐交互模板'},
        ],
        'mustPlayList': <Map<String, dynamic>>[
          <String, dynamic>{'id': 4, 'title': '交互模板精选'},
        ],
        'hotList': <Map<String, dynamic>>[
          <String, dynamic>{'id': 5, 'title': '热门节点榜'},
        ],
      },
    );

    expect(data.total, 5);
    expect(data.categories.single.name, '城市探索');
    expect(data.banner.single.title, '主题推荐');
    expect(data.latest.single.title, '最新主题');
    expect(data.recommended.single.title, '推荐交互模板');
    expect(data.mustPlay.single.title, '交互模板精选');
    expect(data.hot.single.title, '热门节点榜');
  });

  test('默认广场从 homeData 独立段保持推荐与最新顺序', () async {
    PublishTemplate row(int id, String title) => PublishTemplate(
      id: id,
      title: title,
      imgUrl: '',
      players: '--',
      duration: 0,
      raw: <String, dynamic>{},
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[
        publishApiProvider.overrideWithValue(
          _FakePublishApi(
            const <PublishTemplate>[],
            home: PublishTemplateHomeData(
              total: 2,
              categories: const <Category>[],
              banner: const <PublishTemplate>[],
              latest: <PublishTemplate>[row(10, '最新第一')],
              recommended: <PublishTemplate>[row(9, '推荐第一')],
              mustPlay: const <PublishTemplate>[],
              hot: const <PublishTemplate>[],
            ),
          ),
        ),
        templateApiProvider.overrideWithValue(
          _FakeTemplateApi(const <PlayTemplate>[]),
        ),
      ].cast(),
    );
    addTearDown(container.dispose);

    final TemplateSquareData data = await container.read(
      templateSquareProvider(const TemplateSquareQuery()).future,
    );

    expect(data.recommended.map((PlayTemplate row) => row.title), <String>[
      '推荐第一',
    ]);
    expect(data.latest.map((PlayTemplate row) => row.title), <String>['最新第一']);
  });

  test('默认广场把 homeData 五段逐段交给页面', () async {
    PublishTemplate row(int id, String title) => PublishTemplate(
      id: id,
      title: title,
      imgUrl: '',
      players: '--',
      duration: 0,
      raw: <String, dynamic>{},
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[
        publishApiProvider.overrideWithValue(
          _FakePublishApi(
            const <PublishTemplate>[],
            home: PublishTemplateHomeData(
              total: 5,
              categories: categories,
              banner: <PublishTemplate>[row(1, '主题推荐')],
              latest: <PublishTemplate>[row(2, '最新主题')],
              recommended: <PublishTemplate>[row(3, '推荐交互模板')],
              mustPlay: <PublishTemplate>[row(4, '交互模板精选')],
              hot: <PublishTemplate>[row(5, '热门节点榜')],
            ),
          ),
        ),
        templateApiProvider.overrideWithValue(
          _FakeTemplateApi(const <PlayTemplate>[]),
        ),
      ].cast(),
    );
    addTearDown(container.dispose);

    final TemplateSquareData data = await container.read(
      templateSquareProvider(const TemplateSquareQuery()).future,
    );

    expect(data.total, 5);
    expect(data.categories.map((Category row) => row.name), <String>[
      '城市探索',
      '解谜互动',
    ]);
    expect(data.banner.single.title, '主题推荐');
    expect(data.latest.single.title, '最新主题');
    expect(data.recommended.single.title, '推荐交互模板');
    expect(data.mustPlay.single.title, '交互模板精选');
    expect(data.hot.single.title, '热门节点榜');
  });

  test('分类请求携带 categoryId 并重载五段', () async {
    final _FakeTemplateApi templateApi = _FakeTemplateApi(rows);
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[
        templateApiProvider.overrideWithValue(templateApi),
        categoryApiProvider.overrideWithValue(_FakeCategoryApi(categories)),
      ].cast(),
    );
    addTearDown(container.dispose);

    final TemplateSquareData data = await container.read(
      templateSquareProvider(const TemplateSquareQuery(categoryId: 11)).future,
    );

    expect(templateApi.lastCategoryId, 11);
    expect(data.banner.length, 2);
    expect(data.latest.length, 2);
    expect(data.recommended.length, 2);
    expect(data.mustPlay.length, 2);
    expect(data.hot.length, 2);
  });

  testWidgets('模板广场保留头部入口与小程序五段顺序', (WidgetTester tester) async {
    var searchTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateSquareView(
          avatarUrl: '',
          total: 5,
          banner: <PlayTemplate>[const PlayTemplate(id: 21, title: '街角密码')],
          latest: <PlayTemplate>[rows.last],
          recommended: <PlayTemplate>[
            const PlayTemplate(id: 22, title: '相片定向'),
          ],
          mustPlay: <PlayTemplate>[const PlayTemplate(id: 23, title: '城市寻宝')],
          hot: <PlayTemplate>[const PlayTemplate(id: 24, title: '门牌猜谜')],
          categories: categories,
          selectedCategoryId: null,
          selectedPackType: null,  // 形态筛选:null = 全部形态
          onProfileTap: () {},
          onInboxTap: () {},
          onSearchTap: () => searchTaps += 1,
          onCategorySelected: (_) {},
          onPackTypeSelected: (int? _) {},
          onTemplateTap: (_) {},
          onPublish: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('template-profile-target')), findsOneWidget);
    expect(find.byKey(const Key('template-inbox-target')), findsOneWidget);
    expect(find.text('搜索节点玩法与主题'), findsOneWidget);
    await tester.tap(find.byKey(const Key('template-search-target')));
    expect(searchTaps, 1, reason: '搜索框点击目标是独立搜索页，不在广场内改写语义');
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('城市探索'), findsOneWidget);
    expect(find.text('解谜互动'), findsOneWidget);
    expect(find.text('主题推荐'), findsOneWidget);
    expect(find.text('街角密码'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('最新主题'),
      CyTokens.space8 * 4,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('template-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('最新主题'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('城市暗号'),
      CyTokens.space8 * 2,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('template-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('城市暗号'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('推荐交互模板'),
      CyTokens.space8 * 4,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('template-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('推荐交互模板'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('交互模板精选'),
      CyTokens.space8 * 4,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('template-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('交互模板精选'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('热门节点榜'),
      CyTokens.space8 * 4,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('template-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('热门节点榜'), findsOneWidget);
    expect(find.text('5个'), findsOneWidget);
    expect(find.text('2个'), findsOneWidget);
    expect(find.byKey(const Key('template-publish-fab')), findsOneWidget);
  });

  testWidgets('发布入口保留在 Liquid Glass Tab Bar 上方', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateSquareView(
          avatarUrl: '',
          total: 0,
          banner: const <PlayTemplate>[],
          latest: const <PlayTemplate>[],
          recommended: const <PlayTemplate>[],
          mustPlay: const <PlayTemplate>[],
          hot: const <PlayTemplate>[],
          categories: categories,
          selectedCategoryId: null,
          selectedPackType: null,  // 形态筛选:null = 全部形态
          onProfileTap: () {},
          onInboxTap: () {},
          onSearchTap: () {},
          onCategorySelected: (_) {},
          onPackTypeSelected: (int? _) {},
          onTemplateTap: (_) {},
          onPublish: () {},
        ),
      ),
    );

    final Rect publishRect = tester.getRect(
      find.byKey(const Key('template-publish-fab')),
    );
    expect(publishRect.bottom, lessThanOrEqualTo(744));
    expect(publishRect.width, greaterThanOrEqualTo(112));
  });

  testWidgets('模板卡先打开 Apple 预览 Sheet，查看此模板才进详情', (WidgetTester tester) async {
    final List<int> opened = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateSquareView(
          avatarUrl: '',
          total: 1,
          banner: const <PlayTemplate>[
            PlayTemplate(
              id: 31,
              title: '街角密码',
              description: '玩家沿街寻找旧招牌',
              players: '2-6',
              duration: 45,
              requiredMaterials: '手机、纸笔',
              usageLocation: '历史街区',
            ),
          ],
          latest: const <PlayTemplate>[],
          recommended: const <PlayTemplate>[],
          mustPlay: const <PlayTemplate>[],
          hot: const <PlayTemplate>[],
          categories: categories,
          selectedCategoryId: null,
          selectedPackType: null,  // 形态筛选:null = 全部形态
          onProfileTap: () {},
          onInboxTap: () {},
          onSearchTap: () {},
          onCategorySelected: (_) {},
          onPackTypeSelected: (int? _) {},
          onTemplateTap: opened.add,
          onPublish: () {},
        ),
      ),
    );

    await tester.tap(find.text('街角密码'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.byKey(const Key('template-preview-sheet')), findsOneWidget);
    expect(find.text('游戏简介'), findsOneWidget);
    expect(find.text('所需材料'), findsOneWidget);
    expect(find.text('推荐场景'), findsOneWidget);

    await tester.tap(find.byKey(const Key('template-preview-open-detail')));
    await tester.pumpAndSettle();

    expect(opened, <int>[31]);
  });

  testWidgets('分类点击以 categoryId 重载全部区块，游客发布先要求登录', (WidgetTester tester) async {
    final List<TemplateSquareQuery> queries = <TemplateSquareQuery>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          templateSquareProvider.overrideWith((_, TemplateSquareQuery query) {
            queries.add(query);
            return Future<TemplateSquareData>.value(
              TemplateSquareData(
                categories: categories,
                recommended: <PlayTemplate>[rows.first],
                latest: <PlayTemplate>[rows.last],
              ),
            );
          }),
          publishCapabilityProvider.overrideWith(
            (_) async => const PublishCapability(),
          ),
          // 首屏是「主题」tab,它的货架接口与品类接口都要喂假数据 ——
          // 否则真网络请求在测试里永远不落,骨架屏把 pumpAndSettle 拖到超时。
          templateApiProvider.overrideWithValue(
            _FakeTemplateApi(const <PlayTemplate>[]),
          ),
          publishApiProvider.overrideWithValue(
            _FakePublishApi(const <PublishTemplate>[]),
          ),
        ],
        child: const MaterialApp(home: TemplateListPage()),
      ),
    );
    await tester.pumpAndSettle();
    // 广场内容在「游戏」tab 后面(真源 index.js:56 默认 tab='topic'),先切过去。
    await _switchToGameTab(tester);

    await tester.tap(find.byKey(const Key('template-category-11')));
    await tester.pumpAndSettle();
    expect(queries.last.categoryId, 11);

    await tester.tap(find.byKey(const Key('template-publish-fab')));
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
    expect(find.byKey(const Key('publish-card-cta-一条城市路线')), findsNothing);
    expect(find.byKey(const Key('template-editor')), findsNothing);
  });

  testWidgets('已登录用户点发布才打开既有 chooser', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FixedAuth(
              AuthState(
                initialized: true,
                user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
              ),
            ),
          ),
          templateSquareProvider.overrideWith((_, TemplateSquareQuery query) {
            return Future<TemplateSquareData>.value(
              TemplateSquareData(
                categories: categories,
                banner: <PlayTemplate>[rows.first],
                recommended: const <PlayTemplate>[],
                latest: <PlayTemplate>[rows.last],
              ),
            );
          }),
          publishCapabilityProvider.overrideWith(
            (_) async => const PublishCapability(),
          ),
          templateApiProvider.overrideWithValue(
            _FakeTemplateApi(const <PlayTemplate>[]),
          ),
          publishApiProvider.overrideWithValue(
            _FakePublishApi(const <PublishTemplate>[]),
          ),
        ],
        child: const MaterialApp(home: TemplateListPage()),
      ),
    );
    await tester.pumpAndSettle();
    await _switchToGameTab(tester);

    await tester.tap(find.byKey(const Key('template-publish-fab')));
    await tester.pumpAndSettle();

    expect(find.text('登录城瘾'), findsNothing);
    expect(find.byKey(const Key('publish-card-cta-一条城市路线')), findsOneWidget);
    expect(find.byKey(const Key('template-editor')), findsNothing);
  });
}
