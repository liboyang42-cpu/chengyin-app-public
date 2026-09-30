// 活动运营页(event-ops)的负控门:三类权限面、系列表单校验、本场取消的
// 「原因 → 二次确认 → 独立回读」三段式、名册与出勤更正的幂等。
//
// 判据对齐小程序 pages/club/event-ops(@90e66d70):
//   - `club:activity:manage` 管系列与取消;`club:event:checkin` 管名册与更正,
//     且必须带 activityId;两者都没有 → 无权限屏;
//   - 集合时刻是退款钟锚点;取消原因 2–255 字,成功后必须**独立回读** occurrence/status,
//     回读不确认 → readback-error,可重试回读;
//   - 出勤更正 requestId 幂等:网络失败复用同一键,4xx 明确失败才丢。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dio/dio.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/feature/club/club_event_ops_page.dart';
import 'package:chengyin_app/feature/club/club_ops_access.dart';

/// 原生输入弹窗在测试里退成 Cupertino Alert,输入框固定这个 key。
const Key _reasonFieldKey = Key('cy-system-input-alert-field');

Widget _app(Widget home, List<dynamic> overrides) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

ClubOpsAccess _access({
  bool manage = true,
  bool checkin = false,
  bool active = true,
  int clubId = 1,
}) => ClubOpsAccess(
  activeDeclared: true,
  active: active,
  clubId: clubId,
  permissions: <String>{
    if (manage) kClubActivityManage,
    if (checkin) kClubEventCheckin,
  },
  roleCodes: const <String>['CLUB_OWNER'],
  canManageRoles: true,
);

ClubMember _member(int id, String nick, {bool owner = false}) =>
    ClubMember(memberId: id, nickname: nick, isOwner: owner);

EventSeries _series({
  int id = 7,
  int version = 3,
  String recurrence = 'WEEKLY',
  int? capacity,
  bool waitlist = true,
  int offerMinutes = 1440,
  List<String> dates = const <String>['2026-10-01'],
}) => EventSeries(
  id: id,
  clubId: 1,
  topicId: 12,
  leadMemberId: 0,
  version: version,
  recurrenceType: recurrence,
  capacity: capacity,
  waitlistEnabled: waitlist,
  offerMinutes: offerMinutes,
  futureDates: dates,
);

SeriesOccurrence _occurrence({
  String status = 'ACTIVE',
  int? signupCount = 3,
  int? refundedCount,
  bool editable = true,
  String badge = '编辑',
  String badgeKind = 'editable',
}) => SeriesOccurrence(
  occurrenceId: 31,
  activityId: 41,
  dateText: '10月1日 周四 19:30',
  meta: status == 'CANCELLED'
      ? '已退款 ${refundedCount ?? 0} 单'
      : (signupCount == null ? '报名数待确认' : '$signupCount 人已报名'),
  badge: status == 'CANCELLED' ? '本场已取消' : badge,
  badgeKind: status == 'CANCELLED' ? 'cancelled' : badgeKind,
);

RosterMember _rosterMember(int id, String nick, {String state = ''}) =>
    RosterMember(
      memberId: id,
      nickname: nick,
      correctionVersion: 2,
      state: state,
    );

ClubRoster _roster({
  List<RosterMember> registered = const <RosterMember>[],
  List<RosterMember> waitlist = const <RosterMember>[],
  List<RosterMember> arrived = const <RosterMember>[],
  List<RosterMember> noShow = const <RosterMember>[],
  Object? phoneIncluded = false,
}) => ClubRoster(
  registered: registered,
  waitlist: waitlist,
  arrived: arrived,
  noShow: noShow,
  phoneIncluded: phoneIncluded,
);

class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(_dummyDioClient());

  List<ClubMember> membersValue = <ClubMember>[
    _member(1, '小柚', owner: true),
    _member(12, '阿明'),
  ];

  @override
  Future<List<ClubMember>> members(int clubId) async => membersValue;
}

class _FakeClubOpsApi extends ClubOpsApi {
  _FakeClubOpsApi() : super(_dummyDioClient());

