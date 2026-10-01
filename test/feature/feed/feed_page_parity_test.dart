import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/banner.dart';
import 'package:chengyin_app/data/models/play_run_session.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/data/models/upcoming_activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/feed/feed_controller.dart';
import 'package:chengyin_app/feature/feed/feed_page.dart';
import 'package:chengyin_app/feature/feed/feed_sections_controller.dart';
import 'package:chengyin_app/feature/feed/recommendation.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/feature/feed/widgets/home_activity_live.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.value);

  final AuthState value;

  @override
  AuthState build() => value;
}

class _FixedFeed extends FeedNotifier {
  _FixedFeed(this.topics);

  final List<Topic> topics;

  @override
  Future<List<Topic>> build() async => topics;
}

class _HangingImageHttpClient implements HttpClient {
  final Completer<HttpClientRequest> request = Completer<HttpClientRequest>();

  @override
  Future<HttpClientRequest> getUrl(Uri url) => request.future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试假 HttpClient 不支持: $invocation');
}

List<dynamic> _overrides({
  List<MyRegistration> registrations = const [],
  List<PlayRunSession> playRuns = const <PlayRunSession>[],
  List<HomeBanner>? banners,
  bool sourceMarkers = false,
}) => <dynamic>[
  authControllerProvider.overrideWith(
    () => _FixedAuth(
      AuthState(
        user: User(id: 7, nickname: '阿兰', avatar: '', role: 'player'),
        initialized: true,
      ),
    ),
  ),
  feedBannerProvider.overrideWith(
    (ref) async =>
        banners ??
        <HomeBanner>[
          HomeBanner(id: 1, linkType: 4, dataId: '11'),
          HomeBanner(id: 2),
        ],
  ),
  feedNearbyProvider.overrideWith(
    (ref) async => <Activity>[
      Activity(id: 21, name: '外滩夜行', addressName: '外滩',
          startDate: sourceMarkers ? '2000-01-01 00:00:00' : null),
    ],
  ),
  feedRecommendProvider.overrideWith(
    (ref) async => <Topic>[Topic(id: 31, name: '城市夜跑', betaFlag: sourceMarkers ? 1 : 0)],
  ),
  feedUpcomingProvider.overrideWith(
    (ref) async => <UpcomingActivity>[
      UpcomingActivity(id: 41, name: '迷雾剧场', addressName: '静安'),
    ],
  ),
  feedActivityStreamProvider.overrideWith(
    (ref) async => <Activity>[
      Activity(
        id: 71,
        name: '周末城市漫游',
        minAmount: 128,
        startDate: '2025-06-14 22:00',
        addressName: '陆家嘴观景台',
      ),
    ],
  ),
  recommendedTopicsProvider.overrideWith(
    (ref) async => const <RecommendedTopic>[],
  ),
  myJoinedActivitiesProvider.overrideWith((ref) async => registrations),
  playRunSessionsProvider.overrideWith((ref) async => playRuns),
  feedProvider.overrideWith(
    () => _FixedFeed(<Topic>[
      Topic(
        id: 51,
        name: '街角密码',
        minAmount: 38,
        startDate: '2025-06-13 18:30',
        addressName: '静安寺商圈',
      ),
    ]),
  ),
];

