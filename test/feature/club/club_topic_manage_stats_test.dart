// 主题详情的**管理向统计**(拍板1,2026-09-17)与 HO-26 改集合时间的行为门。
//
// 判据对齐小程序 pages/club/topic-detail(@7bdeb58de):
//   - 带 clubId 进页就并发拉 `/api/club/crm/topic-manage-stats`;它失败 = 整页失败,
//     重试把详情与统计**一起**重发(不降级成「看起来是普通成员」);
//   - 三个身份各读各的:canDirect(导演台写动作)/ canManageSessions(场次管理)/
//     canViewVerify(核销区);没有那个字段就不出那块界面;
//   - 唯一一场 + canDirect → 自动接管,统计按这一场**重拉一次**(本场人数/待核销换口径);
//   - 集合时间(HO-26):真源是 activityList 里这一场的 startDate,拿不到合法时间不出这一格;
//     保存 = `POST /api/club/lead/edit-ops`(秒级 startDate);4xx = 明确拒绝
//     (后端原文回显、不回读),5xx 与传输失败 = 结果未知(说「结果待确认」并回读)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/club_director.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/feature/club/club_director_controller.dart';
import 'package:chengyin_app/feature/club/club_topic_detail_page.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

DioException _dioFailure({required String path, int? status, Object? data}) =>
    DioException(
      requestOptions: RequestOptions(path: path),
      type: status == null
          ? DioExceptionType.connectionError
          : DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response<Object?>(
              requestOptions: RequestOptions(path: path),
              statusCode: status,
              data: data,
            ),
    );

Map<String, dynamic> _overviewJson({
  String status = 'preparing',
  int chapterCount = 2,
  int nodeCount = 7,
  List<Map<String, dynamic>> activities = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': 12,
  'name': '静安夜行',
  'status': status,
  'chapterCount': chapterCount,
  'nodeCount': nodeCount,
  'gameConfiguredCount': 3,
  'storyReady': true,
  'playModeText': '经典定向',
  'startDate': '2026-09-01 19:00:00',
  'endDate': '2026-09-30 22:00:00',
  'sessions': const <Map<String, dynamic>>[],
  'activityList': activities,
};

ClubTopicManageStats _stats({
  bool canDirect = true,
  bool canManageSessions = true,
  bool canViewVerify = true,
}) => ClubTopicManageStats(
  canDirect: canDirect,
  canManageSessions: canManageSessions,
  canViewVerify: canViewVerify,
  nodeCount: 7,
  sessionHeadcount: 9,
  pendingVerifyCount: 2,
  verifiedByMeCount: 1,
);

class _FakeClubTopicOpsApi extends ClubTopicOpsApi {
  _FakeClubTopicOpsApi() : super(_dummyDioClient());

  ClubTopicOverview? overviewValue;
  Object? overviewError;
  int overviewCalls = 0;

  ClubTopicManageStats? statsValue;
  Object? statsError;
  final List<Map<String, dynamic>> statsCalls = <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> editOpsCalls = <Map<String, dynamic>>[];
  Object? editOpsError;

  @override
  Future<ClubTopicOverview> overview(int topicId) async {
    overviewCalls += 1;
    if (overviewError != null) throw overviewError!;
    return overviewValue!;
  }

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
}

/// 导演台网关:默认回一张「准备中」的投影 —— 本页 canDirect 时导演台必挂,
/// 集合时间格的闸(真源 `loadState === 'ready'`)要过。写动作在文件级用例里演,
/// 这里不出命令出口。
class _ReadyDirector implements ClubDirectorGateway {
  _ReadyDirector(this.projection);

  ClubDirectorProjection projection;
  final List<GameSessionCommand> submitted = <GameSessionCommand>[];
  final List<Object> outcomes = <Object>[];

  @override
  Future<ClubDirectorProjection> loadClubProjection({
    required int activityId,
  }) async => projection;

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
    return GameSessionReceipt(
      activityId: command.activityId,
      requestId: command.requestId,
      action: command.action,
      outcome: GameReceiptOutcome.applied,
      receiptId: 'r-${command.requestId}',
      revision: 99,
    );
  }

  @override
  Future<GameSessionReceipt> readClubReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async => GameSessionReceipt(
    activityId: activityId,
    requestId: requestId,
    action: expectedAction,
    outcome: GameReceiptOutcome.applied,
    receiptId: 'r-$requestId',
    revision: 99,
  );
}

