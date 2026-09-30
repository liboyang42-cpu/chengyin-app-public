// 提现/支付域 B1 修复线(b1-sim-r10-withdrawal)回归锁。
//
//   P1-1 提现记录页读失败:后端中文原话优先上屏,dio 英文栈换真源兜底文案;
//   P1-2 提现记录从资产页有真实入口(App 内可达);
//   P1-3 会话过期(已登录但 401)两页落「登录状态已失效」门,不谎报故障;
//        游客深链的页顶登录门由 main #279(withdrawal_funds_entry_test)钉住;
//   P2-1 客服弹窗文案逐字对齐真源 utils/withdraw-cs.js。
//
// 反面纪律(同 my_plays_guest_401):断网 / 5xx **不能**被当成要登录。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/api/withdrawal_api.dart';
import 'package:chengyin_app/data/models/asset_record.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/data/models/withdrawal.dart';
import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_contact_dialog.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_records_page.dart';

import '../../support/fixed_auth.dart';

const String _recordsPath = '/api/withdrawal/list';

DioException _http(int status, {Object? body}) => DioException(
  requestOptions: RequestOptions(path: _recordsPath),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: _recordsPath),
    statusCode: status,
    data: body,
  ),
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: _recordsPath),
  type: DioExceptionType.connectionError,
);

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

void main() {
  group('P1-1/P1-3 提现记录页', () {
    // main #279 后记录页先按登录态挡游客,错误分支只在登录态下可达;
    // 这里统一给登录态 fixture,测的是「已登录但这次读失败」那一档。
    Future<void> pumpRecords(WidgetTester tester, Object error) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            authControllerProvider.overrideWith(
              () => FixedAuth(signedInAuthState()),
            ),
            withdrawalRecordsProvider.overrideWith((_) async => throw error),
          ].cast(),
          child: const MaterialApp(home: WithdrawalRecordsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('401(会话过期)→ 登录门,不画 dio 异常原文', (tester) async {
      await pumpRecords(
        tester,
        _http(
          401,
          body: <String, dynamic>{'msg': '登录状态已失效，请重新登录', 'code': 401},
        ),
      );
      expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('developer.mozilla.org'), findsNothing);
    });

    testWidgets('500 带后端中文 msg → 用原话,不画 dio 异常原文', (tester) async {
      await pumpRecords(
        tester,
        _http(500, body: <String, dynamic>{'msg': '服务繁忙，请稍后重试'}),
      );
      expect(find.text('提现记录没加载出来'), findsOneWidget);
      expect(find.text('服务繁忙，请稍后重试'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      // 非 401 不该被推去登录。
      expect(find.text('去登录'), findsNothing);
    });

    testWidgets('断网 → 真源兜底人话,不甩英文堆栈', (tester) async {
      await pumpRecords(tester, _offline());
      expect(find.text('提现记录没加载出来'), findsOneWidget);
      expect(find.text('网络可能不稳定，你的提现记录还在'), findsOneWidget);
      expect(find.textContaining('ConnectionException'), findsNothing);
      expect(find.text('去登录'), findsNothing);
    });
  });

  group('P1-3 提现页登录门(登录态会话过期档)', () {
    // 游客在页顶就被 main #279 的「登录后办理提现」门挡下(已有测试钉住);
    // 这里锁登录态下角色接口 401 的那一档:是可恢复的登录门,不是故障。
    List<dynamic> signedIn() => <dynamic>[
      authControllerProvider.overrideWith(() => FixedAuth(signedInAuthState())),
    ];

    testWidgets('角色接口 401 → 登录门,不是「提现资格暂时无法确认」', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            ...signedIn(),
            roleInfoProvider.overrideWith(
              (_) async => throw _http(
                401,
                body: <String, dynamic>{'msg': '登录状态已失效，请重新登录'},
              ),
            ),
          ].cast(),
          child: const MaterialApp(home: WithdrawalPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('提现资格暂时无法确认'), findsNothing);
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('角色接口断网 → 仍是「提现资格暂时无法确认」,不误判成登录', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            ...signedIn(),
            roleInfoProvider.overrideWith((_) async => throw _offline()),
          ].cast(),
          child: const MaterialApp(home: WithdrawalPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('提现资格暂时无法确认'), findsOneWidget);
      expect(find.text('去登录'), findsNothing);
    });
  });

  group('P1-2 提现记录入口可达', () {
    testWidgets('资产页有「提现记录」入口,点进 /withdrawal-records', (tester) async {
      final router = GoRouter(
        initialLocation: '/assets',
        routes: <RouteBase>[
          GoRoute(
            path: '/assets',
            builder: (_, _) =>
                const AssetsPage(), // 内部 context.push('/withdrawal-records')
          ),
          GoRoute(
            path: '/withdrawal-records',
            builder: (_, _) => const SizedBox(key: Key('records-landed')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            // 登录态才有账本可点(游客落在页内登录门,#276 P1-1)。
            authControllerProvider.overrideWith(
              () => FixedAuth(signedInAuthState()),
            ),
            roleInfoProvider.overrideWith((_) async => _withdrawableRole),
            walletStagesProvider.overrideWith((_) async => null),
            pointsListProvider.overrideWith(
              (_) async => const <PointsRecord>[],
            ),
            balanceListProvider.overrideWith(
              (_) async => const <BalanceRecord>[],
            ),
            withdrawalApiProvider.overrideWithValue(_NullWithdrawalApi()),
          ].cast(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assets-withdrawal-records-entry')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('assets-withdrawal-records-entry')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('records-landed')), findsOneWidget);
    });
  });

  group('P2-1 客服弹窗文案逐字对真源 withdraw-cs.js', () {
    testWidgets('标题 / 正文(客服微信号：… + 线下处理提示)与真源一致', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (inner) => Center(
                child: CupertinoButton(
                  key: const Key('open'),
                  onPressed: () => showWithdrawalContactDialog(inner),
                  child: const Text('提现'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(find.text('联系平台客服提现'), findsOneWidget);
      expect(find.text('提现请联系客服'), findsNothing, reason: '旧偏离文案不该留');
      expect(
        find.textContaining('客服微信号：$kWithdrawalContactWechatId'),
        findsOneWidget,
      );
      expect(find.textContaining('添加客服微信，核对金额后线下处理'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
    });
  });
}

/// 只读 Fake,记录不应被调用(入口测试不触发记录页请求)。
class _NullWithdrawalApi extends Fake implements WithdrawalApi {
  @override
  Future<List<WithdrawalRecord>> list() async => const <WithdrawalRecord>[];
}
