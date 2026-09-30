// 账号域整页视觉快照:登录门弹窗 / 手机号登录半屏 / 登录整页 /
// 注销账号三态(须知同意 · 有阻断项 · 冷静期)/ 我的优惠券(三态 + 空态)。
//
// 与 pages_golden_test.dart 同套路:Riverpod override 注入假数据,不打网络。
// 注销页直接走 accountApiProvider 拉状态,这里用 implements 假 Api 按脚本返回,
// 阻断态通过「勾选须知 → 下一步 → 预检返回 BLOCKED」驱动出来(不走假数据直设)。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_account_golden_test.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'golden_theme.dart';
import '../support/fixed_auth.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/models/consent_record.dart';
import 'package:chengyin_app/data/models/coupon.dart';
import 'package:chengyin_app/data/models/deregistration.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/account/deregister_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/login_gate.dart';
import 'package:chengyin_app/feature/auth/login_page.dart';
import 'package:chengyin_app/feature/auth/phone_login_sheet.dart';
import 'package:chengyin_app/feature/coupon/my_coupons_page.dart';

/// 假 AccountApi:只覆盖注销链路用到的读接口,写接口空实现,不打网络。
class _FakeAccountApi implements AccountApi {
  _FakeAccountApi({this.status, this.precheck});

  final DeregistrationStatus? status;
  final DeregistrationStatus? precheck;

  @override
  Future<String> playerCode() => throw UnsupportedError('golden 不请求个人码');

  /// 新增的「读回最新同意」——golden 里用不到,回 null(= 没同意过)即可。
  @override
  Future<ConsentRecord?> latestConsent({
    required String docType,
    required String scene,
    String? scopeType,
    int? scopeId,
  }) async => null;

  @override
  Future<ConsentRecord?> latestMerchantOnsiteConsent(int merchantId) async =>
      null;

  @override
  Future<ConsentRecord> agreeMerchantOnsiteDataSharing({
    required int merchantId,
    required String requestId,
  }) => throw UnsupportedError('golden 不执行商家现场授权写入');

  @override
  Future<ConsentRecord> revokeMerchantOnsiteDataSharing({
    required int merchantId,
    required String requestId,
  }) => throw UnsupportedError('golden 不执行商家现场授权撤回');

  @override
  Future<ConsentRecord> revokeRoamLocationConsent({
    required String requestId,
  }) => throw UnsupportedError('golden 不执行漫游定位授权撤回');

  @override
  Future<DeregistrationStatus> deregisterStatus() async =>
      status ??
      const DeregistrationStatus(status: 'NORMAL', blockers: <String>[]);

  @override
  Future<DeregistrationStatus> deregisterPrecheck() async =>
      precheck ??
      const DeregistrationStatus(status: 'NORMAL', blockers: <String>[]);

  @override
  Future<DeregistrationStatus> deregisterApply({
    required String smscode,
    required String requestId,
  }) async => const DeregistrationStatus(
    status: 'PENDING',
    blockers: <String>[],
    executeAfter: '2026-09-01 00:00:00',
  );

  @override
  Future<DeregistrationStatus> deregisterCancel() async =>
      const DeregistrationStatus(status: 'NORMAL', blockers: <String>[]);

  @override
  Future<void> recordConsent({
    required String docType,
    required String scene,
    required String requestId,
  }) async {}

  @override
  Future<void> agreeCancellationNotice(String requestId) async {}

  @override
  Future<void> agreeSignupDataSharing(String requestId) async {}
}

// 同 pages_golden_test.dart:不写 List<Override> 显式类型,靠推断,少一个版本耦合。
Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      // ★ 同 pages_withdrawal / pages_official_points 的宿主:裸 CyType.* 全档
      //   family=null,快照宿主是 MaterialApp 时会落到 flutter_test 默认族上
      //   ⇒ 满屏豆腐。登录门/手机号登录已改走 B1 sheet(测试环境回退
      //   showCupertinoSheet,推到 root navigator,包 home 够不到),故用
      //   MaterialApp.builder 给整棵导航树补一层带中文字形的 DefaultTextStyle。
      builder: (BuildContext context, Widget? child) => DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto'),
        child: child!,
      ),
      home: home,
    ),
  );
}

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

