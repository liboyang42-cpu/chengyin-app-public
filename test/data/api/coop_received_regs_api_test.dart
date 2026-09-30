// 「收到的承接报名」两条端点的形状(`/api/coop/candidates/{received,reject}`)。
//
// ★★ 两条都容易错得一声不响:
//   · received 的响应外层是 `{rows, hasMore}`(不是裸 List)——
//     按裸 List 解析会**恒空**,而空列表看起来就像"没人报名";
//   · reject 的键是 **registrationId**(后端 ApiCoopController:1194
//     `body.get("registrationId")`),不是 applyId(那是婉拒**带队申请**的键,
//     走的是另一条路 /api/coop/pool/decline)。发错键不报错,只是永远婉拒不掉。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coop_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({CoopApi api, List<RequestOptions> sent}) build(Map<String, dynamic> reply) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: CoopApi(c), sent: sent);
  }

  Map<String, dynamic> jsonBody(RequestOptions o) =>
      (o.data as Map).cast<String, dynamic>();

  group('收到的承接报名', () {
    test('★★ 取 data.rows —— 裸 List 那套解析拿到的是恒空', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{
              'id': 42,
              'memberId': 9,
              'auditStatus': 0,
              'addressName': '老街咖啡门口',
              'merchantName': '老王菜馆',
              'topicId': 8,
              'topicName': '周末路线',
            },
          ],
          'hasMore': false,
        },
      });
      final List<Map<String, dynamic>> rows = await r.api
          .receivedRegistrations();
      expect(r.sent.single.path, '/api/coop/candidates/received');
      expect(rows.single['id'], 42);
      expect(rows.single['auditStatus'], 0);
      expect(rows.single['topicName'], '周末路线');
    });

    test('★ 没人报名是正常态:空 rows 不抛', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'rows': <dynamic>[], 'hasMore': false},
      });
      expect(await r.api.receivedRegistrations(), isEmpty);
    });

    test('★ 非 200 抛出去(带后端原话),别把失败当空列表', () async {
      final r = build(<String, dynamic>{'code': 403, 'msg': '请先登录'});
      await expectLater(
        r.api.receivedRegistrations(),
        throwsA(predicate((Object e) => e.toString().contains('请先登录'))),
      );
    });
  });

  group('婉拒承接报名', () {
    test('★★ 键是 registrationId —— 不是 applyId(那是婉拒带队申请的键)', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.rejectCandidate(42);
      expect(r.sent.single.path, '/api/coop/candidates/reject');
      expect(
        jsonBody(r.sent.single),
        <String, dynamic>{'registrationId': 42},
        reason: '后端 ApiCoopController:1194 读的就是 registrationId',
      );
      expect(jsonBody(r.sent.single).containsKey('applyId'), isFalse);
      expect(jsonBody(r.sent.single).containsKey('id'), isFalse);
    });

    test('★ 后端拒绝时原话透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '仅主题发布者可婉拒候选'});
      await expectLater(
        r.api.rejectCandidate(42),
        throwsA(predicate((Object e) => e.toString().contains('仅主题发布者可婉拒候选'))),
      );
    });
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);
  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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
