import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';
import 'package:chengyin_app/feature/merchant/merchant_crm_panels.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child));
void main() {
  testWidgets('English CRM segment chip retains backend filter code', (tester) async {
    String? selected;
    await tester.pumpWidget(_host(CrmSegmentChips(segment: 'all', toolsOpen: false, onToggleTools: () {}, onTap: (value) => selected = value)));
    await tester.tap(find.text('Returning customers'));
    expect(selected, 'repeat');
    expect(find.text('Manage'), findsOneWidget);
  });
  testWidgets('English campaigns preserve recipient errors and receipt IDs without adding permission', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final title = TextEditingController();
    final content = TextEditingController();
    addTearDown(title.dispose);
    addTearDown(content.dispose);
    final recipient = CrmCampaignRecipient.tryParse({'status': 'FAILED', 'failureMessage': '待处理', 'messageReceiptId': 42})!;
    await tester.pumpWidget(_host(SingleChildScrollView(child: CrmCampaignPanel(
      canCoupon: false, channel: 'IN_APP', onChannelTap: (_) {}, notificationDeliveryStatus: '', couponDeliveryStatus: '',
      segmentName: '原始分群', onPickSegment: () {}, savedSegmentsError: '', onRetrySavedSegments: () {},
      couponName: '', onPickCoupon: () {}, couponCatalogError: '', onRetryCoupons: () {},
      title: title, content: content, previewing: false, sending: false, onPreview: () {}, onSend: () {},
      preview: null, error: '', campaigns: const [], onOpenCampaign: (_) {}, onRetryTask: () {},
      task: CrmCampaignTask(status: 'PARTIAL_FAILED', deliveredCount: 2, noConsentCount: 3, failedCount: 1, recipients: [recipient]),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Partially completed'), findsOneWidget);
    expect(find.text('Name not provided'), findsOneWidget);
    expect(find.text('待处理'), findsOneWidget);
    expect(find.text('Message receipt #42'), findsOneWidget);
    expect(find.text('Merchant coupons'), findsNothing);
    expect(find.text('Successful 2 · No consent or unsubscribed 3'), findsOneWidget);
    expect(find.text('Only segments saved on the server are used. Customer consent is off by default, and unsubscribing takes effect immediately.'), findsOneWidget);
  });
}
