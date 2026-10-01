import 'dart:async';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/data/models/registration_cancellation_outcome.dart';
// 俱乐部 CRM / 分润 / 核销的行为门(负控)。
//
// 只测「该红的必须红」的判据,不碰网络 —— ClubCrmApi / ClubApi 全部 override 成
// 记录型假实现。判据对齐小程序:
//   - 分润页金额一律透传服务端字符串,前端不做任何运算;字段缺失整块拒收走 error 态,
//     **绝不渲染成 ¥0**(小程序 normalizeSummary 的 fail-closed);
//   - 分润页「提现」按 R10:**不发提现请求、也不进银行卡表单**,只弹客服微信号
//     + 「返回」「复制」;直接打 /api/club/settlement/withdraw = 给 App 开第二条
//     动钱路径;
//   - 核销页退款:确认弹窗点「取消」不发请求;回执未知(网络断/5xx)之后
//     按钮挂闸,再点一次也不会重复提交。

import 'dart:io';
import 'package:chengyin_app/l10n/app_localizations.dart';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/widgets/cy_confirm.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_crm_api.dart';
import 'package:chengyin_app/data/models/club_access.dart';
import 'package:chengyin_app/data/models/club_crm.dart';
import 'package:chengyin_app/data/models/club_settlement.dart';
import 'package:chengyin_app/data/models/club_stats.dart';
import 'package:chengyin_app/feature/club/club_checkin_detail_page.dart';
import 'package:chengyin_app/feature/club/club_settlement_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_contact_dialog.dart';

import '../../support/source_text.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

const Map<String, dynamic> _summaryJson = <String, dynamic>{
  'settledAmountText': '¥12,480.00',
  'settledAmountStatus': 'verified',
  'unverifiedSettledCount': 0,
  'isOwner': true,
  'pendingAdjustment': null,
  'topics': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 7,
      'topicId': 91,
      'name': '外滩建筑线索',
      'amountText': '¥6,240.00',
      'amountStatus': 'verified',
      'originalAmountText': '¥6,240.00',
      'executedAdjustmentText': '¥0.00',
      'netAmountText': '¥6,240.00',
      'arrivedText': '已到账 8月28日',
      'paidText': '实付 ¥7,800.00',
      'status': 'settled',
    },
  ],
};

const Map<String, dynamic> _checkinJson = <String, dynamic>{
  'registrationId': 11,
  'displayName': '林夏',
  'avatar': '',
  'phoneText': '138****5621',
  'phoneVisible': true,
  'sessionTimeText': '2026-08-31 14:00',
  'statusCode': 'PENDING',
  'statusText': '待核销',
  'statusTimeText': '',
  'topicName': '外滩夜行 · 霓虹拾光',
  'topicCover': '',
  'orderNo': 'CY083101',
  'ticketText': '标准单人票 ×1',
  'orderTimeText': '08-28 20:16',
  'paidAmountText': '¥128.00',
  'verifyTimeText': '—',
  'storeName': '巷屿咖啡 · 老城店',
  'operatorName': '阿沐',
  'railStep': 0,
  'canRefund': true,
};

/// 记录调用的 ClubCrmApi 假实现。**没有 withdraw 方法** —— 那正是要守住的事实。
class _FakeClubCrmApi extends ClubCrmApi {
  _FakeClubCrmApi({this.summary, this.checkin}) : super(_dummyDioClient());

  final Map<String, dynamic>? summary;
  final Map<String, dynamic>? checkin;

  int summaryCalls = 0;
  int checkinCalls = 0;

  @override
  Future<ClubSettlementSummary> settlementSummary({required int clubId}) async {
    summaryCalls += 1;
    return ClubSettlementSummary.fromJson(summary!);
  }

  @override
  Future<ClubCheckinDetail> checkinDetail({
    required int clubId,
    required int registrationId,
  }) async {
    checkinCalls += 1;
    return ClubCheckinDetail.fromJson(
      checkin!,
      expectedRegistrationId: registrationId,
    );
  }

