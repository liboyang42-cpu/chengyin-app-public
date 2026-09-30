// 提现页三态快照。**这是资金入口,说错话代价最高。**
//
// ★ 2026-09-17 按 R10 改造后,这一页不再有银行卡表单/风险确认/提交按钮,
//   唯一的动作是「联系客服提现」(弹微信号 + 返回/复制)。
//   余额卡保留,因为这组图要盯的正是它的措辞:
//   · 余额拿不到 → 不能显示成「可提现 ¥0.00」,那是「你没钱」的意思
//   · 余额为 0   → 明确显示 ¥0.00
//   · 有余额     → 正常
//
// 更新基准图:flutter test --update-goldens test/golden/pages_withdrawal_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

import '../support/fixed_auth.dart';
import 'golden_theme.dart';
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

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(() => FixedAuth(signedInAuthState())),
      roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
      // 余额三段是本页的第二来源;不注入就会打真接口,pumpAndSettle 停在加载态。
      fundsStagesProvider.overrideWith((ref) async => kFundsStagesFixture),
      ...overrides,
    ].cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      // ★ 同 pages_official_points_golden_test.dart 的 `_pointsApp`:
      //   真机根 CupertinoApp 给整棵树一层带系统字族的 DefaultTextStyle,
      //   快照宿主是 MaterialApp,裸 TextStyle(CyType.* 全档 family=null)
      //   会落到 flutter_test 的默认族上 ⇒ 满屏豆腐。修在测试侧。
      home: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto'),
        child: home,
      ),
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 860));
  await tester.pumpWidget(app);
  // ⚠️ 只推两帧会拍到 **loading 帧** —— Future 还没 resolve/reject。
  //    我第一次就这么拍的,图上顶部写「加载中…」、底部写「余额没取到」,
  //    我差点把这个矛盾当成产品 bug 报出去 —— 其实 error 分支写得好好的,
  //    是测试没等到位。拍异步页先确认拍到的是**终态**。
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('提现:有可提现余额', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        withdrawableBalanceProvider.overrideWith((ref) async => 328.60),
      ], const WithdrawalPage()),
      'goldens/page_withdrawal_has_balance.png',
    );
  });

  testWidgets('★ 提现:余额是 0(明确没钱,不是拿不到)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        withdrawableBalanceProvider.overrideWith((ref) async => 0.0),
      ], const WithdrawalPage()),
      'goldens/page_withdrawal_zero.png',
    );
  });

  testWidgets('★★ 提现:余额拿不到 —— 绝不能显示成「可提现 ¥0.00」', (WidgetTester tester) async {
    // 「拿不到」和「是 0」在钱面上是两件完全不同的事:
    //   前者该说「余额没取到,请重试」;
    //   后者才能显示 ¥0.00。
    // 渲成同一句「¥0.00」的话,一个余额接口抖动会让用户以为自己的钱没了。
    await _shot(
      tester,
      _app([
        withdrawableBalanceProvider.overrideWith(
          (ref) async => throw Exception('网络连接失败'),
        ),
      ], const WithdrawalPage()),
      'goldens/page_withdrawal_unknown.png',
    );
  });
}
