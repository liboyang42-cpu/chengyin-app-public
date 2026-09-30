// 商家 CRM 导出三条:`/api/merchant/crm/exports[/{taskId}/status|/download]`。
//
// ★★ 三个必须,错了全都**不报错**:
//   ① 创建走 **JSON**`{query, requestId}`(pages/merchant/customer/index.js:1084),
//      发成表单 → query 绑不上 → 导出一份**全量**名单,而调用方以为筛过了;
//   ② query 里要带**当前视图**(关键词),不然导出的是全量;
//   ③ 下载必须带 `X-CRM-Export-Token` 头(index.js:1164)—— 只凭登录态会被拒,
//      而拒绝发生在**文件流里**,外面看起来只是"下载失败"。

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
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

  PageParityApi apiWith(
    HttpClientAdapter adapter,
    List<RequestOptions> sent,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    c.dio.httpClientAdapter = adapter;
    return PageParityApi(c);
  }

  group('创建导出任务', () {
    test('★★ 走 JSON,body 是 {query, requestId}', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final PageParityApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{
              'id': 12,
              'status': 'PENDING',
              'downloadToken': 'tok-1',
            },
          },
          sent,
        ),
        sent,
      );
      final Map<String, dynamic> d = await api.createCrmExport(
        requestId: 'crm-export-abc-1',
        query: const CrmCustomerQuery(keyword: '张').toExportQuery(),
      );
      expect(sent.single.path, '/api/merchant/crm/exports');
      final Map<String, dynamic> body =
          (sent.single.data as Map).cast<String, dynamic>();
      expect(
        sent.single.data,
        isA<Map<String, dynamic>>(),
        reason: '后端 @RequestBody;发表单 query 整个绑不上,'
            '结果是一份全量名单,而调用方以为筛过了',
      );
      expect(body['requestId'], 'crm-export-abc-1');
      final Map<String, dynamic> query =
          (body['query'] as Map).cast<String, dynamic>();
      expect(query['pageNum'], 1);
      expect(query['pageSize'], 20);
      expect(
        query['keyword'],
        '张',
        reason: '导出的就是当前视图;漏了关键词 = 导全量',
      );
      expect(d['downloadToken'], 'tok-1');
    });

    test('★★ 导出 query 带上当前视图的全部筛选(只带关键词 = 导全量)', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final PageParityApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{'id': 12, 'status': 'PENDING'},
          },
          sent,
        ),
        sent,
      );
      await api.createCrmExport(
        requestId: 'r-2',
        query: const CrmCustomerQuery(
          keyword: '张',
          segment: 'repeat',
          tagId: 3,
          sourceType: 2,
          sourceStart: '2026-09-01',
          sourceEnd: '2026-09-30',
        ).toExportQuery(),
      );
      final Map<String, dynamic> q =
          ((sent.single.data as Map)['query'] as Map).cast<String, dynamic>();
      expect(q['segment'], 'repeat');
      expect(q['tagId'], 3);
      expect(q['sourceType'], 2);
      expect(q['sourceStart'], '2026-09-01');
      expect(q['sourceEnd'], '2026-09-30');
      expect(q['keyword'], '张');
    });

    test('★ 没有关键词时发 null(而不是省掉这个键)', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final PageParityApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{'id': 12, 'status': 'PENDING'},
          },
          sent,
        ),
        sent,
      );
      await api.createCrmExport(
        requestId: 'r-1',
        query: const CrmCustomerQuery().toExportQuery(),
      );
      final Map<String, dynamic> body =
          (sent.single.data as Map).cast<String, dynamic>();
      expect((body['query'] as Map)['keyword'], isNull);
    });
  });

  group('查询导出状态', () {
    test('★ 打到 /{taskId}/status,且不带 body 参数', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final PageParityApi api = apiWith(
        _JsonAdapter(
          (RequestOptions o) => <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{
              'id': 12,
              'status': 'SUCCESS',
              'rowCount': 37,
            },
          },
          sent,
        ),
        sent,
      );
      final Map<String, dynamic> d = await api.crmExportStatus(12);
      expect(sent.single.path, '/api/merchant/crm/exports/12/status');
      expect(d['rowCount'], 37);
    });
  });

  group('下载', () {
    test('★★ 必须带 X-CRM-Export-Token 头,且文件真的落到 savePath', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final Directory dir = Directory.systemTemp.createTempSync('crm-export-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String savePath = '${dir.path}/客户资料-12.xlsx';
      final PageParityApi api = apiWith(_BinaryAdapter(sent), sent);

      await api.downloadCrmExport(
        taskId: 12,
        downloadToken: 'tok-1',
        savePath: savePath,
      );

      expect(sent.single.path, '/api/merchant/crm/exports/12/download');
      expect(
        sent.single.headers['X-CRM-Export-Token'],
        'tok-1',
        reason: '小程序 wx.downloadFile 带的同一个头(index.js:1164);'
            '缺了会被拒,而拒绝发生在文件流里,外面只看到"下载失败"',
      );
      final File f = File(savePath);
      expect(f.existsSync(), isTrue);
      expect(f.readAsBytesSync(), <int>[0x50, 0x4B, 0x03, 0x04]);
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

/// 下载走的是**字节流**,不是 JSON —— 用 JSON 桩会掩盖"文件其实是空/坏"的错。
class _BinaryAdapter implements HttpClientAdapter {
  _BinaryAdapter(this.sent);
  final List<RequestOptions> sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromBytes(
      <int>[0x50, 0x4B, 0x03, 0x04],
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/octet-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
