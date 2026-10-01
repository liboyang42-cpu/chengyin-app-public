import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:chengyin_app/feature/merchant/merchant_review_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

void main() {
  test('Schema errors retain FormatException compatibility and local provenance', () {
    expect(() => MerchantReviewStatus.parse('UNKNOWN'), throwsA(
      isA<MerchantReviewLocalFormatException>()
        .having((e) => e.message, 'original message', '评价状态不完整'),
    ));
    expect(() => MerchantReviewStatus.parse('UNKNOWN'), throwsA(isA<FormatException>()));
  });
  test('Invalid drafts retain ArgumentError compatibility without making a request', () {
    const draft = MerchantReviewCreateDraft(merchantRowId: 0, registrationId: 7,
      rating: 5, content: '原始正文', imageUrls: []);
    expect(() => draft.toJson(requestId: 'test-12345'), throwsA(
      isA<MerchantReviewLocalArgumentError>()
        .having((e) => e.localMessage, 'original validation', '核销资格已失效，请刷新'),
    ));
    expect(() => draft.toJson(requestId: 'test-12345'), throwsA(isA<ArgumentError>()));
  });
  testWidgets('English model failures preserve server messages with identical wording', (tester) async {
    await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) => Column(children: [
        Text(merchantReviewErrorText(context, const MerchantReviewLocalFormatException('评价状态不完整'))),
        Text(merchantReviewErrorText(context, const MerchantReviewApiException('评价状态不完整'))),
        Text(merchantReviewErrorText(context, const MerchantReviewApiException('Server refused this request'))),
        Text(merchantReviewErrorText(context, const MerchantReviewLocalFormatException('reviewId 不完整', field: 'reviewId'))),
      ])),
    ));
    expect(find.text('Review status is incomplete'), findsOneWidget);
    expect(find.text('评价状态不完整'), findsOneWidget);
    expect(find.text('Server refused this request'), findsOneWidget);
    expect(find.text('reviewId is incomplete'), findsOneWidget);
  });
}