  /// 权限底座放行 —— 这几条用例测的是钱的判据,不是权限门。
  @override
  Future<ClubAccess> access({required int clubId}) async => ClubAccess(
    active: true,
    clubId: clubId,
    permissions: const <String>{'club:member:list:read', 'club:finance:read'},
    roleCodes: const <String>['OWNER'],
  );

  @override
  Future<ClubStats> stats({required int clubId}) async =>
      throw UnimplementedError();
}

/// 记录 `/api/registration/cancel-by-owner` 调用次数,可注入失败。
class _SessionAuth extends AuthController {
  @override
  AuthState build() => AuthState(initialized: true, user: User(id: 7, nickname: 'A', avatar: '', role: 'player'));
  void switchAccount() {
    state = AuthState(initialized: true, user: User(id: 8, nickname: 'B', avatar: '', role: 'player'));
  }
}

class _FakeClubApi extends ClubApi {
  _FakeClubApi({this.pending, this.throwOnCancel, this.outcome = const RegistrationCancellationOutcome()}) : super(_dummyDioClient());

  final Completer<RegistrationCancellationOutcome>? pending;
  final Object? throwOnCancel;
  final RegistrationCancellationOutcome outcome;
  int cancelCalls = 0;

  @override
  Future<RegistrationCancellationOutcome> cancelRegistrationByOwner(int registrationId) async {
    cancelCalls += 1;
    final Object? error = throwOnCancel;
    if (error != null) throw error;
    return pending == null ? outcome : await pending!.future;
  }
}

/// 可注入结果的确认弹窗:退款是钱路径,确认与否必须能在测试里精确控制。
class _Confirm implements CyNativeConfirmPresenter {
  _Confirm(this.result, {this.pending});
  final Completer<CyNativeConfirmResult>? pending;

  final CyNativeConfirmResult result;
  int shown = 0;

  @override
  Future<CyNativeConfirmResult> show(
    BuildContext context,
    CyNativeConfirmRequest request,
  ) async {
    shown += 1;
    return pending == null ? result : await pending!.future;
  }
}

Widget _host(List<dynamic> overrides, Widget home, {Locale locale = const Locale('zh'), _SessionAuth? auth}) {
  final GoRouter router = GoRouter(
    initialLocation: '/here',
    routes: <RouteBase>[
      GoRoute(path: '/here', builder: (_, _) => home),
      GoRoute(
        path: '/withdrawal',
        builder: (_, _) => const Scaffold(body: Text('银行卡提现表单')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => auth ?? _SessionAuth()), ...overrides.cast()],
    child: MaterialApp.router(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    ),
  );
}

/// 抓「复制」写进剪贴板的东西。
///
/// R10 弹窗收口到共用件后,club 页不再有可注入的 copier ——
/// 要证明「复制的是客服号」只能看平台通道真正收到了什么。
List<String> _captureClipboardWrites(WidgetTester tester) {
  final List<String> copied = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<dynamic, dynamic>)['text'] as String,
          );
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

