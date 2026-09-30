// 资产明细页的「余额三段」块(`POST /api/wallet/stages`)。
//
// 对齐小程序 `components/cy/funds-stages`:三段 + 涉诉单列 + 如实提示;
// 读不到时整块只说「未到账金额暂时取不到」并给「重试」——**不画 ¥0**。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/models/asset_record.dart';
import 'package:chengyin_app/data/models/funds_stages.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import '../../golden/golden_theme.dart';

/// 三段块在登录后的余额 Tab 里(资产页对游客是页内登录门 #276 P1-1)。
class _SignedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '玩家', avatar: '', role: 'player'),
  );
}

const RoleInfo _role = RoleInfo(
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

Widget _app(List<dynamic> overrides) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_SignedInAuth.new),
      ...overrides,
    ].cast(),
    child: MaterialApp(theme: goldenTheme(), home: const AssetsPage()),
  );
}

void main() {
  testWidgets('★★ 三段 + 涉诉单列:金额与「客诉期中 · X月X日可提现」照后端原样', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(<dynamic>[
        roleInfoProvider.overrideWith((ref) async => _role),
        pointsListProvider.overrideWith((ref) async => const <PointsRecord>[]),
        balanceListProvider.overrideWith(
          (ref) async => const <BalanceRecord>[],
        ),
        walletStagesProvider.overrideWith(
          (ref) async => buildFundsStages(<String, dynamic>{
            'amountsKnown': true,
            'pendingSettlement': 90,
            'complaintPeriod': <dynamic>[
              <String, dynamic>{'amount': 45.5, 'availableDate': '2026-09-24'},
            ],
            'disputed': 18,
            'withdrawable': 12,
          }),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('余额'));
    await tester.pumpAndSettle();

    expect(find.text('待结算（活动未结束）'), findsOneWidget);
    expect(find.text('¥90.00'), findsOneWidget);
    expect(find.text('客诉期中 · 9月24日可提现'), findsOneWidget);
    expect(find.text('¥45.50'), findsOneWidget);
    expect(find.text('客诉处理中'), findsOneWidget);
    expect(find.text('¥18.00'), findsOneWidget);
    expect(find.text('可提现'), findsOneWidget);
    expect(find.text('¥12.00'), findsOneWidget);
  });

  testWidgets('★★ 读不到:只说「未到账金额暂时取不到」,不画 ¥0,重试可再拉一次', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int calls = 0;
    await tester.pumpWidget(
      _app(<dynamic>[
        roleInfoProvider.overrideWith((ref) async => _role),
        pointsListProvider.overrideWith((ref) async => const <PointsRecord>[]),
        balanceListProvider.overrideWith(
          (ref) async => const <BalanceRecord>[],
        ),
        walletStagesProvider.overrideWith((ref) async {
          calls += 1;
          return null;
        }),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('余额'));
    await tester.pumpAndSettle();

    expect(find.text('未到账金额暂时取不到'), findsOneWidget);
    expect(find.text('¥0.00'), findsNothing);
    expect(calls, 1);

    await tester.tap(find.byKey(const Key('assets-stages-retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('★ 后端说费率算不出:如实提示「以结算到账为准」', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(<dynamic>[
        roleInfoProvider.overrideWith((ref) async => _role),
        pointsListProvider.overrideWith((ref) async => const <PointsRecord>[]),
        balanceListProvider.overrideWith(
          (ref) async => const <BalanceRecord>[],
        ),
        walletStagesProvider.overrideWith(
          (ref) async => buildFundsStages(<String, dynamic>{
            'amountsKnown': false,
            'pendingSettlement': 0,
            'complaintPeriod': <dynamic>[],
            'disputed': 0,
            'withdrawable': 5,
          }),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('余额'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assets-stages-unknown-note')), findsOneWidget);
    expect(find.text('部分未到账金额暂时算不出，以结算到账为准'), findsOneWidget);
    // 可提现 0 是合法金额:照实画 ¥5.00,只是 ≤0 的段不画。
    expect(find.text('¥5.00'), findsOneWidget);
    expect(find.text('待结算（活动未结束）'), findsNothing);
  });
}
