import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';
import 'package:chengyin_app/data/models/coop_mybiz.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coop/coop_finance_page.dart';
import 'package:chengyin_app/feature/coop/coop_mybiz_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(initialized: true,
    user: User(id: 7, nickname: 'raw name', avatar: '', role: 'merchant'));
}
Widget _app(String locale, Widget home) => CupertinoApp(
  locale: Locale(locale), localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
    textScaler: const TextScaler.linear(1.5)), child: child!), home: home,
);
void main() {
  for (final locale in ['zh', 'en']) {
    for (final scenario in [
      (amount: '0.00', arrived: true, enabled: false, zh: '暂无已入账分润', en: 'No credited revenue share yet'),
      (amount: '10.00', arrived: false, enabled: false, zh: '已入账金额待确认', en: 'Credited amount awaiting confirmation'),
      (amount: '10.00', arrived: true, enabled: true, zh: '', en: ''),
      (amount: 'invalid', arrived: true, enabled: false, zh: '已入账金额待确认', en: 'Credited amount awaiting confirmation'),
    ]) {
      testWidgets('$locale withdrawal facts ${scenario.amount}/${scenario.arrived} unchanged', (tester) async {
        await tester.pumpWidget(ProviderScope(overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          coopFinanceProvider.overrideWith((ref) async => [CoopFinanceRow(topicId: 7,
            topicName: '原样 supplied title', settled: true, myIncome: scenario.amount,
            myIncomeArrived: scenario.arrived, merchantTotal: '3.50', merchantPaid: '1.00')]),
        ], child: _app(locale, const CoopFinancePage())));
        await tester.pumpAndSettle();
        final button = tester.widget<CyNativeButton>(find.byKey(const Key('coop-finance-withdraw')));
        expect(button.onPressed != null, scenario.enabled);
        if (!scenario.enabled) expect(find.text(locale == 'en' ? scenario.en : scenario.zh), findsOneWidget);
        expect(find.text('原样 supplied title'), findsOneWidget);
        expect(find.text('¥3.50'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$locale merchant summary and synthesized labels preserve facts', (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        coopMyBizProvider.overrideWith((ref) async => const CoopMyBiz(
          fulfillmentRate: 96, violationCount: 2, avgRating: 0, reviewCount: 0,
          settlements: [CoopSettlementRow(id: 8, topicId: 12, status: 1, payeeType: 'club',
            amount: 25.5, shareMode: 1, shareRate: 10, verifiedHeads: 3)],
        )),
      ], child: _app(locale, const CoopMyBizPage())));
      await tester.pumpAndSettle();
      expect(find.text('96%'), findsOneWidget);
      expect(find.text(locale == 'en' ? '2 breaches' : '2 次违约'), findsOneWidget);
      expect(find.text('0.0 points'), findsNothing);
      await tester.scrollUntilVisible(find.text('¥25.50'), 150);
      expect(find.text(locale == 'en' ? 'Theme #12' : '主题 #12'), findsOneWidget);
      expect(find.text(locale == 'en' ? 'Club revenue share' : '俱乐部分润'), findsOneWidget);
      expect(find.text(locale == 'en' ? 'Revenue share · 10.0% · Redeemed: 3 people' : '分成 · 10.0% · 核销 3 人'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
