// club 域游客撞 401 的就地登录门。
//
// ★ 来自对生产后端的实测(REPORT-sim-club-full.md §2):club 域 7 条接口对
//   无 token 的请求一律返 `{"code":401,"msg":"登录状态已失效，请重新登录"}`。
//   而路由是让游客自由浏览的(`_loginRequiredPrefixes` 不含 /clubs 与 /club/*),
//   两者对不上 —— 小程序不会撞上,因为那边人人被微信静默登录、没有「游客」。
//
// 说成「检查网络后重试」会把人指去查 WiFi,说成「你没有…权限」会让他去查
// 自己的角色;而「重试」按多少次都还是 401 —— 两条都是死路。对照页
// /club/:id/settlement 的门态本来就是对的,这里是对齐既有口径,不是新能力。
//
// 反面同样守住:断网/超时不能被推去登录,403(登录了但没权限)仍走权限文案。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_enroll_page.dart';
import 'package:chengyin_app/feature/club/club_event_ops_page.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/club/club_governance_page.dart';
import 'package:chengyin_app/feature/club/club_list_page.dart';
import 'package:chengyin_app/feature/club/club_login_gate.dart';
import 'package:chengyin_app/feature/club/club_notify_page.dart';
import 'package:chengyin_app/feature/club/club_roles_page.dart';
import 'package:chengyin_app/feature/club/club_topic_story_page.dart';
import 'package:chengyin_app/feature/club/club_workbench_page.dart';

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/api/club/list'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/club/list'),
    statusCode: status,
  ),
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/api/club/list'),
  type: DioExceptionType.connectionError,
);

class _LoggedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _FakeOpsApi extends ClubOpsApi {
  _FakeOpsApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  Object? accessError;
  int accessCalls = 0;

  @override
  Future<ClubOpsAccess> access({required int clubId, int? activityId}) async {
    accessCalls += 1;
    if (accessError != null) throw accessError!;
    return const ClubOpsAccess(
      activeDeclared: true,
      active: true,
      clubId: 1,
      permissions: <String>{},
      roleCodes: <String>[],
      canManageRoles: false,
    );
  }
}

Widget _app(Widget home, List<dynamic> overrides) => ProviderScope(
  overrides: overrides.cast(),
  // Riverpod 3 默认对失败的 provider 自动重试 10 次 —— 那条策略不是本文件要验
  // 的东西,关掉它才能把「这条门自己发不发请求」数干净。
  retry: (int retryCount, Object error) => null,
  child: MaterialApp(home: home),
);

