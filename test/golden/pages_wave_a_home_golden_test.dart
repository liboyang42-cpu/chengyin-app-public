// Wave-A 首页/详情基线:A01 首页常态 · A02 首页骨架 · A03 首页分区错误 ·
// A13 广场详情加载中。
//
// ★ A04(游客态首页)不在这里:App 的游客访问首页 fail-closed 到整页 /login
//   (app_router.dart `_needsLogin`),「游客看到的首页」这一帧在 App 里不存在,
//   拍它就是造一张没人会看到的假证据 —— 见本批报告。
//
// fixture 刻意造**分区各自的形态**,不造漂亮数据:近处/推荐/主题流各一,
// 即将上线的 startDate 一律 null(渲染「待定」)—— 倒计时是每秒刷新的时钟文本,
// 写成真实日期这张图第二天就自己烂掉(同类踩坑见 no_clock_dependent_goldens_test)。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_a_home_golden_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/banner.dart';
import 'package:chengyin_app/data/models/play_run_session.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/data/models/upcoming_activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/feed/feed_controller.dart';
import 'package:chengyin_app/feature/feed/feed_page.dart';
import 'package:chengyin_app/feature/feed/feed_sections_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_detail_page.dart';

import 'golden_theme.dart';

/// 首页分区高 6/7 屏,用 844 只拍得到 Hero。取一个高视口让
/// 「附近/推荐/主题流」三个分区同屏 —— A02/A03 的验收点正是**三个分区
/// 各自的骨架/错误**,只拍首屏等于没拍。
const Size _kHomeViewport = Size(390, 1600);

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
}

/// 首页主题流:固定列表,不打网络。
class _FixedFeed extends FeedNotifier {
  _FixedFeed(this._topics);
  final List<Topic> _topics;
  @override
  Future<List<Topic>> build() async => _topics;
}

/// 永远不完成 —— 骨架态。
class _HangingFeed extends FeedNotifier {
  @override
  Future<List<Topic>> build() => Completer<List<Topic>>().future;
}

class _ErrorFeed extends FeedNotifier {
  @override
  Future<List<Topic>> build() async => throw Exception('网络请求失败');
}

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

List<dynamic> _baseOverrides() => <dynamic>[
  authControllerProvider.overrideWith(
    () => _FixedAuth(
      AuthState(
        user: User(id: 7, nickname: '阿兰', avatar: '', role: 'player'),
        initialized: true,
      ),
    ),
  ),
  // 首页「继续游戏」卡(_ContinueSection)watch 这个 provider,不 override 会走
  // 真 Dio,在 fake_async 下留下永不落地的 pending timer(A01/A02/A03 都中招)。
  // 空列表与既有渲染一致:没有会话时该卡本就隐藏(SizedBox.shrink)。
  playRunSessionsProvider.overrideWith(
    (ref) async => const <PlayRunSession>[],
  ),
];

List<dynamic> _normalOverrides() => <dynamic>[
  ..._baseOverrides(),
  feedBannerProvider.overrideWith(
    (ref) async => <HomeBanner>[
      HomeBanner(id: 1, picUrl: 'https://img.example/hero.jpg', linkType: 4, dataId: '11'),
      HomeBanner(id: 2, picUrl: 'https://img.example/hero-2.jpg', linkType: 3, dataId: '7'),
    ],
  ),
  feedNearbyProvider.overrideWith(
    (ref) async => <Activity>[
      Activity(id: 21, name: '外滩夜行档案', addressName: '外滩源 · 1.2km', description: '沿江点亮三处城市记忆'),
      Activity(id: 22, name: '苏州河晨跑', addressName: '河滨大楼 · 2.4km'),
    ],
  ),
  feedRecommendProvider.overrideWith(
    (ref) async => <Topic>[
      Topic(id: 31, name: '老建筑年份线索', introduction: '跟着门牌与砖缝里的年份走一条线'),
    ],
  ),
  feedUpcomingProvider.overrideWith(
    (ref) async => <UpcomingActivity>[
      // startDate 故意留空:倒计时文本是时钟依赖的,写真实日期基线会自己烂掉。
      UpcomingActivity(id: 41, name: '迷雾剧场', addressName: '静安'),
    ],
  ),
  feedActivityStreamProvider.overrideWith(
    (ref) async => <Activity>[
      Activity(id: 71, name: '周末城市漫游', description: '半天走完三条弄堂', addressName: '愚园路'),
    ],
  ),
  myJoinedActivitiesProvider.overrideWith(
    (ref) async => const <MyRegistration>[],
  ),
  feedProvider.overrideWith(
    () => _FixedFeed(<Topic>[Topic(id: 51, name: '街角密码')]),
  ),
];

