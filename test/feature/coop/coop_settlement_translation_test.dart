import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';
import 'package:chengyin_app/data/models/coop_mybiz.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coop/coop_settlement_detail_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(initialized: true,
    user: User(id: 7, nickname: 'user', avatar: '', role: 'merchant'));
}
Widget _host(String locale, CoopSettlementDetail detail) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(_Auth.new),
    coopSettlementDetailProvider(const CoopSettlementRef(source: 'finance', recordId: '7'))
      .overrideWith((ref) async => detail),
  ],
  child: CupertinoApp(
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
    home: const CoopSettlementDetailPage(source: 'finance', recordId: '7'),
  ),
);
void main() {
  for (final locale in ['zh', 'en']) {
    final en = locale == 'en';
    for (final scenario in [
      (settled: false, amount: null, arrived: false, zh: '主题待结算', en: 'Theme pending settlement'),
      (settled: true, amount: 'invalid', arrived: true, zh: '主题已结算', en: 'Theme settled'),
      (settled: true, amount: '0.00', arrived: true, zh: '本期无需入账', en: 'No credit required for this period'),
      (settled: true, amount: '12.50', arrived: false, zh: '我的分润待入账', en: 'My revenue share is pending credit'),
      (settled: true, amount: '12.50', arrived: true, zh: '我的分润已入账', en: 'My revenue share has been credited'),
    ]) {
      testWidgets('$locale finance timeline uses flags: ${scenario.en}', (tester) async {
        await tester.pumpWidget(_host(locale, CoopSettlementDetail.finance(CoopFinanceRow(
          topicId: 7, topicName: '原样 supplied theme', settled: scenario.settled,
          myIncome: scenario.amount, myIncomeArrived: scenario.arrived,
          merchantPayoutTime: '2026-09-30 12:34:56',
        ))));
        await tester.pumpAndSettle();
        expect(find.text('原样 supplied theme'), findsOneWidget);
        final label = en ? scenario.en : scenario.zh;
        await tester.scrollUntilVisible(find.text(label), 250);
        expect(find.text(label), findsOneWidget);
        await tester.scrollUntilVisible(find.text('2026-09-30 12:34'), 200);
        expect(find.text('2026-09-30 12:34'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$locale merchant rule and timeline preserve amounts and dates', (tester) async {
      await tester.pumpWidget(_host(locale, const CoopSettlementDetail.merchant(CoopSettlementRow(
        id: 7, topicName: '原样 title', status: 0, payeeType: 'club', amount: 12.5,
        shareMode: 2, fixedFee: 3.5, verifiedHeads: 2, payableTime: '2026-10-07 09:00:00',
      ))));
      await tester.pumpAndSettle();
      expect(find.text('原样 title'), findsOneWidget);
      expect(find.text('¥12.50'), findsWidgets);
      final rule = en ? 'Fixed · ¥3.50/person' : '固定 · ¥3.50/人';
      await tester.scrollUntilVisible(find.text(rule), 200);
      expect(find.text(rule), findsOneWidget);
      await tester.scrollUntilVisible(find.text('2026-10-07 09:00'), 200);
      expect(find.text(en ? 'Expected credit' : '预计入账'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  test('missing finance title has provenance; same-text server title stays supplied', () {
    expect(CoopFinanceRow.fromJson({'topicId': 7}).hasCustomTopicName, isFalse);
    expect(CoopFinanceRow.fromJson({'topicId': 7, 'topicName': '未命名主题'}).hasCustomTopicName, isTrue);
  });
}
