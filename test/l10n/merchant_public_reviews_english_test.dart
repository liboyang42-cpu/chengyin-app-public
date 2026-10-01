import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_reviews_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

MerchantReviewItem _item(int id, {String? author}) => MerchantReviewItem.fromJson({
  'id': id, 'rating': 5, 'content': '原始评价$id', 'imageUrls': <String>[],
  if (author != null) 'authorNickname': author,
  'verifiedRedemption': true, 'status': 'VISIBLE', 'merchantReply': '原始商家回复',
  'createTime': '2026-09-30 12:34:00', 'version': 2, 'canReply': false, 'canReport': true,
});
class _Api implements MerchantPublicReviewGateway {
  bool eligible = false;
  int reads = 0;
  final requests = <String>[];
  final drafts = <MerchantReviewCreateDraft>[];
  @override
  Future<MerchantReviewPage> publicPage({required int merchantRowId, required int pageNum, required int pageSize}) async {
    reads++;
    return MerchantReviewPage(mode: MerchantReviewMode.public, pageNum: pageNum, pageSize: pageSize,
      total: 2, hasMore: false, averageRating: 4.5,
      eligibility: MerchantReviewEligibility(canCreate: eligible, reasonCode: eligible ? 'ELIGIBLE' : 'LOGIN_REQUIRED', registrationId: eligible ? 901 : null),
      items: [_item(1), _item(2, author: '城瘾玩家')]);
  }
  @override
  Future<MerchantReviewReceipt> create({required MerchantReviewCreateDraft draft, required String requestId}) async {
    drafts.add(draft);
    requests.add(requestId);
    if (requests.length == 1) throw const MerchantReviewApiException('评价提交失败');
    return const MerchantReviewReceipt(reviewId: 7, status: 'PENDING_REVIEW', version: 0, replayed: false, auditTaskId: 10);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Widget _page(_Api api, {int? merchantId = 31}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MerchantPublicReviewsPage(api: api, merchantRowId: merchantId, merchantOwnerMemberId: 41,
    liquidGlassSupported: false, requestIdFactory: (_) => 'review-fixed-request',
    uploadImage: (_) async => throw StateError('Images are not used in these tests')),
);
void main() {
  testWidgets('English invalid public review link does not request a guessed merchant', (tester) async {
    final api = _Api();
    await tester.pumpWidget(_page(api, merchantId: null));
    await tester.pumpAndSettle();
    expect(find.text('Invalid link'), findsOneWidget);
    expect(api.reads, 0);
  });
  testWidgets('English review eligibility preserves its policy explanation', (tester) async {
    await tester.pumpWidget(_page(_Api()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to check review eligibility'), findsOneWidget);
    expect(find.text('只有本人报名且目标门店的 ACTIVE 核销可评价；撤销核销不具备资格。'), findsOneWidget);
    expect(find.byKey(const Key('public-review-submit')), findsNothing);
  });
  testWidgets('public reviews distinguish fallback names and retain UGC replies and timestamps', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_page(_Api()));
    await tester.pumpAndSettle();
    expect(find.text('Chengyin player'), findsOneWidget);
    expect(find.text('城瘾玩家'), findsOneWidget);
    expect(find.text('原始评价1'), findsOneWidget);
    expect(find.text('原始商家回复'), findsNWidgets(2));
    expect(find.text('2026-09-30 12:34'), findsNWidgets(2));
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('2 reviews'), findsOneWidget);
  });
  testWidgets('English submission keeps server errors and reuses request identity on retry', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api()..eligible = true;
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('public-review-star-5')));
    await tester.enterText(find.byKey(const Key('public-review-content')), '原始真实评价');
    await tester.pumpAndSettle();
    final submit = find.descendant(of: find.byKey(const Key('public-review-submit')), matching: find.byType(CupertinoButton));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('评价提交失败'), findsOneWidget);
    expect(find.text('Could not submit review'), findsNothing);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.requests, ['review-fixed-request', 'review-fixed-request']);
    expect(api.drafts.every((draft) => draft.content == '原始真实评价' && draft.rating == 5 && draft.registrationId == 901), isTrue);
    expect(find.text('Review submitted, awaiting platform review'), findsOneWidget);
  });
}
