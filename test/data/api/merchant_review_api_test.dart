import 'dart:convert';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('managePage 只向商家管理真接口传分页参数', () async {
    late RequestOptions sent;
    final MerchantReviewApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'mode': 'manage',
          'pageNum': 1,
          'pageSize': 20,
          'total': 0,
          'hasMore': false,
          'averageRating': null,
          'eligibility': null,
          'items': const <dynamic>[],
        },
      };
    });

    final MerchantReviewPage page = await api.managePage(
      pageNum: 1,
      pageSize: 20,
    );

    expect(sent.method, 'POST');
    expect(sent.path, '/api/merchant/reviews/manage');
    expect(sent.queryParameters, <String, dynamic>{
      'pageNum': 1,
      'pageSize': 20,
    });
    expect(page.items, isEmpty);
  });

  test('reply 完整提交 expectedVersion 与 requestId', () async {
    late RequestOptions sent;
    final MerchantReviewApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 81,
          'status': 'VISIBLE',
          'version': 3,
          'replayed': false,
          'auditTaskId': null,
        },
      };
    });
    const MerchantReviewReplyDraft draft = MerchantReviewReplyDraft(
      reviewId: 81,
      expectedVersion: 2,
      content: '谢谢认可',
    );

    await api.reply(draft: draft, requestId: 'mr-reply-abc');

    expect(sent.path, '/api/merchant/reviews/reply');
    expect(sent.data, <String, dynamic>{
      'reviewId': 81,
      'content': '谢谢认可',
      'expectedVersion': 2,
      'requestId': 'mr-reply-abc',
    });
  });

  test('reportAsMerchant 不传客户端猜测的 merchantMemberId', () async {
    late RequestOptions sent;
    final MerchantReviewApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 81,
          'status': 'PENDING_PLATFORM_REVIEW',
          'version': null,
          'replayed': false,
          'auditTaskId': 901,
        },
      };
    });
    const MerchantReviewReportDraft draft = MerchantReviewReportDraft(
      reviewId: 81,
      expectedVersion: 2,
      reason: '评价内容包含与到店体验无关的广告',
    );

    await api.reportAsMerchant(draft: draft, requestId: 'mr-report-abc');

    expect(sent.path, '/api/merchant/reviews/manage/report');
    expect(sent.data, <String, dynamic>{
      'reviewId': 81,
      'reason': '评价内容包含与到店体验无关的广告',
      'expectedVersion': 2,
      'requestId': 'mr-report-abc',
    });
    expect(
      (sent.data as Map<String, dynamic>),
      isNot(contains('merchantMemberId')),
    );
  });

  test('publicPage 只按 merchantRowId 读取公开评价和真实资格', () async {
    late RequestOptions sent;
    final MerchantReviewApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'mode': 'public',
          'pageNum': 1,
          'pageSize': 20,
          'total': 0,
          'hasMore': false,
          'averageRating': null,
          'eligibility': <String, dynamic>{
            'canCreate': false,
            'reasonCode': 'LOGIN_REQUIRED',
            'registrationId': null,
          },
          'items': const <dynamic>[],
        },
      };
    });

    final MerchantReviewPage page = await api.publicPage(
      merchantRowId: 31,
      pageNum: 1,
      pageSize: 20,
    );

    expect(sent.method, 'POST');
    expect(sent.path, '/api/merchant/reviews/public');
    // 真后端实测(2026-09-21,b1-sim-merchant-3 / a1-reviews-public-query 探针):
    // merchantRowId 走 @RequestParam 只读 query,body 传法报 500 缺参。
    expect(sent.queryParameters, <String, dynamic>{
      'merchantRowId': 31,
      'pageNum': 1,
      'pageSize': 20,
    });
    expect(sent.uri.queryParameters['merchantRowId'], '31');
    expect((sent.data as Map?)?.containsKey('merchantRowId'), isNot(true));
    expect(page.eligibility?.reasonCode, 'LOGIN_REQUIRED');
  });

  test('public report 商家主体缺失时本地 fail-closed', () async {
    final MerchantReviewApi api = _api((RequestOptions request) {
      fail('主体缺失时不应发起网络请求');
    });

    await expectLater(
      api.reportPublic(
        merchantOwnerMemberId: 0,
        draft: const MerchantReviewReportDraft(
          reviewId: 81,
          expectedVersion: 2,
          reason: '评价内容包含与到店体验无关的广告',
        ),
        requestId: 'mr-report-invalid-owner',
      ),
      throwsArgumentError,
    );
  });

  test('公开列表业务失败保留服务端错误码与文案', () async {
    final MerchantReviewApi api = _api((RequestOptions request) {
      return <String, dynamic>{'code': '409', 'msg': '商家状态已变更', 'data': null};
    });

    await expectLater(
      api.publicPage(merchantRowId: 31, pageNum: 1, pageSize: 20),
      throwsA(
        isA<MerchantReviewApiException>()
            .having((error) => error.code, 'code', 409)
            .having((error) => error.message, 'message', '商家状态已变更'),
      ),
    );
  });

  test('create 与普通用户 report 使用公开端点并绑定真实主体', () async {
    final List<RequestOptions> sent = <RequestOptions>[];
    final MerchantReviewApi api = _api((RequestOptions request) {
      sent.add(request);
      if (request.path.endsWith('/create')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'reviewId': 81,
            'status': 'PENDING_REVIEW',
            'version': 0,
            'replayed': false,
            'auditTaskId': 901,
          },
        };
      }
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 81,
          'status': 'PENDING_PLATFORM_REVIEW',
          'version': null,
          'replayed': false,
          'auditTaskId': 902,
        },
      };
    });

    await api.create(
      draft: const MerchantReviewCreateDraft(
        merchantRowId: 31,
        registrationId: 902,
        rating: 5,
        content: '真实到店体验很好',
        imageUrls: <String>[],
      ),
      requestId: 'mr-create-abc',
    );
    await api.reportPublic(
      merchantOwnerMemberId: 41,
      draft: const MerchantReviewReportDraft(
        reviewId: 81,
        expectedVersion: 2,
        reason: '评价内容包含与到店体验无关的广告',
      ),
      requestId: 'mr-report-public-abc',
    );

    expect(sent[0].path, '/api/merchant/reviews/create');
    expect(sent[1].path, '/api/merchant/reviews/report');
    expect((sent[1].data as Map<String, dynamic>)['merchantMemberId'], 41);
  });
}

MerchantReviewApi _api(
  Map<String, dynamic> Function(RequestOptions request) reply,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = _StubAdapter(reply);
  return MerchantReviewApi(client);
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> Function(RequestOptions request) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
