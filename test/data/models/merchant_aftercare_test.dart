import 'package:chengyin_app/data/models/merchant_aftercare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MerchantAftercarePage', () {
    test('解析 bucket 与服务端分页，不把未知金额当作 0', () {
      final MerchantAftercarePage page = MerchantAftercarePage.fromJson(
        <String, dynamic>{
          'bucket': 'PENDING',
          'pageNum': 1,
          'pageSize': 20,
          'total': 1,
          'hasMore': false,
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'refundId': 81,
              'refundNo': 'RF-81',
              'sourceType': 'registration',
              'sourceId': 9,
              'refundAmount': null,
              'reason': '行程取消',
              'bucket': 'PENDING',
              'processing': 'WAITING_PLATFORM_REVIEW',
              'merchantOpinion': 'PENDING',
              'canRespond': true,
              'refunded': false,
              'createTime': '2026-08-27 12:30:00',
            },
          ],
        },
        expectedBucket: MerchantAftercareBucket.pending,
        expectedPageNum: 1,
      );

      expect(page.bucket, MerchantAftercareBucket.pending);
      expect(page.total, 1);
      expect(page.hasMore, isFalse);
      expect(page.items.single.refundAmount, isNull);
      expect(page.items.single.refundAmountText, '金额待确认');
      expect(page.items.single.processingText, '平台审核中');
      expect(page.items.single.merchantOpinionText, '等待商家意见');
    });

    test('拒绝伪造的 bucket 或 hasMore 回执', () {
      final Map<String, dynamic> body = <String, dynamic>{
        'bucket': 'COMPLETED',
        'pageNum': 1,
        'pageSize': 20,
        'total': 1,
        'hasMore': true,
        'items': const <dynamic>[],
      };

      expect(
        () => MerchantAftercarePage.fromJson(
          body,
          expectedBucket: MerchantAftercareBucket.pending,
          expectedPageNum: 1,
        ),
        throwsFormatException,
      );
    });
  });

  test('详情保留平台、商家、款项三条独立事实与凭证引用', () {
    final MerchantAftercareDetail detail = MerchantAftercareDetail.fromJson(
      <String, dynamic>{
        'refundId': 81,
        'refundNo': 'RF-81',
        'sourceType': 'registration',
        'sourceId': 9,
        'refundAmount': 88,
        'reason': '行程取消',
        'refundStatus': 0,
        'payoutStatus': 0,
        'processing': 'WAITING_PLATFORM_REVIEW',
        'merchantOpinion': 'AGREE',
        'canRespond': true,
        'allowedDecisions': <String>['AGREE', 'REJECT', 'EVIDENCE'],
        'createTime': '2026-08-27 12:30:00',
        'refundPolicyCode': 'EXPLORE_END_100_0',
        'refundPolicyVersion': 2,
        'refundDeadline': '2026-08-30 18:00:00',
        'responses': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 7,
            'refundId': 81,
            'decision': 'EVIDENCE',
            'content': '现场签到记录',
            'evidenceUrl': 'https://signed.example/evidence.jpg',
            'actorRoleCode': 'MERCHANT_MANAGER',
            'createTime': '2026-08-27 12:35:00',
            'processing': 'WAITING_PLATFORM_REVIEW',
            'merchantOpinion': 'AGREE',
            'refunded': false,
          },
        ],
      },
      expectedRefundId: 81,
    );

    expect(
      detail.processing,
      MerchantAftercareProcessing.waitingPlatformReview,
    );
    expect(detail.merchantOpinion, MerchantAftercareOpinion.agree);
    expect(detail.refunded, isFalse);
    expect(detail.allowedDecisions, contains(MerchantAftercareDecision.reject));
    expect(detail.responses.single.evidenceUrl?.scheme, 'https');
    expect(detail.responses.single.actorText, '店长');
  });

  test('拒绝必须有原因，凭证只接受售后专用 object key', () {
    expect(
      MerchantAftercareResponseDraft(
        decision: MerchantAftercareDecision.reject,
        content: '   ',
      ).validationError,
      '请填写建议驳回的原因',
    );

    const String key =
        'upload/merchant-aftercare-evidence/'
        '0123456789abcdef0123456789abcdef.jpg';
    final MerchantAftercareResponseDraft evidence =
        MerchantAftercareResponseDraft(
          decision: MerchantAftercareDecision.evidence,
          evidenceKey: key,
        );
    expect(evidence.validationError, isNull);
    expect(evidence.toJson(requestId: 'ma:abc:1:def'), <String, dynamic>{
      'decision': 'EVIDENCE',
      'content': null,
      'evidenceKeys': <String>[key],
      'requestId': 'ma:abc:1:def',
    });

    expect(
      MerchantAftercareResponseDraft(
        decision: MerchantAftercareDecision.evidence,
        evidenceKey: 'https://example.com/forever.jpg',
      ).validationError,
      '凭证上传结果无效，请重新上传',
    );
  });

  test('提交回执必须匹配退款 ID、决策与款项状态', () {
    final MerchantAftercareReceipt receipt = MerchantAftercareReceipt.fromJson(
      <String, dynamic>{
        'id': 11,
        'refundId': 81,
        'decision': 'AGREE',
        'processing': 'WAITING_PLATFORM_REVIEW',
        'merchantOpinion': 'AGREE',
        'refunded': false,
      },
      expectedRefundId: 81,
      expectedDecision: MerchantAftercareDecision.agree,
    );
    expect(receipt.id, 11);
    expect(receipt.refunded, isFalse);

    expect(
      () => MerchantAftercareReceipt.fromJson(
        <String, dynamic>{
          'id': 11,
          'refundId': 81,
          'decision': 'AGREE',
          'processing': 'REFUNDED',
          'merchantOpinion': 'AGREE',
          'refunded': false,
        },
        expectedRefundId: 81,
        expectedDecision: MerchantAftercareDecision.agree,
      ),
      throwsFormatException,
    );
  });
}
