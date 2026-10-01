import '../../support/fixed_auth.dart';
// 活动详情(topic-detail)的负控门:六个状态的主键去向、权限面(canManageSessions /
// setting.canManage)、四张半屏的接口参数、结束主题的「失败不关框」。
//
// 判据对齐小程序 pages/club/topic-detail(@7bdeb58de):
//   - 状态胶囊从 STATES 一张表出;审核中不给写动作;
//   - 场次列表空 → 整段不画;有场次且 canManageSessions → 才给「管理场次」;
//     (三个身份与四个数走 /api/club/crm/topic-manage-stats 的假回执,
//      不在公开投影里 —— 见 club_topic_manage_stats_test.dart)
//   - 三个开关一起提交(后端少收一个就拒绝),存不上要拨回原位;
//   - `/api/club/topic-setting/end` 是「先下架、再逐场退款,一场一个事务」,
//     有场次没退成时弹层不许关,得让人能再点一次;
//   - 名单三个统计数是全量口径,四个 chip 就是服务端 filter 的取值。

import 'package:flutter/cupertino.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/club_director.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/feature/club/club_director_controller.dart';
import 'package:chengyin_app/feature/club/club_topic_detail_page.dart';

Widget _app(Widget home, List<dynamic> overrides, {Locale locale = const Locale('zh')}) {
  return ProviderScope(
    overrides: <dynamic>[signedInAuthOverride(role: 'club'), ...overrides].cast(),
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

DioException _networkFailure() => DioException(
  requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
  type: DioExceptionType.connectionError,
);

DioException _forbidden() => DioException(
  requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
    statusCode: 403,
  ),
);

/// 生产实测(同 club_login_gate 注释):无 token / 过期 token 一律
/// `HTTP 401 {"msg":"登录状态已失效，请重新登录"}`。
DioException _unauthorized() => DioException(
  requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
    statusCode: 401,
    data: <String, dynamic>{'code': 401, 'msg': '登录状态已失效，请重新登录'},
  ),
);

