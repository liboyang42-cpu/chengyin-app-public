import 'package:chengyin_app/l10n/app_localizations.dart';
// 券码出示页:四件事各自说自己的话。
//
// ★ 真源 `subpackageMember/coupon-qr/index.{wxml,js}` + `scene-qr-coupon`:
//   ① 链接缺券 id → cy-state-shell kind=missing-param「缺少券信息 / 请返回我的券包重新进入」
//   ② 使用期承诺:start 前**不出码**,只说「还没到可用时间」
//   ③ 核销状态与二维码是两条链路:轮询抖动只横一条「核销状态暂未更新」,
//      不能把屏上还能扫的码撤成整屏报错
//   ④ 游客深链落地给页内登录门,不静默弹回首页(b1-sim-coupon P1-1);
//      终态 3 = 「该券已失效」不是「已过期」(P1-4);410 = 停表撤码(b1-sim S5)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:chengyin_app/data/models/coupon.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coupon/coupon_code_page.dart';

String _futureStart() => DateTime.now()
    .add(const Duration(hours: 2))
    .toIso8601String()
    .replaceFirst('T', ' ')
    .substring(0, 19);

/// 生产里 502 就是这个形状(dio 的 validateStatus 走 `DioException.badResponse`)。
/// ⚠️ 手搓 `DioException(...)` 的 message 是 null,toString 里没有状态码,测不出真身。
DioException _badResponse502(String path) => DioException.badResponse(
  statusCode: 502,
  requestOptions: RequestOptions(path: path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 502,
  ),
);

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
  _FakeCouponApi({this.startTime, this.qrUseStatus = 0, this.unavailableCode});

  final String? startTime;

  /// 换码快照返回的 useStatus(真源在 qr-token 回包里带终态)。
  final int qrUseStatus;

  /// 非 null = 换码/轮询回该业务码(410 → 抛 CouponUnavailableException)。
  final int? unavailableCode;

  /// 非 null = qrToken 直接抛这个异常(测「异常原文不许上屏」)。
  Object? qrError;
  int qrCalls = 0;
  int statusCalls = 0;
  bool statusThrows410 = false;

  @override
  Future<CouponQr> qrToken(int couponHistoryId) async {
    qrCalls += 1;
    if (qrError != null) throw qrError!;
    if (unavailableCode == 410) {
      throw const CouponUnavailableException('该券已停用');
    }
    return CouponQr.fromJson(<String, dynamic>{
      'qrcodeUrl': 'https://cdn.example.com/qr.png',
      'expiresIn': 60,
      'useStatus': qrUseStatus,
      'couponName': '满 50 减 10',
      'endTime': '2026-12-31 23:59:59',
      if (startTime != null) 'startTime': startTime,
    });
  }

  @override
  Future<CouponStatus> status(int couponHistoryId) async {
    statusCalls += 1;
    if (statusThrows410) {
      throw const CouponUnavailableException('该券已停用');
    }
    throw Exception('网络异常');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester t,
  CouponApi api, {
  int id = 7,
  bool signedIn = true,
  Locale locale = const Locale('zh'),
}) async {
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
        home: CouponCodePage(couponHistoryId: id)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

/// 收拾挂着的倒计时/轮询计时器,避免 pending timer。
Future<void> _teardown(WidgetTester t) => t.pumpWidget(const SizedBox.shrink());

void main() {
  testWidgets('English QR failure localizes app error but preserves backend revocation', (t) async {
    final api = _FakeCouponApi()..qrError = StateError('unavailable');
    await _pump(t, api, locale: const Locale('en'));
    expect(find.text('Couldn’t generate the QR code. Try again later.'), findsOneWidget);
    await _teardown(t);
    await _pump(t, _FakeCouponApi(unavailableCode: 410), locale: const Locale('en'));
    expect(find.text('该券已停用'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await _teardown(t);
  });

  testWidgets('★ 链接缺券 id:说「缺少券信息」,不拉接口', (WidgetTester t) async {
    final api = _FakeCouponApi();
    await _pump(t, api, id: 0);
    expect(find.text('缺少券信息'), findsOneWidget);
    expect(find.text('请返回我的券包重新进入'), findsOneWidget);
    expect(api.qrCalls, 0, reason: '券 id 都没有还去换码 = 拿必然失败的请求换一句假错误');
  });

  testWidgets('★★ 游客深链:页内登录门,不换码不轮询(b1-sim P1-1)', (WidgetTester t) async {
    final api = _FakeCouponApi();
    await _pump(t, api, id: 123, signedIn: false);
    expect(find.byKey(const Key('coupon-code-login-gate')), findsOneWidget);
    expect(find.text('登录后查看核销码'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(api.qrCalls, 0, reason: '游客换码 = 注定 401 的请求');
    await t.pump(const Duration(seconds: 6));
    expect(api.statusCalls, 0, reason: '游客态不许起轮询节拍');
    await _teardown(t);
  });

  testWidgets('★ 还没到可用时间:不出码,只说什么时候能用', (WidgetTester t) async {
    final api = _FakeCouponApi(startTime: _futureStart());
    await _pump(t, api, id: 9);
    expect(find.text('还没到可用时间'), findsOneWidget);
    expect(find.textContaining('起可使用'), findsOneWidget);
    expect(find.text('重新获取'), findsOneWidget);
    expect(
      find.textContaining('后自动刷新'),
      findsNothing,
      reason: '到点前亮码 = 拿一张刷不过的码去给商家扫',
    );
    await _teardown(t);
  });

  testWidgets('★★ 轮询失败但码还在:横一条提示,不把码撤下去', (WidgetTester t) async {
    final api = _FakeCouponApi();
    await _pump(t, api, id: 11);
    // 5s 一次轮询:推过第一次轮询,让它失败。
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 100));
    expect(api.statusCalls, greaterThanOrEqualTo(1));
    expect(find.text('核销状态暂未更新'), findsOneWidget);
    expect(find.text('出示给商家扫码核销'), findsOneWidget);
    // ★ 真源亮码态带券名(cy-qr-voucher title):b1-sim S5 此前缺。
    expect(find.text('满 50 减 10'), findsOneWidget);
    await _teardown(t);
  });

  testWidgets('★★ 换码快照 useStatus=3:结果页说「该券已失效」,不是已过期(P1-4)', (
    WidgetTester t,
  ) async {
    final api = _FakeCouponApi(qrUseStatus: 3);
    await _pump(t, api, id: 13);
    expect(find.text('该券已失效'), findsOneWidget);
    expect(find.text('该券已过期'), findsNothing);
    // 真源:失效态不摆「有效期至」(只有已过期才说原因)。
    expect(find.textContaining('有效期至'), findsNothing);
    // 终态:倒计时不再空转。
    await t.pump(const Duration(seconds: 70));
    expect(api.qrCalls, 1, reason: '终态后继续换码 = 白打接口');
    await _teardown(t);
  });

  testWidgets('★ 换码快照 useStatus=2:仍是「该券已过期」,且只到日显示有效期', (WidgetTester t) async {
    final api = _FakeCouponApi(qrUseStatus: 2);
    await _pump(t, api, id: 14);
    expect(find.text('该券已过期'), findsOneWidget);
    // 2026-09-17 全站拍板:日期只到日、点号分隔(真源 formatDayDots)。
    expect(find.text('有效期至 2026.12.31'), findsOneWidget);
    await _teardown(t);
  });

  testWidgets('★★ 换码吃 410(券停用):停表撤码,只留原因,不再重试(S5)', (WidgetTester t) async {
    final api = _FakeCouponApi(unavailableCode: 410);
    await _pump(t, api, id: 15);
    expect(find.text('该券已停用'), findsOneWidget);
    await t.pump(const Duration(seconds: 70));
    expect(api.qrCalls, 1, reason: '410 是终态,到点再换码只是再吃一发 410');
    await _teardown(t);
  });

  testWidgets('★ 出码失败:上屏的是人话,不是异常原文', (WidgetTester t) async {
    final api = _FakeCouponApi()..qrError = _badResponse502('/api/coupon/qr');
    await _pump(t, api, id: 13);

    expect(find.text('网络异常，请稍后重试'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    await _teardown(t);
  });

  testWidgets('★★ 出码失败态不套白码卡:正文吃主题色、重试走实心共用件(a5-ios27-coupon-2)', (
    WidgetTester t,
  ) async {
    // 真源 `cy-qr-voucher`:error 分支渲染 `.qr__error`(scrim 上恒浅正文 +
    // `.qr__err-retry` 实心 btn-solid 药丸),白卡 `.qr__card` 整块不出现 ——
    // 白卡只为承载可扫的码而存在。
    final api = _FakeCouponApi(unavailableCode: 410);
    await _pump(t, api, id: 15);
    final errText = t.widget<Text>(find.text('该券已停用'));
    expect(errText.style?.color, CyTokens.textPrimary);
    expect(errText.style?.fontSize, CyTokens.typeSectionTitle);
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == Colors.white,
      ),
      findsNothing,
      reason: '错误态还画白卡 = 拿「扫码要求物理白底」的豁免去包一段报错',
    );
    // 真源 `.qr__error-ic` 是 no_data 插画,不是码形:这一屏的前提就是
    // 「没有码可扫」,画个二维码等于给了一个假可扫信号。
    expect(find.byIcon(Icons.qr_code_2), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    // 真源注释钉过的事故:错误块与 desc/刷新钮条件必须互斥,不许同屏。
    expect(find.text('刷新二维码'), findsNothing);
    expect(find.text('出示给商家扫码核销'), findsNothing);
    await _teardown(t);
  });

  testWidgets('★ 轮询吃 410:同样停表落不可用态', (WidgetTester t) async {
    final api = _FakeCouponApi()..statusThrows410 = true;
    await _pump(t, api, id: 16);
    expect(find.text('满 50 减 10'), findsOneWidget); // 码先亮着
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('该券已停用'), findsOneWidget);
    // 停表:倒计时不再驱动换码。
    final callsAtStop = api.qrCalls;
    await t.pump(const Duration(seconds: 70));
    expect(api.qrCalls, callsAtStop);
    await _teardown(t);
  });
}
