import 'dart:async';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/activity_waitlist_api.dart';
import 'package:chengyin_app/data/models/activity_waitlist.dart';
import 'package:chengyin_app/feature/activity/activity_waitlist_section.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('售罄票种从原生加载态进入可加入候补态', (WidgetTester tester) async {
    final Completer<ActivityWaitlistStatus> pending =
        Completer<ActivityWaitlistStatus>();
    final _FakeWaitlistApi api = _FakeWaitlistApi(
      statuses: <Future<ActivityWaitlistStatus>>[pending.future],
    );

    await tester.pumpWidget(_app(api: api, soldOut: true));
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('正在读取候补状态'), findsOneWidget);

    pending.complete(_none);
    await tester.pumpAndSettle();

    expect(find.text('本票种已满'), findsOneWidget);
    expect(find.text('加入候补'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(CupertinoButton, '加入候补')).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('加入候补以 API 读回的 WAITING 状态替换本地猜测', (WidgetTester tester) async {
    final List<ActivityWaitlistStatus?> changed = <ActivityWaitlistStatus?>[];
    final _FakeWaitlistApi api = _FakeWaitlistApi(
      statuses: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(_none),
      ],
      joins: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(_waiting),
      ],
    );

    await tester.pumpWidget(
      _app(api: api, soldOut: true, onChanged: changed.add),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入候补'));
    await tester.pumpAndSettle();

    expect(find.text('候补排队中'), findsOneWidget);
    expect(api.joinCalls, 1);
    expect(changed.last?.state, ActivityWaitlistState.waiting);
  });

  testWidgets('候补加载失败显示真实原因和重试，不降级为可加入', (WidgetTester tester) async {
    final Completer<ActivityWaitlistStatus> failed =
        Completer<ActivityWaitlistStatus>();
    final _FakeWaitlistApi api = _FakeWaitlistApi(
      statuses: <Future<ActivityWaitlistStatus>>[
        failed.future,
        Future<ActivityWaitlistStatus>.value(_none),
      ],
    );

    await tester.pumpWidget(_app(api: api, soldOut: true));
    await tester.pump();
    failed.completeError(const ActivityWaitlistException('仅俱乐部正常成员可候补'));
    await tester.pumpAndSettle();

    expect(find.text('候补状态读取失败'), findsOneWidget);
    expect(find.text('仅俱乐部正常成员可候补'), findsOneWidget);
    expect(find.text('加入候补'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('加入候补'), findsOneWidget);
  });

  testWidgets('OFFERED 在 200% 字号下仍显示保留期和操作', (WidgetTester tester) async {
    final ActivityWaitlistStatus offered = ActivityWaitlistStatus(
      id: 19,
      activityId: 7,
      ticketId: 11,
      state: ActivityWaitlistState.offered,
      eligibility: ActivityWaitlistEligibility.eligible,
      joinAllowed: true,
      offerToken: 'secret-token',
      offerExpiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );
    final _FakeWaitlistApi api = _FakeWaitlistApi(
      statuses: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(offered),
      ],
    );

    await tester.pumpWidget(_app(api: api, soldOut: true, textScale: 2));
    await tester.pumpAndSettle();

    expect(find.text('名额已为你保留'), findsOneWidget);
    expect(find.text('放弃名额'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非售罄且服务端无候补记录时不制造候补卡', (WidgetTester tester) async {
    final _FakeWaitlistApi api = _FakeWaitlistApi(
      statuses: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(_none),
      ],
    );

    await tester.pumpWidget(_app(api: api, soldOut: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activity-waitlist-card')), findsNothing);
  });

  testWidgets('退出候补使用 Apple 原生确认弹窗，确认后以读回状态更新', (WidgetTester tester) async {
    final _FakeWaitlistApi api = _FakeWaitlistApi(
      statuses: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(_waiting),
      ],
      cancels: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(_cancelled),
      ],
    );

    await tester.pumpWidget(_app(api: api, soldOut: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出候补'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '退出候补'));
    await tester.pumpAndSettle();

    expect(api.cancelCalls, 1);
    expect(find.text('已退出候补'), findsOneWidget);
  });

  testWidgets('OFFERED 放弃后通知活动详情重读真实库存', (WidgetTester tester) async {
    var inventoryRefreshes = 0;
    final ActivityWaitlistStatus offered = ActivityWaitlistStatus(
      id: 19,
      activityId: 7,
      ticketId: 11,
      state: ActivityWaitlistState.offered,
      eligibility: ActivityWaitlistEligibility.eligible,
      joinAllowed: true,
      offerToken: 'secret-token',
      offerExpiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );
    final _FakeWaitlistApi api = _FakeWaitlistApi(
      statuses: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(offered),
      ],
      cancels: <Future<ActivityWaitlistStatus>>[
        Future<ActivityWaitlistStatus>.value(_cancelled),
      ],
    );

    await tester.pumpWidget(
      _app(
        api: api,
        soldOut: true,
        onInventoryMayHaveChanged: () => inventoryRefreshes += 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃名额'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '退出候补'));
    await tester.pumpAndSettle();

    expect(inventoryRefreshes, 1);
  });
}

const ActivityWaitlistStatus _none = ActivityWaitlistStatus(
  activityId: 7,
  ticketId: 11,
  state: ActivityWaitlistState.none,
  eligibility: ActivityWaitlistEligibility.eligible,
  joinAllowed: true,
);

const ActivityWaitlistStatus _waiting = ActivityWaitlistStatus(
  id: 19,
  activityId: 7,
  ticketId: 11,
  state: ActivityWaitlistState.waiting,
  eligibility: ActivityWaitlistEligibility.eligible,
  joinAllowed: true,
);

const ActivityWaitlistStatus _cancelled = ActivityWaitlistStatus(
  id: 19,
  activityId: 7,
  ticketId: 11,
  state: ActivityWaitlistState.cancelled,
  eligibility: ActivityWaitlistEligibility.eligible,
  joinAllowed: true,
);

Widget _app({
  required ActivityWaitlistGateway api,
  required bool soldOut,
  ValueChanged<ActivityWaitlistStatus?>? onChanged,
  VoidCallback? onInventoryMayHaveChanged,
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.dark(),
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: ActivityWaitlistSection(
      activityId: 7,
      ticketId: 11,
      soldOut: soldOut,
      api: api,
      onChanged: onChanged ?? (_) {},
      onInventoryMayHaveChanged: onInventoryMayHaveChanged,
    ),
  ),
);

class _FakeWaitlistApi implements ActivityWaitlistGateway {
  _FakeWaitlistApi({
    required this.statuses,
    this.joins = const <Future<ActivityWaitlistStatus>>[],
    this.cancels = const <Future<ActivityWaitlistStatus>>[],
  });

  final List<Future<ActivityWaitlistStatus>> statuses;
  final List<Future<ActivityWaitlistStatus>> joins;
  final List<Future<ActivityWaitlistStatus>> cancels;
  int joinCalls = 0;
  int cancelCalls = 0;

  @override
  Future<ActivityWaitlistStatus> status({
    required int activityId,
    required int ticketId,
  }) => statuses.removeAt(0);

  @override
  Future<ActivityWaitlistStatus> join({
    required int activityId,
    required int ticketId,
  }) {
    joinCalls += 1;
    return joins.removeAt(0);
  }

  @override
  Future<ActivityWaitlistStatus> cancel({
    required int activityId,
    required int ticketId,
  }) {
    cancelCalls += 1;
    return cancels.removeAt(0);
  }
}
