// 游客点 IM 入口:弹登录引导、留在原地 —— 不是「跳 /im 被 router 静默兜回首页」。
//
// b1 模拟器真跑报告 P1-1(PR #212 / REPORT-sim-im.md):游客从俱乐部页点「消息」,
// 内容跳到了 feed,而底部 Tab 高亮仍停在「俱乐部」(复现 2/2)。根因是 `/im` 在
// `_loginRequiredPrefixes` 里,而这几个入口没接仓里现成的 requireLogin。
//
// 这里钉住收口:游客点入口 → 出登录 Sheet、IM 接口一次都不打、路由不动。
// 另外几处(俱乐部「进入群聊」只在已加入时出现、商家两处在 `/merchant` 登录前缀
// 后面)在测试里泵不动整页,用源码判据兜住 —— revert 掉任一句门都会红。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/api/template_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/topic_template.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/club/club_list_page.dart';
import 'package:chengyin_app/feature/profile/user_profile_page.dart';
import 'package:chengyin_app/feature/template/template_list_page.dart';

import '../../support/source_text.dart';

const String _imStubText = 'IM-LIST-STUB';

final ProfileDetail _profile = ProfileDetail(
  id: 42,
  nickname: '小李',
  avatar: '',
  introduction: '',
  levelId: 1,
  point: 0,
  balance: 0,
  followNum: 0,
  fansNum: 0,
  likeNum: 0,
  topicNum: 0,
  activityNum: 0,
);

class _LoggedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// 试金石:游客点入口时**一次都不该打** IM 接口。
class _RecordingImApi implements ImApi {
  int startChats = 0;

