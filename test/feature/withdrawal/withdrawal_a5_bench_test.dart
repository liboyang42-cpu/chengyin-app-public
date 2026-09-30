// A5 iOS 27 外观首遍复核(#a5-ios27-payment-101)对资金面的渲染取证(bench)。
//
// 覆盖:提现主页(WithdrawalPage)、提现记录页(WithdrawalRecordsPage)、
//       R10 客服弹窗(showWithdrawalContactDialog 归口 cyConfirm 后的回退形态)。
// 判定口径:结构 1:1 跟真源 `subpackageMember/tixian` + `components/cy/
// funds-stages` + `scene-member-withdraw-history`,字号必须落 CyType 梯级,
// 灰块/圆角/触达按真源归径;色一律取 CyPalette 语义值(双态可读两臂各测)。
//
// 先例:#413 `advanced_configurator_bench_test.dart`、#295 `roam_team_a5_bench_test.dart`。
// 默认只跑轻量断言(任何机器都绿,不进 CI golden);出图:
//   BENCH_CAPTURE=1 flutter test --update-goldens test/feature/withdrawal/withdrawal_a5_bench_test.dart
// 产物写到 `out/bench_a5_pay101_*.png`(复核留档 —— 回归基准在
// test/golden/pages_withdrawal_golden_test.dart)。行为契约(R10 不发提现请求、
// 剪贴板写号、文案逐字)由同目录 withdrawal_r10_* 钉,这里不重复造。

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Material, MaterialApp, Scaffold, ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/data/models/withdrawal.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_contact_dialog.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_records_page.dart';

import '../../golden/golden_theme.dart';
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

const RoleInfo _plainRole = RoleInfo(
  role: 'player',
  permission: <String, dynamic>{'withdrawable': false},
  usage: <String, dynamic>{},
  isClubLeader: false,
  isMerchant: false,
  ownedClubCount: 0,
  maxOwnedClubs: 0,
  ownedClubs: <Map<String, dynamic>>[],
  joinedClubIds: <int>[],
);

bool get _capture => Platform.environment['BENCH_CAPTURE'] == '1';

/// 快照宿主的字族补层(口径同 pages_official_points_golden_test.dart 的
/// `_pointsApp`):真机根 CupertinoApp 自带带系统字族的 DefaultTextStyle,
/// 测试宿主是 MaterialApp,裸 TextStyle(CyType.* 全档 family=null)会落到
/// flutter_test 默认族上 ⇒ 取证图满屏豆腐。修在测试侧,不动 lib/。
Widget _gold(Widget home) => DefaultTextStyle(
  style: const TextStyle(fontFamily: 'Roboto'),
  child: home,
);

final Key _benchKey = const Key('bench-a5-pay101');

// 多 worker 高负载机器上 pumpAndSettle 实测挂满 10 分钟墙钟(先例 #295
// roam_team_a5_bench_test.dart 同款)。本 bench 各臂无永续动画(future 落地后
// spinner 即消失),改为确定性帧数推进:前几帧放 future 落地,后几帧把
// 路由转场一次推到底,再补一帧收尾 rebuild。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump();
}

Future<void> _save(WidgetTester tester, String name) async {
  if (!_capture) return;
  final Finder boundary = find.byKey(_benchKey);
  expect(boundary, findsOneWidget);
  // 出图走 matchesGoldenFile(--update-goldens)而不是手搓
  // `RenderRepaintBoundary.toImage`:后者在本机(Rosetta x64 flutter_tester +
  // 多 worker 负载)实测 body 全部跑完后 teardown 挂满 10 分钟测试超时
  // —— 图画出来了、test 不结束。golden 管线是今天刚验证过能收口的路径。
  // 用法:BENCH_CAPTURE=1 flutter test --update-goldens <本文件>
  // matchesGoldenFile 的相对路径以**测试文件所在目录**为基:
  // test/feature/withdrawal/ → 仓库根要退三级。
  await expectLater(
    boundary,
    matchesGoldenFile('../../../out/bench_a5_pay101_$name.png'),
  );
}

