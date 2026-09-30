// 支付前的就绪探测。
//
// ★ 后端查的是**服务端微信支付配置是否可用**
//   (RegistrationCheckoutServiceImpl:57 → wechatPayService.isReady())。
//   小程序在支付前会先问这条;App 此前**不问** —— 配置没就绪时用户点了
//   「继续支付」才撞失败,而失败信息通常很底层、看不出是配置问题。
//
// ⚠️ 这组测试盯的核心是:**它是软探测,不是硬闸**。
//   探测本身也可能失败(网络抖、接口 500)。把「探测失败」当成
//   「不能支付」去禁掉按钮,会把一条**本来能走通**的支付路径堵死 ——
//   那比让它去试一次更糟:用户明明能付,却被自己的 App 拦住。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/activity_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ActivityApi apiWith(Map<String, dynamic> reply) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    c.dio.httpClientAdapter = _StubAdapter((_) => reply);
    return ActivityApi(c);
  }

  test('ready=true → 可以支付', () async {
    final r = await apiWith(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'ready': true, 'message': '支付服务可用'},
    }).paymentReadiness();
    expect(r.ready, isTrue);
    expect(r.message, '支付服务可用');
  });

  test('★ ready=false → 提示用后端原话', () async {
    final r = await apiWith(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'ready': false, 'message': '支付服务暂不可用'},
    }).paymentReadiness();
    expect(r.ready, isFalse);
    expect(r.message, '支付服务暂不可用');
  });

  test('★ 调用方必须把探测包在 try 里 —— 探测失败不许堵死支付', () {
    // ⚠️ 第一版我在这儿写了 `expect(true, isTrue)` —— 一个永远绿的空壳断言,
    //    自己就在造假测试。改成真去读调用方的代码:
    //    orders_page 的 _pay 必须只在**明确 ready==false** 时停下,
    //    探测本身抛异常时 catch 住继续走真实支付。
    final String page = File(
      'lib/feature/orders/orders_page.dart',
    ).readAsStringSync();
    final int at = page.indexOf('paymentReadiness()');
    expect(at, greaterThan(0), reason: '支付前没有做就绪探测');

    // 探测调用必须落在一个 try 块里(向前找最近的 try)
    final String before = page.substring(0, at);
    final int tryAt = before.lastIndexOf('try {');
    final int payAt = before.lastIndexOf('Future<void> _pay');
    expect(
      tryAt,
      greaterThan(payAt),
      reason: '探测没有被 try 包住 —— 接口一抖就把用户的支付路径堵死了',
    );

    // 且 catch 之后不能 return(那等于阻断)
    final String after = page.substring(at, at + 600);
    expect(after.contains('} catch (_) {'), isTrue, reason: '探测失败要吞掉继续走,不是往上抛');
  });

  test('ready 缺席时保守判 false', () async {
    final r = await apiWith(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{},
    }).paymentReadiness();
    expect(r.ready, isFalse);
    expect(r.message, '');
  });

  test('★ 接口本身失败会抛 —— 调用方必须 catch 住并继续,不能堵死支付', () async {
    await expectLater(
      apiWith(<String, dynamic>{'code': 500, 'msg': '服务异常'}).paymentReadiness(),
      throwsA(anything),
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
