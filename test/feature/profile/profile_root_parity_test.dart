import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/profile/profile_page.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_net_image.dart';

final _user = ProfileDetail(
  id: 7,
  nickname: '探索者',
  avatar: '',
  introduction: '寻找下一条城市路线',
  levelId: 3,
  point: 88,
  balance: 12.5,
  followNum: 2,
  fansNum: 3,
  likeNum: 4,
  topicNum: 0,
  activityNum: 0,
);

Future<void> _pump(
  WidgetTester tester, {
  String role = 'player',
  AsyncValue<Map<String, dynamic>>? merchantInfo,
  AsyncValue<List<MyRegistration>> orders =
      const AsyncData<List<MyRegistration>>(<MyRegistration>[]),
  AsyncValue<List<MyProject>> projects = const AsyncData<List<MyProject>>(
    <MyProject>[],
  ),
  AsyncValue<List<SquarePost>> posts = const AsyncData<List<SquarePost>>(
    <SquarePost>[],
  ),
  AsyncValue<PlayGrowth> playGrowth = const AsyncData<PlayGrowth>(
    PlayGrowth(level: 3, totalCheckins: 9, totalMileage: 12, streakDays: 5),
  ),
  ValueChanged<int>? onPost,
  ValueChanged<ProfileDestination>? onDestination,
  ValueChanged<MyRegistration>? onOrder,
  ValueChanged<MyProject>? onProject,
  bool exploreEnabled = true,
  String? merchantTeam,
  Size viewport = const Size(390, 1100),
  TextScaler textScaler = TextScaler.noScaling,
  double bottomPadding = 0,
  bool disableAnimations = false,
  bool highContrast = false,
}) async {
  await tester.binding.setSurfaceSize(viewport);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            padding: EdgeInsets.only(bottom: bottomPadding),
            disableAnimations: disableAnimations,
            highContrast: highContrast,
          ),
          child: child!,
        ),
        home: ProfileRootView(
          user: _user,
          effectiveRole: role,
          orders: orders,
          projects: projects,
          posts: posts,
          playGrowth: playGrowth,
          growth: AsyncData<GrowthCenter>(
            GrowthCenter(
              levelNo: 3,
              expValue: 88,
              points: 120,
              badges: <MedalBadge>[],
              missions: <GrowthMission>[],
            ),
          ),
          merchantInfo: merchantInfo,
          onPost: onPost ?? (_) {},
          onDestination: onDestination ?? (_) {},
          onOrder: onOrder ?? (_) {},
          onProject: onProject ?? (_) {},
          onRetryOrders: () {},
          onRetryProjects: () {},
          onRetryPosts: () {},
          onRetryGrowth: () {},
          exploreEnabled: exploreEnabled,
          merchantTeam: merchantTeam,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Liquid Glass 底栏内边距会保留在个人页尾部', (WidgetTester tester) async {
    await _pump(tester, bottomPadding: 100);

    final SliverPadding content = tester.widget<SliverPadding>(
      find.byType(SliverPadding).first,
    );
    expect(
      content.padding.resolve(TextDirection.ltr).bottom,
      greaterThanOrEqualTo(100 + CyTokens.space8),
    );
  });

  testWidgets('辅助字号放大到 200% 时 Hero 增长且关键资料和入口不裁切', (WidgetTester tester) async {
    await _pump(tester, textScaler: const TextScaler.linear(2));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('profile-hero'))).height,
      greaterThan(360),
    );
    for (final String label in <String>[
      '探索者',
      'Lv.3 城市探索者',
      '连续探索：5天',
      // 三格 = 好友 / 关注 / 粉丝;好友后端没有 friendNum 契约 ⇒ 写「—」不是 0。
      '— 好友',
      '2 关注',
      '3 粉丝',
      '开始探索',
      '票夹',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    for (final String label in <String>['开始探索', '票夹']) {
      final Finder button = find.ancestor(
        of: find.text(label),
        matching: find.byType(CupertinoButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('320x568、200% 字号下个人封面与核心操作可滚动达到', (WidgetTester tester) async {
    await _pump(
      tester,
      viewport: const Size(320, 568),
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
      highContrast: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('探索者'), findsOneWidget);
    expect(find.text('开始探索'), findsOneWidget);
    await tester.ensureVisible(find.text('票夹'));
    expect(tester.takeException(), isNull);
    expect(find.text('票夹'), findsOneWidget);
    for (final String label in <String>['设置', '编辑个人资料']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(
        tester.getSize(find.bySemanticsLabel(label)).height,
        greaterThanOrEqualTo(44),
      );
    }
  });

  testWidgets('默认字号保持 Hero 几何且图标入口有 VoiceOver 名称和 44pt 触控区', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('profile-hero'))).height,
      360,
    );
    expect(find.bySemanticsLabel('设置'), findsOneWidget);
    expect(find.bySemanticsLabel('编辑个人资料'), findsOneWidget);

    for (final String label in <String>['设置', '编辑个人资料']) {
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      expect(
        tester.getSize(find.bySemanticsLabel(label)).height,
        greaterThanOrEqualTo(44),
      );
    }
    semantics.dispose();
  });

  testWidgets('玩家主页按源顺序呈现身份、开始探索、三页与订单/项目/资产', (WidgetTester tester) async {
    final destinations = <ProfileDestination>[];
    await _pump(tester, onDestination: destinations.add);

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('探索者'), findsOneWidget);
    expect(find.text('Lv.3 城市探索者'), findsOneWidget);
    expect(find.text('开始探索'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('推文'), findsOneWidget);
    expect(find.text('成就'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('票夹'), findsOneWidget);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text text) => text.data)
        .whereType<String>()
        .toList();
    expect(labels.indexOf('我的订单'), lessThan(labels.indexOf('我的项目')));
    expect(labels.indexOf('我的项目'), lessThan(labels.indexOf('我的资产')));
    expect(find.text('暂无订单'), findsOneWidget);
    expect(find.text('还没有项目'), findsOneWidget);
    expect(find.text('账户余额'), findsOneWidget);
    expect(find.text('¥12.50'), findsOneWidget);

    await tester.tap(find.text('开始探索'));
    await tester.pump();
    expect(destinations, <ProfileDestination>[ProfileDestination.explore]);
  });

  testWidgets('订单/项目/资产入口分别保留原目的地', (WidgetTester tester) async {
    final destinations = <ProfileDestination>[];
    await _pump(tester, onDestination: destinations.add);

    for (final destination in <ProfileDestination>[
      ProfileDestination.orders,
      ProfileDestination.projects,
      ProfileDestination.assets,
    ]) {
      final target = find.byKey(
        ValueKey<String>('profile-${destination.name}'),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
    }

    expect(destinations, <ProfileDestination>[
      ProfileDestination.orders,
      ProfileDestination.projects,
      ProfileDestination.assets,
    ]);
  });

  testWidgets('推文与关于是同一根页的真实内容页', (WidgetTester tester) async {
    await _pump(tester);

    await tester.tap(find.text('推文'));
    await tester.pumpAndSettle();
    expect(find.text('还没有推文'), findsOneWidget);
    // 副标逐字对齐真源 cy-profile(index.wxml:223,isSelf 分支)。
    expect(find.text('你还没有发布过推文'), findsOneWidget);

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('个人介绍'), findsOneWidget);
    expect(find.text('探索与更多'), findsOneWidget);
    expect(find.text('成为主理人'), findsOneWidget);
  });

  testWidgets('商家视角显示核销且不露玩家探索入口', (WidgetTester tester) async {
    await _pump(
      tester,
      role: 'merchant',
      merchantInfo: const AsyncData<Map<String, dynamic>>(<String, dynamic>{
        'name': '街角咖啡',
        'description': '一间欢迎城市探索者停靠的店',
        'businessStatusText': '营业中',
        'address': '上海市静安区',
      }),
    );

    expect(find.text('核销'), findsOneWidget);
    expect(find.text('开始探索'), findsNothing);
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('品牌故事'), findsOneWidget);
    expect(find.text('一间欢迎城市探索者停靠的店'), findsOneWidget);
    expect(find.text('营业信息'), findsOneWidget);
    expect(find.text('个人介绍'), findsNothing);
    expect(find.text('探索与更多'), findsNothing);
    expect(find.text('成为主理人'), findsNothing);
  });

  testWidgets('商家 Hero 封面优先读取小程序真源 coverImage', (WidgetTester tester) async {
    await _pump(
      tester,
      role: 'merchant',
      merchantInfo: const AsyncData<Map<String, dynamic>>(<String, dynamic>{
        'name': '街角咖啡',
        'logo': '',
        'coverImage': 'https://example.test/cover-image.png',
        'cover': 'https://example.test/legacy-cover.png',
      }),
    );

    expect(
      tester.widget<CyNetImage>(find.byType(CyNetImage)).url,
      'https://example.test/cover-image.png',
    );
  });

  testWidgets('商家历史数据没有 coverImage 时仍兼容 cover', (WidgetTester tester) async {
    await _pump(
      tester,
      role: 'merchant',
      merchantInfo: const AsyncData<Map<String, dynamic>>(<String, dynamic>{
        'name': '街角咖啡',
        'logo': '',
        'coverImage': '',
        'cover': 'https://example.test/legacy-cover.png',
      }),
    );

    expect(
      tester.widget<CyNetImage>(find.byType(CyNetImage)).url,
      'https://example.test/legacy-cover.png',
    );
  });

  testWidgets('报名状态加载中禁用开始探索，不能先当成无报名跳首页', (WidgetTester tester) async {
    final destinations = <ProfileDestination>[];
    await _pump(tester, exploreEnabled: false, onDestination: destinations.add);

    final CupertinoButton button = tester.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('开始探索'),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('开始探索'));
    await tester.pump();
    expect(destinations, isEmpty);
  });

  testWidgets('订单、项目与推文卡不是只读卡，保留各自目的地', (WidgetTester tester) async {
    final destinations = <ProfileDestination>[];
    final postsOpened = <int>[];
    final ordersOpened = <int>[];
    final projectsOpened = <int>[];
    await _pump(
      tester,
      orders: AsyncData<List<MyRegistration>>(<MyRegistration>[
        MyRegistration(id: 31, ownerType: 2, ownerId: 9, title: '城市夜游'),
      ]),
      projects: const AsyncData<List<MyProject>>(<MyProject>[
        MyProject(id: 41, bizType: 'topic', title: '旧城路线'),
      ]),
      posts: AsyncData<List<SquarePost>>(<SquarePost>[
        SquarePost(id: 51, memberId: 7, contents: '第一条推文'),
      ]),
      onDestination: destinations.add,
      onPost: postsOpened.add,
      onOrder: (MyRegistration value) => ordersOpened.add(value.id),
      onProject: (MyProject value) => projectsOpened.add(value.id),
    );

    await tester.tap(find.text('城市夜游'));
    await tester.pump();
    await tester.ensureVisible(find.text('旧城路线'));
    await tester.tap(find.text('旧城路线'));
    await tester.pump();
    await tester.tap(find.text('推文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条推文'));
    await tester.pump();

    expect(destinations, isEmpty);
    expect(ordersOpened, <int>[31]);
    expect(projectsOpened, <int>[41]);
    expect(postsOpened, <int>[51]);
  });

  testWidgets('成就页保留积分、成长、勋章墙和集邮册四个真实入口', (WidgetTester tester) async {
    final destinations = <ProfileDestination>[];
    await _pump(tester, onDestination: destinations.add);

    await tester.tap(find.text('成就'));
    await tester.pumpAndSettle();

    expect(find.text('120'), findsOneWidget);
    for (final destination in <ProfileDestination>[
      ProfileDestination.points,
      ProfileDestination.growth,
      ProfileDestination.badges,
      ProfileDestination.stamps,
    ]) {
      final target = find.byKey(
        ValueKey<String>('profile-${destination.name}'),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
    }
    expect(destinations, <ProfileDestination>[
      ProfileDestination.points,
      ProfileDestination.growth,
      ProfileDestination.badges,
      ProfileDestination.stamps,
    ]);
  });

  // ★ 经营团队(缺口盘点 2848 · Top3):`/merchant/team` 早就登记在路由表里,
  //   但全 App 没有一个入口 —— 页面等于不存在。真源把它挂在「我的」页
  //   资产之后:资产回答「钱在哪里」,团队回答「谁能经营」。
  testWidgets('激活经营身份时「我的」页出现经营团队入口,点了就是那个目的地', (WidgetTester tester) async {
    final destinations = <ProfileDestination>[];
    await _pump(
      tester,
      role: 'merchant',
      merchantTeam: '店主 · 管理',
      onDestination: destinations.add,
    );

    final Finder entry = find.byKey(
      const ValueKey<String>('profile-merchant-team'),
    );
    expect(entry, findsOneWidget);
    expect(find.text('经营团队'), findsOneWidget);
    expect(find.text('岗位权限、员工邀请与离职回收'), findsOneWidget);
    expect(find.text('店主 · 管理'), findsOneWidget);
    expect(tester.getSize(entry).height, greaterThanOrEqualTo(44));

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text text) => text.data)
        .whereType<String>()
        .toList();
    expect(labels.indexOf('我的资产'), lessThan(labels.indexOf('经营团队')));

    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pump();
    expect(destinations, <ProfileDestination>[ProfileDestination.merchantTeam]);
  });

  testWidgets('玩家视角没有经营团队入口(不是身份就没这一行,不是置灰)', (WidgetTester tester) async {
    await _pump(tester);

    expect(
      find.byKey(const ValueKey<String>('profile-merchant-team')),
      findsNothing,
    );
    expect(find.text('经营团队'), findsNothing);
  });

  test('经营团队目的地接的是已登记的路由,不是一句死文案', () {
    final String page = File(
      'lib/feature/profile/profile_page.dart',
    ).readAsStringSync();
    final String router = File(
      'lib/core/router/app_router.dart',
    ).readAsStringSync();

    expect(
      page,
      contains("ProfileDestination.merchantTeam => '/merchant/team'"),
    );
    expect(router, contains("path: '/merchant/team'"));
    // 右侧那半句取的是 access/me 的岗位与管理位,不是本地 role。
    expect(page, contains("access.canManageOperators ? stringsOf(context).profileManage : stringsOf(context).profileView"));
  });

  // 商城是 App 独有域(小程序没有对应页),入口只能挂在积分块里 —— 这条守住
  // 「挂上去了」和「挂对了地方」:ProfileDestination.mall 必须真的落到 /mall,
  // 拼错一个字符就会掉进 GoRouter 的未匹配页,而那是纯字符串错误,编译器看不见。
  testWidgets('积分商城入口落到真实 /mall 路由', (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: <RouteBase>[
        GoRoute(
          path: '/profile',
          builder: (BuildContext context, GoRouterState state) =>
              CupertinoButton(
                onPressed: () => openProfileDestination(
                  context,
                  ProfileDestination.mall,
                  isMerchantView: false,
                  activeRegistration: const AsyncData<bool>(false),
                  retryActiveRegistration: () {},
                  ownedClubs: const AsyncData<List<Club>>(<Club>[]),
                  retryOwnedClubs: () {},
                ),
                child: const Text('积分商城'),
              ),
        ),
        GoRoute(
          path: '/mall',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('商城首页'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('积分商城'));
    await tester.pumpAndSettle();
    expect(find.text('商城首页'), findsOneWidget);
  });

  // 真源「我的」根场景挂有「我的参与」(utils/scene-registry.js
  // member-participation-history;cy/profile/index.js:1649 goMyJoin →
  // subpackageMember/mycanyu)。App 侧同页 = /participations。
  testWidgets('★ 关于页「探索与更多」有「我的参与」入口,按源 navigateTo 语义 push', (
    WidgetTester tester,
  ) async {
    final destinations = <ProfileDestination>[];
    await _pump(tester, onDestination: destinations.add);

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('我的参与'));
    await tester.tap(find.text('我的参与'));
    await tester.pump();
    expect(destinations, <ProfileDestination>[
      ProfileDestination.participations,
    ]);
  });
}
