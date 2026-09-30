// R10(收款模型过渡期,2026-09-17)的提现出口。
//
// ★ 用户拍板:过渡期**所有「提现」入口**点击后弹中间弹窗 ——
//   显示微信号 + 「返回」「复制」,不再进银行卡表单 / 转零钱,
//   不做提现风险确认,**不发任何提现请求**;双方线下结算。
//   真源:`收款模型_主办方自收与平台自动分账_定稿_20260915.md` §0。
//
// 这一组测试盯三件事(缺一不可):
//   ① 点提现**不发任何提现请求** —— 资金入口,误发一笔就是真金白银;
//   ② 弹窗必须**显示号码** —— 号码不出现,线下就联系不上;
//   ③ 「复制」必须**写进剪贴板** —— 写不进去,用户只能手抄 11 位数字。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/funds_stages_fixture.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/api/withdrawal_api.dart';
import 'package:chengyin_app/data/models/asset_record.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/data/models/withdrawal.dart';
import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_contact_dialog.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';

import '../../support/fixed_auth.dart';

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

/// 任何一次调用都会被记下来 —— 用来证明「一个提现请求都没发」。
class _NoRequestsAccountApi extends Fake implements AccountApi {
  final List<String> calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _NoRequestsWithdrawalApi extends Fake implements WithdrawalApi {
  final List<String> calls = <String>[];

  /// 余额三段是**读**不是提现请求(R10 只禁提现入口),因此不计入 [calls]。
  @override
  Future<MemberFundsStages> stages() async => kFundsStagesFixture;

  @override
  Future<List<WithdrawalRecord>> list() async {
    calls.add('list');
    return const <WithdrawalRecord>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _DialogHost extends StatelessWidget {
  const _DialogHost();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext inner) => Center(
          child: CupertinoButton(
            key: const Key('open-dialog'),
            onPressed: () => showWithdrawalContactDialog(inner),
            child: const Text('提现'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('★ 点提现:弹客服弹窗,且一个提现请求都不发', (WidgetTester tester) async {
    final _NoRequestsAccountApi accountApi = _NoRequestsAccountApi();
    final _NoRequestsWithdrawalApi withdrawalApi = _NoRequestsWithdrawalApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          // 资产页游客是登录门,点提现这条测的是登录后账本(#276 P1-1)。
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
          pointsListProvider.overrideWith(
            (ref) async => const <PointsRecord>[],
          ),
          balanceListProvider.overrideWith(
            (ref) async => const <BalanceRecord>[],
          ),
          walletStagesProvider.overrideWith((ref) async => null),
          accountApiProvider.overrideWithValue(accountApi),
          withdrawalApiProvider.overrideWithValue(withdrawalApi),
        ].cast(),
        child: const MaterialApp(home: AssetsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assets-withdrawal-entry')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.textContaining(kWithdrawalContactWechatId), findsOneWidget);
    expect(accountApi.calls, isEmpty, reason: '过渡期不再收集银行卡敏感信息,不该有任何同意写入');
    expect(withdrawalApi.calls, isEmpty, reason: '点提现不发任何提现请求');
  });

  testWidgets('★ 提现页「联系客服提现」:同样弹窗且不发请求', (WidgetTester tester) async {
    final _NoRequestsAccountApi accountApi = _NoRequestsAccountApi();
    final _NoRequestsWithdrawalApi withdrawalApi = _NoRequestsWithdrawalApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
          withdrawableBalanceProvider.overrideWith((ref) async => 328.6),
          accountApiProvider.overrideWithValue(accountApi),
          withdrawalApiProvider.overrideWithValue(withdrawalApi),
        ].cast(),
        child: const MaterialApp(home: WithdrawalPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('withdrawal-contact-button')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.textContaining(kWithdrawalContactWechatId), findsOneWidget);
    expect(accountApi.calls, isEmpty);
    expect(withdrawalApi.calls, isEmpty);
  });

  testWidgets('弹窗显示号码 + 「返回」「复制」两个按钮', (WidgetTester tester) async {
    await tester.pumpWidget(const _DialogHost());
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();

    expect(find.textContaining(kWithdrawalContactWechatId), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
  });

  testWidgets('★ 「复制」把微信号写进剪贴板', (WidgetTester tester) async {
    final List<MethodCall> platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(const _DialogHost());
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    final MethodCall copy = platformCalls.singleWhere(
      (MethodCall call) => call.method == 'Clipboard.setData',
    );
    expect(
      (copy.arguments as Map<dynamic, dynamic>)['text'],
      kWithdrawalContactWechatId,
    );
    // 复制后弹窗关闭,回到页面。
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('★ 弹窗文案 1:1 贴真源 withdraw-cs.js(标题/正文/复制提示)', (
    WidgetTester tester,
  ) async {
    // B1 真跑报告 P2-1:App 侧曾自造三处文案,这里逐字钉回真源。
    // 剪贴板走平台通道,测试环境没有真实现 —— 先挂一个静默 mock,
    // 否则「复制」按下去直接 MissingPluginException,弹窗都关不掉。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(const _DialogHost());
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();

    expect(find.text('联系平台客服提现'), findsOneWidget);
    expect(
      find.text('客服微信号：$kWithdrawalContactWechatId\n添加客服微信，核对金额后线下处理'),
      findsOneWidget,
    );

    await tester.tap(find.text('复制'));
    // 浮层入场动画走完后 pumpAndSettle 就停(2.4s 退场是 Timer,不排帧),
    // toast 还挂在 overlay 上 —— 这正是能断言到措辞的窗口。
    await tester.pumpAndSettle();
    expect(find.text('已复制微信号'), findsOneWidget, reason: 'toast 措辞跟真源');
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  // b1 报告 P2-6:真源 copyWithdrawCsWechat 有 fail 分支,App 此前只处理成功半边。
  testWidgets('★ 复制失败(平台通道抛错)→ 「复制失败，请手动添加客服微信」toast', (
    WidgetTester tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'copy_failed');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(const _DialogHost());
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(
      find.text('复制失败，请手动添加客服微信'),
      findsOneWidget,
      reason: '失败兜底文案 1:1 真源 withdraw-cs.js',
    );
    expect(find.text('已复制微信号'), findsNothing);
    // ⚠️ 别把 11 位微信号拼进失败 toast:真源 safeUserMessage 会把它过滤成「操作失败」。
    expect(
      find.textContaining(kWithdrawalContactWechatId),
      findsNothing,
      reason: '弹窗已关,失败提示里不该带号码',
    );
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('「返回」只关闭弹窗,不复制也不跳转', (WidgetTester tester) async {
    await tester.pumpWidget(const _DialogHost());
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('提现'), findsOneWidget);
  });
}