Future<GoRouter> _pumpHome(
  WidgetTester tester, {
  List<MyRegistration> registrations = const [],
  List<PlayRunSession> playRuns = const <PlayRunSession>[],
  List<HomeBanner>? banners,
  Locale locale = const Locale('zh'),
  bool sourceMarkers = false,
  double width = 390,
  double height = 844,
  bool disableAnimations = false,
  bool highContrast = false,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  final router = GoRouter(
    initialLocation: '/feed',
    routes: <RouteBase>[
      GoRoute(path: '/feed', builder: (_, _) => const FeedPage()),
      GoRoute(
        path: '/topic/:id',
        builder: (_, state) => Text('topic:${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/activity/:id',
        builder: (_, state) => Text('activity:${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/tickets',
        builder: (_, state) => Text(
          'tickets:${state.uri.queryParameters['focusId']}:${state.uri.queryParameters['stype']}',
        ),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const Text('profile')),
      GoRoute(path: '/search', builder: (_, _) => const Text('search')),
      GoRoute(
        path: '/official-events',
        builder: (_, _) => const Text('官方活动列表'),
      ),
      GoRoute(
        path: '/play/:activityId',
        builder: (_, state) => Text(
          'play:${state.pathParameters['activityId']}:${state.uri.queryParameters['topicId']}',
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        registrations: registrations,
        playRuns: playRuns,
        banners: banners,
        sourceMarkers: sourceMarkers,
      ).cast(),
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(),
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            highContrast: highContrast,
            textScaler: textScaler,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  addTearDown(router.dispose);
  return router;
}

/// 列表是懒建的:大字号下靠后的区块(推荐主题插到最前后,附近活动更沉)
/// 不进缓存区就不存在,只能滚到脸上再断言。
Future<void> _scrollToSection(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.dragUntilVisible(
    target,
    find.byType(Scrollable).first,
    const Offset(0, -120),
  );
  await tester.pump();
  expect(target, findsOneWidget);
}

void main() {
  test('Home markers retain source beta flag and China-time start semantics', () {
    expect(Topic.fromJson({'id': 1, 'name': '', 'betaFlag': 1}).betaFlag, 1);
    expect(Topic.fromJson({'id': 1, 'name': ''}).betaFlag, 0);
    final boundary = DateTime.utc(2026, 9, 30, 2);
    expect(homeActivityStarted('2026-09-30 10:00:00', boundary), isTrue);
    expect(homeActivityStarted('2026-09-30T10:00:00+08:00', boundary), isTrue);
    expect(homeActivityStarted('2026-09-30 10:00:01', boundary), isFalse);
    expect(homeActivityStarted(null, boundary), isFalse);
    expect(homeActivityStarted('2026-02-30 10:00:00', boundary), isFalse);
    expect(homeActivityStarted('invalid', boundary), isFalse);
  });

  testWidgets('English Home at large text preserves UGC and source Beta/LIVE markers', (tester) async {
    await _pumpHome(tester, locale: const Locale('en'), sourceMarkers: true,
        textScaler: const TextScaler.linear(2), disableAnimations: true);
    expect(find.text('Hi, 阿兰!'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _scrollToSection(tester, const Key('home-recommend'));
    expect(find.text('Beta trial'), findsOneWidget);
    expect(find.text('城市夜跑'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _scrollToSection(tester, const Key('home-nearby'));
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('外滩夜行'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首页在 200% Dynamic Type 下保留 Hero 与关键入口', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester, textScaler: const TextScaler.linear(2));

    expect(tester.takeException(), isNull);
    expect(find.text('Hi, 阿兰!'), findsOneWidget);
    expect(find.byKey(const Key('home-avatar')), findsOneWidget);
    await _scrollToSection(tester, const Key('home-nearby'));
  });

  testWidgets('320x568、200% 字号与高对比度下首页关键入口不裁切', (WidgetTester tester) async {
    await _pumpHome(
      tester,
      width: 320,
      height: 568,
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
      highContrast: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Hi, 阿兰!'), findsOneWidget);
    expect(find.byKey(const Key('home-avatar')), findsOneWidget);
    // 搜索条入口加入后小屏 200% 下「附近活动」滚出首屏,lazy 列表要先滚到才在树里。
    await _scrollToSection(tester, const Key('home-nearby'));
    expect(
      tester.getSize(find.byKey(const Key('home-nearby'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('系统减少动态时 Hero 轮播指示不再执行过渡', (WidgetTester tester) async {
    await _pumpHome(tester, disableAnimations: true);

    final Iterable<AnimatedContainer> indicators = tester.widgetList(
      find.descendant(
        of: find.byKey(const Key('home-hero')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(indicators, isNotEmpty);
    expect(
      indicators.every(
        (AnimatedContainer indicator) => indicator.duration == Duration.zero,
      ),
      isTrue,
    );
  });

  testWidgets('远程 Hero 图片加载中保留可见占位,不出现大块黑屏', (WidgetTester tester) async {
    final _HangingImageHttpClient client = _HangingImageHttpClient();
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
      imageCache.clear();
      imageCache.clearLiveImages();
    });

    await _pumpHome(
      tester,
      banners: <HomeBanner>[
        HomeBanner(id: 1, picUrl: 'https://example.invalid/slow-hero.jpg'),
      ],
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('home-hero')),
        matching: find.byIcon(Icons.explore_outlined),
      ),
      findsOneWidget,
    );
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('首页按小程序顺序恢复 Hero 到主题流', (WidgetTester tester) async {
    final registration = MyRegistration.fromJson(<String, dynamic>{
      'id': 61,
      'ownerType': 2,
      'ownerId': 21,
      'registrationStatus': 2,
      'verificationStatus': 0,
      'cmsActivity': <String, dynamic>{'name': '继续外滩探索', 'addressName': '外滩源'},
    });
    await _pumpHome(tester, registrations: <MyRegistration>[registration]);

    expect(find.text('任务流'), findsNothing);
    expect(find.text('Hi, 阿兰!'), findsOneWidget);

    const orderedKeys = <Key>[
      Key('home-hero'),
      // 2026-09-17 拍板 #15:首页补搜索入口,位置紧跟 Hero(小程序 .v3-search)。
      Key('home-search'),
      Key('home-recommend'),
      Key('home-continue'),
      Key('home-nearby'),
      Key('home-upcoming'),
      Key('home-topic-stream'),
    ];
    final elementOrder = tester.allElements
        .where((element) => orderedKeys.contains(element.widget.key))
        .map((element) => element.widget.key)
        .toList();
    expect(elementOrder, orderedKeys);
  });

  testWidgets('首页带搜索条入口;Hero 只保留头像与 Banner 点击目标', (WidgetTester tester) async {
    GoRouter router = await _pumpHome(tester);

    // P1-1(b1-sim-search):小程序 index.wxml `.v3-search` 有首页搜索入口,
    // 点它进既有搜索页,本页不另造搜索态。
    expect(find.byKey(const Key('home-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-search')));
    await tester.pumpAndSettle();
    expect(find.text('search'), findsOneWidget);

    expect(find.byKey(const Key('home-publish')), findsNothing);

    router.go('/feed');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('打开我的主页'));
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsOneWidget);

    router.go('/feed');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('打开推荐内容'));
    await tester.pumpAndSettle();
    expect(find.text('topic:11'), findsOneWidget);
  });

  testWidgets('Hero 无跳转目标时只作为图像朗读，不伪装成按钮', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpHome(tester, banners: <HomeBanner>[HomeBanner(id: 1)]);

    final Finder hero = find.bySemanticsLabel('推荐内容');
    expect(hero, findsOneWidget);
    final data = tester.getSemantics(hero).getSemanticsData();
    expect(data.flagsCollection.isButton, isFalse);
    expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  // 真源 utils/index/home-action-banner.js `home-action-activity`:
  // 首页固定行动卡是官方活动列表在首页的入口(gap-spec-roam §4 #21)。
  testWidgets('★ 首页固定卡「和朋友报名活动」滑到尾页可点,进官方活动列表', (WidgetTester tester) async {
    await _pumpHome(tester);

    await tester.drag(
      find.descendant(
        of: find.byKey(const Key('home-hero')),
        matching: find.byType(PageView),
      ),
      const Offset(-800, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('和朋友报名活动'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-action-activity')));
    await tester.pumpAndSettle();
    expect(find.text('官方活动列表'), findsOneWidget);
  });

  testWidgets('后台 banner 为空时固定行动卡仍占 Hero,不再是一整块灰底', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester, banners: <HomeBanner>[]);

    expect(find.byKey(const Key('home-action-activity')), findsOneWidget);
    expect(find.text('和朋友报名活动'), findsOneWidget);
  });

  testWidgets('继续探索沿用票夹入口,已结束报名不占首页', (WidgetTester tester) async {
    final active = MyRegistration.fromJson(<String, dynamic>{
      'id': 61,
      'ownerType': 2,
      'ownerId': 21,
      'registrationStatus': 2,
      'verificationStatus': 0,
      'cmsActivity': <String, dynamic>{'name': '继续外滩探索'},
    });
    await _pumpHome(tester, registrations: <MyRegistration>[active]);
    final Finder continueCard = find.byKey(const Key('home-continue'));
    await _scrollToSection(tester, const Key('home-continue'));
    final Finder continueAction = find.descendant(
      of: continueCard,
      matching: find.byType(CupertinoButton),
    );
    tester.widget<CupertinoButton>(continueAction).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('tickets:61:2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    final completed = MyRegistration.fromJson(<String, dynamic>{
      'id': 62,
      'ownerType': 2,
      'ownerId': 21,
      'registrationStatus': 2,
      'verificationStatus': 1,
      'cmsActivity': <String, dynamic>{'name': '已经结束'},
    });
    await _pumpHome(tester, registrations: <MyRegistration>[completed]);
    expect(find.byKey(const Key('home-continue')), findsNothing);
    expect(find.byType(FeedPage), findsOneWidget);
  });

  testWidgets('进行中的游戏会话优先占「继续」卡,直达游玩页', (WidgetTester tester) async {
    // 小程序首页 `game || journey`:有暂停中的一局时,这张卡说的是游戏,不是报名。
    final active = MyRegistration.fromJson(<String, dynamic>{
      'id': 61,
      'ownerType': 2,
      'ownerId': 21,
      'registrationStatus': 2,
      'verificationStatus': 0,
      'cmsActivity': <String, dynamic>{'name': '继续外滩探索'},
    });
    await _pumpHome(
      tester,
      registrations: <MyRegistration>[active],
      playRuns: const <PlayRunSession>[
        PlayRunSession(
          activityId: 27,
          topicId: 71,
          elapsedSeconds: 305,
          title: '外滩谜案',
        ),
      ],
    );

    // main 布局演进后继续卡落在懒建视口外,与 journey 卡同款先滚到脸上。
    await _scrollToSection(tester, const Key('home-continue-game'));
    final Finder gameCard = find.byKey(const Key('home-continue-game'));
    expect(find.byKey(const Key('home-continue')), findsNothing);
    expect(find.text('继续游戏'), findsOneWidget);
    expect(find.text('已暂停 · 已用时 05:05'), findsOneWidget);

    await tester.ensureVisible(gameCard);
    tester
        .widget<CupertinoButton>(
          find.descendant(of: gameCard, matching: find.byType(CupertinoButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('play:27:null'), findsOneWidget);
  });

  testWidgets('自玩的一局没有活动场次时走 topicId;拿不到用时就只说「已暂停」', (
    WidgetTester tester,
  ) async {
    await _pumpHome(
      tester,
      playRuns: const <PlayRunSession>[
        PlayRunSession(activityId: 0, topicId: 71, title: '自玩主题'),
      ],
    );

    await _scrollToSection(tester, const Key('home-continue-game'));
    expect(find.text('已暂停'), findsOneWidget);

    final Finder gameCard = find.byKey(const Key('home-continue-game'));
    await tester.ensureVisible(gameCard);
    tester
        .widget<CupertinoButton>(
          find.descendant(of: gameCard, matching: find.byType(CupertinoButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('play:0:71'), findsOneWidget);
  });

  testWidgets('底部流保留主题/活动切换与各自点击目标', (WidgetTester tester) async {
    await _pumpHome(tester, height: 5000);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('活动'), findsOneWidget);

    await tester.tap(find.text('活动'));
    await tester.pumpAndSettle();
    expect(find.text('周末城市漫游'), findsOneWidget);
    await tester.tap(find.text('周末城市漫游'));
    await tester.pumpAndSettle();
    expect(find.text('activity:71'), findsOneWidget);
  });

  testWidgets('底部流卡片出「价格/时间/地点」三行,值缺了写「—」', (WidgetTester tester) async {
    await _pumpHome(tester, height: 5000);

    // 主题流:价格带上「起」,时间取 MM-dd HH:mm,地点是 addressName。
    expect(find.text('价格'), findsOneWidget);
    expect(find.text('¥38.00 起'), findsOneWidget);
    expect(find.text('06-13 18:30'), findsOneWidget);
    expect(find.text('静安寺商圈'), findsOneWidget);

    await tester.tap(find.text('活动'));
    await tester.pumpAndSettle();
    expect(find.text('¥128.00 起'), findsOneWidget);
    expect(find.text('06-14 22:00'), findsOneWidget);
    expect(find.text('陆家嘴观景台'), findsOneWidget);
  });
}
