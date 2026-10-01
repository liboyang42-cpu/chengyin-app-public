import 'package:chengyin_app/feature/merchant/project_players_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_predict_page.dart';
import 'package:chengyin_app/data/api/merchant_predict_api.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English roster preserves names, contact hints and state distinctions', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [projectPlayersProvider(7).overrideWith((ref) async => {
        'summary': {'paidCount': 2, 'arrivedCount': 1, 'pendingCount': 1, 'refundedCount': 1},
        'contactHint': '请联系活动主办方',
        'rows': [
          {'name': '玩家', 'state': 'arrived', 'ticketName': '普通票'},
          {'state': 'pending'},
          {'name': '小李', 'state': 'refunded'},
        ],
      })],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProjectPlayersPage(topicId: 7),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Player roster'), findsOneWidget);
    expect(find.text('请联系活动主办方'), findsOneWidget);
    expect(find.text('玩家'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('普通票'), findsOneWidget);
    expect(find.text('Arrived'), findsOneWidget);
    expect(find.text('Not arrived'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only provenance-marked prediction error is translated', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        expect(predictErrorCopy(context, const MerchantPredictApiException('请求失败', localCode: 'request')), 'Request failed');
        expect(predictErrorCopy(context, const MerchantPredictApiException('请求失败')), '请求失败');
        return const SizedBox.shrink();
      }),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