/// 详情(`/api/topic/info-to-user`)只提供陈列:四个管理向数字与三个身份
/// 都不在这里 —— 它们在 [ClubTopicManageStats] 里(拍板1,2026-09-17)。
Map<String, dynamic> _overviewJson({
  String name = '静安夜行',
  String status = 'preparing',
  Object? auditStatus,
  Object? rejectReason,
  int chapterCount = 2,
  int nodeCount = 7,
  int gameConfigured = 3,
  List<Map<String, dynamic>> sessions = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> activities = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': 12,
  'name': name,
  'status': status,
  if (auditStatus != null) 'auditStatus': auditStatus,
  if (rejectReason != null) 'rejectReason': rejectReason,
  'chapterCount': chapterCount,
  'nodeCount': nodeCount,
  'gameConfiguredCount': gameConfigured,
  'storyReady': true,
  'playModeText': '经典定向',
  'startDate': '2026-09-01 19:00:00',
  'endDate': '2026-09-30 22:00:00',
  'sessions': sessions,
  'activityList': activities,
};

/// 管理向统计 + 三个身份的假回执(`POST /api/club/crm/topic-manage-stats`)。
/// 默认一档 = 主理人视角,与本文件改造前 `_overviewJson` 的缺省值逐项对齐。
ClubTopicManageStats _stats({
  bool canDirect = true,
  bool canManageSessions = true,
  bool canViewVerify = true,
  int nodeCount = 7,
  int headcount = 9,
  int pendingVerify = 2,
  int verifiedByMe = 1,
}) => ClubTopicManageStats(
  canDirect: canDirect,
  canManageSessions: canManageSessions,
  canViewVerify: canViewVerify,
  nodeCount: nodeCount,
  sessionHeadcount: headcount,
  pendingVerifyCount: pendingVerify,
  verifiedByMeCount: verifiedByMe,
);

Map<String, dynamic> _sessionJson({
  String id = 's1',
  String whenText = '9月20日 14:00',
  String whoText = '阿岚带队',
  String etaText = '约 3 小时',
  String kind = 'club',
}) => <String, dynamic>{
  'id': id,
  'whenText': whenText,
  'whoText': whoText,
  'etaText': etaText,
  'kind': kind,
};

TopicSetting _setting({
  String topicName = '静安夜行',
  bool coopOpen = false,
  bool pinned = true,
  bool memberOnly = false,
  bool canManage = true,
  List<TopicSettingChapter> chapters = const <TopicSettingChapter>[],
}) => TopicSetting(
  topicName: topicName,
  lifecycleText: '准备中 · 9月1日开跑',
  coopOpen: coopOpen,
  pinned: pinned,
  memberOnly: memberOnly,
  canManage: canManage,
  chapters: chapters,
);

/// 记录调用、可挂错误的 ClubTopicOpsApi 假实现。
class _FakeClubTopicOpsApi extends ClubTopicOpsApi {
  _FakeClubTopicOpsApi() : super(_dummyDioClient());

  ClubTopicOverview? overviewValue;
  Object? overviewError;
  int overviewCalls = 0;

  TopicSetting? settingValue;
  Object? settingError;
  int settingCalls = 0;
  final List<Map<String, dynamic>> saves = <Map<String, dynamic>>[];
  Object? saveError;

  final List<Object> endResponses = <Object>[];
  int endCalls = 0;

  RecruitOverview? recruitValue;
  Object? recruitError;

  TopicCustomers? customersValue;
  Object? customersError;
  final List<String> customerFilters = <String>[];

  final List<Map<String, dynamic>> chapterRecruits = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> chapterFinishes = <Map<String, dynamic>>[];

  @override
  Future<ClubTopicOverview> overview(int topicId) async {
    overviewCalls += 1;
    if (overviewError != null) throw overviewError!;
    return overviewValue!;
  }

  ClubTopicManageStats? statsValue;
  Object? statsError;
  final List<Map<String, dynamic>> statsCalls = <Map<String, dynamic>>[];

  @override
  Future<ClubTopicManageStats> manageStats({
    required int clubId,
    required int topicId,
    int? activityId,
  }) async {
    statsCalls.add(<String, dynamic>{
      'clubId': clubId,
      'topicId': topicId,
      'activityId': activityId,
    });
    if (statsError != null) throw statsError!;
    return statsValue ?? _stats();
  }

  final List<Map<String, dynamic>> editOpsCalls = <Map<String, dynamic>>[];
  Object? editOpsError;

  @override
  Future<void> editOps({
    required int activityId,
    required String startDate,
  }) async {
    editOpsCalls.add(<String, dynamic>{
      'activityId': activityId,
      'startDate': startDate,
    });
    if (editOpsError != null) throw editOpsError!;
  }

  @override
  Future<TopicSetting> settingDetail({
    required int clubId,
    required int topicId,
  }) async {
    settingCalls += 1;
    if (settingError != null) throw settingError!;
    return settingValue!;
  }

  @override
  Future<TopicSetting> saveSetting({
    required int clubId,
    required int topicId,
    required bool coopOpen,
    required bool pinned,
    required bool memberOnly,
  }) async {
    saves.add(<String, dynamic>{
      'clubId': clubId,
      'topicId': topicId,
      'coopOpen': coopOpen,
      'pinned': pinned,
      'memberOnly': memberOnly,
    });
    if (saveError != null) throw saveError!;
    final TopicSetting base = settingValue!;
    return TopicSetting(
      topicName: base.topicName,
      lifecycleText: base.lifecycleText,
      coopOpen: coopOpen,
      pinned: pinned,
      memberOnly: memberOnly,
      canManage: base.canManage,
      chapters: base.chapters,
    );
  }

  @override
  Future<TopicEndResult> endTopic({
    required int clubId,
    required int topicId,
  }) async {
    endCalls += 1;
    if (endResponses.isEmpty) {
      throw ClubApiException('假实现没有准备结束应答');
    }
    final Object next = endResponses.removeAt(0);
    if (next is Exception) throw next;
    return next as TopicEndResult;
  }

  @override
  Future<RecruitOverview> recruitOverview({
    required int clubId,
    required int topicId,
  }) async {
    if (recruitError != null) throw recruitError!;
    return recruitValue!;
  }

  @override
  Future<TopicCustomers> customers({
    required int clubId,
    required int topicId,
    String filter = '',
  }) async {
    customerFilters.add(filter);
    if (customersError != null) throw customersError!;
    return customersValue!;
  }

  @override
  Future<void> chapterRecruit({
    required int chapterId,
    required bool enabled,
    String scope = '',
  }) async {
    chapterRecruits.add(<String, dynamic>{
      'chapterId': chapterId,
      'enabled': enabled,
      'scope': scope,
    });
  }

  @override
  Future<void> chapterFinish({
    required int chapterId,
    String scope = '',
  }) async {
    chapterFinishes.add(<String, dynamic>{
      'chapterId': chapterId,
      'scope': scope,
    });
  }
}

/// 导演台网关的假实现。**默认报 SESSION_NOT_FOUND** —— 导演台进「还没有
/// 可管理的活动局」空态:页面六态仍由主题审核态说话(空态不接管投影),
/// 原有结构测试保持原样。要演导演台行为的行为测试往 [projection] /
/// [outcomes] 里喂真形状。
class _FakeClubDirectorGateway implements ClubDirectorGateway {
  ClubDirectorProjection? projection;
  Object? loadError;

  /// 发出去的命令(顺序、requestId、payload 都可回看)。
  final List<GameSessionCommand> submitted = <GameSessionCommand>[];

  /// 命令回执队列:元素是 [GameSessionReceipt](返回)或 [Exception](抛)。
  /// 用完没指定时一律回 APPLIED。
  final List<Object> outcomes = <Object>[];

  /// 核对结果(readClubReceipt)的回执队列;用完默认 APPLIED。
  final List<GameSessionReceipt> receipts = <GameSessionReceipt>[];

  int loadCalls = 0;

  @override
  Future<ClubDirectorProjection> loadClubProjection({
    required int activityId,
  }) async {
    loadCalls += 1;
    if (loadError != null) throw loadError!;
    final ClubDirectorProjection? p = projection;
    if (p == null) {
      throw const GameSessionContractException(
        '这一场还没开局',
        reasonCode: 'SESSION_NOT_FOUND',
      );
    }
    return p;
  }

  @override
  Future<GameSessionReceipt> submitClubCommand(
    GameSessionCommand command,
  ) async {
    submitted.add(command);
    if (outcomes.isNotEmpty) {
      final Object next = outcomes.removeAt(0);
      if (next is Exception) throw next;
      return next as GameSessionReceipt;
    }
    return _applied(command.activityId, command.requestId, command.action);
  }

  @override
  Future<GameSessionReceipt> readClubReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async {
    if (receipts.isNotEmpty) return receipts.removeAt(0);
    return _applied(activityId, requestId, expectedAction);
  }

  static GameSessionReceipt _applied(
    int activityId,
    String requestId,
    String action,
  ) => GameSessionReceipt(
    activityId: activityId,
    requestId: requestId,
    action: action,
    outcome: GameReceiptOutcome.applied,
    receiptId: 'r-$requestId',
    revision: 99,
  );
}

/// 导演台投影的最小合法形状(perspective=CLUB,`ClubDirectorProjection.fromJson`)。
Map<String, dynamic> _projectionJson({
  String status = 'RUNNING',
  int revision = 3,
  List<String> actions = const <String>['FINISH'],
  Map<String, dynamic>? club,
}) => <String, dynamic>{
  'perspective': 'CLUB',
  'status': status,
  'revision': revision,
  'activityId': 41,
  'availableActions': actions,
  'club':
      club ??
      <String, dynamic>{
        'readiness': <String, dynamic>{
          'requiredStations': 0,
          'readyStations': 0,
          'teamsReady': false,
        },
      },
};

ClubDirectorProjection _directorProjection({
  String status = 'RUNNING',
  int revision = 3,
  List<String> actions = const <String>['FINISH'],
  Map<String, dynamic>? club,
}) => ClubDirectorProjection.fromJson(
  _projectionJson(
    status: status,
    revision: revision,
    actions: actions,
    club: club,
  ),
);

/// 长列表是懒构建的:把目标滚进可见视口中央附近再操作。
Future<void> _reveal(WidgetTester tester, Key key, {Finder? within}) async {
  final Finder target = find.byKey(key);
  final Finder scrollableFinder = within ?? find.byType(Scrollable).first;
  final ScrollPosition position = tester
      .state<ScrollableState>(scrollableFinder)
      .position;

  void jump(double delta) {
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  for (int pass = 0; pass < 2 && target.evaluate().isEmpty; pass += 1) {
    if (pass == 1) {
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
    }
    for (int step = 0; step < 40 && target.evaluate().isEmpty; step += 1) {
      final double before = position.pixels;
      jump(400);
      await tester.pumpAndSettle();
      if (position.pixels == before) break;
    }
  }
  if (target.evaluate().isEmpty) return;

  for (int step = 0; step < 10; step += 1) {
    final Rect viewport = tester.getRect(scrollableFinder);
    final Rect rect = tester.getRect(target);
    if (rect.top >= viewport.top + 8 && rect.bottom <= viewport.bottom - 8) {
      break;
    }
    jump(
      rect.top < viewport.top + 8
          ? rect.top - viewport.top - 60
          : rect.bottom - viewport.bottom + 60,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _tapVisible(WidgetTester tester, Key key, {Finder? within}) async {
  await _reveal(tester, key, within: within);
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// 半屏内容是自己的 SingleChildScrollView:要滚它,不是滚页面。
Finder _inSheet(Key sheetKey) => find.descendant(
  of: find.byKey(sheetKey),
  matching: find.byType(Scrollable),
);

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeClubTopicOpsApi fake,
  _FakeClubDirectorGateway? director,
  Locale locale = const Locale('zh'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  await tester.pumpWidget(
    _app(
      ClubTopicDetailPage(
        key: ObjectKey(fake),
        clubId: 1,
        topicId: 12,
        activityId: 41,
      ),
      <dynamic>[
        clubTopicOpsApiProvider.overrideWithValue(fake),
        clubDirectorApiProvider.overrideWithValue(
          director ?? _FakeClubDirectorGateway(),
        ),
        clubDirectorPendingStoreProvider.overrideWith(
          (ref) => ClubDirectorPendingStore.memory(),
        ),
      ],
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

/// 挂真 Navigator 的泵:出站 push 的目标路由把 query 回声成文本,
/// 用来钉「带没带 topicId」这种参数传递。
Future<GoRouter> _pumpRouted(
  WidgetTester tester,
  _FakeClubTopicOpsApi fake,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  final GoRouter router = GoRouter(
    initialLocation: '/club/1/topic/12',
    routes: <RouteBase>[
      GoRoute(
        path: '/club/:id/topic/:topicId',
        builder: (_, _) => ClubTopicDetailPage(
          key: ObjectKey(fake),
          clubId: 1,
          topicId: 12,
          activityId: 41,
        ),
      ),
      GoRoute(
        path: '/club/:id/enroll',
        builder: (_, GoRouterState state) => Scaffold(
          body: Text('enroll-${state.uri.queryParameters['topicId']}'),
        ),
      ),
      GoRoute(
        path: '/club/:id/event-ops',
        builder: (_, GoRouterState state) => Scaffold(
          body: Text('event-ops-${state.uri.queryParameters['topicId']}'),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
            signedInAuthOverride(role: 'club'),
        clubTopicOpsApiProvider.overrideWithValue(fake),
        clubDirectorApiProvider.overrideWithValue(_FakeClubDirectorGateway()),
        clubDirectorPendingStoreProvider.overrideWith(
          (ref) => ClubDirectorPendingStore.memory(),
        ),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// 打开「更多」半屏(设置页)。
Future<void> _openMoreSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('topic-detail-quick-more')));
  await tester.pumpAndSettle();
}

Finder _switchIn(Key rowKey) => find.descendant(
  of: find.byKey(rowKey),
  matching: find.byType(CupertinoSwitch),
);

bool _switchValue(WidgetTester tester, Key rowKey) =>
    tester.widget<CupertinoSwitch>(_switchIn(rowKey)).value;

bool _switchEnabled(WidgetTester tester, Key rowKey) =>
    tester.widget<CupertinoSwitch>(_switchIn(rowKey)).onChanged != null;

bool _primaryEnabled(WidgetTester tester) =>
    tester
        .widget<CyNativeButton>(find.byKey(const Key('topic-detail-primary')))
        .onPressed !=
    null;

void main() {
  testWidgets('English activity details preserve raw title and reviewing state', (tester) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(
        _overviewJson(name: '原始活动名', status: 'reviewing'),
      )!;
    await _pumpPage(tester, fake: fake, locale: const Locale('en'));
    expect(find.text('Activity details'), findsOneWidget);
    expect(find.text('原始活动名'), findsOneWidget);
    expect(find.text('Under review'), findsOneWidget);
    expect(find.text('Start activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('topic-detail:结构与状态表', () {
    testWidgets('进行中:状态胶囊/四圆钮/核销三格/主题卡/场次一次读齐', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(
            status: 'running',
            sessions: <Map<String, dynamic>>[_sessionJson()],
          ),
        )!;
      await _pumpPage(tester, fake: fake);

      expect(fake.overviewCalls, 1, reason: '一次请求喂整页');
      expect(fake.statsCalls.single, <String, dynamic>{
        'clubId': 1,
        'topicId': 12,
        'activityId': 41,
      }, reason: '管理向统计与详情并发,且照传这一场(不是省掉键)');
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('玩家可到店核销'), findsOneWidget);
      expect(find.text('9月1日 – 9月30日'), findsOneWidget);

      expect(
        find.byKey(const Key('topic-detail-quick-merchant')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('topic-detail-quick-customer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('topic-detail-quick-groupcode')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('topic-detail-quick-more')), findsOneWidget);

      expect(find.text('待核销'), findsOneWidget);
      expect(find.text('我已核销'), findsOneWidget);
      expect(find.text('本场总人数'), findsOneWidget);
      expect(find.text('9'), findsOneWidget, reason: '本场人数 9');

      expect(find.byKey(const Key('topic-detail-story')), findsOneWidget);
      expect(find.text('2 章 · 7 站 · 经典定向'), findsOneWidget);
      expect(find.text('剧情已写'), findsOneWidget);
      expect(find.text('玩法 3/7'), findsOneWidget);

      expect(find.byKey(const Key('topic-detail-session-s1')), findsOneWidget);
      expect(find.text('9月20日 14:00'), findsOneWidget);
      expect(find.text('俱乐部包团'), findsOneWidget);
      expect(find.text('结束活动'), findsOneWidget);
      expect(_primaryEnabled(tester), isTrue);
    });

    testWidgets('审核中:主键是禁用的等待态,不给任何写动作', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(status: 'confirmed', auditStatus: 1),
        )!;
      await _pumpPage(tester, fake: fake);

      expect(find.text('审核中'), findsOneWidget);
      expect(find.text('等待审核中'), findsOneWidget);
      expect(_primaryEnabled(tester), isFalse);
      expect(find.text('核销'), findsNothing, reason: '审核中不出核销区');
    });

    testWidgets('未通过:原样回显原因,主键改成「修改并重新提交」', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(status: '', rejectReason: '封面有二维码，换一张'),
        )!;
      await _pumpPage(tester, fake: fake);

      expect(find.text('未通过'), findsOneWidget);
      expect(
        find.byKey(const Key('topic-detail-reject-reason')),
        findsOneWidget,
      );
      expect(find.text('封面有二维码，换一张'), findsOneWidget);
      expect(find.text('修改并重新提交'), findsOneWidget);
      expect(find.text('核销'), findsNothing);
    });

    testWidgets('已结束:照样出核销区(还有票要退),主键进结算', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(status: 'ended'),
        )!;
      await _pumpPage(tester, fake: fake);

      expect(find.text('已结束'), findsOneWidget);
      expect(find.text('查看结算报告'), findsOneWidget);
      expect(find.text('核销'), findsOneWidget);
    });
  });

  group('topic-detail:权限面', () {
    testWidgets('能管场次才给「管理场次」入口', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(sessions: <Map<String, dynamic>>[_sessionJson()]),
        )!;
      await _pumpPage(tester, fake: fake);
      expect(
        find.byKey(const Key('topic-detail-manage-sessions')),
        findsOneWidget,
      );
    });

    testWidgets('普通成员:场次照看,但没有管理入口,也没有设置写权限', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(sessions: <Map<String, dynamic>>[_sessionJson()]),
        )!
        ..settingValue = _setting(canManage: false)
        ..statsValue = _stats(canDirect: false, canManageSessions: false);
      await _pumpPage(tester, fake: fake);

      expect(find.byKey(const Key('topic-detail-session-s1')), findsOneWidget);
      expect(
        find.byKey(const Key('topic-detail-manage-sessions')),
        findsNothing,
      );

      await _openMoreSheet(tester);
      expect(find.byKey(const Key('topic-setting-sheet')), findsOneWidget);
      expect(_switchEnabled(tester, const Key('topic-setting-coop')), isFalse);
      expect(find.byKey(const Key('topic-setting-end')), findsNothing);
      expect(find.byKey(const Key('topic-setting-sessions')), findsNothing);
    });
  });

  group('topic-detail:空态与失败态', () {
    testWidgets('没有场次 → 「接下来」整段不画,但页面其余照常', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      await _pumpPage(tester, fake: fake);

      expect(find.text('接下来'), findsNothing);
      expect(find.byKey(const Key('topic-detail-story')), findsOneWidget);
    });

    testWidgets('403 → 权限拒绝屏;网络失败 → 网络态可重试', (WidgetTester tester) async {
      final _FakeClubTopicOpsApi denied = _FakeClubTopicOpsApi()
        ..overviewError = _forbidden();
      await _pumpPage(tester, fake: denied);
      expect(find.text('你看不到这条活动'), findsOneWidget);

      final _FakeClubTopicOpsApi offline = _FakeClubTopicOpsApi()
        ..overviewError = _networkFailure();
      await _pumpPage(tester, fake: offline);
      expect(find.text('网络连接失败'), findsOneWidget);
      // 小程序的 retry 文案是「重新连接」——网络态说清重试的是连接。
      expect(find.text('重新连接'), findsOneWidget);
      expect(find.byKey(const Key('topic-detail-primary')), findsNothing);
    });

    // #258 域内口径:401 ≠ 无权限 ≠ 网络错。游客深链进主题详情(路由不在
    // _loginRequiredPrefixes),撞见的是后端 401,该给页内登录门,
    // 不该说「你看不到这条活动」让人以为永远没资格。
    testWidgets('游客 401 → 页内登录门,不冒充「没权限」也不指去查网络', (WidgetTester tester) async {
      final _FakeClubTopicOpsApi guest = _FakeClubTopicOpsApi()
        ..overviewError = _unauthorized();
      await _pumpPage(tester, fake: guest);
      expect(find.text('登录后查看活动详情'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('你看不到这条活动'), findsNothing);
      expect(find.text('网络连接失败'), findsNothing);
    });

    testWidgets('业务失败带后端原话,不当成没权限', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewError = ClubApiException('这个主题已经下架');
      await _pumpPage(tester, fake: fake);

      expect(find.text('活动暂时打不开'), findsOneWidget);
      expect(find.text('这个主题已经下架'), findsOneWidget);
      expect(find.text('你看不到这条活动'), findsNothing);
    });
  });

  group('topic-detail:更多半屏(设置)', () {
    testWidgets('三个开关一起提交,存不上拨回原位并说不成的原因', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!
        ..settingValue = _setting(coopOpen: false);
      await _pumpPage(tester, fake: fake);
      await _openMoreSheet(tester);

      expect(fake.settingCalls, 1);
      expect(_switchValue(tester, const Key('topic-setting-coop')), isFalse);

      await _reveal(
        tester,
        const Key('topic-setting-coop'),
        within: _inSheet(const Key('topic-setting-sheet')),
      );
      await tester.tap(_switchIn(const Key('topic-setting-coop')));
      await tester.pumpAndSettle();
      expect(fake.saves, hasLength(1));
      expect(fake.saves.single, <String, dynamic>{
        'clubId': 1,
        'topicId': 12,
        'coopOpen': true,
        'pinned': true,
        'memberOnly': false,
      });
      expect(_switchValue(tester, const Key('topic-setting-coop')), isTrue);

      fake.saveError = ClubApiException('当前岗位没有这个权限');
      await _reveal(
        tester,
        const Key('topic-setting-pinned'),
        within: _inSheet(const Key('topic-setting-sheet')),
      );
      await tester.tap(_switchIn(const Key('topic-setting-pinned')));
      await tester.pumpAndSettle();

      expect(find.text('当前岗位没有这个权限'), findsOneWidget);
      expect(
        _switchValue(tester, const Key('topic-setting-pinned')),
        isTrue,
        reason: '存不上就回原位,不留在新位置骗人',
      );
    });

    testWidgets('结束主题:有场次没退成 → 框不关并说清;再点一次成功才收尾', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!
        ..settingValue = _setting()
        ..endResponses.addAll(<Object>[
          const TopicEndResult(
            refundedOrders: 1,
            manualOrders: 0,
            failedSessions: <String>['9月20日 场次'],
          ),
          const TopicEndResult(
            refundedOrders: 2,
            manualOrders: 0,
            failedSessions: <String>[],
          ),
        ]);
      await _pumpPage(tester, fake: fake);
      await _openMoreSheet(tester);

      await _tapVisible(
        tester,
        const Key('topic-setting-end'),
        within: _inSheet(const Key('topic-setting-sheet')),
      );
      expect(
        find.byKey(const Key('topic-setting-end-confirm')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('topic-setting-end-confirm')));
      await tester.pumpAndSettle();

      expect(fake.endCalls, 1);
      expect(
        find.textContaining('1 场没能取消：9月20日 场次'),
        findsOneWidget,
        reason: '退款没退干净必须留在屏幕上,只报「已结束」会让主理人以为钱退完了',
      );
      expect(
        find.byKey(const Key('topic-setting-end-confirm')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('topic-setting-end-confirm')));
      await tester.pumpAndSettle();

      expect(fake.endCalls, 2);
      expect(find.byKey(const Key('topic-setting-end-confirm')), findsNothing);
      expect(find.text('已结束，退款 2 笔'), findsOneWidget);
      expect(fake.overviewCalls, 2, reason: '结束成功要回读整页');
    });

    testWidgets('章节行:开放承接传取反值,结束后回读;结束本章单独一条', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!
        ..settingValue = _setting(
          chapters: <TopicSettingChapter>[
            const TopicSettingChapter(
              id: 1,
              name: '第一章 · 古城',
              recruiting: false,
              category: '',
              merchantCount: 0,
              finishTime: '',
            ),
          ],
        );
      await _pumpPage(tester, fake: fake);
      await _openMoreSheet(tester);

      await _tapVisible(
        tester,
        const Key('topic-setting-chapter-1'),
        within: _inSheet(const Key('topic-setting-sheet')),
      );
      await tester.tap(
        find.byKey(const Key('topic-setting-chapter-recruit-1')),
      );
      await tester.pumpAndSettle();

      expect(fake.chapterRecruits, hasLength(1));
      expect(fake.chapterRecruits.single['chapterId'], 1);
      expect(fake.chapterRecruits.single['enabled'], isTrue);
      expect(fake.settingCalls, greaterThan(1), reason: '写完回读服务端值');

      await _tapVisible(
        tester,
        const Key('topic-setting-chapter-1'),
        within: _inSheet(const Key('topic-setting-sheet')),
      );
      await tester.tap(find.byKey(const Key('topic-setting-chapter-finish-1')));
      await tester.pumpAndSettle();

      expect(fake.chapterFinishes, hasLength(1));
      expect(fake.chapterFinishes.single['chapterId'], 1);
    });
  });

  group('topic-detail:商家与成员半屏', () {
    testWidgets('商家:OPEN 还在招商不进名单;未确认不给手机号也不给复制', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!
        ..recruitValue = RecruitOverview.tryFromJson(<String, dynamic>{
          'nodes': <Map<String, dynamic>>[
            <String, dynamic>{
              'nodeId': 1,
              'name': '钟楼',
              'merchantName': '还在招商的商家',
              'state': 'OPEN',
            },
            <String, dynamic>{
              'nodeId': 2,
              'name': '',
              'merchantName': '甲店',
              'phone': '18000000000',
              'state': 'ACCEPTED',
            },
            <String, dynamic>{
              'nodeId': 3,
              'name': '城墙',
              'merchantName': '乙店',
              'state': 'ACCEPTED',
            },
          ],
        })!;
      await _pumpPage(tester, fake: fake);

      await tester.tap(find.byKey(const Key('topic-detail-quick-merchant')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('topic-merchants-sheet')), findsOneWidget);
      expect(find.text('甲店'), findsOneWidget);
      expect(find.text('乙店'), findsOneWidget);
      expect(find.text('还在招商的商家'), findsNothing);
      expect(find.text('180****0000'), findsOneWidget);
      expect(find.textContaining('未确认，暂无联系方式'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
    });

    testWidgets('成员:三个统计数不随 chip 变,chip 就是服务端 filter', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!
        ..customersValue = TopicCustomers.tryFromJson(<String, dynamic>{
          'soldCount': 12,
          'pendingCount': 5,
          'verifiedCount': 7,
          'sessions': <Map<String, dynamic>>[
            <String, dynamic>{
              'timeText': '9月20日 14:00',
              'rows': <Map<String, dynamic>>[
                <String, dynamic>{
                  'key': 'u1',
                  'displayName': '阿明',
                  'phoneText': '180****0001',
                  'statusText': '待核销',
                },
              ],
            },
          ],
        })!;
      await _pumpPage(tester, fake: fake);

      await tester.tap(find.byKey(const Key('topic-detail-quick-customer')));
      await tester.pumpAndSettle();

      expect(fake.customerFilters, <String>['']);
      expect(find.byKey(const Key('topic-customers-sheet')), findsOneWidget);
      expect(find.text('已售 12'), findsOneWidget);
      expect(find.text('待核销 5'), findsOneWidget);
      expect(find.text('已核销 7'), findsOneWidget);
      expect(find.byKey(const Key('topic-customer-u1')), findsOneWidget);
      expect(find.text('阿明'), findsOneWidget);

      await tester.tap(find.byKey(const Key('topic-customers-chip-pending')));
      await tester.pumpAndSettle();

      expect(fake.customerFilters, <String>['', 'pending']);
      expect(find.text('已售 12'), findsOneWidget, reason: '统计数是全量口径,不随筛选变');

      // 空名单:给的是「这一档还没有人」,不是「这个主题没有成员」。
      fake.customersValue = TopicCustomers.tryFromJson(<String, dynamic>{
        'soldCount': 12,
        'pendingCount': 0,
        'verifiedCount': 7,
        'sessions': <List<dynamic>>[],
      })!;
      await tester.tap(find.byKey(const Key('topic-customers-chip-verified')));
      await tester.pumpAndSettle();
      expect(find.text('这一档还没有人'), findsOneWidget);
    });
  });

  group('topic-detail:导演台宿主态', () {
    /// 点确认弹层里的动作(页面上同名单键在 barrier 后面,必须限定在弹层里)。
    Future<void> confirmDialog(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    DioException networkDown() => DioException(
      requestOptions: RequestOptions(path: '/api/game/session/command'),
      type: DioExceptionType.connectionTimeout,
    );

    testWidgets('PREPARE:已确认态主键 → 确认弹层 → 发 PREPARE,成功后宿主页一起回读', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()
        ..projection = _directorProjection(
          status: 'NOT_PREPARED',
          revision: 0,
          actions: <String>['PREPARE'],
        );
      await _pumpPage(tester, fake: fake, director: director);

      // 主题本体是 preparing,但投影说 NOT_PREPARED → 六态跟着走「已确认」。
      expect(find.text('已确认'), findsOneWidget);
      expect(find.byKey(const Key('topic-detail-primary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('topic-detail-primary')));
      await tester.pumpAndSettle();
      expect(find.text('进入准备'), findsOneWidget);
      expect(find.text('进入后将开始收集站点和队伍 READY 状态。'), findsOneWidget);
      expect(director.submitted, isEmpty, reason: '确认之前一条都不发');

      await confirmDialog(tester, '开始准备');

      expect(director.submitted.single.action, 'PREPARE');
      expect(director.submitted.single.expectedRevision, 0);
      expect(fake.overviewCalls, 2, reason: 'refreshTick → 宿主页回读(核销数/场次在变)');
    });

    testWidgets('START:PREPARING 且没备齐 → 主键挡下,只说不行动;READY 备齐才发', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final notReady = _FakeClubDirectorGateway()
        ..projection = _directorProjection(
          status: 'PREPARING',
          actions: <String>['START'],
        );
      await _pumpPage(tester, fake: fake, director: notReady);

      // D1 准备总览在 preparing 态出,「开始活动」是禁用而不是消失(卡在哪要看得见)。
      expect(find.text('准备总览'), findsOneWidget);
      expect(
        tester
            .widget<CyNativeButton>(
              find.byKey(const Key('topic-director-d1-start')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('topic-detail-primary')));
      await tester.pumpAndSettle();
      expect(find.text('准备未完成，暂时不能开局'), findsOneWidget);
      expect(notReady.submitted, isEmpty);

      final ready = _FakeClubDirectorGateway()
        ..projection = _directorProjection(
          status: 'READY',
          actions: <String>['START'],
          club: <String, dynamic>{
            'readiness': <String, dynamic>{
              'requiredStations': 2,
              'readyStations': 2,
              'teamsReady': true,
            },
          },
        );
      final fake2 = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      await _pumpPage(tester, fake: fake2, director: ready);

      expect(
        tester
            .widget<CyNativeButton>(
              find.byKey(const Key('topic-director-d1-start')),
            )
            .onPressed,
        isNotNull,
      );
      await _tapVisible(tester, const Key('topic-director-d1-start'));
      await tester.pumpAndSettle();
      expect(find.text('确认开局'), findsOneWidget);
      await confirmDialog(tester, '开始活动');
      expect(ready.submitted.single.action, 'START');
    });

    testWidgets('FINISH:进行中主键「结束活动」→ 不可撤销话术 → 发 FINISH', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()
        ..projection = _directorProjection(actions: <String>['FINISH']);
      await _pumpPage(tester, fake: fake, director: director);

      await tester.tap(find.byKey(const Key('topic-detail-primary')));
      await tester.pumpAndSettle();
      expect(find.text('结束这场活动？'), findsOneWidget);
      expect(
        find.text('结束后不能再核销、不能再改队伍与角色;已产生的结算事实会保留。此操作不可撤销。'),
        findsOneWidget,
      );
      await confirmDialog(tester, '结束活动');

      expect(director.submitted.single.action, 'FINISH');
      expect(fake.overviewCalls, 2);
    });

    testWidgets('unknown-write:断网回执未到 → 锁条出「核对结果/重试原操作」;核对不重发', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()
        ..projection = _directorProjection(actions: <String>['FINISH'])
        ..outcomes.add(networkDown());
      await _pumpPage(tester, fake: fake, director: director);

      await tester.tap(find.byKey(const Key('topic-detail-primary')));
      await tester.pumpAndSettle();
      await confirmDialog(tester, '结束活动');

      expect(find.byKey(const Key('director-unknown-title')), findsOneWidget);
      expect(find.text('结果待核对'), findsOneWidget);
      expect(find.text('请求结果待核对，核对前已锁定全部写操作'), findsOneWidget);
      expect(find.text('核对结果'), findsOneWidget);
      expect(find.text('重试原操作'), findsOneWidget);

      await _tapVisible(tester, const Key('director-unknown-reconcile'));

      expect(find.text('结果已确认'), findsOneWidget);
      expect(director.submitted, hasLength(1), reason: '核对是回读,绝不重发原命令');
      expect(
        find.byKey(const Key('director-unknown-title')),
        findsNothing,
        reason: '收敛完成,锁条不占位',
      );
    });

    testWidgets('重试原操作:同 requestId 重放;再断就还锁着', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()
        ..projection = _directorProjection(actions: <String>['FINISH'])
        ..outcomes.add(networkDown())
        ..outcomes.add(networkDown());
      await _pumpPage(tester, fake: fake, director: director);

      await tester.tap(find.byKey(const Key('topic-detail-primary')));
      await tester.pumpAndSettle();
      await confirmDialog(tester, '结束活动');
      final String original = director.submitted.single.requestId;

      await _tapVisible(tester, const Key('director-unknown-retry'));

      expect(director.submitted, hasLength(2));
      expect(director.submitted.last.requestId, original, reason: '重放必须用原请求号');
      expect(find.text('重试结果仍待核对，写操作继续锁定'), findsOneWidget);
      expect(find.byKey(const Key('director-unknown-title')), findsOneWidget);
    });

    testWidgets('投影说「已取消」:胶囊改「已取消」、核销区收掉、主键进结算', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(status: 'running'),
        )!;
      final director = _FakeClubDirectorGateway()
        ..projection = _directorProjection(
          status: 'CANCELLED',
          actions: <String>[],
        );
      await _pumpPage(tester, fake: fake, director: director);

      expect(find.text('已取消'), findsOneWidget);
      expect(find.text('核销'), findsNothing, reason: '取消的场没有要核销的票');
      expect(find.text('查看结算报告'), findsOneWidget);
    });

    testWidgets('工具条按各自的闸出:解锁/队伍/角色三件齐,现场事件没行就不出', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()
        ..projection = _directorProjection(
          actions: <String>['UNLOCK_CHAPTER', 'ASSIGN_ROLES'],
          club: <String, dynamic>{
            'readiness': <String, dynamic>{'requiredStations': 0},
            'chapterOptions': <Map<String, dynamic>>[
              <String, dynamic>{'chapterId': 2, 'title': '第二章'},
            ],
            'teams': <Map<String, dynamic>>[
              <String, dynamic>{'teamId': 5, 'name': '红队'},
            ],
            'roleOptions': <Map<String, dynamic>>[
              <String, dynamic>{'roleCode': 'LEADER', 'roleName': '队长'},
            ],
            'roles': <Map<String, dynamic>>[
              <String, dynamic>{
                'teamId': 5,
                'memberId': 11,
                'memberName': '阿岚',
              },
            ],
          },
        );
      await _pumpPage(tester, fake: fake, director: director);

      // 工具条在页尾,懒列表里没滚到就不构建。
      await tester.scrollUntilVisible(
        find.byKey(const Key('director-tool-unlock')),
        300,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('director-tool-unlock')), findsOneWidget);
      expect(find.byKey(const Key('director-tool-teams')), findsOneWidget);
      expect(find.byKey(const Key('director-tool-roles')), findsOneWidget);
      expect(
        find.byKey(const Key('director-tool-incidents')),
        findsNothing,
        reason: '没有暂停/积压/待审/被驳回的行,事件入口就是空话',
      );

      // 最小投影:一个工具都不亮,整条不画。
      final bare = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      await _pumpPage(
        tester,
        fake: bare,
        director: _FakeClubDirectorGateway()
          ..projection = _directorProjection(actions: <String>[]),
      );
      expect(find.byKey(const Key('director-tool-unlock')), findsNothing);
      expect(find.byKey(const Key('director-tool-teams')), findsNothing);
    });

    testWidgets('导演台读挂了要能原地重试,不拖垮整页(连接失败态)', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()..loadError = networkDown();
      await _pumpPage(tester, fake: fake, director: director);

      expect(
        find.byKey(const Key('topic-detail-story')),
        findsOneWidget,
        reason: '主题本体照常渲染,失败只落在导演台那一格',
      );
      expect(find.text('网络连接失败'), findsWidgets);
      expect(find.text('重新连接'), findsOneWidget);

      director.loadError = null;
      director.projection = _directorProjection();
      await tester.tap(find.text('重新连接'));
      await tester.pumpAndSettle();

      expect(find.text('重新连接'), findsNothing, reason: '重试成功后格子回到就绪态');
      expect(director.loadCalls, greaterThanOrEqualTo(2));
    });

    testWidgets('导演台读遇 401(登录过期)→ 格子里出登录引导,不说「暂时无法打开」', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()..loadError = _unauthorized();
      await _pumpPage(tester, fake: fake, director: director);

      expect(
        find.byKey(const Key('topic-detail-story')),
        findsOneWidget,
        reason: '页面本体照常,只有导演台格子换成登录引导',
      );
      expect(find.text('登录后查看活动导演台'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('导演台读取失败'), findsNothing);
      expect(find.text('网络连接失败'), findsNothing);
    });

    testWidgets('导演台真业务错(非 401)仍走原口径:读取失败 + 后端原话', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      final director = _FakeClubDirectorGateway()
        ..loadError = const GameSessionContractException(
          '这一局没给导演权限',
          reasonCode: 'OWNER_REQUIRED',
        );
      await _pumpPage(tester, fake: fake, director: director);

      expect(find.text('导演台读取失败'), findsOneWidget);
      expect(find.text('这一局没给导演权限'), findsOneWidget);
      expect(find.text('登录后查看活动导演台'), findsNothing);
    });
  });

  group('topic-detail:出站 push 带参', () {
    testWidgets('「台账」与「管理场次」都带着本主题 topicId 出站', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(
            status: 'running',
            sessions: <Map<String, dynamic>>[_sessionJson()],
          ),
        )!;
      final GoRouter router = await _pumpRouted(tester, fake);

      // 真源 goLedger(js:641-644)带 clubId&topicId → enroll E-07 到达即展开本团。
      await tester.tap(find.byKey(const Key('topic-detail-ledger')));
      await tester.pumpAndSettle();
      expect(find.text('enroll-12'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      // 真源 goEventOps(js:635-639)带 topicId → event-ops E-07 预选本主题。
      await tester.tap(find.byKey(const Key('topic-detail-manage-sessions')));
      await tester.pumpAndSettle();
      expect(find.text('event-ops-12'), findsOneWidget);
      router.dispose();
    });
  });

  group('a2 入口接线:点得到且带得上下级 id', () {
    testWidgets('台账/管理场次/编辑主题分别带 topicId 或 id 落到目标页', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(
            status: 'running',
            sessions: <Map<String, dynamic>>[_sessionJson()],
          ),
        )!
        ..settingValue = const TopicSetting(
          topicName: '静安夜行',
          lifecycleText: '进行中',
          coopOpen: true,
          pinned: false,
          memberOnly: false,
          canManage: true,
          chapters: <TopicSettingChapter>[],
        );
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      final router = GoRouter(
        initialLocation: '/club/1/topic/12',
        routes: <RouteBase>[
          GoRoute(
            path: '/club/1/topic/12',
            builder: (_, _) => ClubTopicDetailPage(
              key: ObjectKey(fake),
              clubId: 1,
              topicId: 12,
              activityId: 41,
            ),
          ),
          GoRoute(
            path: '/club/:id/enroll',
            builder: (_, state) => Scaffold(
              body: Text(
                'enroll|${state.uri.queryParameters['topicId'] ?? '-'}',
              ),
            ),
          ),
          GoRoute(
            path: '/club/:id/event-ops',
            builder: (_, state) => Scaffold(
              body: Text('ops|${state.uri.queryParameters['topicId'] ?? '-'}'),
            ),
          ),
          GoRoute(
            path: '/publish/pro',
            builder: (_, state) => Scaffold(
              body: Text('publish|${state.uri.queryParameters['id'] ?? '-'}'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            signedInAuthOverride(role: 'club'),
            clubTopicOpsApiProvider.overrideWithValue(fake),
            // main 的详情页多了导演台宿主态,不挡这两个 provider 会一直重试。
            clubDirectorApiProvider.overrideWithValue(
              _FakeClubDirectorGateway(),
            ),
            clubDirectorPendingStoreProvider.overrideWith(
              (ref) => ClubDirectorPendingStore.memory(),
            ),
          ].cast(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 核销区的「台账」→ 报名名册,必须带 topicId(否则整团名册空白)。
      await _tapVisible(tester, const Key('topic-detail-ledger'));
      expect(find.text('enroll|12'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      // 「管理场次」→ 活动运营,必须预选这条主题。
      await _tapVisible(tester, const Key('topic-detail-manage-sessions'));
      expect(find.text('ops|12'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      // 「更多 → 编辑主题内容」→ 发布页认 `?id=`,推 `topicId` 会落空白新建。
      await _openMoreSheet(tester);
      await tester.tap(find.byKey(const Key('topic-setting-edit')));
      await tester.pumpAndSettle();
      expect(find.text('publish|12'), findsOneWidget);
      router.dispose();
    });
  });
}
