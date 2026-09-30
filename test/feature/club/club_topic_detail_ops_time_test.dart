// 导演台 · 集合时间(小程序 HO-26 `pages/club/topic-detail` 的 `.ctd-opstime`):
// 入口条件、半屏保存 → `POST /api/club/lead/edit-ops` 的请求契约,以及三路结果。
//
// ★ 为什么要一条行为门:这条端点在 App 侧**曾经完全没有落点**(端点裁判 46 条
//   未解释缺口里唯一没人接的一条),而小程序真源里它是一个有闸、有校验、
//   有三种失败口径的写动作 —— 只判「路径字符串在不在 lib/ 里」会漏掉整件事。
//
// 真源:`pages/club/topic-detail/index.js` 的 `_opsTimeMatch` / `openOpsTimeSheet`
//   / `confirmOpsTime` + `index.wxml` 的 `.ctd-opstime` 与 `cy-scene-sheet`。
//
// 接线口径(与 `club_topic_manage_stats_test.dart` 同一张真源表):
//   · 闸在 manageStats 的 `canDirect` + `_directorActivityId`(带 activityId 进来
//     就是这一场;没有且不止一场 → 不猜、不画);
//   · 保存 = `ClubTopicOpsApi.editOps(activityId, 秒级 startDate)`;
//   · 4xx = 明确拒绝(后端原文回显、不回读);5xx / 传输失败 = 结果未知
//     (说「结果待确认」并回读)。
// 本文件另钉住 `ClubLeadApi.editOpsTime` 的请求编码契约(同一端点的领队封装)。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_lead_api.dart';
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
  List<Map<String, dynamic>> activities = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': 12,
  'name': '静安夜行',
  'status': 'preparing',
  'chapterCount': 2,
  'nodeCount': 7,
  'gameConfiguredCount': 3,
  'storyReady': true,
  'playModeText': '经典定向',
  'startDate': '2026-09-01 19:00:00',
  'endDate': '2026-09-30 22:00:00',
  'sessions': const <Map<String, dynamic>>[],
  'activityList': activities,
};

Map<String, dynamic> _activity({
  int id = 41,
  String startDate = '2026-09-20 14:00:00',
}) => <String, dynamic>{'id': id, 'name': '9月20日场', 'startDate': startDate};

ClubTopicManageStats _stats({bool canDirect = true}) => ClubTopicManageStats(
  canDirect: canDirect,
  canManageSessions: canDirect,
  canViewVerify: canDirect,
  nodeCount: 7,
  sessionHeadcount: 9,
  pendingVerifyCount: 2,
  verifiedByMeCount: 1,
);

class _FakeTopicOpsApi extends ClubTopicOpsApi {
  _FakeTopicOpsApi() : super(_dummyDioClient());

  ClubTopicOverview overviewValue = ClubTopicOverview.tryFromJson(
    _overviewJson(),
  )!;
  int overviewCalls = 0;

  ClubTopicManageStats statsValue = _stats();

  final List<Map<String, dynamic>> editOpsCalls = <Map<String, dynamic>>[];
  Object? editOpsError;

  @override
  Future<ClubTopicOverview> overview(int topicId) async {
    overviewCalls += 1;
    return overviewValue;
  }

  @override
  Future<ClubTopicManageStats> manageStats({
    required int clubId,
    required int topicId,
    int? activityId,
  }) async => statsValue;

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
/// 集合时间格的闸(真源 `loadState === 'ready'`)要过。写动作不在这里演。
class _ReadyDirector implements ClubDirectorGateway {
  _ReadyDirector(this.projection);

  ClubDirectorProjection projection;

  @override
  Future<ClubDirectorProjection> loadClubProjection({
    required int activityId,
  }) async => projection;

