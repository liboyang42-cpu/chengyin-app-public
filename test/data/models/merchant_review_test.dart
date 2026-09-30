import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('商家管理列表保留真实分页、状态与操作权限', () {
    final MerchantReviewPage page = MerchantReviewPage.fromJson(
      <String, dynamic>{
        'mode': 'manage',
        'pageNum': 1,
        'pageSize': 20,
        'total': 1,
        'hasMore': false,
        'averageRating': null,
        'eligibility': null,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 81,
            'rating': 5,
            'content': '环境很好，服务也很耐心。',
            'imageUrls': <String>['https://cdn.example/review.jpg'],
            'authorNickname': '城瘾玩家',
            'authorAvatar': '',
            'verifiedRedemption': true,
            'status': 'VISIBLE',
            'merchantReply': null,
            'repliedAt': null,
            'createTime': '2026-08-27 12:30:00',
            'version': 2,
            'canReply': true,
            'canReport': true,
          },
        ],
      },
      expectedPageNum: 1,
      expectedPageSize: 20,
    );

    expect(page.averageRating, isNull, reason: '无均分不能伪造成 0 分');
    expect(page.items.single.status, MerchantReviewStatus.visible);
    expect(page.items.single.canReply, isTrue);
    expect(page.items.single.canReport, isTrue);
    expect(page.items.single.imageUrls.single.scheme, 'https');
  });

  test('分页回执或行数据畸形时整页 fail-closed', () {
    expect(
      () => MerchantReviewPage.fromJson(
        <String, dynamic>{
          'mode': 'manage',
          'pageNum': 2,
          'pageSize': 20,
          'total': 21,
          'hasMore': true,
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 21,
              'rating': 6,
              'imageUrls': const <String>[],
              'verifiedRedemption': true,
              'status': 'VISIBLE',
              'version': 0,
              'canReply': true,
              'canReport': true,
            },
          ],
        },
        expectedPageNum: 2,
        expectedPageSize: 20,
      ),
      throwsFormatException,
    );
  });

  test('公开回复和举报保留 expectedVersion 与稳定回执', () {
    const MerchantReviewReplyDraft reply = MerchantReviewReplyDraft(
      reviewId: 81,
      expectedVersion: 2,
      content: ' 谢谢认可，欢迎下次再来。 ',
    );
    expect(reply.validationError, isNull);
    expect(reply.toJson(requestId: 'mr-reply-abc'), <String, dynamic>{
      'reviewId': 81,
      'content': '谢谢认可，欢迎下次再来。',
      'expectedVersion': 2,
      'requestId': 'mr-reply-abc',
    });

    expect(
      const MerchantReviewReportDraft(
        reviewId: 81,
        expectedVersion: 2,
        reason: ' ',
      ).validationError,
      '举报原因需填写 2 到 500 字',
    );

    final MerchantReviewReceipt receipt = MerchantReviewReceipt.fromJson(
      <String, dynamic>{
        'reviewId': 81,
        'status': 'VISIBLE',
        'version': 3,
        'replayed': false,
        'auditTaskId': null,
      },
      expectedReviewId: 81,
      expectedAction: MerchantReviewAction.reply,
    );
    expect(receipt.version, 3);
    expect(receipt.replayed, isFalse);
  });

  test('公开评价页保留核销资格，不把未登录或无资格伪装成可评价', () {
    final MerchantReviewPage page = MerchantReviewPage.fromJson(
      <String, dynamic>{
        'mode': 'public',
        'pageNum': 1,
        'pageSize': 20,
        'total': 0,
        'hasMore': false,
        'averageRating': null,
        'eligibility': <String, dynamic>{
          'canCreate': true,
          'reasonCode': 'ELIGIBLE',
          'registrationId': 902,
        },
        'items': const <dynamic>[],
      },
      expectedMode: MerchantReviewMode.public,
      expectedPageNum: 1,
      expectedPageSize: 20,
    );

    expect(page.mode, MerchantReviewMode.public);
    expect(page.eligibility?.canCreate, isTrue);
    expect(page.eligibility?.registrationId, 902);
  });

  test('公开列表只接受 VISIBLE，审核中或下架条目整页 fail-closed', () {
    Map<String, dynamic> pageWithStatus(String status) => <String, dynamic>{
      'mode': 'public',
      'pageNum': 1,
      'pageSize': 20,
      'total': 1,
      'hasMore': false,
      'averageRating': 4.0,
      'eligibility': <String, dynamic>{
        'canCreate': false,
        'reasonCode': 'NO_UNUSED_ACTIVE_REDEMPTION',
        'registrationId': null,
      },
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 81,
          'rating': 4,
          'content': '真实到店体验',
          'imageUrls': const <String>[],
          'authorNickname': '城瘾玩家',
          'authorAvatar': null,
          'verifiedRedemption': true,
          'status': status,
          'merchantReply': null,
          'repliedAt': null,
          'createTime': '2026-08-27 12:30:00',
          'version': 1,
          'canReply': false,
          'canReport': false,
        },
      ],
    };

    for (final String status in <String>['PENDING_REVIEW', 'HIDDEN']) {
      expect(
        () => MerchantReviewPage.fromJson(
          pageWithStatus(status),
          expectedMode: MerchantReviewMode.public,
          expectedPageNum: 1,
          expectedPageSize: 20,
        ),
        throwsFormatException,
      );
    }
  });

  test('真实评价草稿绑定门店、核销、评分和稳定 requestId', () {
    final MerchantReviewImageUrlPolicy productionPolicy =
        MerchantReviewImageUrlPolicy.fromBackendOssConfig(
          endpoint: 'oss-cn-hangzhou.aliyuncs.com',
          bucket: 'chengyin-review',
        );
    final MerchantReviewCreateDraft draft = MerchantReviewCreateDraft(
      merchantRowId: 31,
      registrationId: 902,
      rating: 5,
      content: ' 环境很好，服务也很耐心。 ',
      imageUrls: <String>[
        'https://chengyin-review.oss-cn-hangzhou.aliyuncs.com/upload/'
            '0123456789abcdef0123456789abcdef.jpg?'
            'OSSAccessKeyId=test&Expires=2000000000&Signature=test',
      ],
      imageUrlPolicy: productionPolicy,
    );

    expect(draft.validationError, isNull);
    expect(draft.toJson(requestId: 'mr-create-abc'), <String, dynamic>{
      'merchantRowId': 31,
      'registrationId': 902,
      'rating': 5,
      'content': '环境很好，服务也很耐心。',
      'imageUrls': <String>[
        'https://chengyin-review.oss-cn-hangzhou.aliyuncs.com/upload/'
            '0123456789abcdef0123456789abcdef.jpg?'
            'OSSAccessKeyId=test&Expires=2000000000&Signature=test',
      ],
      'requestId': 'mr-create-abc',
    });

    expect(
      () => MerchantReviewReceipt.fromJson(
        <String, dynamic>{
          'reviewId': 81,
          'status': 'VISIBLE',
          'version': 1,
          'replayed': false,
          'auditTaskId': 901,
        },
        expectedReviewId: 81,
        expectedAction: MerchantReviewAction.create,
      ),
      throwsFormatException,
      reason: '新请求不能把公开状态伪装成初始审核中',
    );
    final MerchantReviewReceipt replay = MerchantReviewReceipt.fromJson(
      <String, dynamic>{
        'reviewId': 81,
        'status': 'VISIBLE',
        'version': 1,
        'replayed': true,
        'auditTaskId': null,
      },
      expectedReviewId: 81,
      expectedAction: MerchantReviewAction.create,
    );
    expect(replay.replayed, isTrue);
    expect(replay.auditTaskId, isNull);
    expect(
      () => MerchantReviewReceipt.fromJson(
        <String, dynamic>{
          'reviewId': 81,
          'status': 'VISIBLE',
          'version': null,
          'replayed': true,
          'auditTaskId': null,
        },
        expectedReviewId: 81,
        expectedAction: MerchantReviewAction.create,
      ),
      throwsFormatException,
      reason: '重放也必须保留实体版本，不能接受不完整回执',
    );
    expect(
      () => MerchantReviewReceipt.fromJson(
        <String, dynamic>{
          'reviewId': 81,
          'status': 'VISIBLE',
          'version': 1,
          'replayed': true,
          'auditTaskId': 901,
        },
        expectedReviewId: 81,
        expectedAction: MerchantReviewAction.create,
      ),
      throwsFormatException,
      reason: '幂等重放不能创建或冒充新的审核任务',
    );

    expect(
      const MerchantReviewCreateDraft(
        merchantRowId: 31,
        registrationId: 902,
        rating: 5,
        content: '真实到店体验',
        imageUrls: <String>[
          'https://attacker.example/upload/'
              '0123456789abcdef0123456789abcdef.jpg?'
              'OSSAccessKeyId=test&Expires=2000000000&Signature=test',
        ],
      ).validationError,
      '评价图片必须来自城瘾安全上传链路',
    );
    expect(
      () => MerchantReviewReceipt.fromJson(
        <String, dynamic>{
          'reviewId': 81,
          'status': 'PENDING_REVIEW',
          'version': 0,
          'replayed': false,
          'auditTaskId': null,
        },
        expectedReviewId: 81,
        expectedAction: MerchantReviewAction.create,
      ),
      throwsFormatException,
      reason: '没有平台审核任务不能宣称评价提交完成',
    );

    final MerchantReviewImageUrlPolicy stagingPolicy =
        MerchantReviewImageUrlPolicy.fromBackendOssConfig(
          endpoint: 'oss-cn-shanghai.aliyuncs.com',
          bucket: 'chengyin-review-staging',
        );
    const String stagingImage =
        'https://chengyin-review-staging.oss-cn-shanghai.aliyuncs.com/upload/'
        '0123456789abcdef0123456789abcdef.png?'
        'OSSAccessKeyId=test&Expires=2000000000&Signature=test';
    expect(
      const MerchantReviewCreateDraft(
        merchantRowId: 31,
        registrationId: 902,
        rating: 5,
        content: '真实到店体验',
        imageUrls: <String>[stagingImage],
      ).validationError,
      '评价图片必须来自城瘾安全上传链路',
      reason: '默认生产策略不能信任未配置的环境 host',
    );
    expect(
      MerchantReviewCreateDraft(
        merchantRowId: 31,
        registrationId: 902,
        rating: 5,
        content: '真实到店体验',
        imageUrls: const <String>[stagingImage],
        imageUrlPolicy: stagingPolicy,
      ).validationError,
      isNull,
    );
    final MerchantReviewImageUrlPolicy uploadReceiptPolicy =
        MerchantReviewImageUrlPolicy.failClosed.allowingTrustedUploadReceipt(
          stagingImage,
        );
    expect(
      MerchantReviewCreateDraft(
        merchantRowId: 31,
        registrationId: 902,
        rating: 5,
        content: '真实到店体验',
        imageUrls: const <String>[stagingImage],
        imageUrlPolicy: uploadReceiptPolicy,
      ).validationError,
      isNull,
    );
    expect(
      () => MerchantReviewImageUrlPolicy.failClosed
          .allowingTrustedUploadReceipt('https://cdn.example/review.jpg'),
      throwsArgumentError,
      reason: '即使是上传回调也不接受普通 HTTPS 地址',
    );
    expect(
      () => MerchantReviewImageUrlPolicy.fromBackendOssConfig(
        endpoint: 'https://oss-cn-shanghai.aliyuncs.com',
        bucket: '../attacker',
      ),
      throwsArgumentError,
    );
  });
}
