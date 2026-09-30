import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:chengyin_app/feature/merchant/merchant_reviews_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('按小程序顺序显示口碑概览、真实到店评价并真分页', (WidgetTester tester) async {
    final _Gateway api = _Gateway()..paged = true;
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: MerchantReviewsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('口碑评价管理'), findsOneWidget);
    expect(find.text('公开口碑'), findsOneWidget);
    expect(find.text('评价资格来自已生效核销，商家回复不会改写用户原评。'), findsOneWidget);
    expect(find.text('评价管理'), findsOneWidget);
    expect(find.text('公开列表仅展示平台当前判定为 VISIBLE 的内容'), findsOneWidget);
    expect(find.byKey(const Key('merchant-review-201')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('merchant-review-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();

    expect(api.pages, <int>[1, 2]);
    expect(find.byKey(const Key('merchant-review-202')), findsOneWidget);
    expect(find.text('已经到底了'), findsOneWidget);
  });

  testWidgets('公开回复失败后可原地重试并复用同一 requestId', (WidgetTester tester) async {
    final _Gateway api = _Gateway()..failFirstReply = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantReviewsPage(
          api: api,
          requestIdFactory: (_) => 'mr-reply-fixed',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('merchant-review-reply-101')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-review-action-input')),
      '谢谢认可，欢迎下次再来。',
    );
    await tester.tap(find.byKey(const Key('merchant-review-action-submit')));
    await tester.pumpAndSettle();

    expect(find.text('网络中断'), findsOneWidget);
    await tester.tap(find.byKey(const Key('merchant-review-action-submit')));
    await tester.pumpAndSettle();

    expect(api.replyRequestIds, <String>['mr-reply-fixed', 'mr-reply-fixed']);
    expect(api.replyDrafts.single.content, '谢谢认可，欢迎下次再来。');
    expect(find.byKey(const Key('merchant-review-action-input')), findsNothing);
  });

  testWidgets('商家举报只提交当前评价版本并显示平台复核闭环', (WidgetTester tester) async {
    final _Gateway api = _Gateway();
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantReviewsPage(
          api: api,
          requestIdFactory: (_) => 'mr-report-fixed',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('merchant-review-report-101')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-review-action-input')),
      '评价中含有与真实到店体验无关的广告。',
    );
    await tester.tap(find.byKey(const Key('merchant-review-action-submit')));
    await tester.pumpAndSettle();

    expect(api.reportRequestIds, <String>['mr-report-fixed']);
    expect(api.reportDrafts.single.reviewId, 101);
    expect(api.reportDrafts.single.expectedVersion, 2);
    expect(find.byKey(const Key('merchant-review-action-input')), findsNothing);
  });

  testWidgets('已有回复可修改:回填原文,提交走 reply/update 并复用同一 requestId', (
    WidgetTester tester,
  ) async {
    final _Gateway api = _Gateway()..withMerchantReply = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantReviewsPage(
          api: api,
          requestIdFactory: (_) => 'mr-reply-fixed',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('merchant-review-edit-reply-101')));
    await tester.pumpAndSettle();

    final CupertinoTextField field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('merchant-review-action-input')),
    );
    expect(field.controller?.text, '谢谢认可，欢迎再来。', reason: '修改要先回填原文');

    await tester.enterText(
      find.byKey(const Key('merchant-review-action-input')),
      '谢谢认可，下次请你喝杯咖啡。',
    );
    await tester.tap(find.byKey(const Key('merchant-review-action-submit')));
    await tester.pumpAndSettle();

    expect(api.updatedDrafts.single.content, '谢谢认可，下次请你喝杯咖啡。');
    expect(
      api.updatedDrafts.single.expectedVersion,
      2,
      reason: 'CAS 版本必须是当前行版本',
    );
    expect(api.updatedRequestIds, <String>['mr-reply-fixed']);
    expect(find.text('公开回复已更新'), findsOneWidget);
    expect(api.pages, <int>[1, 1], reason: '改完要重拉列表');
  });

  testWidgets('删除公开回复:先过危险确认,确认后才发请求', (WidgetTester tester) async {
    final _Gateway api = _Gateway()..withMerchantReply = true;
    await tester.pumpWidget(MaterialApp(home: MerchantReviewsPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('merchant-review-delete-reply-101')));
    await tester.pumpAndSettle();

    expect(find.text('删除这条公开回复?'), findsOneWidget);
    expect(api.deletes, isEmpty, reason: '确认之前不许发删除请求');

    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.text('删除回复'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.deletes.single.reviewId, 101);
    expect(api.deletes.single.version, 2);
    expect(find.text('回复已删除，这条评价已回到待回复'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('回复不可改时(服务端没给 canEditReply)不摆修改/删除入口', (
    WidgetTester tester,
  ) async {
    final _Gateway api = _Gateway()
      ..withMerchantReply = true
      ..canEditReply = false;
    await tester.pumpWidget(MaterialApp(home: MerchantReviewsPage(api: api)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('merchant-review-edit-reply-101')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('merchant-review-delete-reply-101')),
      findsNothing,
    );
  });

  testWidgets('无 MARKETING_READ 权限显示独立权限态，不伪装成空列表', (
    WidgetTester tester,
  ) async {
    final _Gateway api = _Gateway()..forbidden = true;
    await tester.pumpWidget(MaterialApp(home: MerchantReviewsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('没有口碑管理权限'), findsOneWidget);
    expect(find.text('当前账号不能查看、回复或举报商家口碑。'), findsOneWidget);
    expect(find.text('暂无真实到店评价'), findsNothing);
  });

  testWidgets('评价图片可用 Apple 弹层放大预览', (WidgetTester tester) async {
    final _Gateway api = _Gateway()..withImage = true;
    await tester.pumpWidget(MaterialApp(home: MerchantReviewsPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('merchant-review-image-101-0')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('merchant-review-image-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('merchant-review-image-close')),
      findsOneWidget,
    );
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('merchant-review-image-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('作者、核销、回复时间与操作顺序对齐小程序', (WidgetTester tester) async {
    final _Gateway repliedApi = _Gateway()..withMerchantReply = true;
    await tester.pumpWidget(
      MaterialApp(home: MerchantReviewsPage(api: repliedApi)),
    );
    await tester.pumpAndSettle();

    expect(find.text('城'), findsOneWidget, reason: '无头像时保留小程序回退');
    expect(find.text('核销已验证'), findsOneWidget);
    expect(find.text('你的回复 · 2026-08-27 13:00'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey<String>('fresh-actions'),
        home: MerchantReviewsPage(api: _Gateway()),
      ),
    );
    await tester.pumpAndSettle();
    final double replyX = tester
        .getTopLeft(find.byKey(const Key('merchant-review-reply-101')))
        .dx;
    final double reportX = tester
        .getTopLeft(find.byKey(const Key('merchant-review-report-101')))
        .dx;
    expect(replyX, lessThan(reportX), reason: '小程序顺序为公开回复、举报');
  });
}

class _Gateway implements MerchantReviewGateway {
  final List<int> pages = <int>[];
  bool paged = false;
  bool failFirstReply = false;
  bool forbidden = false;
  bool withImage = false;
  bool withMerchantReply = false;
  bool canEditReply = true;
  bool failUpdate = false;
  bool failDelete = false;
  final List<String> replyRequestIds = <String>[];
  final List<MerchantReviewReplyDraft> replyDrafts =
      <MerchantReviewReplyDraft>[];
  final List<String> reportRequestIds = <String>[];
  final List<MerchantReviewReportDraft> reportDrafts =
      <MerchantReviewReportDraft>[];
  final List<MerchantReviewReplyDraft> updatedDrafts =
      <MerchantReviewReplyDraft>[];
  final List<String> updatedRequestIds = <String>[];
  final List<({int reviewId, int version})> deletes =
      <({int reviewId, int version})>[];

  @override
  Future<MerchantReviewPage> managePage({
    required int pageNum,
    required int pageSize,
  }) async {
    pages.add(pageNum);
    if (forbidden) {
      throw const MerchantReviewApiException('当前账号没有口碑管理权限', code: 403);
    }
    final int id = paged ? (pageNum == 1 ? 201 : 202) : 101;
    return MerchantReviewPage(
      pageNum: pageNum,
      pageSize: pageSize,
      total: paged ? 2 : 1,
      hasMore: paged && pageNum == 1,
      averageRating: 4.8,
      items: <MerchantReviewItem>[
        MerchantReviewItem(
          id: id,
          rating: 5,
          content: '环境很好，服务也很耐心。',
          imageUrls: withImage
              ? <Uri>[
                  Uri.parse('https://cdn.example/review-1.jpg'),
                  Uri.parse('https://cdn.example/review-2.jpg'),
                ]
              : const <Uri>[],
          authorNickname: '城瘾玩家',
          authorAvatar: null,
          verifiedRedemption: true,
          status: MerchantReviewStatus.visible,
          merchantReply: withMerchantReply ? '谢谢认可，欢迎再来。' : null,
          repliedAt: withMerchantReply ? DateTime(2026, 8, 27, 13) : null,
          createTime: DateTime(2026, 8, 27, 12, 30),
          version: 2,
          canReply: !withMerchantReply,
          canReport: true,
          canEditReply: withMerchantReply && canEditReply,
        ),
      ],
    );
  }

  @override
  Future<MerchantReviewReceipt> reply({
    required MerchantReviewReplyDraft draft,
    required String requestId,
  }) async {
    replyRequestIds.add(requestId);
    if (failFirstReply && replyRequestIds.length == 1) {
      throw const MerchantReviewApiException('网络中断');
    }
    replyDrafts.add(draft);
    return MerchantReviewReceipt(
      reviewId: draft.reviewId,
      status: 'VISIBLE',
      version: draft.expectedVersion + 1,
      replayed: false,
      auditTaskId: null,
    );
  }

  @override
  Future<void> updateReply({
    required MerchantReviewReplyDraft draft,
    required String requestId,
  }) async {
    updatedDrafts.add(draft);
    updatedRequestIds.add(requestId);
    if (failUpdate) throw const MerchantReviewApiException('版本已过期，请刷新后重试');
  }

  @override
  Future<void> deleteReply({
    required int reviewId,
    required int expectedVersion,
    required String requestId,
  }) async {
    deletes.add((reviewId: reviewId, version: expectedVersion));
    if (failDelete) throw const MerchantReviewApiException('删除回复失败，请稍后重试');
  }

  @override
  Future<MerchantReviewReceipt> reportAsMerchant({
    required MerchantReviewReportDraft draft,
    required String requestId,
  }) async {
    reportRequestIds.add(requestId);
    reportDrafts.add(draft);
    return MerchantReviewReceipt(
      reviewId: draft.reviewId,
      status: 'PENDING_PLATFORM_REVIEW',
      version: null,
      replayed: false,
      auditTaskId: 901,
    );
  }
}