/// 主页(双源:余额 + 三段)。视口给足高度,ListView 外不构建。
Future<void> _pumpWithdrawal(
  WidgetTester tester, {
  double? balance = 328.6,
  Object? balanceError,
  Object? stagesError,
  RoleInfo role = _withdrawableRole,
  bool signedIn = true,
  ThemeData? theme,
}) async {
  // 口径同 #295:`setGoldenViewport`(view.physicalSize+dpr)而非
  // `binding.setSurfaceSize` —— 后者与 RepaintBoundary.toImage 组合在本机
  // 实测 body 跑完后 teardown 挂满 10 分钟超时(图写出来了、test 不结束)。
  setGoldenViewport(tester, const Size(390, 1400));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedIn ? signedInAuthState() : guestAuthState),
        ),
        roleInfoProvider.overrideWith((ref) async => role),
        withdrawableBalanceProvider.overrideWith((ref) async {
          if (balanceError != null) throw balanceError;
          return balance;
        }),
        fundsStagesProvider.overrideWith((ref) async {
          if (stagesError != null) throw stagesError;
          return kFundsStagesFixture;
        }),
      ].cast(),
      child: RepaintBoundary(
        key: _benchKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme ?? goldenTheme(),
          home: _gold(const WithdrawalPage()),
        ),
      ),
    ),
  );
  await _settle(tester);
}

CyPalette _palette(WidgetTester tester, Finder f) =>
    CyPalette.of(tester.element(f));

