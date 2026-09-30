// 三处 body key / 响应解析对不上后端的修复(2026-08-19)。
//
// 动手前核实字段名时在 ApiCoopController.java 里发现的,三条此前都是零调用方
// 的方法,没有任何界面因这处改动而变化:
//   ① confirmCandidate:发的是 'regId',后端读 'registrationId'(:766)——
//      调用恒得到「缺少报名」,与传的 id 无关。
//   ② inviteList(对接 /api/coop/list):读的是 data['rows'],但后端 list()
//      返回裸 Map { sent, received, slots }(:957-961),没有 rows 这层——
//      照原实现调用只会拿到恒空列表。
//   ③ saveReview:发的是 'content',后端 CoopReview 域对象的字段是
//      'comment'(CoopReview.java:19)——评语被静默丢弃,rating 照样保存成功。

import 'dart:convert';
import 'dart:typed_data';

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

  Map<String, dynamic> body(RequestOptions o) =>
      (o.data as Map).cast<String, dynamic>();

  group('★ 确认候选:body key 必须是 registrationId', () {
    test('发的键是 registrationId,不是 regId', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'msg': '已选定该候选',
        'data': <String, dynamic>{},
      });
      await r.api.confirmCandidate(88);
      final Map<String, dynamic> b = body(r.sent.single);
      expect(
        b['registrationId'],
        88,
        reason:
            '后端 ApiCoopController.confirmCandidate 读的是 body.get("registrationId")',
      );
      expect(b.containsKey('regId'), isFalse, reason: '发这个键后端读不到,恒得到「缺少报名」');
    });
  });

  group('★ 我的协作邀请列表:响应是裸 Map,不是分页 rows', () {
    test('sent/received/slots 原样透出,不会被错读成空列表', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'sent': <dynamic>[
            <String, dynamic>{
              'id': 1,
              'fromId': 10,
              'toType': 'merchant',
              'toId': 20,
            },
          ],
          'received': <dynamic>[
            <String, dynamic>{
              'id': 2,
              'fromId': 30,
              'toType': 'merchant',
              'toId': 40,
            },
          ],
          'slots': <String, dynamic>{},
        },
      });
      final Map<String, dynamic> data = await r.api.inviteList();
      expect(
        (data['sent'] as List).length,
        1,
        reason: '后端 list() 返回裸 Map{sent,received,slots},没有 rows 这层',
      );
      expect((data['received'] as List).length, 1);
    });
  });

  group('★ 提交互评:评语字段是 comment', () {
    test('填了评语要发 comment 键,而不是 content', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.saveReview(topicId: 1, toId: 2, rating: 5, content: '很靠谱');
      final Map<String, dynamic> b = body(r.sent.single);
      expect(
        b['comment'],
        '很靠谱',
        reason: '后端 CoopReview 域对象按 comment 属性反序列化(CoopReview.java:19)',
      );
      expect(
        b.containsKey('content'),
        isFalse,
        reason: '发这个键后端 Jackson 反序列化不到,评语会被静默丢弃',
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
