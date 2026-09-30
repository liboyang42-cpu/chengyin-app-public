// 提现页余额卡的状态分派。**资金入口,说错话代价最高。**
//
// 盯的是一个具体形态:Riverpod 的 `AsyncLoading` 可以**同时带着上一次的错误**
// (刷新时就是这样,实测 hasError=true 且 isLoading=true)。
// `AsyncValue.when()` 遇到它会走 loading 分支 —— 于是卡片写「加载中…」,
// 而用户同时看到别处写着「余额没取到」,两句话互相矛盾,
// 用户会一直等一个不会来的数字。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

import '../support/fixed_auth.dart';

import '../support/funds_stages_fixture.dart';

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

Future<void> _pump(WidgetTester tester, List<dynamic> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
        fundsStagesProvider.overrideWith((ref) async => kFundsStagesFixture),
        ...overrides,
      ].cast(),
      child: MaterialApp(theme: AppTheme.dark(), home: const WithdrawalPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★ 带着错误的 loading:说「没取到」,不许说「加载中」', (WidgetTester tester) async {
    await _pump(tester, <dynamic>[
      withdrawableBalanceProvider.overrideWith(
        (ref) async => throw Exception('网络连接失败'),
      ),
    ]);

    expect(find.text('余额没取到'), findsOneWidget);
    expect(
      find.text('加载中…'),
      findsNothing,
      reason: '已经拿到错误了还说在加载 —— 同一屏会出现两句互相矛盾的话',
    );
    expect(find.text('重试'), findsOneWidget, reason: '说了「请先重试」就得给得出重试的地方');
  });

  testWidgets('★ 余额为 0 与余额拿不到必须是两句话', (WidgetTester tester) async {
    await _pump(tester, <dynamic>[
      withdrawableBalanceProvider.overrideWith((ref) async => 0.0),
    ]);
    // 0 是一个**已知**的事实,要如实显示金额,不能说「没取到」
    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.text('余额没取到'), findsNothing, reason: '「你没有钱」和「我不知道你有多少钱」是两件事');
  });

  testWidgets('有余额时如实显示金额', (WidgetTester tester) async {
    await _pump(tester, <dynamic>[
      withdrawableBalanceProvider.overrideWith((ref) async => 328.60),
    ]);
    expect(find.text('¥328.60'), findsOneWidget);
  });
}