void main() {
  testWidgets('A01 首页 · 常态(hero + 附近 + 推荐 + 即将上线 + 主题流)', (
    WidgetTester tester,
  ) async {
    setGoldenViewport(tester, _kHomeViewport);
    await tester.pumpWidget(_app(_normalOverrides(), const FeedPage()));
    // 「即将上线」卡里有每秒刷新的倒计时(CountdownText),pumpAndSettle 永远等不到静止。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('home-hero')), findsOneWidget);
    expect(find.byKey(const Key('home-nearby')), findsOneWidget);
    expect(find.byKey(const Key('home-recommend')), findsOneWidget);
    expect(find.text('外滩夜行档案'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_home_wave_a_normal.png'),
    );
  });

  testWidgets('A02 首页 · 骨架(三个分区同构骨架)', (WidgetTester tester) async {
    setGoldenViewport(tester, _kHomeViewport);
    await tester.pumpWidget(
      _app(<dynamic>[
        ..._baseOverrides(),
        feedBannerProvider.overrideWith(
          (ref) => Completer<List<HomeBanner>>().future,
        ),
        feedNearbyProvider.overrideWith(
          (ref) => Completer<List<Activity>>().future,
        ),
        feedRecommendProvider.overrideWith(
          (ref) => Completer<List<Topic>>().future,
        ),
        feedUpcomingProvider.overrideWith(
          (ref) => Completer<List<UpcomingActivity>>().future,
        ),
        feedActivityStreamProvider.overrideWith(
          (ref) => Completer<List<Activity>>().future,
        ),
        myJoinedActivitiesProvider.overrideWith(
          (ref) => Completer<List<MyRegistration>>().future,
        ),
        feedProvider.overrideWith(_HangingFeed.new),
      ], const FeedPage()),
    );
    // 骨架的微光是无限循环动画,只能固定推进一帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_home_wave_a_loading.png'),
    );
  });

  testWidgets('A03 首页 · 三个分区各自带重试的错误态', (WidgetTester tester) async {
    setGoldenViewport(tester, _kHomeViewport);
    await tester.pumpWidget(
      _app(<dynamic>[
        ..._baseOverrides(),
        feedBannerProvider.overrideWith(
          (ref) async => throw Exception('网络请求失败'),
        ),
        feedNearbyProvider.overrideWith(
          (ref) async => throw Exception('网络请求失败'),
        ),
        feedRecommendProvider.overrideWith(
          (ref) async => throw Exception('网络请求失败'),
        ),
        feedUpcomingProvider.overrideWith(
          (ref) async => throw Exception('网络请求失败'),
        ),
        feedActivityStreamProvider.overrideWith(
          (ref) async => throw Exception('网络请求失败'),
        ),
        myJoinedActivitiesProvider.overrideWith(
          (ref) async => throw Exception('网络请求失败'),
        ),
        feedProvider.overrideWith(_ErrorFeed.new),
      ], const FeedPage()),
    );
    // ★ 错误态必须 pumpAndSettle:Riverpod 3 对抛错的 provider 自带指数退避重试,
    //   固定推一帧只拍得到重试间隙里的 loading(实测 10s 都还在 loading,
    //   真正落到 AsyncError 要等退避走完)。
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 说人话、点名失败的是什么 —— 且每个失败分区各自带重试 CTA,不是整页一个。
    // main 演进后主题流在 CustomScrollView 懒加载区:先拍页顶,再滚下去验第三分区。
    expect(find.text('附近活动没能加载出来'), findsOneWidget);
    expect(find.text('推荐主题没能加载出来'), findsOneWidget);
    expect(find.text('重试'), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_home_wave_a_error.png'),
    );
    await tester.dragUntilVisible(
      find.text('主题列表没有加载出来'),
      find.byType(CustomScrollView).first,
      const Offset(0, -300),
    );
    expect(find.text('主题列表没有加载出来'), findsOneWidget);
  });

  testWidgets('A13 广场详情 · 加载中(骨架,清空迟到正文)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        ..._baseOverrides(),
        squareDetailProvider(
          1,
        ).overrideWith((ref) => Completer<SquarePost>().future),
      ], const SquareDetailPage(postId: 1)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('动态详情'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_square_detail_loading.png'),
    );
  });
}