ClubDirectorProjection _directorProjection({String status = 'PREPARING'}) =>
    ClubDirectorProjection.fromJson(<String, dynamic>{
      'perspective': 'CLUB',
      'status': status,
      'revision': 1,
      'activityId': 41,
      'availableActions': const <String>['PREPARE'],
      'club': <String, dynamic>{
        'readiness': <String, dynamic>{
          'requiredStations': 0,
          'readyStations': 0,
          'teamsReady': false,
        },
      },
    });

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeClubTopicOpsApi fake,
  int? activityId = 41,
  _ReadyDirector? director,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        clubTopicOpsApiProvider.overrideWithValue(fake),
        clubDirectorApiProvider.overrideWithValue(
          director ?? _ReadyDirector(_directorProjection()),
        ),
        clubDirectorPendingStoreProvider.overrideWith(
          (ref) => ClubDirectorPendingStore.memory(),
        ),
      ].cast(),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        debugShowCheckedModeBanner: false,
        home: ClubTopicDetailPage(
          key: ObjectKey(fake),
          clubId: 1,
          topicId: 12,
          activityId: activityId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 集合时间那一格在页尾:先滚进视口再点。
Future<void> _tapVisible(WidgetTester tester, Key key) async {
  if (find.byKey(key).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.byKey(key), 300);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('统计失败 → 整页失败(不装作普通成员);重试把两条一起重发', (WidgetTester tester) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!
      ..statsError = _dioFailure(path: '/api/club/crm/topic-manage-stats');
    await _pumpPage(tester, fake: fake);

    expect(fake.overviewCalls, 1);
    expect(fake.statsCalls, hasLength(1));
    expect(find.text('网络连接失败'), findsOneWidget, reason: '统计拉不到不能降级成普通成员视角');
    expect(find.text('重新连接'), findsOneWidget);
    expect(find.byKey(const Key('topic-detail-primary')), findsNothing);

    fake.statsError = null;
    await tester.tap(find.text('重新连接'));
    await tester.pumpAndSettle();

    expect(fake.overviewCalls, 2);
    expect(fake.statsCalls, hasLength(2), reason: '重试 = 详情 + 统计一起重发');
    expect(
      find.byKey(const Key('topic-detail-story')),
      findsOneWidget,
      reason: '整页回到 ready',
    );
  });

  testWidgets('只有 canViewVerify:出核销区,不出场次管理、不出导演台写动作', (
    WidgetTester tester,
  ) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(
        _overviewJson(
          status: 'running',
          activities: <Map<String, dynamic>>[
            <String, dynamic>{'id': 41, 'name': '周六场'},
          ],
        ),
      )!
      ..statsValue = _stats(canDirect: false, canManageSessions: false);
    await _pumpPage(tester, fake: fake);

    expect(find.text('核销'), findsOneWidget);
    expect(find.text('待核销'), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: '核销三格的数由统计下发');
    expect(
      find.byKey(const Key('topic-detail-manage-sessions')),
      findsNothing,
      reason: 'canManageSessions 缺席就不出场次管理入口',
    );
    expect(
      find.byKey(const Key('topic-detail-primary')),
      findsNothing,
      reason: '不是这一场的导演,连状态流转主键都不给',
    );
  });

  testWidgets('能管场次但没带 activityId → 主键退到「去选一场」,统计照传 null', (
    WidgetTester tester,
  ) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(
        _overviewJson(
          activities: <Map<String, dynamic>>[
            <String, dynamic>{'id': 41, 'name': '周六场'},
            <String, dynamic>{'id': 42, 'name': '周日场'},
          ],
        ),
      )!
      ..statsValue = _stats(canDirect: false);
    await _pumpPage(tester, fake: fake, activityId: null);

    expect(
      fake.statsCalls.single['activityId'],
      isNull,
      reason: '没有这一场就照传 null,不省键',
    );
    expect(find.text('去选一场'), findsOneWidget);
  });

  testWidgets('唯一一场 + canDirect:自动接管,统计按这一场重拉;集合时间格照 startDate 出', (
    WidgetTester tester,
  ) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(
        _overviewJson(
          activities: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 41,
              'name': '周六场',
              'startDate': '2026-09-20 14:30:00',
            },
          ],
        ),
      )!;
    await _pumpPage(tester, fake: fake, activityId: null);

    expect(
      fake.statsCalls,
      hasLength(2),
      reason: 'maybeEnterDirector:唯一一场要按它重拉一次',
    );
    expect(fake.statsCalls.first['activityId'], isNull);
    expect(fake.statsCalls.last['activityId'], 41);
    expect(find.byKey(const Key('topic-ops-time')), findsOneWidget);
    expect(find.text('9月20日 14:30'), findsOneWidget);
  });

  testWidgets('改集合时间:保存 = editOps(activityId, 秒级 startDate),成功回读整页', (
    WidgetTester tester,
  ) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(
        _overviewJson(
          activities: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 41,
              'name': '周六场',
              'startDate': '2026-09-20 14:30:00',
            },
          ],
        ),
      )!;
    await _pumpPage(tester, fake: fake);
    await _tapVisible(tester, const Key('topic-ops-time-edit'));

    expect(find.byKey(const Key('topic-ops-time-sheet')), findsOneWidget);
    expect(
      find.text('已有人报名或下单的场次，集合时间和地点不能再改（当日备注仍可改）。'),
      findsOneWidget,
      reason: '已售锁定是后端判的,半屏先把规则说在前面',
    );

    await tester.tap(find.byKey(const Key('topic-ops-time-save')));
    await tester.pumpAndSettle();

    expect(fake.editOpsCalls.single, <String, dynamic>{
      'activityId': 41,
      'startDate': '2026-09-20 14:30:00',
    });
    expect(find.byKey(const Key('topic-ops-time-sheet')), findsNothing);
    expect(find.text('集合时间已更新\n已报备发起人；退款截止按新的集合时间前 24 小时计算。'), findsOneWidget);
    expect(fake.overviewCalls, 2, reason: '新时间从服务端回读,不在本地先改');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('后端明确拒绝(4xx):原样回显后端文案,不回读', (WidgetTester tester) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(
        _overviewJson(
          activities: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 41,
              'name': '周六场',
              'startDate': '2026-09-20 14:30:00',
            },
          ],
        ),
      )!
      ..editOpsError = _dioFailure(
        path: '/api/club/lead/edit-ops',
        status: 400,
        data: <String, dynamic>{'msg': '已有人报名或下单的场次，集合时间和地点不能再改'},
      );
    await _pumpPage(tester, fake: fake);
    await _tapVisible(tester, const Key('topic-ops-time-edit'));
    await tester.tap(find.byKey(const Key('topic-ops-time-save')));
    await tester.pumpAndSettle();

    expect(find.text('集合时间没改成\n已有人报名或下单的场次，集合时间和地点不能再改'), findsOneWidget);
    expect(fake.overviewCalls, 1, reason: '明确拒绝 = 没改成,不用回读');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('5xx / 传输失败:标「结果待确认」并回读', (WidgetTester tester) async {
    for (final ({Object error, String copy}) case_
        in <({Object error, String copy})>[
          (
            error: _dioFailure(path: '/api/club/lead/edit-ops', status: 503),
            copy: '集合时间没改成\n服务暂时不可用，结果待确认；已重新读取当前时间',
          ),
          (
            error: _dioFailure(path: '/api/club/lead/edit-ops'),
            copy: '集合时间没改成\n网络异常，结果待确认；已重新读取当前时间',
          ),
        ]) {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(
            activities: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 41,
                'name': '周六场',
                'startDate': '2026-09-20 14:30:00',
              },
            ],
          ),
        )!
        ..editOpsError = case_.error;
      await _pumpPage(tester, fake: fake);
      await _tapVisible(tester, const Key('topic-ops-time-edit'));
      await tester.tap(find.byKey(const Key('topic-ops-time-save')));
      await tester.pumpAndSettle();

      expect(find.text(case_.copy), findsOneWidget);
      expect(fake.overviewCalls, 2, reason: '结果未知要回读服务端真相');
      await tester.pump(const Duration(seconds: 3));
    }
  });
}
