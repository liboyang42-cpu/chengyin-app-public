import 'package:chengyin_app/data/api/merchant_aftercare_api.dart';
import 'package:chengyin_app/data/models/merchant_aftercare.dart';
import 'package:chengyin_app/feature/merchant/merchant_aftercare_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('按待回应/处理中/已完成 bucket 请求并打开正确详情', (WidgetTester tester) async {
    final _Gateway api = _Gateway();
    int? openedRefundId;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantAftercareListPage(
          api: api,
          onOpenDetail: (int refundId) => openedRefundId = refundId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.requests, <({MerchantAftercareBucket bucket, int pageNum})>[
      (bucket: MerchantAftercareBucket.pending, pageNum: 1),
    ]);
    expect(find.text('待回应售后'), findsOneWidget);

    await tester.tap(find.text('处理中'));
    await tester.pumpAndSettle();
    expect(api.requests.last, (
      bucket: MerchantAftercareBucket.processing,
      pageNum: 1,
    ));
    expect(find.text('处理中售后'), findsOneWidget);

    await tester.tap(find.byKey(const Key('aftercare-item-102')));
    await tester.pump();
    expect(openedRefundId, 102);
  });

  testWidgets('滚动到底请求下一页并保留已有售后', (WidgetTester tester) async {
    final _Gateway api = _Gateway()..paged = true;
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: MerchantAftercareListPage(api: api)),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('aftercare-list')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(api.requests.any((request) => request.pageNum == 2), isTrue);
    expect(find.byKey(const Key('aftercare-item-201')), findsOneWidget);
    expect(find.byKey(const Key('aftercare-item-202')), findsOneWidget);
    expect(find.text('已经到底了'), findsOneWidget);
  });

  testWidgets('无查看权限时显示岗位说明而不是故障重试', (WidgetTester tester) async {
    final _Gateway api = _Gateway()..forbidden = true;
    await tester.pumpWidget(
      MaterialApp(home: MerchantAftercareListPage(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前岗位没有售后查看权限'), findsOneWidget);
    expect(find.text('请联系店主调整经营团队权限'), findsOneWidget);
    expect(find.text('重新加载'), findsNothing);
  });
}

class _Gateway implements MerchantAftercareGateway {
  final List<({MerchantAftercareBucket bucket, int pageNum})> requests =
      <({MerchantAftercareBucket bucket, int pageNum})>[];
  bool paged = false;
  bool forbidden = false;

  @override
  Future<MerchantAftercarePage> listPage({
    required MerchantAftercareBucket bucket,
    required int pageNum,
    required int pageSize,
  }) async {
    requests.add((bucket: bucket, pageNum: pageNum));
    if (forbidden) {
      throw const MerchantAftercareApiException('当前岗位无权查看', code: 403);
    }
    final int id = paged
        ? (pageNum == 1 ? 201 : 202)
        : bucket == MerchantAftercareBucket.pending
        ? 101
        : 102;
    return MerchantAftercarePage(
      bucket: bucket,
      pageNum: pageNum,
      pageSize: pageSize,
      total: paged ? 2 : 1,
      hasMore: paged && pageNum == 1,
      items: <MerchantAftercareListItem>[
        MerchantAftercareListItem(
          refundId: id,
          refundNo: 'RF-$id',
          sourceType: 'registration',
          sourceId: 1,
          refundAmount: 88,
          reason: bucket == MerchantAftercareBucket.pending ? '待回应售后' : '处理中售后',
          bucket: bucket,
          processing: MerchantAftercareProcessing.waitingPlatformReview,
          merchantOpinion: bucket == MerchantAftercareBucket.pending
              ? MerchantAftercareOpinion.pending
              : MerchantAftercareOpinion.agree,
          canRespond: true,
          refunded: false,
          createTime: DateTime(2026, 8, 27, 12, 30),
        ),
      ],
    );
  }

  @override
  Future<MerchantAftercareDetail> detail({required int refundId}) =>
      throw UnimplementedError();

  @override
  Future<MerchantAftercareReceipt> respond({
    required int refundId,
    required MerchantAftercareResponseDraft draft,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<MerchantAftercareEvidence> uploadEvidence(String filePath) =>
      throw UnimplementedError();
}
