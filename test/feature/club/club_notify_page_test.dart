// 群发通知页(notify)的负控门:权限面、受众禁用、预览 0 人禁发送、坏回执。
//
// 只测「该红的必须红」的判据,不碰网络 —— clubOpsApiProvider 全部 override 成假实现。
// 判据对齐小程序 pages/club/notify(@90e66d70):
//   - 本场三组(本场已报名/本场候补/本场未到场)要 club:event:operate 且必须带 activityId;
//     其余三组要 club:notify:send;
//   - 人数只是行内装饰:算不出来不显示,也不弹 toast;
//   - 预览 0 人 → 不创建空任务(发送键保持禁用);
//   - 发送中禁连点;投递有失败项才给「只重试失败项」。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dio/dio.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/feature/club/club_notify_page.dart';
import 'package:chengyin_app/feature/club/club_ops_access.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _app(Widget home, List<dynamic> overrides, {Locale? locale}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      locale: locale ?? const Locale('zh'),
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

ClubOpsAccess _access({
  Set<String> permissions = const <String>{kClubNotifySend},
  int clubId = 1,
  bool active = true,
  bool activeDeclared = true,
}) => ClubOpsAccess(
  activeDeclared: activeDeclared,
  active: active,
  clubId: clubId,
  permissions: permissions,
  roleCodes: const <String>['CLUB_OWNER'],
  canManageRoles: true,
);

/// 记录调用、可挂闸的 ClubOpsApi 假实现。
class _FakeClubOpsApi extends ClubOpsApi {
  _FakeClubOpsApi() : super(_dummyDioClient());

  ClubOpsAccess accessValue = _access();
  Object? accessError;
  AudienceCounts? counts;
  NotificationPreview? preview;
  Object? previewError;
  NotificationCampaign? sendResult;
  Object? sendError;
  Completer<void>? sendGate;
  NotificationCampaign? retryResult;
  Object? retryError;

  final List<Map<String, dynamic>> sends = <Map<String, dynamic>>[];
  int previewCalls = 0;
  int retryCalls = 0;
  int statusCalls = 0;
  Object? statusError;
  NotificationCampaign? statusResult;

  @override
  Future<NotificationCampaign?> notificationStatus({required int campaignId}) async {
    expect(campaignId, 88);
    statusCalls++;
    if (statusError != null) throw statusError!;
    return statusResult;
  }


  @override
  Future<ClubOpsAccess> access({required int clubId, int? activityId}) async {
    if (accessError != null) throw accessError!;
    return accessValue;
  }

  @override
  Future<AudienceCounts?> audienceCounts({
    required int clubId,
    int? activityId,
  }) async => counts;

  @override
  Future<NotificationPreview?> notificationPreview({
    required int clubId,
    int? activityId,
    required String audienceType,
    required String title,
    required String content,
  }) async {
    previewCalls += 1;
    if (previewError != null) throw previewError!;
    return preview;
  }

  @override
  Future<NotificationCampaign?> notificationSend({
    required int clubId,
    int? activityId,
    required String audienceType,
    required String title,
    required String content,
    required String requestId,
  }) async {
    sends.add(<String, dynamic>{
      'clubId': clubId,
      'activityId': activityId,
      'audienceType': audienceType,
      'title': title,
      'content': content,
      'requestId': requestId,
    });
    if (sendError != null) throw sendError!;
    if (sendGate != null) await sendGate!.future;
    return sendResult;
  }

  @override
  Future<NotificationCampaign?> notificationRetry({
    required int campaignId,
  }) async {
    retryCalls += 1;
    if (retryError != null) throw retryError!;
    return retryResult;
  }
}

List<String> _textsIn(WidgetTester tester, Key key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    )
    .map((Text text) => text.data ?? '')
    .where((String value) => value.isNotEmpty)
    .toList();

bool _rowShows(WidgetTester tester, String key, String text) =>
    _textsIn(tester, Key(key)).contains(text);

bool _sendEnabled(WidgetTester tester) =>
    tester.widget<CyNativeButton>(find.byKey(const Key('notify-send')))
        .onPressed !=
    null;

/// 内容区的按钮常在折线以下:tap 之前先滚到可见,否则命中不到。
Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
}

Future<void> _fillDraft(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('notify-title')), '周六集合提醒');
  await tester.enterText(
    find.byKey(const Key('notify-content')),
    '九点静安寺地铁站 2 号口集合，带上水。',
  );
  await tester.pump();
}