  @override
  Future<int> startChat(int targetMemberId) async {
    startChats += 1;
    throw StateError('游客不该走到 IM 接口');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTemplateApi implements TemplateApi {
  @override
  Future<List<TopicTemplate>> topicTemplateList() async =>
      const <TopicTemplate>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryApi implements CategoryApi {
  @override
  Future<List<Category>> list({String? type}) async => const <Category>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePublishApi implements PublishApi {
  @override
  Future<PublishTemplateHomeData> templateHomeSections() async =>
      const PublishTemplateHomeData(
        total: 0,
        categories: <Category>[],
        banner: <PublishTemplate>[],
        latest: <PublishTemplate>[],
        recommended: <PublishTemplate>[],
        mustPlay: <PublishTemplate>[],
        hot: <PublishTemplate>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `/im` 与 `/im/chat/:id` 的桩:门没接上时会**被建出来**,断言就靠它落空。
List<RouteBase> _imRoutes() => <RouteBase>[
  GoRoute(
    path: '/im',
    builder: (_, _) => const Scaffold(body: Text(_imStubText)),
  ),
  GoRoute(
    path: '/im/chat/:conversationId',
    builder: (_, _) => const Scaffold(body: Text(_imStubText)),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  GoRouter router,
  List<dynamic> overrides,
) async {
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_LoggedOutAuth.new),
        ...overrides,
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// 点入口后必须:出登录 Sheet + 没进 /im。
Future<void> _expectGateStopsGuest(WidgetTester tester, Finder entry) async {
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.text('登录城瘾'), findsOneWidget, reason: '游客点 IM 入口要弹登录引导');
  expect(find.text(_imStubText), findsNothing, reason: '没登录就不许路由到 /im');
}

void main() {
  testWidgets('游客点俱乐部页「消息」:出登录引导,不跳 /im', (WidgetTester tester) async {
    // 铃铛语义标签逐字对齐源 pages/talent/list/index.wxml:12 aria-label="站内消息"
    // (club_root_parity_test 同口径);String bySemanticsLabel 是全等匹配,须用完整标签。
    // 要开语义树才找得到。
    final SemanticsHandle semantics = tester.ensureSemantics();
    final GoRouter router = GoRouter(
      initialLocation: '/clubs',
      routes: <RouteBase>[
        GoRoute(path: '/clubs', builder: (_, _) => const ClubListPage()),
        ..._imRoutes(),
      ],
    );
    await _pump(
      tester,
      router,
      <dynamic>[
        clubHomeProvider.overrideWith(
          (ref) async => const ClubHome(
            owned: <Club>[],
            joined: <Club>[],
            nearby: <Club>[],
            events: <ClubHomeEvent>[],
          ),
        ),
        clubFeedProvider.overrideWith((ref) async => const ClubFeed()),
      ].cast(),
    );

    await _expectGateStopsGuest(tester, find.bySemanticsLabel('站内消息'));
    semantics.dispose();
  });

  testWidgets('游客点模板广场「通知」入口:出登录引导,不跳 /im', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/template-square',
      routes: <RouteBase>[
        GoRoute(
          path: '/template-square',
          builder: (_, _) => const TemplateListPage(),
        ),
        ..._imRoutes(),
      ],
    );
    await _pump(
      tester,
      router,
      <dynamic>[
        templateApiProvider.overrideWithValue(_FakeTemplateApi()),
        categoryApiProvider.overrideWithValue(_FakeCategoryApi()),
        publishApiProvider.overrideWithValue(_FakePublishApi()),
      ].cast(),
    );

    await _expectGateStopsGuest(
      tester,
      find.byKey(const Key('template-inbox-target')),
    );
  });

  testWidgets('游客点他人主页「发消息」:出登录引导,一次 IM 接口都不打', (WidgetTester tester) async {
    final _RecordingImApi im = _RecordingImApi();
    final GoRouter router = GoRouter(
      initialLocation: '/member',
      routes: <RouteBase>[
        GoRoute(
          path: '/member',
          builder: (_, _) => const UserProfilePage(memberId: 42),
        ),
        ..._imRoutes(),
      ],
    );
    await _pump(
      tester,
      router,
      <dynamic>[
        otherProfileProvider(42).overrideWith((ref) async => _profile),
        otherPostsProvider(
          42,
        ).overrideWith((ref) async => const <SquarePost>[]),
        imApiProvider.overrideWithValue(im),
      ].cast(),
    );

    await _expectGateStopsGuest(tester, find.text('发消息'));
    expect(im.startChats, 0, reason: '登录门要在接口之前,不能先撞一个 401 回来');
  });

  test('每处 IM 入口都是「先 requireLogin,再进 /im」', () {
    // 泵不动的几处靠这一段兜:门必须紧跟在入口之后。
    const Map<String, int> gatedPushes = <String, int>{
      'lib/feature/club/club_list_page.dart': 1,
      // 两个 tab 的 inbox 入口在 #402 收编成共用的 _openInbox(),门只有一处。
      'lib/feature/template/template_list_page.dart': 1,
      'lib/feature/merchant/merchant_home_page.dart': 1,
      'lib/feature/merchant/merchant_game_node_page.dart': 1,
    };
    final RegExp gatedPush = RegExp(
      r"requireLogin\(context, ref\)[\s\S]{0,120}?push\('/im'",
    );
    for (final MapEntry<String, int> entry in gatedPushes.entries) {
      expect(
        gatedPush.allMatches(codeOf(entry.key)).length,
        entry.value,
        reason: '${entry.key} 的 IM 入口丢了登录门',
      );
    }

    // 「先取会话 id 再进聊天页」的两处:门在取 id 之前,中间隔着一次接口调用。
    const Map<String, String> gatedEntries = <String, String>{
      'lib/feature/profile/user_profile_page.dart':
          'Future<void> _startChat() async {',
      'lib/feature/club/club_detail_page.dart':
          'Future<void> _openGroupChat() async {',
    };
    for (final MapEntry<String, String> entry in gatedEntries.entries) {
      final RegExp re = RegExp(
        '${RegExp.escape(entry.value)}[\\s\\S]{0,120}?requireLogin\\(context, ref\\)',
      );
      expect(
        re.hasMatch(codeOf(entry.key)),
        isTrue,
        reason: '${entry.key} 的 ${entry.value} 丢了登录门',
      );
    }
  });
}