  ClubOpsAccess accessValue = _access();
  Object? accessError;
  List<EventOpsTopic> topics = <EventOpsTopic>[
    const EventOpsTopic(id: 12, name: '静安夜跑'),
  ];
  List<EventSeries> seriesRows = <EventSeries>[];
  Object? seriesError;
  List<SeriesOccurrence> occurrences = <SeriesOccurrence>[];
  EventSeries? seriesDetailValue;
  Object? seriesDetailError;
  OccurrenceStatus? statusValue = const OccurrenceStatus(
    activityId: 41,
    cancelled: false,
    publishStatus: 1,
    cancelReason: '',
  );
  Object? statusError;
  CancellationOutcome? cancelResult;
  Object? cancelError;
  ClubRoster? rosterValue;
  Object? rosterError;
  Object? correctError;
  Object? createError;
  Object? updateError;

  final List<Map<String, dynamic>> creates = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> updates = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> cancels = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> corrections = <Map<String, dynamic>>[];
  int seriesListCalls = 0;
  int statusCalls = 0;

  @override
  Future<ClubOpsAccess> access({required int clubId, int? activityId}) async {
    if (accessError != null) throw accessError!;
    return accessValue;
  }

  @override
  Future<List<EventOpsTopic>> eventTopics({required int clubId}) async =>
      topics;

  @override
  Future<List<EventSeries>> seriesList({required int clubId}) async {
    seriesListCalls += 1;
    if (seriesError != null) throw seriesError!;
    return seriesRows;
  }

  @override
  Future<List<SeriesOccurrence>> seriesOccurrences({
    required int clubId,
    required int seriesId,
  }) async => occurrences;

  @override
  Future<EventSeries> seriesDetail({
    required int clubId,
    required int seriesId,
  }) async {
    if (seriesDetailError != null) throw seriesDetailError!;
    return seriesDetailValue ?? _series(id: seriesId);
  }

  @override
  Future<int> createSeries(Map<String, dynamic> payload) async {
    creates.add(Map<String, dynamic>.from(payload));
    if (createError != null) throw createError!;
    seriesRows = <EventSeries>[_series(id: 7)];
    return 7;
  }

