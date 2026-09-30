import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_customer_detail_api.dart';
import 'package:chengyin_app/data/models/merchant_customer_detail.dart';
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

  test('access 先读权限真源，detail 只用路由客户 ID 请求详情', () async {
    final List<RequestOptions> sent = <RequestOptions>[];
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
      sent.add(request);
      if (request.path == '/api/merchant/access/me') {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'active': true,
            'merchant': <String, dynamic>{'id': 7, 'name': '山屿咖啡'},
            'roleCode': 'MERCHANT_OWNER',
            'permissions': <dynamic>[
              'merchant:crm:read',
              'merchant:crm:segment',
            ],
          },
        };
      }
      return <String, dynamic>{
        'code': 200,
        'data': _detailJson(customerMemberId: 41),
      };
    });
    final MerchantCustomerDetailApi api = MerchantCustomerDetailApi(client);

    final MerchantCustomerAccess access = await api.access();
    final MerchantCustomerDetail detail = await api.detail(41);

    expect(access.active, isTrue);
    expect(access.canReadCrm, isTrue);
    expect(access.canSegmentCrm, isTrue);
    expect(detail.summary.customerMemberId, 41);
    expect(sent.map((RequestOptions request) => request.path), <String>[
      '/api/merchant/access/me',
      '/api/merchant/crm/customers/41/detail',
    ]);
    expect(sent.last.data, isNull);
  });

  test('新增备注只提交白名单字段，并保留服务端回执', () async {
    late RequestOptions sent;
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'msg': '操作成功',
        'data': <String, dynamic>{'id': 8, 'requestId': 'crm-note-fixed'},
      };
    });

    final MerchantCustomerMutationReceipt receipt =
        await MerchantCustomerDetailApi(client).addNote(
          customerMemberId: 41,
          content: '  记得无糖  ',
          requestId: 'crm-note-fixed',
          correctsNoteId: 7,
        );

    expect(sent.path, '/api/merchant/crm/customers/41/notes');
    expect(sent.data, <String, dynamic>{
      'content': '记得无糖',
      'requestId': 'crm-note-fixed',
      'correctsNoteId': 7,
    });
    expect(receipt.message, '操作成功');
    expect(receipt.data, containsPair('id', 8));
  });

  test('隐藏备注带 CAS 版本和幂等标识，不修改原文', () async {
    late RequestOptions sent;
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
      sent = request;
      return <String, dynamic>{'code': 200, 'data': '备注已隐藏'};
    });

    final MerchantCustomerMutationReceipt receipt =
        await MerchantCustomerDetailApi(client).hideNote(
          customerMemberId: 41,
          noteId: 8,
          expectedVersion: 2,
          requestId: 'crm-note-hide-8',
        );

    expect(sent.path, '/api/merchant/crm/customers/41/notes/hide');
    expect(sent.data, <String, dynamic>{
      'noteId': 8,
      'expectedVersion': 2,
      'requestId': 'crm-note-hide-8',
    });
    expect(receipt.message, '备注已隐藏');
  });

  test('店内标签加删都使用独立幂等回执', () async {
    final List<RequestOptions> sent = <RequestOptions>[];
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
      sent.add(request);
      if (request.path.endsWith('/tags/remove')) {
        return <String, dynamic>{'code': 200, 'data': '标签已移除'};
      }
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 3,
          'tagName': '高频复购',
          'tagColor': '#2E6D5A',
        },
      };
    });
    final MerchantCustomerDetailApi api = MerchantCustomerDetailApi(client);

    await api.assignTag(
      customerMemberId: 41,
      tagName: '  高频复购  ',
      tagColor: '#2e6d5a',
      requestId: 'crm-tag-add-3',
    );
    final MerchantCustomerMutationReceipt removed = await api.removeTag(
      customerMemberId: 41,
      tagId: 3,
      requestId: 'crm-tag-remove-3',
    );

    expect(sent.first.path, '/api/merchant/crm/customers/41/tags');
    expect(sent.first.data, <String, dynamic>{
      'tagName': '高频复购',
      'tagColor': '#2E6D5A',
      'requestId': 'crm-tag-add-3',
    });
    expect(sent.last.path, '/api/merchant/crm/customers/41/tags/remove');
    expect(sent.last.data, <String, dynamic>{
      'tagId': 3,
      'requestId': 'crm-tag-remove-3',
    });
    expect(removed.message, '标签已移除');
  });
}

Map<String, dynamic> _detailJson({required int customerMemberId}) =>
    <String, dynamic>{
      'summary': <String, dynamic>{
        'customerMemberId': customerMemberId,
        'displayName': '林青',
        'arrivedCount': 2,
        'pendingCount': 1,
        'refundedCount': 0,
        'paidAmount': '38.00',
      },
      'systemTags': <dynamic>[],
      'merchantTags': <dynamic>[],
      'timeline': <dynamic>[],
    };

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> Function(RequestOptions request) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
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
