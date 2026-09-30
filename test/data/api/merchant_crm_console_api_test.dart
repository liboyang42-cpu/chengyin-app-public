// CRM 运营台接口层的**形状判据**:请求体逐键、畸形回包的处理方式。
//
// 为什么单独钉:页面侧全用 Fake 注入,回包形状写错**不会红任何一条用例** ——
// 「data 不是数组就当成空历史」这种写法会在真实刷新失败时把屏上已加载的
// 触达历史**悄悄清掉**,而所有测试照绿。快照的口径是保留旧数据
// (`pages/merchant/customer/index.js:1020`)。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_crm_console_api.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  MerchantCrmConsoleApi apiWith(
    HttpClientAdapter adapter,
    List<RequestOptions> sent,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    c.dio.httpClientAdapter = adapter;
    return MerchantCrmConsoleApi(c);
  }

  group('触达历史 GET /crm/campaigns', () {
    test('★★ data 不是数组:抛出去(保留屏上历史),不是返空列表', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final MerchantCrmConsoleApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{'rows': <dynamic>[]},
          },
          sent,
        ),
        sent,
      );
      await expectLater(
        api.campaigns(),
        throwsA(isA<MerchantCrmApiException>()),
        reason: '返空列表 = 调用方把屏上历史当成"没有历史"清掉;'
            '快照 index.js:1020 是 return(保留旧数据)',
      );
      expect(sent.single.path, '/api/merchant/crm/campaigns');
    });

    test('★ 正常数组:逐条解析,畸形行丢弃', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final MerchantCrmConsoleApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <dynamic>[
              <String, dynamic>{'id': 7, 'status': 'SUCCESS', 'title': '周末提醒'},
              'not-a-map',
            ],
          },
          sent,
        ),
        sent,
      );
      final List<CrmCampaignTask> rows = await api.campaigns();
      expect(rows.length, 1);
      expect(rows.single.id, 7);
    });
  });

  group('名册 POST /crm/customers/list', () {
    test('★★ 请求体六键与快照一致(空值也发键,不是省键)', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final MerchantCrmConsoleApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{
              'total': 0,
              'rows': <dynamic>[],
              'segmentCounts': <String, dynamic>{'all': 0},
            },
          },
          sent,
        ),
        sent,
      );
      await api.customers(const CrmCustomerQuery());
      final Map<String, dynamic> body =
          (sent.single.data as Map).cast<String, dynamic>();
      expect(sent.single.path, '/api/merchant/crm/customers/list');
      expect(
        body.keys.toSet(),
        <String>{
          'pageNum',
          'pageSize',
          'keyword',
          'segment',
          'tagId',
          'sourceType',
          'sourceStart',
          'sourceEnd',
        },
        reason: '快照 _customerQuery():pageNum/pageSize 加六个筛选键,'
            '每一个都发(值可以是 null)',
      );
    });

    test('★ 回包形状不对(rows 不是数组):抛可展示的异常', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final MerchantCrmConsoleApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{'total': 3, 'rows': 'nope'},
          },
          sent,
        ),
        sent,
      );
      await expectLater(
        api.customers(const CrmCustomerQuery()),
        throwsA(isA<MerchantCrmApiException>()),
      );
    });
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.onRequest, this.sent);
  final Map<String, dynamic> Function(RequestOptions) onRequest;
  final List<RequestOptions> sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode(onRequest(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
