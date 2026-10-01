import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/merchant_aftercare_api.dart';
import 'package:chengyin_app/data/models/merchant_aftercare.dart';
import 'package:chengyin_app/feature/merchant/merchant_aftercare_detail_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/l10n/strings.dart';

Widget _host(Widget child) => MaterialApp(locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: child);
void main() {
  testWidgets('Aftercare history localizes the actual response decision and preserves raw evidence text', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Gateway();
    await tester.pumpWidget(_host(MerchantAftercareDetailPage(api: api, refundId: 81)));
    await tester.pumpAndSettle();
    expect(find.text('Add evidence'), findsOneWidget);
    expect(find.text('原始售后凭证内容'), findsOneWidget);
    expect(find.text('原始退款原因'), findsOneWidget);
    expect(find.byKey(const Key('aftercare-submit')), findsNothing);
    expect(api.reads, 1);
  });
  testWidgets('English disclosures retain purpose boundaries and irreversible result', (tester) async {
    await tester.pumpWidget(_host(Builder(builder: (context) => Column(children: [
      Text(stringsOf(context).merchantResidualPolicyReviewPhoto),
      Text(stringsOf(context).merchantResidualPolicyEvidencePhoto),
      Text(stringsOf(context).merchantResidualPolicyPredict),
      Text(stringsOf(context).merchantResidualPolicyNodeApprove),
    ]))));
    expect(find.text('The camera or photos are accessed only after you choose to use them, to supplement this review of your actual visit. Other images will not be accessed in the background.'), findsOneWidget);
    expect(find.text('The camera or photos are accessed only after you choose to use them, to capture and upload authentic evidence for this after-sales case. Other images will not be accessed in the background.'), findsOneWidget);
    expect(find.text('Winners will receive rewards according to the rules you configured. This round’s result can only be announced once and cannot be changed afterward.'), findsOneWidget);
    expect(find.text('This grants content access and does not mean the platform or organizer endorses the merchant.'), findsOneWidget);
  });
}
class _Gateway implements MerchantAftercareGateway {
  int reads = 0;
  @override
  Future<MerchantAftercareDetail> detail({required int refundId}) async {
    reads++;
    return MerchantAftercareDetail(refundId: refundId, refundNo: 'RF-81', sourceType: 'registration',
      sourceId: 9, refundAmount: 88, reason: '原始退款原因',
      processing: MerchantAftercareProcessing.waitingPlatformReview,
      merchantOpinion: MerchantAftercareOpinion.pending, canRespond: false,
      allowedDecisions: const [], createTime: DateTime(2026, 8, 27, 12, 30),
      refundPolicyCode: 'EXPLORE_END_100_0', refundPolicyVersion: 2,
      refundDeadline: DateTime(2026, 8, 30, 18), responses: [
        MerchantAftercareResponse(id: 7, refundId: refundId, decision: MerchantAftercareDecision.evidence,
          content: '原始售后凭证内容', evidenceUrl: null, actorRoleCode: 'MERCHANT_MANAGER',
          createTime: DateTime(2026, 8, 27, 12, 35)),
      ]);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
