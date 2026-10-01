import 'package:chengyin_app/l10n/app_localizations.dart';
// 券包页(scene-game-coupon-wallet 口径)。
//
// ★ 盯两件事:
//   ① 游客深链 `/coupons` 落地给页内登录门,不发注定 401 的请求
//     (b1-sim-coupon P1-1,静默弹回首页会让用户以为链接坏了);
//   ② useStatus=3「已失效」渲染成 danger +「该券已被平台手动失效」,
//     不给核销入口(P1-4:此前落 default 冒充「待使用」还能点)。
//   未到 start 的待使用券保留查看入口,文案是「查看可用时间」(真源 _canView/_isUsable 拆分)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:chengyin_app/data/models/coupon.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coupon/my_coupons_page.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

final _loggedIn = AuthState(
  user: User(id: 1, nickname: '旅人', avatar: '', role: 'player'),
  initialized: true,
);

class _FakeCouponApi implements CouponApi {
  int recvCalls = 0;

  @override
  Future<List<CouponRecord>> myReceivedList({String? keyword}) async {
    recvCalls += 1;
    return _records;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final List<CouponRecord> _records = <CouponRecord>[
  CouponRecord(
    id: 1,
    couponId: 1,
    couponCode: 'A',
    useStatus: 0,
    couponName: '已到期的待使用券',
    startTime: '2026-08-01 00:00:00',
    endTime: '2099-12-31 23:59:59',
  ),
  CouponRecord(
    id: 2,
    couponId: 2,
    couponCode: 'B',
    useStatus: 0,
    couponName: '未来的券',
    startTime: '2099-01-01 00:00:00',
    endTime: '2099-12-31 23:59:59',
  ),
  CouponRecord(
    id: 3,
    couponId: 3,
    couponCode: 'C',
    useStatus: 3,
    couponName: '被平台撤掉的券',
    endTime: '2099-12-31 23:59:59',
  ),
  CouponRecord(
    id: 4,
    couponId: 4,
    couponCode: 'D',
    useStatus: 9,
    couponName: '状态看不懂的券',
  ),
];

Future<_FakeCouponApi> _pump(WidgetTester t, {bool signedIn = true, Locale locale = const Locale('zh'), TextScaler textScaler = TextScaler.noScaling}) async {
  final api = _FakeCouponApi();
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        couponApiProvider.overrideWithValue(api),
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            signedIn ? _loggedIn : const AuthState(initialized: true),
          ),
        ),
      ].cast(),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: textScaler), child: child!),
        home: const MyCouponsPage()),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
  return api;
}

void main() {
  testWidgets('English coupon wallet preserves names and filter state at large text', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await _pump(t, locale: const Locale('en'), textScaler: const TextScaler.linear(2));
    expect(find.text('My coupons'), findsOneWidget);
    expect(find.text('已到期的待使用券'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Expired').first);
    await t.pump();
    expect(find.text('No coupons match this filter'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('★★ 游客:页内登录门,不发 myrecvlist 请求(P1-1)', (WidgetTester t) async {
    final api = await _pump(t, signedIn: false);
    expect(find.byKey(const Key('coupons-login-gate')), findsOneWidget);
    expect(find.text('登录后查看优惠券'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('我的优惠券'), findsOneWidget, reason: '页面本身要落地,不是弹回首页');
    expect(api.recvCalls, 0);
  });

  testWidgets('★ useStatus=3:「已失效」danger tag + 平台失效说明,无核销入口(P1-4)', (
    WidgetTester t,
  ) async {
    await _pump(t);
    expect(find.text('已失效'), findsOneWidget);
    expect(find.text('该券已被平台手动失效'), findsOneWidget);
    // 「待使用」全文只应出现在:tab 栏 1 次 + 两张 useStatus=0 券卡。
    // 若 3 落 default 渲染成「待使用」,这里会多出 1 个(把撤掉的券当还能用的券)。
    expect(find.text('待使用'), findsNWidgets(3));
    expect(find.textContaining('出示核销码'), findsOneWidget); // 只有 1 号券有
    // 真源箭头是独立图标(a5-ios27-coupon:文字不再带「 ›」字符)。
    expect(find.text('查看可用时间'), findsOneWidget); // 只有未来的 2 号券
  });

  testWidgets('★ 真源 decorate:待使用未到 start →「查看可用时间」,已到 start →「出示核销码」', (
    WidgetTester t,
  ) async {
    await _pump(t);
    expect(find.text('有效期至 2099.12.31'), findsOneWidget);
    expect(find.text('2099.01.01 起可用 · 有效期至 2099.12.31'), findsOneWidget);
  });

  testWidgets('★ 未知状态不冒充「待使用」:显「状态待确认」', (WidgetTester t) async {
    await _pump(t);
    expect(find.text('状态待确认'), findsOneWidget);
  });
}
