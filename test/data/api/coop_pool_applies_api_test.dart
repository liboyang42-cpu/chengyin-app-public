// 合作池的两路收件箱 + 两个动作键(`/api/coop/pool/{received,mine,withdraw,decline}`)。
//
// ★★ 这里两个键都曾经是错的,而且错得**一声不响**:
//   · withdraw 原来发 `{id: applyId}`,真源发的是 **`{topicId}`**
//     (pages/coop/list/index.js:420-424,且 tests/unit/coop-list-inbox.test.js:71
//      把它钉死:`assert.deepEqual(JSON.parse(w.data), { topicId: 8 })`);
//   · decline 原来发 `{id: applyId}`,真源发的是 **`{applyId[, scope]}`**
//     (pages/coop/list/index.js:456 / pages/coop/candidates/index.js:402-406)。
//   后端绑不到参数时不报错,表现只是"操作没成",按钮看着一直在。
//
// ★ 另一条:发件箱(`/mine`)不能拿池子列表(`/list`)顶替 —— 池子只列**还开放**的
//   主题,已拒绝/已撤回的申请会从发件箱里凭空消失
//   (tests/unit/coop-list-inbox.test.js 专门钉了这一点)。

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

  ({CoopApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
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

  group('撤回申请', () {
    test('★★ 键是 topicId,不是申请 id —— 发错键不报错,只是永远撤不掉', () async {
      // 真源自带的测试里 withdraw/decline 的成功响应就是 `{code: 200}`(不带 data)——
      // tests/unit/coop-list-inbox.test.js:73 `w.success({ code: 200 })`。
      final r = build(<String, dynamic>{'code': 200});
      await r.api.withdraw(8);
      expect(r.sent.single.path, '/api/coop/pool/withdraw');
      expect(
        jsonBody(r.sent.single),
        <String, dynamic>{'topicId': 8},
        reason: '真源钉死的就是这一个键(tests/unit/coop-list-inbox.test.js:71)',
      );
      expect(jsonBody(r.sent.single).containsKey('id'), isFalse);
    });
  });

  group('婉拒申请', () {
    test('★★ 键是 applyId', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.declineApply(31);
      expect(r.sent.single.path, '/api/coop/pool/decline');
      expect(jsonBody(r.sent.single), <String, dynamic>{'applyId': 31});
    });

    test('★★ 商家员工处理 owner 主题时要带上行上的 scope', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.declineApply(31, scope: 'MERCHANT');
      expect(jsonBody(r.sent.single), <String, dynamic>{
        'applyId': 31,
        'scope': 'MERCHANT',
      });
    });

    test('★ scope 是空串时不出现在 body 里(别发一个空标记)', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.declineApply(31, scope: '');
      expect(jsonBody(r.sent.single), <String, dynamic>{'applyId': 31});
    });
  });

  group('两路收件箱', () {
    test('★ mine / received 是两条不同的端点', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.poolMine();
      await r.api.poolReceived();
      expect(
        r.sent.map((RequestOptions o) => o.path).toList(),
        <String>['/api/coop/pool/mine', '/api/coop/pool/received'],
      );
    });

    test('★ data 是裸 List,不是 {rows: [...]}', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[
          <String, dynamic>{
            'applyId': 31,
            'topicId': 8,
            'status': 0,
            'clubId': 7,
            'clubName': '夜跑团',
            'topicName': '周末路线',
          },
        ],
      });
      final List<Map<String, dynamic>> rows = await r.api.poolMine();
      expect(rows.single['applyId'], 31);
      expect(rows.single['clubName'], '夜跑团');
    });

    test('★ 空的 data 不抛 —— 没有申请是正常态', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      expect(await r.api.poolReceived(), isEmpty);
    });

    test('★ 非 200 抛出去,别把失败当空列表', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '没有权限'});
      await expectLater(
        r.api.poolReceived(),
        throwsA(predicate((Object e) => e.toString().contains('没有权限'))),
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
