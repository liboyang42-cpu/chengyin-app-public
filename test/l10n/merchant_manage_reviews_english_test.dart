import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:chengyin_app/feature/merchant/merchant_reviews_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Api implements MerchantReviewGateway {
  bool canReply = true;
  final requestIds = <String>[];
  final drafts = <MerchantReviewReplyDraft>[];
  @override
  Future<MerchantReviewPage> managePage({required int pageNum, required int pageSize}) async => MerchantReviewPage(
    pageNum: pageNum, pageSize: pageSize, total: 1, hasMore: false, averageRating: 4.5,
    items: [MerchantReviewItem(id: 1, rating: 5, content: '原始玩家评价', imageUrls: const [],
      authorNickname: '城瘾玩家', authorAvatar: null, verifiedRedemption: true,
      status: MerchantReviewStatus.visible, merchantReply: null, repliedAt: null,
      createTime: DateTime(2026, 9, 30, 12, 34), version: 7, canReply: canReply, canReport: false)],
  );
  @override
  Future<MerchantReviewReceipt> reply({required MerchantReviewReplyDraft draft, required String requestId}) async {
    drafts.add(draft);
    requestIds.add(requestId);
    if (requestIds.length == 1) throw const MerchantReviewApiException('原始服务端拒绝');
    return const MerchantReviewReceipt(reviewId: 1, status: 'VISIBLE', version: 8, replayed: false, auditTaskId: null);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Widget _page(_Api api) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MerchantReviewsPage(api: api, requestIdFactory: (_) => 'reply-fixed'),
);
void main() {
  testWidgets('English review manager respects server permissions and original review', (tester) async {
    await tester.pumpWidget(_page(_Api()..canReply = false));
    await tester.pumpAndSettle();
    expect(find.text('Publicly visible'), findsOneWidget);
    expect(find.text('原始玩家评价'), findsOneWidget);
    expect(find.text('城瘾玩家'), findsOneWidget);
    expect(find.byKey(const Key('merchant-review-reply-1')), findsNothing);
    expect(find.byKey(const Key('merchant-review-report-1')), findsNothing);
  });
  testWidgets('English reply validation and retry preserve content version and request identity', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api();
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-review-reply-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-review-action-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Reply text must contain 1–500 characters'), findsOneWidget);
    expect(api.requestIds, isEmpty);
    expect(find.text('回复后可修改，也可以删除；商家回复不会改写用户评分与正文。'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('merchant-review-action-input')), '原始商家回复');
    await tester.tap(find.byKey(const Key('merchant-review-action-submit')));
    await tester.pumpAndSettle();
    expect(find.text('原始服务端拒绝'), findsOneWidget);
    await tester.tap(find.byKey(const Key('merchant-review-action-submit')));
    await tester.pumpAndSettle();
    expect(api.requestIds, ['reply-fixed', 'reply-fixed']);
    expect(api.drafts.every((draft) => draft.content == '原始商家回复' && draft.expectedVersion == 7), isTrue);
    expect(find.text('Public reply published'), findsOneWidget);
  });
}
