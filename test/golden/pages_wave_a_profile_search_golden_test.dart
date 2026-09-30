// Wave-A:搜索索引页(A22/A23/A24)· 我的(四 Tab:A32/A34/A35/A36/A37/A38)·
// 他人主页(A42)· 隐私撤回(A58)。
//
// 「我的」四 Tab 与小程序 `pages/member/index/index` 的 主页/推文/成就/关于 一一对应,
// 所以四张图都拍同一个 ProfileRootView,只切 tab —— 结构差异一眼可比。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_a_profile_search_golden_test.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/profile/profile_controller.dart';
import 'package:chengyin_app/feature/profile/profile_page.dart';
import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/search_page.dart';
import 'package:chengyin_app/feature/settings/settings_page.dart';

import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
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

Future<void> _shot(WidgetTester tester, String path) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

ProfileDetail _me({int balance = 128}) => ProfileDetail(
  id: 7,
  nickname: '阿兰',
  avatar: '',
  introduction: '走完这条线,就把这座城记住了。',
  levelId: 7,
  point: 8800,
  balance: balance.toDouble(),
  followNum: 12,
  fansNum: 34,
  likeNum: 56,
  topicNum: 3,
  activityNum: 9,
  isFollow: false,
);

MyRegistration _order(int id, String title) =>
    MyRegistration.fromJson(<String, dynamic>{
      'id': id,
      'ownerType': 2,
      'ownerId': 100 + id,
      'registrationNo': 'R2026091700$id',
      'registrationStatus': 2,
      'verificationStatus': 0,
      'participateDate': '2099-08-24 14:00',
      'cmsActivity': <String, dynamic>{
        'name': title,
        'productType': 2,
        'startDate': '2099-08-24 14:00:00',
        'endDate': '2099-08-24 18:00:00',
        'addressName': '静安寺 1 号口',
      },
    });

const MyProject _project = MyProject(
  id: 3001,
  bizType: 'topic',
  title: '老建筑年份线索',
  projectTypeText: '主题',
  state: 'online',
  stateText: '进行中',
  publishStatus: 'online',
  signupCount: 12,
  viewCount: 340,
  ownerType: 'member',
);

SquarePost _post(int id, String text) => SquarePost.fromJson(<String, dynamic>{
  'id': id,
  'memberId': 7,
  'memberNickname': '阿兰',
  'contents': text,
  'likeNum': 3,
  'commentCount': 1,
  'isLiked': 0,
});

GrowthCenter _growth() => GrowthCenter(
  levelNo: 7,
  expValue: 12345,
  points: 8800,
  badges: <MedalBadge>[
    MedalBadge(badgeName: '开始在场', iconUrl: '', badgeCode: 'FIRST_STEP'),
  ],
  missions: <GrowthMission>[],
);