void main() {
  testWidgets('English audience labels and refresh preserve protocol values', (
    tester,
  ) async {
    final fake = _FakeClubOpsApi()
      ..counts = const AudienceCounts({'ALL_MEMBERS': 1, 'ADMINS': 2})
      ..preview = const NotificationPreview(
        recipientCount: 1,
        phoneIncluded: false,
        inApp: 'AVAILABLE',
        wechatSubscription: 'UNAVAILABLE',
      )
      ..sendResult = const NotificationCampaign(
        id: 88, totalCount: 1, successCount: 0, failedCount: 0,
      )
      ..statusResult = const NotificationCampaign(
        id: 88, totalCount: 1, successCount: 1, failedCount: 0,
      );
    await tester.pumpWidget(_app(
      const ClubNotifyPage(clubId: 1),
      [clubOpsApiProvider.overrideWithValue(fake)],
      locale: const Locale('en'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Group notifications'), findsOneWidget);
    expect(find.text('All members'), findsOneWidget);
    expect(find.text('1 person'), findsOneWidget);
    expect(find.text('2 people'), findsOneWidget);
    await _fillDraft(tester);
    await _tapVisible(tester, const Key('notify-preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 recipient ·'), findsOneWidget);
    await _tapVisible(tester, const Key('notify-send'));
    await tester.pumpAndSettle();
    expect(fake.sends.single['audienceType'], 'ALL_MEMBERS');
    expect(fake.sends.single['title'], '周六集合提醒');
    await _tapVisible(tester, const Key('notify-refresh'));
    await tester.pumpAndSettle();
    expect(fake.statusCalls, 1);
    expect(fake.sends, hasLength(1));
    expect(fake.retryCalls, 0);
    expect(find.text('Delivery status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('notify:权限面', () {
    testWidgets('普通成员(无 notify:send)→ 无权限屏,不给发送入口', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..accessValue = _access(permissions: const <String>{});
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('你没有发通知的权限'), findsOneWidget);
      expect(find.byKey(const Key('notify-send')), findsNothing);
      expect(find.byKey(const Key('notify-preview')), findsNothing);
    });

    testWidgets('clubId 与回执不一致 → 按「不属于该俱乐部」拒绝', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..accessValue = _access(clubId: 2);
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('当前账号不属于该俱乐部'), findsOneWidget);
      expect(find.byKey(const Key('notify-send')), findsNothing);
    });

    testWidgets('读权限时网络失败 → 网络态可重试,不当成没权限', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..accessError = _networkFailure();
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('网络连接失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('notify:受众门', () {
    testWidgets('无 activityId:本场三组禁用,点了也不改选中', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      // 默认选中「全部成员」。
      expect(_rowShows(tester, 'notify-audience-ALL_MEMBERS', '已选'), isTrue);
      // 三个本场组:明说要从具体活动进入,并且不可点。
      for (final String value in <String>[
        'REGISTERED',
        'WAITLIST',
        'NO_SHOW',
      ]) {
        expect(
          _rowShows(tester, 'notify-audience-$value', '从具体活动进入后才可选'),
          isTrue,
          reason: '$value 没有 activityId 时必须禁用并说明原因',
        );
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('notify-audience-REGISTERED')),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason: '禁用行必须不挂手势,点了也不该改选中',
      );
      expect(_rowShows(tester, 'notify-audience-ALL_MEMBERS', '已选'), isTrue);
    });

    testWidgets('有 activityId 但无 event:operate:本场组仍禁用并写明缺权限', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1, activityId: 9), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        _rowShows(
          tester,
          'notify-audience-REGISTERED',
          '当前角色没有本场通知权限',
        ),
        isTrue,
      );
      expect(_rowShows(tester, 'notify-audience-ALL_MEMBERS', '已选'), isTrue);
    });

    testWidgets('有 event:operate:本场组合可用且默认选中「本场已报名」', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..accessValue = _access(
          permissions: const <String>{kClubNotifySend, kClubEventOperate},
        );
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1, activityId: 9), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      expect(_rowShows(tester, 'notify-audience-REGISTERED', '已选'), isTrue);
      expect(
        _rowShows(tester, 'notify-audience-REGISTERED', '当前角色没有本场通知权限'),
        isFalse,
        reason: '有 event:operate 时不该再挂缺权限提示',
      );
    });

    testWidgets('人数算不出来 → 那一行不显示数字(不拿 0 兜底)', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..counts = const AudienceCounts(<String, int?>{
          'ALL_MEMBERS': null,
          'ADMINS': 3,
        });
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      expect(_rowShows(tester, 'notify-audience-ALL_MEMBERS', '0 人'), isFalse);
      expect(_rowShows(tester, 'notify-audience-ADMINS', '3 人'), isTrue);
    });
  });

  group('notify:预览与发送门', () {
    testWidgets('标题/内容不合法 → 不发预览请求,先弹校验', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, const Key('notify-preview'));
      await tester.pump();
      expect(find.text('标题需为 1–80 字'), findsOneWidget);
      expect(fake.previewCalls, 0);
    });

    testWidgets('预览 0 人 → 明说不会创建空任务,发送键保持禁用', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..preview = const NotificationPreview(
          recipientCount: 0,
          phoneIncluded: false,
          inApp: 'AVAILABLE',
          wechatSubscription: 'UNAVAILABLE',
        );
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();
      await _fillDraft(tester);

      await _tapVisible(tester, const Key('notify-preview'));
      await tester.pumpAndSettle();

      expect(
        find.text('0 人 · 当前分群没有可发送成员，不会创建空任务。'),
        findsOneWidget,
      );
      expect(_sendEnabled(tester), isFalse, reason: '0 人预览后发送键必须禁用');
      expect(fake.sends, isEmpty);
    });

    testWidgets('预览回执坏了 → 进错误态并给重试,不显示 0 人', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..preview = null;
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();
      await _fillDraft(tester);

      await _tapVisible(tester, const Key('notify-preview'));
      await tester.pumpAndSettle();

      expect(find.text('受众预览不可用'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(_sendEnabled(tester), isFalse);
    });

    testWidgets('预览失败 → 后端原文上屏', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..previewError = ClubApiException('该分群暂不支持发送');
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();
      await _fillDraft(tester);

      await _tapVisible(tester, const Key('notify-preview'));
      await tester.pumpAndSettle();

      expect(find.text('该分群暂不支持发送'), findsOneWidget);
    });

    testWidgets('预览合法 → 人数上屏、发送中禁连点、失败项可单独重试', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..preview = const NotificationPreview(
          recipientCount: 12,
          phoneIncluded: false,
          inApp: 'AVAILABLE',
          wechatSubscription: 'UNAVAILABLE',
        )
        ..sendGate = Completer<void>()
        ..sendResult = const NotificationCampaign(
          id: 88,
          totalCount: 12,
          successCount: 10,
          failedCount: 2,
        )
        ..retryResult = const NotificationCampaign(
          id: 88,
          totalCount: 12,
          successCount: 12,
          failedCount: 0,
        );
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();
      await _fillDraft(tester);

      await _tapVisible(tester, const Key('notify-preview'));
      await tester.pumpAndSettle();
      expect(
        find.text('12 人 · 不会下发手机号；发送后可按失败项重试。'),
        findsOneWidget,
      );
      expect(_sendEnabled(tester), isTrue);

      // 发送:请求已挂闸 → 按钮转「正在投递…」且不可再点(防连点重复投递)。
      await _tapVisible(tester, const Key('notify-send'));
      await tester.pump();
      await tester.pump();
      expect(fake.sends, hasLength(1));
      expect(_sendEnabled(tester), isFalse);
      expect(find.text('正在投递…'), findsOneWidget);
      expect(fake.sends.single['audienceType'], 'ALL_MEMBERS');
      expect(
        '${fake.sends.single['requestId']}',
        startsWith('campaign-'),
        reason: '发送必须带幂等键',
      );

      fake.sendGate!.complete();
      await tester.pumpAndSettle();

      // 有失败项 → 投递状态上屏 + 只重试失败项。
      expect(find.text('投递状态'), findsOneWidget);
      expect(find.text('总人数'), findsOneWidget);
      expect(find.byKey(const Key('notify-retry')), findsOneWidget);
      await _tapVisible(tester, const Key('notify-retry'));
      await tester.pumpAndSettle();
      expect(fake.retryCalls, 1);
      expect(find.byKey(const Key('notify-retry')), findsNothing);
      // Status refresh is read-only: no second send and no automatic retry.
      fake.statusResult = const NotificationCampaign(
        id: 88, totalCount: 12, successCount: 11, failedCount: 1,
      );
      await _tapVisible(tester, const Key('notify-refresh'));
      await tester.pumpAndSettle();
      expect(fake.statusCalls, 1);
      expect(fake.sends, hasLength(1));
      expect(fake.retryCalls, 1);
      expect(find.byKey(const Key('notify-retry')), findsOneWidget);
      fake.statusError = StateError('offline');
      await _tapVisible(tester, const Key('notify-refresh'));
      await tester.pumpAndSettle();
      expect(fake.statusCalls, 2);
      expect(fake.sends, hasLength(1));
      expect(find.byKey(const Key('notify-retry')), findsOneWidget);

    });

    testWidgets('发送失败 → 后端原文上屏,不假装已发送', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..preview = const NotificationPreview(
          recipientCount: 5,
          phoneIncluded: false,
          inApp: 'AVAILABLE',
          wechatSubscription: 'UNAVAILABLE',
        )
        ..sendError = ClubApiException('今日发送额度已用完');
      await tester.pumpWidget(
        _app(const ClubNotifyPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
        ]),
      );
      await tester.pumpAndSettle();
      await _fillDraft(tester);

      await _tapVisible(tester, const Key('notify-preview'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('notify-send'));
      await tester.pumpAndSettle();

      expect(find.text('今日发送额度已用完'), findsOneWidget);
      expect(find.text('投递状态'), findsNothing);
    });
  });
}

DioException _networkFailure() => DioException(
  requestOptions: RequestOptions(path: '/api/club/event-notification/preview'),
  type: DioExceptionType.connectionError,
);
