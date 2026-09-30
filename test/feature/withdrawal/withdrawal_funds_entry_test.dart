// B1 提现域真跑报告(REPORT-sim-r10-withdrawal)三条 P1 的行为测试:
//   P1-1 提现记录页错误归一 —— DioException 英文原文一个字都不许上屏;
//   P1-2 资产页补「提现记录」入口 —— 此前 /withdrawal-records 全仓零入口;
//   P1-3 两个资金页的游客深链给页内登录门(修法同 roam #208),
//        且那个注定失败的请求根本不发。
//
// ★ 这一页是资金页:错误态里挂「fix the server code」= 让用户去修服务端。

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/api/withdrawal_api.dart';
import 'package:chengyin_app/data/models/asset_record.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/data/models/withdrawal.dart';
import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_records_page.dart';

import '../../support/fixed_auth.dart';
import '../../support/funds_stages_fixture.dart';

const RoleInfo _withdrawableRole = RoleInfo(
  role: 'player',
  permission: <String, dynamic>{'withdrawable': true},
  usage: <String, dynamic>{},
  isClubLeader: false,
  isMerchant: false,
  ownedClubCount: 0,
  maxOwnedClubs: 0,
  ownedClubs: <Map<String, dynamic>>[],
  joinedClubIds: <int>[],
);

/// 与实拍 `02-withdrawal-records-guest.jpg` 同形态的失败:
/// DioException 带整段英文报错体 —— 曾经被 `e.toString()` 直出上屏。
DioException _httpError(int code) => DioException(
  type: DioExceptionType.badResponse,
  requestOptions: RequestOptions(path: '/api/withdrawal/list'),
  response: Response(
    requestOptions: RequestOptions(path: '/api/withdrawal/list'),
    statusCode: code,
    statusMessage: code == 401 ? 'Unauthorized' : 'Internal Server Error',
    data: <String, dynamic>{
      'error':
          'Client error - the request contains bad syntax. '
          'See https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/$code '
          'and fix the server code before retrying.',
    },
  ),
);

class _FakeWithdrawalApi implements WithdrawalApi {
  _FakeWithdrawalApi({this.error});

  /// 非 null 时 list() 抛它;否则返回 [rows]。
  final Object? error;
  List<WithdrawalRecord> rows = const <WithdrawalRecord>[];
  int listCalls = 0;

  @override
  Future<List<WithdrawalRecord>> list() async {
    listCalls += 1;
    if (error != null) throw error!;
    return rows;
  }

  /// 本组用例只测提现记录与入口,不渲染余额三段那块;给个固定替身,
  /// 免得 `implements WithdrawalApi` 少一个成员编不过、更不要打真接口。
  @override
  Future<MemberFundsStages> stages() async => kFundsStagesFixture;
}

class _UnusedAccountApi extends Fake implements AccountApi {}

Future<void> _pump(
  WidgetTester tester, {
  required Widget page,
  required List<dynamic> overrides,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('P1-3 游客深链:页内登录门,注定失败的请求不发', () {
    testWidgets('提现页游客:给「登录后办理提现」+「去登录」,不发 role/info', (
      WidgetTester tester,
    ) async {
      int roleLoads = 0;
      final _FakeWithdrawalApi api = _FakeWithdrawalApi();
      await _pump(
        tester,
        page: const WithdrawalPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(() => FixedAuth(guestAuthState)),
          roleInfoProvider.overrideWith((ref) {
            roleLoads += 1;
            return Completer<RoleInfo>().future;
          }),
          withdrawalApiProvider.overrideWithValue(api),
        ],
      );

      expect(find.byKey(const Key('withdrawal-login-gate')), findsOneWidget);
      expect(find.text('登录后办理提现'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(
        find.text('提现资格暂时无法确认'),
        findsNothing,
        reason: '游客不是「资格无法确认」,是没登录 —— 得说准',
      );
      expect(roleLoads, 0, reason: '游客直达时那个必然 401 的 /api/role/info 不该发');
      expect(api.listCalls, 0);
    });

    testWidgets('提现记录页游客:给登录门,不发 /api/withdrawal/list', (
      WidgetTester tester,
    ) async {
      final _FakeWithdrawalApi api = _FakeWithdrawalApi();
      await _pump(
        tester,
        page: const WithdrawalRecordsPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(() => FixedAuth(guestAuthState)),
          withdrawalApiProvider.overrideWithValue(api),
        ],
      );

      expect(
        find.byKey(const Key('withdrawal-records-login-gate')),
        findsOneWidget,
      );
      expect(find.text('登录后查看提现记录'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(api.listCalls, 0, reason: '游客不发注定失败的记录请求');
    });
  });

  group('P1-1 提现记录错误归一:登录态失败也只说人话', () {
    testWidgets('登录态 401 → 「登录状态已失效」+ 去登录,不拼英文', (WidgetTester tester) async {
      await _pump(
        tester,
        page: const WithdrawalRecordsPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          withdrawalApiProvider.overrideWithValue(
            _FakeWithdrawalApi(error: _httpError(401)),
          ),
        ],
      );

      expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('mozilla'), findsNothing);
    });

    testWidgets('登录态 5xx → 真源文案「提现记录没加载出来」,异常原文不上屏', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        page: const WithdrawalRecordsPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          withdrawalApiProvider.overrideWithValue(
            _FakeWithdrawalApi(error: _httpError(500)),
          ),
        ],
      );

      // title/sub 逐字对齐真源 scene-member-withdraw-history 的 cy-error。
      expect(find.text('提现记录没加载出来'), findsOneWidget);
      expect(find.text('网络可能不稳定，你的提现记录还在'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(
        find.textContaining('fix the server code'),
        findsNothing,
        reason: '资金页不能挂着英文异常让用户去「修服务端」',
      );
      expect(find.textContaining('Client error'), findsNothing);
    });

    testWidgets('回执不完整(非 HTTP 错)同样只落人话文案', (WidgetTester tester) async {
      await _pump(
        tester,
        page: const WithdrawalRecordsPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          withdrawalApiProvider.overrideWithValue(
            _FakeWithdrawalApi(error: const WithdrawalException('提现记录回执不完整')),
          ),
        ],
      );

      expect(find.text('提现记录没加载出来'), findsOneWidget);
    });
  });

  group('P1-2 资产页「提现记录」入口(真源 earnings 卡第三动作)', () {
    testWidgets('入口在列表里,点了进 /withdrawal-records,且不发任何提现请求', (
      WidgetTester tester,
    ) async {
      final _FakeWithdrawalApi api = _FakeWithdrawalApi();
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(path: '/', builder: (_, _) => const AssetsPage()),
          GoRoute(
            path: '/withdrawal-records',
            builder: (_, _) => const Text('records-page-landed'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            // 登录态才有账本可点(游客落在页内登录门,#276 P1-1)。
            authControllerProvider.overrideWith(
              () => FixedAuth(signedInAuthState()),
            ),
            roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
            walletStagesProvider.overrideWith((ref) async => null),
            pointsListProvider.overrideWith(
              (ref) async => const <PointsRecord>[],
            ),
            balanceListProvider.overrideWith(
              (ref) async => const <BalanceRecord>[],
            ),
            accountApiProvider.overrideWithValue(_UnusedAccountApi()),
            withdrawalApiProvider.overrideWithValue(api),
          ].cast(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('assets-withdrawal-records-entry')),
      );
      await tester.pumpAndSettle();

      expect(find.text('records-page-landed'), findsOneWidget);
      expect(api.listCalls, 0, reason: '列表数据由记录页自己拉,点入口这一下不发请求');
    });
  });
}