  @override
  Future<GameSessionReceipt> submitClubCommand(
    GameSessionCommand command,
  ) async => GameSessionReceipt(
    activityId: command.activityId,
    requestId: command.requestId,
    action: command.action,
    outcome: GameReceiptOutcome.applied,
    receiptId: 'r-${command.requestId}',
    revision: 99,
  );

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
  required _FakeTopicOpsApi ops,
  int? activityId = 41,
  bool canDirect = true,
}) async {
  ops.statsValue = _stats(canDirect: canDirect);
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        clubTopicOpsApiProvider.overrideWithValue(ops),
        clubDirectorApiProvider.overrideWithValue(
          _ReadyDirector(_directorProjection()),
        ),
        clubDirectorPendingStoreProvider.overrideWith(
          (ref) => ClubDirectorPendingStore.memory(),
        ),
      ].cast(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ClubTopicDetailPage(
          key: ObjectKey(ops),
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
  tearDown(CyNativeNotice.hide);

  group('集合时间入口:条件不成立就整格不画', () {
    testWidgets('带 activityId + 能管场次:出「集合时间」一格,值是这一场的集合时间', (
      WidgetTester tester,
    ) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(activities: <Map<String, dynamic>>[_activity()]),
        )!;
      await _pumpPage(tester, ops: ops);

      expect(find.byKey(const Key('topic-ops-time')), findsOneWidget);
      expect(find.text('集合时间'), findsOneWidget);
      expect(find.text('9月20日 14:00'), findsOneWidget);
      expect(find.byKey(const Key('topic-ops-time-edit')), findsOneWidget);
    });

    testWidgets('集合时间解析不出来:不画那一格(不兜底成 1970)', (WidgetTester tester) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(
            activities: <Map<String, dynamic>>[_activity(startDate: '')],
          ),
        )!;
      await _pumpPage(tester, ops: ops);

      expect(find.byKey(const Key('topic-ops-time')), findsNothing);
    });

    testWidgets('普通成员(不能管场次、又不是从场次进来):不画那一格', (WidgetTester tester) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(activities: <Map<String, dynamic>>[_activity()]),
        )!;
      await _pumpPage(tester, ops: ops, activityId: null, canDirect: false);

      expect(find.byKey(const Key('topic-ops-time')), findsNothing);
      expect(find.text('集合时间'), findsNothing);
    });

    testWidgets('主题下不止一场、又没带 activityId:不猜是哪一场,不画', (
      WidgetTester tester,
    ) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(
            activities: <Map<String, dynamic>>[
              _activity(),
              _activity(id: 42, startDate: '2026-09-21 14:00:00'),
            ],
          ),
        )!;
      await _pumpPage(tester, ops: ops, activityId: null);

      expect(find.byKey(const Key('topic-ops-time')), findsNothing);
    });
  });

  group('集合时间半屏:保存 → /api/club/lead/edit-ops', () {
    testWidgets('半屏带小程序原文的两句提示 + 预填当前时刻', (WidgetTester tester) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(activities: <Map<String, dynamic>>[_activity()]),
        )!;
      await _pumpPage(tester, ops: ops);
      await _tapVisible(tester, const Key('topic-ops-time-edit'));

      expect(find.byKey(const Key('topic-ops-time-sheet')), findsOneWidget);
      expect(find.text('修改集合时间'), findsOneWidget);
      expect(find.text('已有人报名或下单的场次，集合时间和地点不能再改（当日备注仍可改）。'), findsOneWidget);
      expect(find.text('改完会报备发起人；退款截止按新的集合时间前 24 小时计算。'), findsOneWidget);
      expect(find.text('2026-09-20'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
    });

    testWidgets('保存:activityId + 这一场的时刻(补 :00),成功后关半屏回读真源', (
      WidgetTester tester,
    ) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(activities: <Map<String, dynamic>>[_activity()]),
        )!;
      await _pumpPage(tester, ops: ops);
      await _tapVisible(tester, const Key('topic-ops-time-edit'));
      await tester.tap(find.byKey(const Key('topic-ops-time-save')));
      await tester.pumpAndSettle();

      expect(ops.editOpsCalls, <Map<String, dynamic>>[
        <String, dynamic>{'activityId': 41, 'startDate': '2026-09-20 14:00:00'},
      ]);
      expect(find.textContaining('集合时间已更新'), findsOneWidget);
      expect(find.byKey(const Key('topic-ops-time-sheet')), findsNothing);
      expect(
        ops.overviewCalls,
        2,
        reason: '改完必须回读真源 —— 新时间从服务端 activityList 重取,不在本地先改',
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('回读后显示服务端新时间(不是本地草稿)', (WidgetTester tester) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(activities: <Map<String, dynamic>>[_activity()]),
        )!;
      await _pumpPage(tester, ops: ops);

      ops.overviewValue = ClubTopicOverview.tryFromJson(
        _overviewJson(
          activities: <Map<String, dynamic>>[
            _activity(startDate: '2026-09-20 18:30:00'),
          ],
        ),
      )!;
      await _tapVisible(tester, const Key('topic-ops-time-edit'));
      await tester.tap(find.byKey(const Key('topic-ops-time-save')));
      await tester.pumpAndSettle();

      expect(find.text('9月20日 18:30'), findsOneWidget);
      expect(find.text('9月20日 14:00'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('后端明确拒绝(4xx):原话进提示,不回读', (WidgetTester tester) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(activities: <Map<String, dynamic>>[_activity()]),
        )!
        ..editOpsError = _dioFailure(
          path: '/api/club/lead/edit-ops',
          status: 400,
          data: <String, dynamic>{'msg': '该场次已售出，集合时间与地点不能修改；当日备注仍可改'},
        );
      await _pumpPage(tester, ops: ops);
      await _tapVisible(tester, const Key('topic-ops-time-edit'));
      await tester.tap(find.byKey(const Key('topic-ops-time-save')));
      await tester.pumpAndSettle();

      expect(
        find.text('集合时间没改成\n该场次已售出，集合时间与地点不能修改；当日备注仍可改'),
        findsOneWidget,
        reason: '后端原话写给主理人看的,不许改写成自己的话',
      );
      expect(ops.overviewCalls, 1, reason: '明确拒绝 = 一定没改成功,不必回读');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('传输失败:不谎报「没改成」,关半屏回读让页面显示服务端真相', (WidgetTester tester) async {
      final ops = _FakeTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(activities: <Map<String, dynamic>>[_activity()]),
        )!
        ..editOpsError = _dioFailure(path: '/api/club/lead/edit-ops');
      await _pumpPage(tester, ops: ops);
      await _tapVisible(tester, const Key('topic-ops-time-edit'));
      await tester.tap(find.byKey(const Key('topic-ops-time-save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('网络异常，结果待确认'), findsOneWidget);
      expect(find.byKey(const Key('topic-ops-time-sheet')), findsNothing);
      expect(ops.overviewCalls, 2, reason: '写结果未知时,页面上显示的必须是服务端真相');
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('request 契约:JSON body 不是表单', () {
    test(
      'POST /api/club/lead/edit-ops,JSON + {activityId, startDate}',
      () async {
        final List<RequestOptions> seen = <RequestOptions>[];
        final DioClient client = DioClient(
          TokenStore(const FlutterSecureStorage()),
        );
        client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
          seen.add(options);
          return <String, dynamic>{'code': 200, 'msg': '已更新并报备发起人'};
        });

        await ClubLeadApi(
          client,
        ).editOpsTime(activityId: 41, startDate: '2026-09-20 14:00:00');

        expect(seen, hasLength(1));
        expect(seen.single.path, '/api/club/lead/edit-ops');
        expect(seen.single.method, 'POST');
        expect(
          seen.single.contentType,
          Headers.jsonContentType,
          reason: '后端是 @RequestBody Map:发成表单会 415 且行为完全静默',
        );
        expect(seen.single.data, <String, dynamic>{
          'activityId': 41,
          'startDate': '2026-09-20 14:00:00',
        });
      },
    );

    test('后端拒绝原话照抛(4xx 是明确拒绝,不当成功)', () async {
      final DioClient client = DioClient(
        TokenStore(const FlutterSecureStorage()),
      );
      client.dio.httpClientAdapter = _StubAdapter(
        (RequestOptions options) => <String, dynamic>{
          'code': 500,
          'msg': '只有承接方领队可改运营详情',
        },
      );

      await expectLater(
        ClubLeadApi(
          client,
        ).editOpsTime(activityId: 41, startDate: '2026-09-20 14:00:00'),
        throwsA(
          isA<ClubApiException>().having(
            (ClubApiException e) => e.message,
            'message',
            '只有承接方领队可改运营详情',
          ),
        ),
      );
    });
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);
  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(onRequest(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
