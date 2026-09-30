// 读回最新同意状态。
//
// ★ 又一处「只写不读」:App 能**提交**同意,但读不回**已经同意过什么** ——
//   于是每次进到需要同意的场景都只能重新弹一次,用户明明签过了还要再签。
//   而合规上真正要的恰恰是「这个人在**哪个版本**上同意过」。
//
// ★ 最容易接错的一条:**`success()` 不带 data 表示「没同意过」**,不是错误。
//   判据是 data 有没有,不是 code。当失败弹红字,用户会以为系统坏了。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/models/consent_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({AccountApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: AccountApi(c), sent: sent);
  }

  test('★ 没同意过 → 返回 null,不是抛异常', () async {
    // 后端此时回的是 `success()`,code 200 但没有 data。
    final r = build(<String, dynamic>{'code': 200});
    expect(
      await r.api.latestConsent(docType: 'privacy', scene: 'login'),
      isNull,
    );
  });

  test('★ data 是空对象也算没同意过', () async {
    final r = build(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{},
    });
    expect(
      await r.api.latestConsent(docType: 'privacy', scene: 'login'),
      isNull,
    );
  });

  test('同意过 → 带出版本与时间', () async {
    final r = build(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'docType': 'privacy',
        'docVersion': 'v2.1',
        'scene': 'login',
        'eventType': 'AGREE',
        'occurredAt': '2026-08-18 10:00:00',
      },
    });
    final ConsentRecord? c = await r.api.latestConsent(
      docType: 'privacy',
      scene: 'login',
    );
    expect(c, isNotNull);
    expect(c!.docVersion, 'v2.1');
    expect(c.occurredAt, '2026-08-18 10:00:00');
  });

  test('★ 不传 docVersion —— 客户端猜的版本会被判成「未同意」', () async {
    final r = build(<String, dynamic>{'code': 200});
    await r.api.latestConsent(docType: 'privacy', scene: 'login');
    final Map<String, dynamic> sent = (r.sent.single.data as Map)
        .cast<String, dynamic>();
    expect(
      sent.containsKey('docVersion'),
      isFalse,
      reason: '版本由服务端算 —— 客户端一旦猜错,后端会判定未同意',
    );
  });

  test('无范围的场景不下发 scopeType/scopeId', () async {
    final r = build(<String, dynamic>{'code': 200});
    await r.api.latestConsent(docType: 'privacy', scene: 'login');
    final Map<String, dynamic> sent = (r.sent.single.data as Map)
        .cast<String, dynamic>();
    expect(
      sent.containsKey('scopeType'),
      isFalse,
      reason: '后端对无范围场景校验「授权范围不合法」—— 塞空值会被拒',
    );
  });

  test('真错误仍然抛', () async {
    final r = build(<String, dynamic>{'code': 500, 'msg': '授权状态暂不可用'});
    await expectLater(
      r.api.latestConsent(docType: 'x', scene: 'y'),
      throwsA(predicate((Object e) => e.toString().contains('暂不可用'))),
    );
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
