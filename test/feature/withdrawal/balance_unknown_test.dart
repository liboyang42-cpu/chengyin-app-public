import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';

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

/// 提现页余额卡的措辞。**资金入口,说错话代价最高。**
///
/// ★ 余额没取到时,界面**绝不能**显示 ¥0.00 ——
///   那是在替用户陈述他的资产,而我们其实不知道。
///   这一页按 R10(2026-09-17)已不再发起提现,但余额仍要如实展示。
Future<void> _pump(WidgetTester tester, double? balance) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
        withdrawableBalanceProvider.overrideWith((ref) async => balance),
        // 余额三段是同一页的第二来源:不注入就会打真接口、pumpAndSettle 停在加载态。
        fundsStagesProvider.overrideWith((ref) async => kFundsStagesFixture),
      ].cast(),
      child: const MaterialApp(home: WithdrawalPage()),
    ),
  );
  // ⚠️ 视口要够高:这些断言用 find.text 直接找,ListView 视口外不构建。
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpAndSettle();
}

Future<void> _pumpError(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
        withdrawableBalanceProvider.overrideWith(
          (ref) async => throw Exception('网络连接失败'),
        ),
        fundsStagesProvider.overrideWith((ref) async => kFundsStagesFixture),
      ].cast(),
      child: const MaterialApp(home: WithdrawalPage()),
    ),
  );
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('余额请求失败 → 说「余额没取到」,不显示 ¥0.00,且给得出重试', (
    WidgetTester tester,
  ) async {
    await _pumpError(tester);

    expect(find.text('余额没取到'), findsOneWidget);
    expect(find.text('¥0.00'), findsNothing, reason: '我们并不知道用户余额是 0,不能这么说');
    expect(find.text('重试'), findsOneWidget, reason: '说了「没取到」就得给得出重试的地方');
  });

  testWidgets('后端 200 但没下发 balance → 同样不显示 ¥0.00', (WidgetTester tester) async {
    // ★ 这是真实可达的一条路:后端 200 了,但 UmsMember 没带 balance。
    //   把它 `?? 0` 掉就会告诉用户「你余额 0」,而我们其实没拿到数 ——
    //   模型把 balance 做成可空,就是为了这条。
    await _pump(tester, null);

    expect(find.text('余额没取到'), findsOneWidget);
    expect(find.text('¥0.00'), findsNothing, reason: '我们并不知道用户余额是 0,不能这么说');
  });

  testWidgets('★ 余额确实是 0 → 才显示 ¥0.00', (WidgetTester tester) async {
    await _pump(tester, 0.0);

    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.text('余额没取到'), findsNothing);
  });

  testWidgets('有余额 → 如实显示金额', (WidgetTester tester) async {
    await _pump(tester, 128.5);

    expect(find.text('¥128.50'), findsOneWidget);
    expect(find.text('余额没取到'), findsNothing);
  });

  testWidgets('★ R10:页面不再有银行卡表单,也不再有任何提交提现的入口', (WidgetTester tester) async {
    await _pump(tester, 328.6);

    expect(
      find.byType(CupertinoTextField),
      findsNothing,
      reason: '银行卡表单已按 R10 删除',
    );
    expect(
      find.byType(CupertinoCheckbox),
      findsNothing,
      reason: '敏感信息同意随表单一起作废',
    );
    expect(find.text('确认提现'), findsNothing);
    expect(find.text('全部提现'), findsNothing, reason: '没有金额输入框了,填金额的按钮不该留');
    // 余额仍照常展示(余额不下线),唯一的动作是联系客服。
    expect(find.text('¥328.60'), findsOneWidget);
    expect(find.byKey(const Key('withdrawal-contact-button')), findsOneWidget);
    expect(find.text('联系客服提现'), findsOneWidget);
  });
}
