import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_marketing.dart';
import 'package:chengyin_app/data/models/merchant_insight.dart';
import 'package:chengyin_app/feature/merchant/merchant_ai_insight_page.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coupon/coupon_publish_sheet.dart';
import 'package:chengyin_app/feature/coupon/merchant_coupon_strings.dart';
import 'package:chengyin_app/feature/coupon/my_published_coupons_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_marketing_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 1, nickname: '原始店名', avatar: '', role: 'merchant'),
    initialized: true,
  );
}

Widget _host(WidgetBuilder builder) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Builder(builder: builder)),
);

void main() {
  testWidgets('only typed local coupon failures receive English messages', (tester) async {
    await tester.pumpWidget(_host((context) => Column(children: [
      Text(couponLocalFailureText(context, const CouponLocalFailure(CouponLocalFailureKind.publish, '发布失败'))),
      const Text('发布失败'),
    ])));
    expect(find.text('Could not publish coupon'), findsOneWidget);
    expect(find.text('发布失败'), findsOneWidget);
  });

  testWidgets('coupon types and validation retain wire values and ordering', (tester) async {
    final blocker = couponFormBlocker(
      name: '服务器券名', startTime: DateTime(2026, 9, 1),
      endTime: DateTime(2026, 9, 30), typePickerIndex: 2, publishCount: 0,
    );
    await tester.pumpWidget(_host((context) => Column(children: [
      Text(merchantCouponLocalText(context, couponTypeLabel(1))),
      Text(merchantCouponLocalText(context, couponTypeLabel(2))),
      Text(merchantCouponLocalText(context, blocker!)),
    ])));
    expect(find.text('10% off coupon'), findsOneWidget);
    expect(find.text('20% off coupon'), findsOneWidget);
    expect(find.text('Enter an issue quantity greater than 0'), findsOneWidget);
    expect(couponTypeWire(2), 1);
    expect(couponTypeWire(3), 2);
    expect(couponTypeWire(0), isNull);
    expect(couponCanStop(0), isTrue);
    expect(couponCanStop(4), isFalse);
  });

  testWidgets('published coupon keeps backend name, description and dates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        myPublishedCouponsProvider.overrideWith((ref) async => [
          {'id': 1, 'name': '优惠券', 'description': '未填写说明',
           'couponType': 1, 'status': 4, 'publishCount': 10, 'receiveCount': 3,
           'useCount': 0, 'startTime': '2026-09-01', 'endTime': '2026-09-30'},
        ]),
      ],
      child: _host((_) => const MyPublishedCouponsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('My published coupons'), findsOneWidget);
    expect(find.text('Issuing stopped'), findsOneWidget);
    expect(find.text('优惠券'), findsOneWidget);
    expect(find.text('未填写说明'), findsOneWidget);
    expect(find.text('10% off coupon'), findsOneWidget);
    expect(find.text('7 in stock'), findsOneWidget);
    expect(find.text('2026.09.01 – 2026.09.30'), findsOneWidget);
    expect(find.byKey(const Key('coupon-stop-优惠券')), findsNothing);
  });

  testWidgets('marketing totals localize while backend funnel labels stay verbatim', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantMarketingProvider.overrideWith((ref) async =>
        const MerchantMarketing(couponReceived: 10, couponVerified: 3,
          funnel: [FunnelStep(step: '后端转化档', count: 7, rate: '0.125')],
        ))],
      child: _host((_) => const MerchantMarketingPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Marketing'), findsOneWidget);
    expect(find.text('Redemption rate 30%'), findsOneWidget);
    expect(find.text('后端转化档'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget);
  });
  testWidgets('advisor localizes empty data and preserves backend AI errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final insight = MerchantInsight.fromJson({
      'facts': <String, dynamic>{}, 'aiError': '服务器解读暂不可用',
      'generatedAt': '2026-09-30 08:09:10',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantInsightProvider.overrideWith((ref) async => insight)],
      child: _host((_) => const MerchantAiInsightPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Store advisor'), findsOneWidget);
    expect(find.text('No visit data yet'), findsOneWidget);
    expect(find.text('Generated 2026-09-30 08:09:10; updates the next day'), findsOneWidget);
    expect(find.text('服务器解读暂不可用. The business data above is unaffected.'), findsOneWidget);
    expect(find.text('Regenerate insights'), findsOneWidget);
  });

}
