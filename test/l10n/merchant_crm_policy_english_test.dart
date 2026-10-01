import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';
import 'package:chengyin_app/feature/merchant/merchant_crm_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/l10n/strings.dart';

void main() {
  const preview = CrmBroadcastPreview(audienceCount: 8, consentedCount: 5,
    noConsentCount: 3, frequencyLimitedCount: 2, deliverableCount: 3,
    recipientLimit: 8, merchantDailyLimit: 4, merchantDailyUsed: 4,
    merchantDailyRemaining: 0, filterTotalCount: 12);
  for (final language in ['zh', 'en']) {
    testWidgets('CRM disclosure preserves consent and limits in $language', (tester) async {
      await tester.pumpWidget(MaterialApp(locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) => Column(children: [
          Text(merchantCrmBroadcastPreviewText(context, preview)),
          Text(stringsOf(context).merchantCrmPolicyDailyLimit(preview.merchantDailyLimit)),
          Text(stringsOf(context).merchantCrmPolicySegmentSend('原始分群')),
          Text(stringsOf(context).merchantCrmPolicyCorrection(42)),
          Text(merchantCrmDeliveryPolicy(context, 'CONSENT_REQUIRED')),
          Text(merchantCrmDeliveryPolicy(context, 'UNKNOWN')),
        ])),
      ));
      if (language == 'zh') {
        expect(find.text(crmBroadcastPreviewText(preview)), findsOneWidget);
        expect(find.text('每个商家每天最多发 4 条广播，今天已经发满，明天再来。'), findsOneWidget);
        expect(find.text('正在更正备注 #42；系统会追加新记录，不改原文。'), findsOneWidget);
      } else {
        expect(find.text('This in-app message will be sent to 3 customers who have consented to merchant messages. Another 3 customers have not consented and will not receive it. Another 2 customers have already received a message today and will not be sent another. This recipient list is limited to 8 people per send.'), findsOneWidget);
        expect(find.text('Each merchant can send up to 4 broadcasts per day. Today’s limit has been reached. Try again tomorrow.'), findsOneWidget);
        expect(find.text('Create and send a campaign for “原始分群”. It cannot be recalled after sending.'), findsOneWidget);
        expect(find.text('Correcting note #42. The system will add a new record and leave the original text unchanged.'), findsOneWidget);
        expect(find.text('Only contact customers who have consented'), findsOneWidget);
        expect(find.text('Rules awaiting synchronization'), findsOneWidget);
      }
      expect(crmBroadcastDailyExhausted(preview), isTrue);
    });
  }
}
