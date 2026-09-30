import 'dart:convert';
import 'dart:io';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_aftercare_api.dart';
import 'package:chengyin_app/data/models/merchant_aftercare.dart';
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

  test('listPage 用 bucket/pageNum/pageSize 查询后端真分页', () async {
    late RequestOptions sent;
    final MerchantAftercareApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'bucket': 'PROCESSING',
          'pageNum': 2,
          'pageSize': 1,
          'total': 2,
          'hasMore': false,
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'refundId': 82,
              'refundNo': 'RF-82',
              'sourceType': 'registration',
              'sourceId': 10,
              'refundAmount': 18.5,
              'reason': '已提交意见',
              'bucket': 'PROCESSING',
              'processing': 'WAITING_PLATFORM_REVIEW',
              'merchantOpinion': 'AGREE',
              'canRespond': true,
              'refunded': false,
              'createTime': '2026-08-27 12:30:00',
            },
          ],
        },
      };
    });

    final MerchantAftercarePage page = await api.listPage(
      bucket: MerchantAftercareBucket.processing,
      pageNum: 2,
      pageSize: 1,
    );

    expect(sent.path, '/api/merchant/aftercare/list');
    expect(sent.method, 'POST');
    expect(sent.queryParameters, <String, dynamic>{
      'bucket': 'PROCESSING',
      'pageNum': 2,
      'pageSize': 1,
    });
    expect(page.items.single.refundId, 82);
  });

  test('detail 用 refundId 查询并拒绝串单回执', () async {
    late RequestOptions sent;
    final MerchantAftercareApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'refundId': 81,
          'processing': 'WAITING_PLATFORM_REVIEW',
          'merchantOpinion': 'PENDING',
          'canRespond': true,
          'allowedDecisions': <String>['AGREE', 'REJECT'],
          'responses': const <dynamic>[],
        },
      };
    });

    final MerchantAftercareDetail detail = await api.detail(refundId: 81);

    expect(sent.path, '/api/merchant/aftercare/detail');
    expect(sent.queryParameters, <String, dynamic>{'refundId': 81});
    expect(detail.refundId, 81);
  });

  test('respond 只提交决策、内容、凭证 key 与 requestId', () async {
    late RequestOptions sent;
    final MerchantAftercareApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 11,
          'refundId': 81,
          'decision': 'REJECT',
          'processing': 'WAITING_PLATFORM_REVIEW',
          'merchantOpinion': 'REJECT',
          'refunded': false,
        },
      };
    });
    final MerchantAftercareResponseDraft draft = MerchantAftercareResponseDraft(
      decision: MerchantAftercareDecision.reject,
      content: ' 未参加活动不属实 ',
    );

    final MerchantAftercareReceipt receipt = await api.respond(
      refundId: 81,
      draft: draft,
      requestId: 'ma:abc:1:def',
    );

    expect(sent.path, '/api/merchant/aftercare/respond');
    expect(sent.queryParameters, <String, dynamic>{'refundId': 81});
    expect(sent.data, <String, dynamic>{
      'decision': 'REJECT',
      'content': '未参加活动不属实',
      'requestId': 'ma:abc:1:def',
    });
    expect(receipt.decision, MerchantAftercareDecision.reject);
  });

  test('uploadEvidence 使用专用 bizType，只接收 object key', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'merchant-aftercare-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final File file = File('${temp.path}/proof.jpg')
      ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    late RequestOptions sent;
    final MerchantAftercareApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'fileName':
            'upload/merchant-aftercare-evidence/'
            '0123456789abcdef0123456789abcdef.jpg',
      };
    });

    final MerchantAftercareEvidence evidence = await api.uploadEvidence(
      file.path,
    );

    expect(sent.path, '/api/common/uploadOSS');
    final FormData form = sent.data as FormData;
    expect(
      form.fields.any(
        (MapEntry<String, String> entry) =>
            entry.key == 'bizType' &&
            entry.value == 'merchant_aftercare_evidence',
      ),
      isTrue,
    );
    expect(form.files.single.key, 'file');
    expect(evidence.localPath, file.path);
    expect(
      evidence.objectKey,
      startsWith('upload/merchant-aftercare-evidence/'),
    );
  });
}

MerchantAftercareApi _api(
  Map<String, dynamic> Function(RequestOptions request) reply,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
    // 每个写/读操作前先读服务端经营权限;该步不是被测对象,固定回一份有
    // 售后权限的身份,让断言只盯业务请求。
    if (request.path == '/api/merchant/access/me') {
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'active': true,
          'merchant': <String, dynamic>{'id': 7, 'name': '山屿咖啡'},
          'roleCode': 'MERCHANT_OWNER',
          'permissions': <dynamic>[
            'merchant:aftercare:read',
            'merchant:aftercare:respond',
            'merchant:aftercare:evidence',
          ],
        },
      };
    }
    return reply(request);
  });
  return MerchantAftercareApi(client);
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
