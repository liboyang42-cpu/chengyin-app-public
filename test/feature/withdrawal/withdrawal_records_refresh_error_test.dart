// 提现记录页「刷新失败但记录还在」分支 —— 真源 scene-member-withdraw-history:
// 有列表时 loadErr 只在列表顶部挂非阻断横幅(「更多提现记录没加载出来 /
// 已加载的记录仍为你保留」),整屏 cy-error 只留给一条都没有的情况。
// 与 #200 订单页同一纪律(资金页更不该把已看到的记录整屏吃掉)。

import 'package:chengyin_app/data/models/withdrawal.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_records_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixed_auth.dart';

WithdrawalRecord _record() => WithdrawalRecord(
  id: 7,
  amount: 128.0,
  status: 1,
  bankName: '招商银行',
  bankAccount: '6225880123456789',
  createTime: '2026-08-18 10:20:00',
);

Future<void> _pumpLoggedIn(WidgetTester tester, List<dynamic> overrides) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        ...overrides,
      ].cast(),
      child: const MaterialApp(home: WithdrawalRecordsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('刷新失败但记录还在:保留列表 + 真源横幅,不整屏翻错误', (WidgetTester tester) async {
    int calls = 0;
    await _pumpLoggedIn(tester, <dynamic>[
      withdrawalRecordsProvider.overrideWith((Ref ref) async {
        calls++;
        if (calls == 1) return <WithdrawalRecord>[_record()];
        throw Exception('boom');
      }),
    ]);
    expect(find.text('¥128.00'), findsOneWidget);

    ProviderScope.containerOf(
      tester.element(find.byType(WithdrawalRecordsPage)),
    ).invalidate(withdrawalRecordsProvider);
    await tester.pumpAndSettle();

    expect(
      find.text('¥128.00'),
      findsOneWidget,
      reason: '刷新失败不该丢掉已加载的提现记录(真源同分支保留列表)',
    );
    expect(find.text('更多提现记录没加载出来'), findsOneWidget);
    expect(find.text('已加载的记录仍为你保留'), findsOneWidget);
    expect(find.text('提现记录没加载出来'), findsNothing);
  });

  testWidgets('一条都没有时刷新失败:仍是整屏人话错误 + 重试', (WidgetTester tester) async {
    await _pumpLoggedIn(tester, <dynamic>[
      withdrawalRecordsProvider.overrideWith(
        (Ref ref) async => throw Exception('boom'),
      ),
    ]);
    expect(find.text('提现记录没加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('更多提现记录没加载出来'), findsNothing);
  });

  testWidgets('空态文案逐字贴真源 cy-empty(不说「发起提现后…」)', (WidgetTester tester) async {
    await _pumpLoggedIn(tester, <dynamic>[
      withdrawalRecordsProvider.overrideWith(
        (Ref ref) async => const <WithdrawalRecord>[],
      ),
    ]);
    expect(find.text('暂无提现记录'), findsOneWidget);
    expect(find.text('你还没有发起过提现，提现记录会显示在这里'), findsOneWidget);
  });
}