Widget _profile({
  required AsyncValue<List<MyRegistration>> orders,
  required AsyncValue<List<MyProject>> projects,
  required AsyncValue<List<SquarePost>> posts,
  AsyncValue<GrowthCenter>? growth,
  AsyncValue<PlayGrowth>? playGrowth,
  int balance = 128,
}) {
  return _app(
    <dynamic>[
      authControllerProvider.overrideWith(
        () => _FixedAuth(
          AuthState(
            user: User(id: 7, nickname: '阿兰', avatar: '', role: 'player'),
            initialized: true,
          ),
        ),
      ),
    ],
    ProfileRootView(
      user: _me(balance: balance),
      effectiveRole: 'player',
      orders: orders,
      projects: projects,
      posts: posts,
      growth: growth ?? AsyncData<GrowthCenter>(_growth()),
      playGrowth:
          playGrowth ??
          const AsyncData<PlayGrowth>(
            PlayGrowth(
              level: 3,
              totalCheckins: 9,
              totalMileage: 12,
              streakDays: 5,
            ),
          ),
      onPost: (int _) {},
      onDestination: (ProfileDestination _) {},
      onOrder: (MyRegistration _) {},
      onProject: (MyProject _) {},
      onRetryOrders: () {},
      onRetryProjects: () {},
      onRetryPosts: () {},
      onRetryGrowth: () {},
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 搜索索引页 pages/search2/index ─────────────────────────────────────
  testWidgets('A23 搜索 · 常态(历史 + 八大热搜词 + 类别 + 地图入口)', (
    WidgetTester tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'search2_history': jsonEncode(<String>['静安寺', '咖啡']),
    });
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        searchCategoriesProvider.overrideWith(
          (ref) async => <Category>[
            Category(id: 1, name: '主题', type: 1),
            Category(id: 2, name: '活动', type: 2),
            Category(id: 3, name: '俱乐部', type: 5),
            Category(id: 4, name: '商家', type: 5),
          ],
        ),
      ], const SearchPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('猜你想搜'), findsOneWidget);
    expect(find.text('类别'), findsOneWidget);
    await _shot(tester, 'goldens/page_search_index_normal.png');
  });

  testWidgets('A22 搜索 · 类别为空 ⇒ 整块不渲染(搜索仍可用)', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        searchCategoriesProvider.overrideWith((ref) async => <Category>[]),
      ], const SearchPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('类别'), findsNothing);
    expect(find.text('猜你想搜'), findsOneWidget);
    await _shot(tester, 'goldens/page_search_index_no_category.png');
  });

  testWidgets('A24 搜索 · 空(无历史 / 无类别,热搜词与地图入口仍在)', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        searchCategoriesProvider.overrideWith((ref) async => <Category>[]),
      ], const SearchPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索历史'), findsNothing);
    expect(find.text('在地图上搜城市节点'), findsOneWidget);
    await _shot(tester, 'goldens/page_search_index_empty.png');
  });

  // ── 我的 pages/member/index/index ─────────────────────────────────────
  testWidgets('A32 我的 · 主页(资料头 + 订单/项目/资产分组)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _profile(
        orders: AsyncData<List<MyRegistration>>(<MyRegistration>[
          _order(1, '外滩夜行档案'),
        ]),
        projects: const AsyncData<List<MyProject>>(<MyProject>[_project]),
        posts: AsyncData<List<SquarePost>>(<SquarePost>[_post(1, '今晚静安寺人少。')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的订单'), findsOneWidget);
    expect(find.text('我的项目'), findsOneWidget);
    expect(find.text('我的资产'), findsOneWidget);
    await _shot(tester, 'goldens/page_member_home_normal.png');
  });

  testWidgets('A34 我的 · 空(订单/项目都没有 ⇒ 虚线空态卡,不是空白)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _profile(
        orders: const AsyncData<List<MyRegistration>>(<MyRegistration>[]),
        projects: const AsyncData<List<MyProject>>(<MyProject>[]),
        posts: const AsyncData<List<SquarePost>>(<SquarePost>[]),
        balance: 0,
      ),
    );
    await tester.pumpAndSettle();

    await _shot(tester, 'goldens/page_member_home_empty.png');
  });

  testWidgets('A36 我的 · 推文 Tab', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _profile(
        orders: const AsyncData<List<MyRegistration>>(<MyRegistration>[]),
        projects: const AsyncData<List<MyProject>>(<MyProject>[]),
        posts: AsyncData<List<SquarePost>>(<SquarePost>[
          _post(1, '今晚静安寺这一段人少得不像周五。'),
          _post(2, '刚发的,还没人看到。'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('推文'));
    await tester.pumpAndSettle();

    await _shot(tester, 'goldens/page_member_posts_tab.png');
  });

  testWidgets('A37 我的 · 成就 Tab(积分/排名/探索数都是填充数据)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _profile(
        orders: const AsyncData<List<MyRegistration>>(<MyRegistration>[]),
        projects: const AsyncData<List<MyProject>>(<MyProject>[]),
        posts: const AsyncData<List<SquarePost>>(<SquarePost>[]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('成就'));
    await tester.pumpAndSettle();

    await _shot(tester, 'goldens/page_member_achievements_tab.png');
  });

  testWidgets('A38 我的 · 关于 Tab', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _profile(
        orders: const AsyncData<List<MyRegistration>>(<MyRegistration>[]),
        projects: const AsyncData<List<MyProject>>(<MyProject>[]),
        posts: const AsyncData<List<SquarePost>>(<SquarePost>[]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    await _shot(tester, 'goldens/page_member_about_tab.png');
  });

  testWidgets('A35 我的 · 加载中(整页骨架)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              user: User(id: 7, nickname: '阿兰', avatar: '', role: 'player'),
              initialized: true,
            ),
          ),
        ),
        profileDetailProvider.overrideWith(
          (ref) => Completer<ProfileDetail>().future,
        ),
      ], const ProfilePage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await _shot(tester, 'goldens/page_member_loading.png');
  });

  // ── 隐私保护 pages/privacy/index(撤回态)────────────────────────────────
  // 小程序那一页是**微信隐私授权闸**:文案「漫游定位仅用于实时位置展示、到点打卡
  // 和轨迹记录；不使用时不会在后台持续采集。」+《用户隐私保护指引》+ 撤回。
  // App 侧同一张卡不在 /legal/privacy_policy(那只是政策正文),而是
  // 设置 →「隐私与定位」的原生半屏 —— 文案与小程序的撤回分支逐字一致。
  testWidgets('A58 隐私保护 · 撤回漫游定位同意(设置 → 隐私与定位)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              user: User(id: 7, nickname: '阿兰', avatar: '', role: 'player'),
              initialized: true,
            ),
          ),
        ),
      ], const SettingsPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私与定位'));
    await tester.pumpAndSettle();

    expect(find.text('撤回漫游定位同意'), findsOneWidget);
    expect(find.text('查看《用户隐私保护指引》'), findsOneWidget);
    await _shot(tester, 'goldens/page_privacy_withdraw_sheet.png');
  });
}