  @override
  Future<int> updateSeriesFuture(Map<String, dynamic> payload) async {
    updates.add(Map<String, dynamic>.from(payload));
    if (updateError != null) throw updateError!;
    return (payload['seriesId'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<OccurrenceStatus?> occurrenceStatus({
    required int clubId,
    required int activityId,
  }) async {
    statusCalls += 1;
    if (statusError != null) throw statusError!;
    return statusValue;
  }

  @override
  Future<CancellationOutcome?> cancelOccurrence({
    required int clubId,
    required int activityId,
    required String reason,
    required String requestId,
  }) async {
    cancels.add(<String, dynamic>{
      'activityId': activityId,
      'reason': reason,
      'requestId': requestId,
    });
    if (cancelError != null) throw cancelError!;
    return cancelResult;
  }

  @override
  Future<ClubRoster?> roster({
    required int clubId,
    required int activityId,
  }) async {
    if (rosterError != null) throw rosterError!;
    return rosterValue;
  }

  @override
  Future<bool> correctAttendance({
    required int clubId,
    required int activityId,
    required int memberId,
    required bool arrived,
    required int expectedVersion,
    required String reason,
    required String requestId,
  }) async {
    corrections.add(<String, dynamic>{
      'memberId': memberId,
      'arrived': arrived,
      'expectedVersion': expectedVersion,
      'reason': reason,
      'requestId': requestId,
    });
    if (correctError != null) throw correctError!;
    return true;
  }
}

/// 长列表是懒构建的:把目标滚进可见视口中央附近再操作。
/// 不用 tester.ensureVisible —— 它会把目标滚到被裁掉的边缘,点不到。
Future<void> _reveal(WidgetTester tester, Key key) async {
  final Finder target = find.byKey(key);
  final Finder scrollableFinder = find.byType(Scrollable).first;
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

  // 第一遍从当前位置往下找;找不到就回到顶部再找一遍(目标可能在视口上方被回收)。
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

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await _reveal(tester, key);
  await tester.tap(find.byKey(key));
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required int? activityId,
  int? topicId,
  ClubOpsAccess? access,
  ClubOpsApi? opsApi,
  ClubApi? clubApi,
}) async {
  final _FakeClubOpsApi fake = opsApi is _FakeClubOpsApi
      ? opsApi
      : _FakeClubOpsApi();
  if (access != null) fake.accessValue = access;
  await tester.pumpWidget(
    _app(
      ClubEventOpsPage(clubId: 1, activityId: activityId, topicId: topicId),
      <dynamic>[
        clubOpsApiProvider.overrideWithValue(fake),
        clubApiProvider.overrideWithValue(clubApi ?? _FakeClubApi()),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('event-ops:E-07 主题预选', () {
    testWidgets('带 topicId 进来 → 主题下拉预选到它;找不到维持第一个', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi()
        ..topics = <EventOpsTopic>[
          const EventOpsTopic(id: 7, name: '主题甲'),
          const EventOpsTopic(id: 8, name: '主题乙'),
        ];
      await _pumpPage(tester, activityId: null, topicId: 8, opsApi: fake);
      expect(
        find.text('主题乙'),
        findsOneWidget,
        reason: '系列表单的主题下拉默认选中带进来的那个',
      );
    });

    testWidgets('topicId 找不到对应主题 → 维持第一个,不静默改口径', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi()
        ..topics = <EventOpsTopic>[
          const EventOpsTopic(id: 7, name: '主题甲'),
          const EventOpsTopic(id: 8, name: '主题乙'),
        ];
      await _pumpPage(tester, activityId: null, topicId: 999, opsApi: fake);
      expect(find.text('主题甲'), findsOneWidget);
    });
  });

  group('event-ops:权限面', () {
    testWidgets('两类权限都没有 → 无权限屏,表单与名册都不给', (WidgetTester tester) async {
      await _pumpPage(tester, activityId: 41, access: _access(manage: false));

      expect(find.text('你没有活动运营的权限'), findsOneWidget);
      expect(find.byKey(const Key('event-ops-submit')), findsNothing);
      expect(find.text('本场名册'), findsNothing);
    });

    testWidgets('只有 checkin(带 activityId)→ 只给名册,不给系列表单', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi()
        ..rosterValue = _roster(
          registered: <RosterMember>[_rosterMember(12, '阿明')],
        );
      await _pumpPage(
        tester,
        activityId: 41,
        access: _access(manage: false, checkin: true),
        opsApi: fake,
      );

      expect(find.text('本场名册'), findsOneWidget);
      expect(find.text('日期清单'), findsNothing);
      expect(find.byKey(const Key('event-ops-submit')), findsNothing);
      expect(find.byKey(const Key('event-ops-roster-12')), findsOneWidget);
    });

    testWidgets('checkin 权限不带 activityId → 仍是无权限(核销必须落到具体场次)', (
      WidgetTester tester,
    ) async {
      await _pumpPage(
        tester,
        activityId: null,
        access: _access(manage: false, checkin: true),
      );

      expect(find.text('你没有活动运营的权限'), findsOneWidget);
    });

    testWidgets('读权限网络失败 → 网络态可重试', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..accessError = _networkFailure();
      await _pumpPage(tester, activityId: null, opsApi: fake);

      expect(find.text('网络连接失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('event-ops:系列清单与表单', () {
    testWidgets('没有系列 → 空态', (WidgetTester tester) async {
      await _pumpPage(tester, activityId: null, opsApi: _FakeClubOpsApi());

      expect(find.text('还没有系列场次'), findsOneWidget);
      expect(find.text('从下方创建第一组场次'), findsOneWidget);
    });

    testWidgets('展开日期清单:「报名数待确认」与「0 人」分得清,取消行给退款单数', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi()
        ..seriesRows = <EventSeries>[_series(id: 7)]
        ..occurrences = <SeriesOccurrence>[
          _occurrence(),
          _occurrence(signupCount: null, badge: '已锁定', badgeKind: 'locked'),
          _occurrence(status: 'CANCELLED', refundedCount: 2, editable: false),
        ];
      await _pumpPage(tester, activityId: null, opsApi: fake);

      expect(find.byKey(const Key('event-ops-series-7')), findsOneWidget);
      await _tapVisible(tester, const Key('event-ops-series-dates-7'));
      await tester.pumpAndSettle();

      expect(find.text('3 人已报名'), findsOneWidget);
      expect(find.text('报名数待确认'), findsOneWidget, reason: '算不出来 ≠ 0 人');
      expect(find.text('已退款 2 单'), findsOneWidget);
      expect(find.text('本场已取消'), findsOneWidget);
    });

    testWidgets('表单校验:容量/场次数/候补窗口/主题逐条挡在请求之前', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await _pumpPage(tester, activityId: null, opsApi: fake);

      // 容量超界。
      await _reveal(tester, const Key('event-ops-capacity'));
      await tester.enterText(find.byKey(const Key('event-ops-capacity')), '0');
      await _tapVisible(tester, const Key('event-ops-submit'));
      await tester.pump();
      expect(find.text('容量需为 1–10000'), findsOneWidget);
      expect(fake.creates, isEmpty);

      // 候补窗口超界。
      await tester.enterText(find.byKey(const Key('event-ops-capacity')), '');
      await _reveal(tester, const Key('event-ops-offer'));
      await tester.enterText(find.byKey(const Key('event-ops-offer')), '1');
      await _tapVisible(tester, const Key('event-ops-submit'));
      await tester.pump();
      expect(find.text('候补窗口需为 5–1440 分钟'), findsOneWidget);
      expect(fake.creates, isEmpty);

      // 每周场次数超界。
      await tester.enterText(find.byKey(const Key('event-ops-offer')), '1440');
      await _tapVisible(tester, const Key('event-ops-recurrence-WEEKLY'));
      await tester.pumpAndSettle();
      await _reveal(tester, const Key('event-ops-count'));
      await tester.enterText(find.byKey(const Key('event-ops-count')), '0');
      await _tapVisible(tester, const Key('event-ops-submit'));
      await tester.pump();
      expect(find.text('每周场次数需为 1–64'), findsOneWidget);
      expect(fake.creates, isEmpty);
    });

    testWidgets('没有可开场主题 → 表单空态,提交被挡', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..topics = <EventOpsTopic>[];
      await _pumpPage(tester, activityId: null, opsApi: fake);

      expect(find.text('暂无可开场的主题'), findsWidgets);
      await _tapVisible(tester, const Key('event-ops-submit'));
      await tester.pump();
      expect(find.text('暂无可开场的主题'), findsWidgets);
      expect(fake.creates, isEmpty);
    });

    testWidgets('创建成功:payload 完整、成功后表单复位并重拉列表', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await _pumpPage(tester, activityId: null, opsApi: fake);

      await _reveal(tester, const Key('event-ops-capacity'));
      await tester.enterText(find.byKey(const Key('event-ops-capacity')), '20');
      await _tapVisible(tester, const Key('event-ops-submit'));
      await tester.pumpAndSettle();

      expect(fake.creates, hasLength(1));
      final Map<String, dynamic> payload = fake.creates.single;
      expect(payload['clubId'], 1);
      expect(payload['topicId'], 12);
      expect(payload['recurrenceType'], 'ONCE');
      expect(payload['occurrenceCount'], 1);
      expect(payload['capacity'], 20);
      expect(payload['waitlistEnabled'], isTrue);
      expect(payload['offerMinutes'], 1440);
      expect(payload['defaultLeadMemberId'], isNull);
      expect(
        '${payload['requestId']}',
        startsWith('series'),
        reason: '创建必须带幂等键',
      );
      expect(fake.seriesListCalls, greaterThanOrEqualTo(2));
      await _reveal(tester, const Key('event-ops-series-7'));
      expect(find.byKey(const Key('event-ops-series-7')), findsOneWidget);
      expect(find.text('静安夜跑 · 每周'), findsOneWidget);
    });

    testWidgets('编辑未来场次:详情回填、主题锁定、提交带 expectedVersion', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi()
        ..seriesRows = <EventSeries>[_series(id: 7, version: 3)];
      await _pumpPage(tester, activityId: null, opsApi: fake);

      await _tapVisible(tester, const Key('event-ops-series-7'));
      await tester.pumpAndSettle();

      expect(find.text('编辑未来场次'), findsWidgets);
      expect(find.text('主题 #12 · 已锁定'), findsOneWidget);

      await _tapVisible(tester, const Key('event-ops-submit'));
      await tester.pumpAndSettle();

      expect(fake.updates, hasLength(1));
      expect(fake.updates.single['seriesId'], 7);
      expect(fake.updates.single['expectedVersion'], 3);
    });

    testWidgets('编辑撞版本(409)→ 明说「已被更新」并重新拉列表', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..seriesRows = <EventSeries>[_series(id: 7, version: 3)]
        ..updateError = ClubOpsConflictException('内容已被更新');
      await _pumpPage(tester, activityId: null, opsApi: fake);

      await _tapVisible(tester, const Key('event-ops-series-7'));
      await tester.pumpAndSettle();
      final int callsBefore = fake.seriesListCalls;

      await _tapVisible(tester, const Key('event-ops-submit'));
      await tester.pumpAndSettle();

      expect(find.text('系列已被更新，正在刷新'), findsOneWidget);
      expect(fake.seriesListCalls, greaterThan(callsBefore));
    });
  });

  group('event-ops:本场取消', () {
    testWidgets('原因不足 2 字 → 中止,一个请求都不发', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await _pumpPage(tester, activityId: 41, opsApi: fake);

      await _tapVisible(tester, const Key('event-ops-cancel'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '雨');
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();

      expect(find.text('取消原因需为 2–255 个字'), findsOneWidget);
      expect(fake.cancels, isEmpty);
      expect(find.text('确认取消本场？'), findsNothing, reason: '原因不合法时连二次确认都不该走到');
    });

    testWidgets('合法原因 → 二次确认 → 独立回读确认取消', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..cancelResult = const CancellationOutcome(
          activityId: 41,
          refundStatus: 'REFUND_REQUESTED',
        );
      await _pumpPage(tester, activityId: 41, opsApi: fake);

      await _tapVisible(tester, const Key('event-ops-cancel'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '场馆临时封闭');
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();

      // 二次确认(只有按钮能点)。
      expect(find.text('确认取消本场？'), findsOneWidget);
      expect(fake.cancels, isEmpty, reason: '二次确认之前不能发请求');
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('取消本场'),
        ),
      );

      // 回读第一次仍返回 ACTIVE → 必须判「未确认」,不能假装成功。
      await tester.pumpAndSettle();
      expect(fake.cancels, hasLength(1));
      expect(fake.cancels.single['reason'], '场馆临时封闭');
      expect(
        find.byKey(const Key('event-ops-cancel-readback')),
        findsOneWidget,
      );
      expect(
        find.textContaining('独立回读尚未确认取消'),
        findsOneWidget,
        reason: '取消请求受理 ≠ 已取消',
      );

      // 回读改判 CANCELLED → 页面才显示已取消 + 退款进度。
      fake.statusValue = const OccurrenceStatus(
        activityId: 41,
        cancelled: true,
        publishStatus: 0,
        cancelReason: '场馆临时封闭',
      );
      await _tapVisible(tester, const Key('event-ops-cancel-readback'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('event-ops-cancelled')), findsOneWidget);
      expect(find.textContaining('退款任务已受理'), findsOneWidget);
      expect(find.byKey(const Key('event-ops-cancel')), findsNothing);
    });

    testWidgets('取消失败 → 给出可重试入口;同原因重试复用同一 requestId', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi()..cancelError = _networkFailure();
      await _pumpPage(tester, activityId: 41, opsApi: fake);

      await _tapVisible(tester, const Key('event-ops-cancel'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '场馆临时封闭');
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('取消本场'),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.cancels, hasLength(1));
      expect(find.byKey(const Key('event-ops-cancel-retry')), findsOneWidget);

      fake.cancelError = null;
      fake.cancelResult = const CancellationOutcome(
        activityId: 41,
        refundStatus: 'NOT_REQUIRED',
      );
      fake.statusValue = const OccurrenceStatus(
        activityId: 41,
        cancelled: true,
        publishStatus: 0,
        cancelReason: '场馆临时封闭',
      );

      await _tapVisible(tester, const Key('event-ops-cancel-retry'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '场馆临时封闭');
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('取消本场'),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.cancels, hasLength(2));
      expect(
        fake.cancels[1]['requestId'],
        fake.cancels[0]['requestId'],
        reason: '同一原因的重试是同一意图,幂等键必须稳定',
      );
      expect(find.byKey(const Key('event-ops-cancelled')), findsOneWidget);
    });
  });

  group('event-ops:名册与出勤更正', () {
    testWidgets('四桶分栏与空桶提示;手机号越界判回执坏了', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..rosterValue = _roster(
          registered: <RosterMember>[_rosterMember(12, '阿明')],
        );
      await _pumpPage(
        tester,
        activityId: 41,
        access: _access(manage: false, checkin: true),
        opsApi: fake,
      );

      expect(find.text('已报名 1 · 候补 0 · 已到场 0 · 未到场 0'), findsOneWidget);
      expect(find.byKey(const Key('event-ops-roster-12')), findsOneWidget);

      await tester.tap(find.text('候补'));
      await tester.pumpAndSettle();
      expect(find.text('这一段暂时没有成员'), findsOneWidget);
    });

    testWidgets('名册回执坏了(含手机号越界)→ 错误态可重试,不拿空桶兜底', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..rosterValue = null;
      await _pumpPage(
        tester,
        activityId: 41,
        access: _access(manage: false, checkin: true),
        opsApi: fake,
      );

      expect(find.text('名册加载失败'), findsOneWidget);
      expect(find.text('名册数据不完整'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('更正:原因不足 2 字不发请求;2 字以上带 expectedVersion 与幂等键', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi()
        ..rosterValue = _roster(
          registered: <RosterMember>[_rosterMember(12, '阿明')],
        );
      await _pumpPage(
        tester,
        activityId: 41,
        access: _access(manage: false, checkin: true),
        opsApi: fake,
      );

      await _tapVisible(tester, const Key('event-ops-correct-12'));
      await tester.pumpAndSettle();
      expect(find.text('更正为已到场'), findsOneWidget);
      await tester.enterText(find.byKey(_reasonFieldKey), '到');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(fake.corrections, isEmpty);

      await _tapVisible(tester, const Key('event-ops-correct-12'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '现场漏扫');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      expect(fake.corrections, hasLength(1));
      expect(fake.corrections.single['memberId'], 12);
      expect(fake.corrections.single['arrived'], isTrue);
      expect(fake.corrections.single['expectedVersion'], 2);
      expect(
        '${fake.corrections.single['requestId']}',
        startsWith('attendance'),
      );
    });

    testWidgets('更正幂等:网络失败复用同一键,4xx 明确失败才换新键', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..rosterValue = _roster(
          registered: <RosterMember>[_rosterMember(12, '阿明')],
        )
        ..correctError = _networkFailure();
      await _pumpPage(
        tester,
        activityId: 41,
        access: _access(manage: false, checkin: true),
        opsApi: fake,
      );

      await _tapVisible(tester, const Key('event-ops-correct-12'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '现场漏扫');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      // 网络失败 → 复用同一 requestId。
      fake.correctError = null;
      await _tapVisible(tester, const Key('event-ops-correct-12'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '现场漏扫');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(fake.corrections, hasLength(2));
      expect(
        fake.corrections[1]['requestId'],
        fake.corrections[0]['requestId'],
        reason: '网络结果未知时必须复用幂等键',
      );

      // 4xx 明确拒绝 → 重开一条意图(新 requestId)。
      fake.correctError = ClubOpsRejectedException('该成员不在本场名册');
      await _tapVisible(tester, const Key('event-ops-correct-12'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '现场漏扫');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      fake.correctError = null;
      await _tapVisible(tester, const Key('event-ops-correct-12'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '现场漏扫');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      expect(fake.corrections, hasLength(4));
      expect(
        fake.corrections[3]['requestId'],
        isNot(fake.corrections[2]['requestId']),
        reason: '4xx 明确失败后必须换新键,否则重试永远不会成功',
      );
    });

    testWidgets('已到场分栏的更正方向是「更正未到」', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..rosterValue = _roster(
          arrived: <RosterMember>[_rosterMember(13, '小静')],
        );
      await _pumpPage(
        tester,
        activityId: 41,
        access: _access(manage: false, checkin: true),
        opsApi: fake,
      );

      await tester.tap(find.text('已到场'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('event-ops-correct-13'));
      await tester.pumpAndSettle();
      expect(find.text('更正为未到场'), findsOneWidget);
      await tester.enterText(find.byKey(_reasonFieldKey), '误扫了');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      expect(fake.corrections, hasLength(1));
      expect(fake.corrections.single['arrived'], isFalse);
    });
  });

  group('a2 入口接线:带 topicId 进来自预选', () {
    testWidgets('预选在 topicId 那条,不是永远第一条(E-07)', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..topics = const <EventOpsTopic>[
          EventOpsTopic(id: 12, name: '静安夜跑'),
          EventOpsTopic(id: 13, name: '徐汇晨光'),
        ];
      await tester.pumpWidget(
        _app(ClubEventOpsPage(clubId: 1, topicId: 13), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      // 表单的主题位直接显示被带来的那条。
      expect(find.text('徐汇晨光'), findsOneWidget);
      // 打开选择器:已选标记落在 13,不是第一行。
      await tester.tap(find.text('徐汇晨光'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('event-ops-topic-13')),
          matching: find.text('已选'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('topicId 不在清单里 → 维持第一条,不空选', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..topics = const <EventOpsTopic>[
          EventOpsTopic(id: 12, name: '静安夜跑'),
          EventOpsTopic(id: 13, name: '徐汇晨光'),
        ];
      await tester.pumpWidget(
        _app(ClubEventOpsPage(clubId: 1, topicId: 999), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('静安夜跑'), findsOneWidget);
    });
  });
}

DioException _networkFailure() => DioException(
  requestOptions: RequestOptions(path: '/api/club/event-ops/occurrence/status'),
  type: DioExceptionType.connectionError,
);