void main() {
  test('clubLoginRequired 只认 401(403/断网都不是「要登录」)', () {
    expect(clubLoginRequired(_http(401)), isTrue);
    expect(clubLoginRequired(_http(403)), isFalse);
    expect(clubLoginRequired(_offline()), isFalse);
    expect(clubLoginRequired(ClubApiException('回执坏了')), isFalse);
  });

  group('/clubs', () {
    testWidgets('游客 401 → 登录引导,不再说「检查网络后重试」,也不自动重发请求', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await tester.pumpWidget(
        _app(const ClubListPage(), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubHomeProvider.overrideWith((ref) async {
            calls += 1;
            throw _http(401);
          }),
          clubFeedProvider.overrideWith((ref) async => const ClubFeed()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看俱乐部'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('没能加载俱乐部'), findsNothing);
      expect(find.text('检查网络后重试'), findsNothing);
      expect(calls, 1, reason: '401 不该触发任何自动重取');

      // 「去登录」要真的能把登录弹窗叫出来 —— 光有一句话不算出口。
      await tester.tap(find.text('去登录'));
      await tester.pumpAndSettle();
      expect(find.text('登录城瘾'), findsOneWidget);
      // 登录弹窗打开这个动作本身不碰俱乐部接口。
      expect(calls, 1);
    });

    testWidgets('同一页的帖文 tab 撞 401 也走登录引导', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubListPage(), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubHomeProvider.overrideWith(
            (ref) async => const ClubHome(
              owned: <Club>[],
              joined: <Club>[],
              nearby: <Club>[],
              events: <ClubHomeEvent>[],
            ),
          ),
          clubFeedProvider.overrideWith((ref) async => throw _http(401)),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('帖文'));
      await tester.pumpAndSettle();

      expect(find.text('登录后查看帖文'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('动态加载失败'), findsNothing);
    });

    testWidgets('断网 → 仍是网络文案,不把人推去登录', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubListPage(), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubHomeProvider.overrideWith((ref) async => throw _offline()),
          clubFeedProvider.overrideWith((ref) async => const ClubFeed()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('没能加载俱乐部'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });
  });

  testWidgets('/club/:id 游客 401 → 登录引导', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(const ClubDetailPage(clubId: 1), <dynamic>[
        authControllerProvider.overrideWith(_LoggedOutAuth.new),
        clubDetailProvider(1).overrideWith((ref) async => throw _http(401)),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看俱乐部详情'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('没能打开这个俱乐部'), findsNothing);
  });

  group('/club/:id 运营页:401 与 403 分得开', () {
    testWidgets('event-ops 401 → 登录引导,不再说「你没有活动运营的权限」', (
      WidgetTester tester,
    ) async {
      final _FakeOpsApi fake = _FakeOpsApi()..accessError = _http(401);
      await tester.pumpWidget(
        _app(const ClubEventOpsPage(clubId: 1, activityId: 41), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_NoopClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看活动运营'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('你没有活动运营的权限'), findsNothing);
      expect(fake.accessCalls, 1, reason: '401 不该触发任何自动重取');
    });

    testWidgets('event-ops 403 → 真没权限,文案不变', (WidgetTester tester) async {
      final _FakeOpsApi fake = _FakeOpsApi()..accessError = _http(403);
      await tester.pumpWidget(
        _app(const ClubEventOpsPage(clubId: 1, activityId: 41), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_NoopClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('你没有活动运营的权限'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });

    testWidgets('governance 401 → 登录引导,不再说「你没有成员治理的权限」', (
      WidgetTester tester,
    ) async {
      final _FakeOpsApi fake = _FakeOpsApi()..accessError = _http(401);
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_NoopClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看成员治理'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('你没有成员治理的权限'), findsNothing);
      expect(fake.accessCalls, 1);
    });

    testWidgets('notify 401 → 登录引导,不再说「你没有发通知的权限」', (
      WidgetTester tester,
    ) async {
      final _FakeOpsApi fake = _FakeOpsApi()..accessError = _http(401);
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_NoopClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看群发通知'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('你没有发通知的权限'), findsNothing);
      expect(fake.accessCalls, 1, reason: '401 不该触发任何自动重取');
    });

    testWidgets('notify 403 → 真没权限,文案不变', (WidgetTester tester) async {
      final _FakeOpsApi fake = _FakeOpsApi()..accessError = _http(403);
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_NoopClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('你没有发通知的权限'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });

    testWidgets('roles 401 → 登录引导,不再说「你没有管理角色的权限」', (
      WidgetTester tester,
    ) async {
      final _FakeOpsApi fake = _FakeOpsApi()..accessError = _http(401);
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_NoopClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看角色与权限'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('你没有管理角色的权限'), findsNothing);
      expect(fake.accessCalls, 1);
    });

    testWidgets('roles 403 → 真没权限,文案不变', (WidgetTester tester) async {
      final _FakeOpsApi fake = _FakeOpsApi()..accessError = _http(403);
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_NoopClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('你没有管理角色的权限'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });
  });

  // 旧 workbench 深链(/club/workbench 不带 id)靠 /api/club/my 找「我的第一个
  // 俱乐部」。游客打进来接口返 401,原文案「加载你的俱乐部失败/检查网络后重试」
  // 与 P1-1 同一条死路 —— 重试多少次都还是 401。
  group('/club/workbench', () {
    testWidgets('游客无 id 撞 401 → 登录引导,不再指去查网络', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(
        _app(const ClubWorkbenchPage(), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubMyProvider.overrideWith((ref) async {
            calls += 1;
            throw _http(401);
          }),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看我的俱乐部'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('加载你的俱乐部失败'), findsNothing);
      expect(find.text('检查网络后重试'), findsNothing);
      expect(calls, 1, reason: '401 不该触发任何自动重取');
    });

    testWidgets('断网 → 仍是网络文案,不把人推去登录', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubWorkbenchPage(), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubMyProvider.overrideWith((ref) async => throw _offline()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('加载你的俱乐部失败'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });
  });

  // b1-sim-club-5 C5-1(模拟器实拍 c07):topic-story 游客 401 被
  // clubOpsFailureState 吞成 denied →「你看不到这条路线 / 这条主题可能只对
  // 成员可见」——冒充没权限,且无登录出口。同型漏网补门(#258 口径)。
  group('/club/:id/topic/:topicId/story', () {
    testWidgets('游客 401 → 登录引导,不再冒充「看不到这条路线」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubTopicStoryPage(topicId: 1, clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubTopicOpsApiProvider.overrideWithValue(_Always401TopicOpsApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看剧情与玩法'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('你看不到这条路线'), findsNothing);
    });

    testWidgets('403 → 仍是权限文案,不把人推去登录', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubTopicStoryPage(topicId: 1, clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubTopicOpsApiProvider.overrideWithValue(
            _CannedErrorTopicOpsApi(_http(403)),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('你看不到这条路线'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });
  });

  // b1-sim-club-5 C5-1 同族:enroll 权限层 401 说成「暂时无法确认查看权限」
  // +「重新检查」(实拍 c05),名册层 401 说成「报名名册加载失败」。
  group('/club/:id/enroll', () {
    testWidgets('权限层游客 401 → 登录引导,不再「暂时无法确认查看权限」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubEnrollPage(clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubDetailProvider(1).overrideWith((ref) async => throw _http(401)),
          clubTopicsProvider(1).overrideWith((ref) async => <Never>[]),
          clubMembersProvider(1).overrideWith((ref) async => <Never>[]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看报名名册'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('暂时无法确认查看权限'), findsNothing);
    });

    testWidgets('权限层断网 → 仍是网络文案,不把人推去登录', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubEnrollPage(clubId: 1), <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubDetailProvider(1).overrideWith((ref) async => throw _offline()),
          clubTopicsProvider(1).overrideWith((ref) async => <Never>[]),
          clubMembersProvider(1).overrideWith((ref) async => <Never>[]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('网络连接失败'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });
  });
}

class _NoopClubApi extends ClubApi {
  _NoopClubApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));
}

class _Always401TopicOpsApi extends ClubTopicOpsApi {
  _Always401TopicOpsApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<ClubTopicOverview> overview(int topicId) async => throw _http(401);
}

class _CannedErrorTopicOpsApi extends ClubTopicOpsApi {
  _CannedErrorTopicOpsApi(this.error)
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final Object error;

  @override
  Future<ClubTopicOverview> overview(int topicId) async => throw error;
}