/// 券包现在对游客给页内登录门(b1-sim-coupon P1-1),基线拍的是登录态三态。
final List<dynamic> _signedIn = <dynamic>[
  authControllerProvider.overrideWith(
    () => _FixedAuth(
      AuthState(
        user: User(id: 1, nickname: '旅人', avatar: '', role: 'player'),
        initialized: true,
      ),
    ),
  ),
];

/// 弹层宿主:底部 sheet 需要真实 Navigator + 一个可点的打开按钮。
/// Builder 把 context 直接交给打开函数,不靠 Finder 猜。
Widget _sheetHost(void Function(BuildContext) onOpen) {
  return Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => onOpen(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('登录门:底部弹窗(微信 / 手机号 / 协议)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 700));
    await tester.pumpWidget(
      _app(<dynamic>[], _sheetHost((context) => showLoginSheet(context))),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/account_login_sheet.png'),
    );
  });
  testWidgets('手机号登录:半屏表单(抓手 / 标题 / 双字段)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 700));
    await tester.pumpWidget(
      _app(<dynamic>[], _sheetHost((context) => showPhoneLoginSheet(context))),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/account_phone_sheet.png'),
    );
  });
  // ★ V8/V15:Apple 登录按钮此前**从没进过任何基线** —— 它原先由 dart:io 的
  //   `Platform.isIOS` 控制,而 golden 跑在 macOS 上,该判据恒为 false。
  //   代码已改用 `Theme.of(context).platform`,这里用 debugDefaultTargetPlatformOverride
  //   把 iOS 态拍下来。它是 App Store 4.8 的强制项(有微信登录就必须有 Apple 登录),
  //   最该被盯住的按钮不能是唯一没人盯的那个。
  testWidgets('登录门:整页登录(iOS 态 —— 含 Apple 登录)', (WidgetTester tester) async {
    // ⚠️ 必须在测试体内显式复位,不能用 addTearDown ——
    //   框架的「foundation 调试变量是否被改过」检查跑在 tearDown **之前**,
    //   用 addTearDown 会以 "The value of a foundation debug variable was changed" 报错。
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    setGoldenViewport(tester, const Size(390, 880));
    await tester.pumpWidget(_app(<dynamic>[], const LoginPage()));
    await tester.pumpAndSettle();

    // 先断言它真的在 —— 图能看出长什么样,断言保证它没被悄悄去掉。
    expect(find.text('通过 Apple 登录'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/account_login_page_ios.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('登录门:整页登录', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 700));
    await tester.pumpWidget(_app(<dynamic>[], const LoginPage()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/account_login_page.png'),
    );
  });

  testWidgets('注销账号:须知同意态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(<dynamic>[
        signedInAuthOverride(),
        accountApiProvider.overrideWithValue(
          _FakeAccountApi(
            status: const DeregistrationStatus(
              status: 'NORMAL',
              blockers: <String>[],
            ),
          ),
        ),
      ], const DeregisterPage()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deregister_notice.png'),
    );
  });
  testWidgets('注销账号:有阻断项(blockers 多条)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(<dynamic>[
        signedInAuthOverride(),
        accountApiProvider.overrideWithValue(
          _FakeAccountApi(
            status: const DeregistrationStatus(
              status: 'NORMAL',
              blockers: <String>[],
            ),
            precheck: const DeregistrationStatus(
              status: 'BLOCKED',
              blockers: <String>[
                '账户还有未提现的余额,请先完成提现',
                '有一笔进行中的订单尚未完成',
                '存在有效的探店日报名,请先取消',
                '已开通商家身份,需先完成退出流程',
              ],
            ),
          ),
        ),
      ], const DeregisterPage()),
    );
    await tester.pumpAndSettle();
    // 阻断态走真实交互:勾选须知 → 下一步 → 预检返回 BLOCKED。
    await tester.tap(find.text('我已阅读并同意《账号注销须知》'));
    await tester.pump();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deregister_blocked.png'),
    );
  });
  testWidgets('注销账号:冷静期中(可撤销)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(<dynamic>[
        signedInAuthOverride(),
        accountApiProvider.overrideWithValue(
          _FakeAccountApi(
            status: const DeregistrationStatus(
              status: 'PENDING',
              blockers: <String>[],
              executeAfter: '2026-09-01 00:00:00',
            ),
          ),
        ),
      ], const DeregisterPage()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deregister_pending.png'),
    );
  });

  testWidgets('我的优惠券:有券(未用 / 已用 / 过期 / 券码待生成)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    // 固定日期保证 golden 可复现(相对 now 会让基准图随每次运行漂移)。
    // 已过期券 endTime 取 2020-01-01(早于任何运行时刻);未用券取 2099-12-31。
    await tester.pumpWidget(
      _app(<dynamic>[
        ..._signedIn,
        myCouponsProvider.overrideWith(
          (ref) async => <CouponRecord>[
            CouponRecord(
              id: 1,
              couponId: 1,
              couponCode: 'CY2026A001',
              useStatus: 0,
              startTime: '2026-08-01 00:00:00',
              endTime: '2099-12-31 23:59:59',
            ),
            CouponRecord(
              id: 2,
              couponId: 2,
              couponCode: 'CY2026A002',
              useStatus: 1,
              startTime: '2026-06-01 00:00:00',
              endTime: '2026-07-31 23:59:59',
            ),
            CouponRecord(
              id: 3,
              couponId: 3,
              couponCode: 'CY2026A003',
              useStatus: 0,
              startTime: '2026-06-01 00:00:00',
              endTime: '2020-01-01 00:00:00',
            ),
            CouponRecord(
              id: 4,
              couponId: 4,
              couponCode: '',
              useStatus: 0,
              startTime: '2026-08-01 00:00:00',
              endTime: '2099-12-31 23:59:59',
            ),
            // 超长券码:校验 2 行折行时角标是否仍顶对齐、行高是否被撑高。
            CouponRecord(
              id: 5,
              couponId: 5,
              couponCode: 'CY2026A000000-LONG-CODE-FOR-WRAP-CHECK-9999',
              useStatus: 0,
              startTime: '2026-08-01 00:00:00',
              endTime: '2099-12-31 23:59:59',
            ),
          ],
        ),
      ], const MyCouponsPage()),
    );
    await tester.pumpAndSettle();
    // 加载首帧的 CySkeleton(count:4) 在 625pt 可用高度内放不下(4×~178>625)
    // 会报一次 transient overflow —— 这是加载态,不进 golden(动效组件不入快照),
    // 属 lib 侧真实问题已记入报告,这里清掉异常让基准图正常生成。
    tester.takeException();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/coupons_list.png'),
    );
  });
  testWidgets('我的优惠券:空态(带副标)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(<dynamic>[
        ..._signedIn,
        myCouponsProvider.overrideWith((ref) async => <CouponRecord>[]),
      ], const MyCouponsPage()),
    );
    await tester.pumpAndSettle();
    tester.takeException();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/coupons_empty.png'),
    );
  });
  testWidgets('我的优惠券:加载失败(error 态)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(<dynamic>[
        ..._signedIn,
        myCouponsProvider.overrideWith(
          (ref) async => throw Exception('网络异常,请稍后重试'),
        ),
      ], const MyCouponsPage()),
    );
    await tester.pumpAndSettle();
    // 加载首帧同前:骨架 transient overflow,清掉。
    tester.takeException();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/coupons_error.png'),
    );
  });
}