void main() {
  // R10 弹窗是共用件,「复制」后由它自己弹提示 —— 提示带定时器,收尾要收掉。
  tearDown(CyNativeNotice.hide);

  // 门禁:App 不许开第二条提现路径。
  //
  // 小程序 `pages/club/settlement/index.js#goWithdraw` 明说不打这条口子 ——
  // 分润页没有收集 realname/bankName/bankAccount/mobilephone 的入口,
  // 直接打 `/api/club/settlement/withdraw` 就是绕开资金前置门禁。
  // 这条扫的是**剥掉注释后**的代码:解释禁令的注释不算犯规。
  test('lib 里没有任何一处真调 /api/club/settlement/withdraw', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (codeOf(f.path).contains('/api/club/settlement/withdraw')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  group('分润页 · 金额只透传,不运算', () {
    testWidgets('服务端格式化好的金额原样上屏', (WidgetTester tester) async {
      final _FakeClubCrmApi api = _FakeClubCrmApi(summary: _summaryJson);
      await tester.pumpWidget(
        _host(<dynamic>[
          clubCrmApiProvider.overrideWithValue(api),
        ], const ClubSettlementPage(clubId: 42)),
      );
      await tester.pumpAndSettle();

      expect(find.text('¥12,480.00'), findsOneWidget);
      expect(find.text('¥6,240.00'), findsOneWidget);
      expect(find.text('实付 ¥7,800.00'), findsOneWidget);
      // 前端一分钱都不算:不许出现自己拼出来的合计/差额。
      expect(find.textContaining('12480'), findsNothing);
    });

    testWidgets('缺字段整块拒收走 error 态,绝不渲染成 ¥0', (WidgetTester tester) async {
      final _FakeClubCrmApi api = _FakeClubCrmApi(
        summary: const <String, dynamic>{
          'pendingAdjustment': null,
          'topics': <Map<String, dynamic>>[],
        },
      );
      await tester.pumpWidget(
        _host(<dynamic>[
          clubCrmApiProvider.overrideWithValue(api),
        ], const ClubSettlementPage(clubId: 42)),
      );
      await tester.pumpAndSettle();

      expect(find.text('结算数据暂不可用'), findsOneWidget);
      expect(find.textContaining('¥0'), findsNothing);
    });
  });

  group('分润页 · void / 金额待核验不再整页崩', () {
    testWidgets('未核验合计 + 待核验/作废行都渲染,不落 error 态', (WidgetTester tester) async {
      final _FakeClubCrmApi api = _FakeClubCrmApi(
        summary: const <String, dynamic>{
          'settledAmountText': null,
          'settledAmountStatus': 'unverified',
          'unverifiedSettledCount': 1,
          'isOwner': true,
          'topics': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 7,
              'topicId': 91,
              'name': '待核验团',
              'amountText': null,
              'amountStatus': 'unverified',
              'originalAmountText': '¥100.00',
              'executedAdjustmentText': '¥0.00',
              'netAmountText': '¥100.00',
              'arrivedText': '已到账时间待确认',
              'paidText': '实付 ¥100.00',
              'status': 'settled',
            },
            <String, dynamic>{
              'id': 8,
              'topicId': 92,
              'name': '作废团',
              'amountText': '¥50.00',
              'amountStatus': 'verified',
              'originalAmountText': '¥50.00',
              'executedAdjustmentText': '¥10.00',
              'netAmountText': '¥40.00',
              'arrivedText': '已作废',
              'paidText': '实付 ¥50.00',
              'status': 'void',
            },
          ],
        },
      );
      await tester.pumpWidget(
        _host(<dynamic>[
          clubCrmApiProvider.overrideWithValue(api),
        ], const ClubSettlementPage(clubId: 42)),
      );
      await tester.pumpAndSettle();

      // 顶部合计显「金额待核验」而不是报错;副文案点名待核验笔数。
      expect(find.text('结算数据暂不可用'), findsNothing);
      expect(find.text('金额待核验'), findsOneWidget);
      expect(find.text('1 笔已结算记录缺少入账证据，合计待核验'), findsOneWidget);
      // 三列金额逐行上屏(原始应结 / 已执行调整 / 核算净额)。
      expect(find.text('已执行调整 ¥10.00'), findsOneWidget);
      expect(find.text('核算净额 ¥40.00'), findsOneWidget);
      // 状态四态:待核验 / 已作废。
      expect(find.text('待核验'), findsWidgets);
      expect(find.textContaining('已作废'), findsWidgets);
    });

    test('模型:缺原始应结 / 待核验笔数对不上 → 真坏回执,拒收走 error', () {
      expect(
        () => ClubSettlementSummary.fromJson(const <String, dynamic>{
          'settledAmountText': '¥10.00',
          'settledAmountStatus': 'verified',
          'unverifiedSettledCount': 0,
          'topics': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'topicId': 2,
              'name': '缺列团',
              'amountText': '¥10.00',
              'amountStatus': 'verified',
              'arrivedText': 'x',
              'paidText': 'y',
              'status': 'settled',
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('模型:void / 待核验是合法回执,不抛', () {
      final ClubSettlementSummary s = ClubSettlementSummary.fromJson(
        const <String, dynamic>{
          'settledAmountText': null,
          'settledAmountStatus': 'unverified',
          'unverifiedSettledCount': 1,
          'isOwner': true,
          'topics': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 7,
              'topicId': 91,
              'name': '待核验团',
              'amountText': null,
              'amountStatus': 'unverified',
              'originalAmountText': '¥100.00',
              'executedAdjustmentText': '¥0.00',
              'netAmountText': '¥100.00',
              'arrivedText': '待确认',
              'paidText': '实付 ¥100.00',
              'status': 'settled',
            },
          ],
        },
      );
      expect(s.amountUnverified, isTrue);
      expect(s.settledAmountText, isNull);
      expect(s.isOwner, isTrue);
      expect(s.topics.single.amountText, isNull);
      expect(s.topics.single.amountUnverified, isTrue);
    });
  });

  group('分润页 · 提现按 R10 只走客服号', () {
    testWidgets('点提现:不发请求、不进银行卡表单,弹的是共用 R10 弹窗', (WidgetTester tester) async {
      final _FakeClubCrmApi api = _FakeClubCrmApi(summary: _summaryJson);
      final List<String> copied = _captureClipboardWrites(tester);
      await tester.pumpWidget(
        _host(<dynamic>[
          clubCrmApiProvider.overrideWithValue(api),
        ], const ClubSettlementPage(clubId: 42)),
      );
      await tester.pumpAndSettle();

      // 按钮字逐字取小程序 pages/club/settlement 原文。
      expect(find.text('联系平台客服提现'), findsOneWidget);
      await tester.tap(find.byKey(const Key('club-settlement-withdraw')));
      await tester.pumpAndSettle();

      // ★ 落点必须是**共用件**(withdrawal_contact_dialog.dart)—— 标题/文案/号码
      //   都归那一处,本页不再自己写一套(两套实现正是 R10 出错的来源)。
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      // 钮字与弹窗标题都是小程序原文「联系平台客服提现」(settlement/index.wxml:25),
      // 弹窗打开时按钮仍在树后,所以是两处而不是两处不同文案。
      expect(find.text('联系平台客服提现'), findsNWidgets(2));
      // 号码必须真的上屏 —— R10 要用户能看见、能复制。
      expect(find.textContaining(kWithdrawalContactWechatId), findsOneWidget);
      expect(find.textContaining('添加客服微信，核对金额后线下处理'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
      // 进的是弹窗,不是银行卡表单页。
      expect(find.text('银行卡提现表单'), findsNothing);
      // 本页只读过一次 summary,没有第二条动钱的链路。
      expect(api.summaryCalls, 1);
      // 还没点「复制」,不许先写剪贴板。
      expect(copied, isEmpty);
    });

    // ⚠️ 两条判据拆成两个 testWidgets:pumpWidget 会复用已有的 ProviderScope,
    //    在同一个测试里 pump 第二次拿到的还是第一次的 overrides
    //    (见 pages_square_club_detail_golden_test.dart 里同一条教训)。
    testWidgets('点「返回」:只关弹窗,不写剪贴板', (WidgetTester tester) async {
      final List<String> copied = _captureClipboardWrites(tester);
      await tester.pumpWidget(
        _host(<dynamic>[
          clubCrmApiProvider.overrideWithValue(
            _FakeClubCrmApi(summary: _summaryJson),
          ),
        ], const ClubSettlementPage(clubId: 42)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-settlement-withdraw')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();

      expect(copied, isEmpty, reason: '「返回」只关弹窗,不该写剪贴板');
      expect(find.text('复制'), findsNothing);
    });

    testWidgets('点「复制」:写的就是客服微信号', (WidgetTester tester) async {
      final List<String> copied = _captureClipboardWrites(tester);
      await tester.pumpWidget(
        _host(<dynamic>[
          clubCrmApiProvider.overrideWithValue(
            _FakeClubCrmApi(summary: _summaryJson),
          ),
        ], const ClubSettlementPage(clubId: 42)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-settlement-withdraw')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      expect(copied, <String>[kWithdrawalContactWechatId]);
    });
  });

  group('分润页 · E-02 主题行跳转', () {
    testWidgets('点主题行按 topicId 跳结算详情(结算行 id 会永远落「不存在或已不可见」)', (
      WidgetTester tester,
    ) async {
      String? pushed;
      final GoRouter router = GoRouter(
        initialLocation: '/here',
        routes: <RouteBase>[
          GoRoute(
            path: '/here',
            builder: (_, _) => const ClubSettlementPage(clubId: 42),
          ),
          GoRoute(
            path: '/coop/settlement-detail',
            builder: (context, state) {
              pushed = state.uri.toString();
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            clubCrmApiProvider.overrideWithValue(
              _FakeClubCrmApi(summary: _summaryJson),
            ),
          ].cast(),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // fixture:结算行 id=7、topicId=91 —— 两个值不同,跳错立刻可见。
      await tester.tap(find.byKey(const Key('club-settlement-topic-7')));
      await tester.pumpAndSettle();

      expect(
        pushed,
        '/coop/settlement-detail?source=finance&recordId=91',
        reason:
            '真源 pages/club/settlement/index.js#goTopicSettlement 与 coop_finance_page '
            '同口径:source=finance 的 recordId 承载的是 **topicId**,不是结算行 id(E-02)。',
      );
    });
  });

  group('核销页 · 退款是钱路径', () {
    testWidgets('English receipt preserves backend money and cancel does not refund', (tester) async {
      final crm = _FakeClubCrmApi(checkin: _checkinJson);
      final club = _FakeClubApi();
      final cancelled = _Confirm(CyNativeConfirmResult.cancelled);
      await tester.pumpWidget(_host([
        clubCrmApiProvider.overrideWithValue(crm),
        clubApiProvider.overrideWithValue(club),
      ], ClubCheckinDetailPage(clubId: 1, registrationId: 11,
        confirmPresenter: cancelled), locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Redemption details'), findsOneWidget);
      expect(find.text('¥128.00'), findsOneWidget);
      expect(find.text('标准单人票 ×1'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      expect(cancelled.shown, 1);
      expect(club.cancelCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('确认弹窗点「取消」不发退款请求', (WidgetTester tester) async {
      final _FakeClubCrmApi crm = _FakeClubCrmApi(checkin: _checkinJson);
      final _FakeClubApi club = _FakeClubApi();
      final _Confirm cancelled = _Confirm(CyNativeConfirmResult.cancelled);
      await tester.pumpWidget(
        _host(
          <dynamic>[
            clubCrmApiProvider.overrideWithValue(crm),
            clubApiProvider.overrideWithValue(club),
          ],
          ClubCheckinDetailPage(
            clubId: 1,
            registrationId: 11,
            confirmPresenter: cancelled,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();

      expect(cancelled.shown, 1);
      expect(club.cancelCalls, 0);
    });

    testWidgets('回执未知之后按钮挂闸:再点一次不会重复提交', (WidgetTester tester) async {
      final _FakeClubCrmApi crm = _FakeClubCrmApi(checkin: _checkinJson);
      // 网络断在半路:请求可能已经到了服务端 —— 这是「未知」不是「失败」。
      final _FakeClubApi club = _FakeClubApi(
        throwOnCancel: DioException.connectionError(
          requestOptions: RequestOptions(
            path: '/api/registration/cancel-by-owner',
          ),
          reason: 'connection lost',
        ),
      );
      final _Confirm confirmed = _Confirm(CyNativeConfirmResult.confirmed);
      await tester.pumpWidget(
        _host(
          <dynamic>[
            clubCrmApiProvider.overrideWithValue(crm),
            clubApiProvider.overrideWithValue(club),
          ],
          ClubCheckinDetailPage(
            clubId: 1,
            registrationId: 11,
            confirmPresenter: confirmed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();

      expect(club.cancelCalls, 1);
      expect(find.text('退款结果待确认'), findsOneWidget);

      // 再点一次:按钮已挂闸,不许出第二笔。
      await tester.tap(
        find.byKey(const Key('club-checkin-refund')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(club.cancelCalls, 1);
    });
    testWidgets('manual review response is preserved and never toasted as refunded', (tester) async {
      final crm = _FakeClubCrmApi(checkin: _checkinJson);
      final club = _FakeClubApi(outcome: const RegistrationCancellationOutcome(
        cancellationStatus: 'MANUAL_REVIEW', cashRefundStatus: 'MANUAL_REVIEW',
        message: '同单有票已核销，本单未自动退款，已转平台人工处理',
      ));
      await tester.pumpWidget(_host(<dynamic>[
        clubCrmApiProvider.overrideWithValue(crm), clubApiProvider.overrideWithValue(club),
      ], ClubCheckinDetailPage(clubId: 1, registrationId: 11,
        confirmPresenter: _Confirm(CyNativeConfirmResult.confirmed))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      expect(club.cancelCalls, 1);
      expect(find.textContaining('本单未自动退款'), findsWidgets);
      expect(find.text('已退款'), findsNothing);
      await tester.tap(find.byKey(const Key('club-checkin-refund')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(club.cancelCalls, 1);
    });
    testWidgets('late cancellation response after account switch is discarded', (tester) async {
      final pending = Completer<RegistrationCancellationOutcome>();
      final club = _FakeClubApi(pending: pending);
      final crm = _FakeClubCrmApi(checkin: _checkinJson);
      final auth = _SessionAuth();
      await tester.pumpWidget(_host(<dynamic>[
        clubCrmApiProvider.overrideWithValue(crm), clubApiProvider.overrideWithValue(club),
      ], ClubCheckinDetailPage(clubId: 1, registrationId: 11,
        confirmPresenter: _Confirm(CyNativeConfirmResult.confirmed)), auth: auth));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-checkin-refund')));
      await tester.pump();
      expect(club.cancelCalls, 1);
      final readCalls = crm.checkinCalls;
      auth.switchAccount();
      await tester.pump();
      pending.complete(const RegistrationCancellationOutcome(message: 'A-private-refund-receipt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A-private-refund-receipt'), findsNothing);
      expect(crm.checkinCalls, readCalls, reason: 'Do not read A registration back using B session');
      expect(tester.takeException(), isNull);
    });
    testWidgets('account switch while confirming cancels the original refund intent', (tester) async {
      final confirmation = Completer<CyNativeConfirmResult>();
      final presenter = _Confirm(CyNativeConfirmResult.confirmed, pending: confirmation);
      final club = _FakeClubApi();
      final crm = _FakeClubCrmApi(checkin: _checkinJson);
      final auth = _SessionAuth();
      await tester.pumpWidget(_host(<dynamic>[
        clubCrmApiProvider.overrideWithValue(crm), clubApiProvider.overrideWithValue(club),
      ], ClubCheckinDetailPage(clubId: 1, registrationId: 11,
        confirmPresenter: presenter), auth: auth));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('club-checkin-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('club-checkin-refund')));
      await tester.pump();
      expect(presenter.shown, 1, reason: 'The confirmation must be open before switching accounts');
      expect(confirmation.isCompleted, isFalse);
      expect(club.cancelCalls, 0);
      auth.switchAccount();
      await tester.pump();
      confirmation.complete(CyNativeConfirmResult.confirmed);
      await tester.pumpAndSettle();
      expect(club.cancelCalls, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
