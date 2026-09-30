// PublisherIdentityApi 的真实形状:两条端点的路径/方法/体、状态映射、失败原样冒泡。
//
// 用 HttpClientAdapter 桩顶住传输层(不发真假数据 —— 请求形状与后端
// ApiMemberIdentityController 逐键核对),业务码分支走真实代码路径。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/publisher_identity_api.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._handler);
  final Map<String, dynamic> Function(RequestOptions) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(_handler(options)),
      200,
      headers: {
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({DioClient client, List<RequestOptions> sent}) stub(
    Map<String, dynamic> Function(RequestOptions) handler,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return handler(o);
    });
    return (client: c, sent: sent);
  }

  Map<String, dynamic> bodyOf(RequestOptions o) {
    final data = o.data;
    // 自换 adapter 后 dio 还没做 JSON 编码,这里两态都要能吃。
    return data is String
        ? jsonDecode(data) as Map<String, dynamic>
        : Map<String, dynamic>.from(data as Map);
  }

  group('status:只回状态,查不到一律按未登记', () {
    test('registered=true 才真', () async {
      final s = stub(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'registered': true},
        },
      );
      expect(await PublisherIdentityApi(s.client).status(), isTrue);
      expect(s.sent.single.path, '/api/publisher/identity/status');
      expect(s.sent.single.method, 'POST');
      expect(bodyOf(s.sent.single), isEmpty, reason: '无入参:查的是当前登录人');
    });

    test('data 不下发任何字段值也不影响判定;registered 非真即假', () async {
      for (final data in <Object?>[
        <String, dynamic>{'registered': false},
        <String, dynamic>{'registered': 'true'},
        <String, dynamic>{},
        null,
      ]) {
        final s = stub(
          (_) => <String, dynamic>{'code': 200, 'data': ?data},
        );
        expect(
          await PublisherIdentityApi(s.client).status(),
          isFalse,
          reason: 'data=$data 不能被读成已登记',
        );
      }
    });

    test('业务码不是 200 → 未登记(不把"没拿到"说成"已登记")', () async {
      final s = stub(
        (_) => <String, dynamic>{'code': 500, 'msg': '服务异常'},
      );
      expect(await PublisherIdentityApi(s.client).status(), isFalse);
    });

    test('传输失败(连不上/超时) → 未登记,不冒泡', () async {
      final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
      c.dio.httpClientAdapter = _StubAdapter(
        (_) => throw DioException.connectionTimeout(
          requestOptions: RequestOptions(path: '/x'),
          timeout: const Duration(seconds: 1),
        ),
      );
      expect(await PublisherIdentityApi(c).status(), isFalse);
    });

    test('回包哪怕混进姓名字段也不回显 —— API 只吐 bool', () async {
      final s = stub(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'registered': true,
            'realName': '陈晨',
            'idCard': '99000019491231019X',
          },
        },
      );
      final result = await PublisherIdentityApi(s.client).status();
      expect(result, isA<bool>());
      expect('$result', isNot(contains('110105')));
    });
  });

  group('register:体恰好四个键,业务失败带原文', () {
    test('路径与方法对齐 ApiMemberIdentityController', () async {
      final s = stub((_) => <String, dynamic>{'code': 200});
      await PublisherIdentityApi(s.client).register(
        realName: '陈晨',
        idCard: '99000019491231019X',
        consent: true,
        source: 'topic_publish',
      );
      expect(s.sent.single.path, '/api/publisher/identity');
      expect(s.sent.single.method, 'POST');
      expect(bodyOf(s.sent.single), <String, Object?>{
        'realName': '陈晨',
        'idCard': '99000019491231019X',
        'consent': true,
        'source': 'topic_publish',
      });
    });

    test('code!=200 → 抛 PublisherIdentityException 带接口原文', () async {
      final s = stub(
        (_) => <String, dynamic>{'code': 500, 'msg': '实名信息已登记,如需变更请联系平台客服'},
      );
      await expectLater(
        PublisherIdentityApi(s.client).register(
          realName: '陈晨',
          idCard: '99000019491231019X',
          consent: true,
          source: 'club_apply',
        ),
        throwsA(
          isA<PublisherIdentityException>().having(
            (e) => e.message,
            'message',
            '实名信息已登记,如需变更请联系平台客服',
          ),
        ),
      );
    });

    test('msg 缺失 → 空文案(由共用件落兜底话,不在这里编)', () async {
      final s = stub((_) => <String, dynamic>{'code': 500});
      await expectLater(
        PublisherIdentityApi(s.client).register(
          realName: '陈晨',
          idCard: '99000019491231019X',
          consent: true,
          source: 'club_apply',
        ),
        throwsA(
          isA<PublisherIdentityException>().having(
            (e) => e.message,
            'message',
            isEmpty,
          ),
        ),
      );
    });

    test('传输失败冒泡 DioException(共用件归成网络文案)', () async {
      final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
      c.dio.httpClientAdapter = _StubAdapter(
        (_) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/x'),
          reason: 'boom',
        ),
      );
      await expectLater(
        PublisherIdentityApi(c).register(
          realName: '陈晨',
          idCard: '99000019491231019X',
          consent: true,
          source: 'merchant_apply',
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}
