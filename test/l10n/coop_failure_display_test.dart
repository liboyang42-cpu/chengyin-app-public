import 'package:chengyin_app/data/models/coop_failure.dart';
import 'package:chengyin_app/feature/coop/coop_guard.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets('$language distinguishes collaboration local fallback from identical server text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          final strings = AppLocalizations.of(context);
          expect(coopErrorSub(const CoopFailure.local(CoopFailureKind.operation, '操作失败'), context: context), strings.operationFailed);
          for (final message in ['操作失败', '  Business detail  ', '']) {
            expect(coopErrorSub(CoopFailure.server(message), context: context), message);
          }
          expect(coopErrorSub(const CoopFailure.local(CoopFailureKind.refundUnknown, '退款结果暂无法确认，请先核对，勿重复提交'), context: context), strings.coopFailureRefundUnknown);
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