/// 取包含 [child] 的第一个带色 DecoratedBox(灰块/灰行容器)。
BoxDecoration _boxAround(WidgetTester tester, Finder child, Color color) {
  final Iterable<DecoratedBox> boxes = tester
      .widgetList<DecoratedBox>(
        find.ancestor(of: child, matching: find.byType(DecoratedBox)),
      )
      .where((DecoratedBox b) => b.decoration is BoxDecoration)
      .where(
        (DecoratedBox b) => (b.decoration as BoxDecoration).color == color,
      );
  expect(boxes, isNotEmpty, reason: '找不到底色为 $color 的容器');
  return boxes.first.decoration as BoxDecoration;
}

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('主页·正常态:记录入口灰块 44pt 触达、圆角归径 radiusMd', (
    WidgetTester tester,
  ) async {
    await _pumpWithdrawal(tester);
    final CyPalette palette = _palette(tester, find.text('提现记录'));
    expect(
      tester.getSize(find.byKey(const Key('withdrawal-records-entry'))).height,
      greaterThanOrEqualTo(44),
    );
    final BoxDecoration deco = _boxAround(
      tester,
      find.text('提现记录'),
      palette.actionSecondaryBg,
    );
    expect((deco.borderRadius! as BorderRadius).topLeft.x, CyTokens.radiusMd);
    // 入口文字在梯级上:headline 17 w600(真源 .tx-history-entry body w600)。
    final TextStyle entryStyle = tester.widget<Text>(find.text('提现记录')).style!;
    expect(entryStyle.fontSize, 17);
    expect(entryStyle.fontWeight, FontWeight.w600);
    await _save(tester, 'withdrawal_normal_dark');
  });

  testWidgets('主页·余额行:真源单行左右制,金额 headline 17 w600,底色 inputBgEmpty', (
    WidgetTester tester,
  ) async {
    await _pumpWithdrawal(tester);
    final CyPalette palette = _palette(tester, find.text('可提现余额'));
    final Offset label = tester.getCenter(find.text('可提现余额'));
    final Offset amount = tester.getCenter(find.text('¥328.60'));
    expect(amount.dy, closeTo(label.dy, 12), reason: '真源 .txyr 是单行左右排');
    expect(amount.dx, greaterThan(label.dx));
    final TextStyle amountStyle = tester
        .widget<Text>(find.text('¥328.60'))
        .style!;
    expect(amountStyle.fontSize, 17);
    expect(amountStyle.fontWeight, FontWeight.w600);
    expect(
      amountStyle.color,
      palette.textPrimary,
      reason: 'C4:内容层取值色走 palette 语义值',
    );
    _boxAround(tester, find.text('可提现余额'), palette.inputBgEmpty);
    // 不再单设「特写」取证点:整页图 withdrawal_normal_dark 已含余额行,
    // 同视口同状态的第二次拍摄没有证据价值(critic round2 B3)。
  });

  testWidgets('主页·三段灰块:label caption1 12、金额 12 w600、底色 actionSecondaryBg', (
    WidgetTester tester,
  ) async {
    await _pumpWithdrawal(tester);
    final Finder label = find.text('待结算（活动未结束）');
    expect(label, findsOneWidget);
    final CyPalette palette = _palette(tester, label);
    expect(tester.widget<Text>(label).style!.fontSize, 12);
    final TextStyle valueStyle = tester
        .widget<Text>(find.text('¥88.50'))
        .style!;
    expect(valueStyle.fontSize, 12);
    expect(valueStyle.fontWeight, FontWeight.w600);
    _boxAround(tester, label, palette.actionSecondaryBg);
    // 客诉档如实成行(真源 fs-row 循环)。
    expect(find.text('客诉期中 · 9月25日可提现'), findsOneWidget);
  });

  testWidgets('主页·取不到档:余额行内「余额没取到」+ 重试药丸 44pt;三段错误同灰块', (
    WidgetTester tester,
  ) async {
    await _pumpWithdrawal(
      tester,
      balanceError: Exception('boom'),
      stagesError: Exception('boom'),
    );
    expect(find.text('余额没取到'), findsOneWidget);
    final Size retry = tester.getSize(find.byKey(const Key('balance-retry')));
    expect(retry.height, greaterThanOrEqualTo(44));
    expect(retry.width, greaterThanOrEqualTo(44));
    expect(find.text('未到账金额暂时取不到'), findsOneWidget);
    final Size stagesRetry = tester.getSize(
      find.byKey(const Key('funds-stages-retry')),
    );
    expect(stagesRetry.height, greaterThanOrEqualTo(44));
    // 真源错误档 `.fs fs-row`:同一行两端排,左说明右「重试」。
    final Offset fsMsg = tester.getCenter(find.text('未到账金额暂时取不到'));
    final Offset fsRetry = tester.getCenter(
      find.byKey(const Key('funds-stages-retry')),
    );
    expect(fsRetry.dy, closeTo(fsMsg.dy, 12), reason: '真源是单行左右排');
    expect(fsRetry.dx, greaterThan(fsMsg.dx));
    // 真源 `.fs-retry`:label 档(12) w600 标题色的纯文字重试。
    final TextStyle fsRetryStyle = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('funds-stages-retry')),
            matching: find.byType(Text),
          ),
        )
        .style!;
    expect(fsRetryStyle.fontSize, 12);
    expect(fsRetryStyle.fontWeight, FontWeight.w600);
    expect(
      fsRetryStyle.color,
      _palette(tester, find.byKey(const Key('funds-stages-retry'))).textPrimary,
    );
    await _save(tester, 'withdrawal_unknown_dark');
  });

  testWidgets('主页·提现方式单行(真源 .txcon_ly),说明标题 headline 正文 caption1', (
    WidgetTester tester,
  ) async {
    await _pumpWithdrawal(tester);
    final Offset name = tester.getCenter(find.text('提现方式'));
    final Offset value = tester.getCenter(find.text('联系平台客服,由客服协助线下处理'));
    expect(value.dy, closeTo(name.dy, 12), reason: '真源是单行左名右值');
    expect(tester.widget<Text>(find.text('提现说明')).style!.fontSize, 17);
    expect(
      tester
          .widget<Text>(find.text('提现已改为客服协助线下处理,请添加平台客服微信核对。'))
          .style!
          .fontSize,
      12,
    );
    // 真源 `.tx-bottom { margin-top: auto }`:内容不足一屏时说明+CTA 贴底
    // (视口 1400,底衬 pageX)。
    final Rect cta = tester.getRect(
      find.byKey(const Key('withdrawal-contact-button')),
    );
    expect(cta.bottom, closeTo(1400 - CyTokens.pageX, 1));
    final Offset note = tester.getCenter(
      find.text('提现已改为客服协助线下处理,请添加平台客服微信核对。'),
    );
    expect(note.dy, greaterThan(800), reason: '贴底不是顶在内容尾巴上');
  });

  testWidgets('主页·浅色臂:取值文字在浅底上够深可读(双态归 C4)', (WidgetTester tester) async {
    await _pumpWithdrawal(tester, theme: merchantGoldenTheme());
    final CyPalette palette = _palette(tester, find.text('¥328.60'));
    final TextStyle amountStyle = tester
        .widget<Text>(find.text('¥328.60'))
        .style!;
    expect(amountStyle.color, palette.textPrimary, reason: '同一语义色随主题走,不写死暗色常量');
    expect(
      palette.textPrimary.computeLuminance(),
      lessThan(0.5),
      reason: '浅臂:textPrimary 必须取深色值 —— 页面不留暗色编译期常量',
    );
    await _save(tester, 'withdrawal_normal_light');
  });

  // ⚠️ 一个用例只 pump 一次 ProviderScope:overrides 在 scope 创建时读一次,
  //    同位置重挂新 scope 不会换替身(游客门会赖在屏上),各态各开一条。
  testWidgets('游客门:去 Material 锁(口径同 #465)', (WidgetTester tester) async {
    await _pumpWithdrawal(tester, signedIn: false);
    final Icon lock = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('withdrawal-login-gate')),
        matching: find.byType(Icon),
      ),
    );
    expect(lock.icon, CupertinoIcons.lock, reason: '#465 口径:游客门不留 Material 锁');
  });

  testWidgets('角色门:无资格整屏走共用 StatusView,不自绘裸文字裸按钮', (WidgetTester tester) async {
    await _pumpWithdrawal(tester, role: _plainRole);
    expect(find.text('当前身份不支持提现'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WithdrawalPage),
        matching: find.byType(StatusView),
      ),
      findsOneWidget,
      reason: '门态整屏走共用件 StatusView(排版/出口都在共用层)',
    );
    expect(find.text('去登录'), findsNothing);
  });

  testWidgets('记录页·行制对齐真源:左「提现到银行卡」+时间,右金额 headline + 状态 caption1', (
    WidgetTester tester,
  ) async {
    WithdrawalRecord rec() => WithdrawalRecord(
      id: 7,
      amount: 128.0,
      status: 1,
      bankName: '招商银行',
      bankAccount: '6225880123456789',
      createTime: '2026-08-18 10:20:00',
    );
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          withdrawalRecordsProvider.overrideWith(
            (ref) async => <WithdrawalRecord>[rec()],
          ),
        ].cast(),
        child: RepaintBoundary(
          key: _benchKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: goldenTheme(),
            home: _gold(const WithdrawalRecordsPage()),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('提现到银行卡'), findsOneWidget);
    final Offset title = tester.getCenter(find.text('提现到银行卡'));
    final Offset amount = tester.getCenter(find.text('¥128.00'));
    expect(amount.dx, greaterThan(title.dx), reason: '真源右列是金额');
    final TextStyle amountStyle = tester
        .widget<Text>(find.text('¥128.00'))
        .style!;
    expect(amountStyle.fontSize, 17);
    expect(amountStyle.fontWeight, FontWeight.w600);
    expect(tester.widget<Text>(find.text('审核通过')).style!.fontSize, 12);
    expect(
      find.textContaining('2026-08-18 10:20:00'),
      findsOneWidget,
      reason: '时间原样上屏,和真源 createTimeText 同口径',
    );
    // 去 Material 残留:页体内不再有 Material 包裹件。
    expect(
      find.descendant(
        of: find.byType(WithdrawalRecordsPage),
        matching: find.byType(Material),
      ),
      findsNothing,
    );
    // 真源 `.txjl`:整个列表是一张浅卡(bg-surface-subtle + radius-lg),
    // 行 `.txjl_li` min-h btn-h+space5=68。
    final CyPalette palette = _palette(tester, find.text('提现到银行卡'));
    final BoxDecoration card = _boxAround(
      tester,
      find.text('提现到银行卡'),
      palette.bgSurfaceSubtle,
    );
    expect((card.borderRadius! as BorderRadius).topLeft.x, CyTokens.radiusLg);
    expect(
      tester.getSize(find.byType(CyCell)).height,
      greaterThanOrEqualTo(CyTokens.btnH + CyTokens.space5),
    );
    await _save(tester, 'records_list_dark');
  });

  testWidgets('R10 客服弹窗·cyConfirm 回退档:号码/两钮齐全,「返回」只关窗', (
    WidgetTester tester,
  ) async {
    // 弹窗证据也要 iPhone 竖屏视口,不然拍到 800×600 横屏。
    setGoldenViewport(tester, const Size(390, 844));
    // RepaintBoundary 包在 MaterialApp **外面**:弹窗走 Navigator 覆盖层,
    // 挂在 home 子树里的边界拍不到它(口径同 #295 roam bench)。
    await tester.pumpWidget(
      RepaintBoundary(
        key: _benchKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: goldenTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext inner) => Center(
                child: CupertinoButton(
                  key: const Key('open'),
                  onPressed: () => showWithdrawalContactDialog(inner),
                  child: const Text('提现'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await _settle(tester);

    // 测试环境没有原生 alert 插件 ⇒ 走降级臂,形态必须是 CupertinoAlertDialog
    // (iOS 26+ 真机由系统 Liquid Glass alert 呈现 —— 同一无源话术)。
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(
      find.textContaining('客服微信号：$kWithdrawalContactWechatId'),
      findsOneWidget,
    );
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    await _save(tester, 'contact_dialog_fallback');

    await tester.tap(find.text('返回'));
    await _settle(tester);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('已复制微信号'), findsNothing, reason: '返回不该触发复制');
  });
}
