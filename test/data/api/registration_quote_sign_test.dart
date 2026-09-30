import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/activity_api.dart';

/// 报名建单必须携带 `quoteSign`。
///
/// ★ 为什么要专门锁这条:后端 `RegistrationOrderCreateGateImpl:37` 对活动报名
///   (ownerType=2)空签名**直接 400**「缺少报价签名」。App 之前就是没传,
///   于是活动报名**一次都没建单成功过** —— 而 App 侧没有任何测试能发现,
///   因为它请求发出去了、异常也被 catch 成一句 toast,看着像「用户点了没成」。
///
/// 这个测试拦截真实请求体,断言 quoteSign 确实进了 payload —— 谁再把它删掉就红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // secure storage 在测试环境没有原生实现,喂一个空的读回值即可。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  /// 拦下请求、返回一个成功壳,并把请求体交出去。
  Future<Map<String, dynamic>> captureCreateBody({
    required String quoteSign,
  }) async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    late Map<String, dynamic> captured;
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      captured = (options.data as Map).cast<String, dynamic>();
      return <String, dynamic>{
        'code': 200,
        'msg': 'ok',
        'data': <String, dynamic>{
          'registrationId': 1,
          'registrationNo': 'R1',
          'payableAmount': 0,
        },
      };
    });
    await ActivityApi(client).createRegistration(
      ownerId: 9,
      realName: '张三',
      phone: '13800000000',
      quoteSign: quoteSign,
    );
    return captured;
  }

  test('建单请求体必须带上 quoteSign,且原样透传', () async {
    final body = await captureCreateBody(quoteSign: 'sign-abc');
    expect(
      body['quoteSign'],
      'sign-abc',
      reason: '后端 RegistrationOrderCreateGateImpl 空签名直接 400,漏传即报名全挂',
    );
  });

  test('积分开关决定 isUsePoint,不再恒为 0', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    late Map<String, dynamic> captured;
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      captured = (options.data as Map).cast<String, dynamic>();
      return <String, dynamic>{
        'code': 200,
        'msg': 'ok',
        'data': <String, dynamic>{
          'registrationId': 1,
          'registrationNo': 'R1',
          'payableAmount': 0,
        },
      };
    });
    await ActivityApi(client).createRegistration(
      ownerId: 9,
      realName: '张三',
      phone: '13800000000',
      quoteSign: 's',
      usePoints: true,
    );
    expect(captured['isUsePoint'], 1);
  });
}

/// 不发真请求的适配器:把 RequestOptions 交给回调,回调返回的 map 当响应体。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);
  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = onRequest(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
