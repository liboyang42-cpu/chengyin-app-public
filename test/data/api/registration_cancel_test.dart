// 取消报名走哪个接口。**走错的后果不对称:已支付却调 /cancel,票没了钱不退。**
//
// 后端是两个接口(ApiRegistrationController:256 / :288):
//   · /api/registration/cancel         未支付 —— 只释放库存与已抵扣积分
//   · /api/registration/cancel-refund  已支付 —— 成团前可退,原路退回 + 返积分
// 判据 `registrationStatus == 2`(已支付)取自小程序同一条,
// 那边用 `tests/unit/requestbody-dynamic-url.test.js` 锁着。
//
// ★ 顺带记一句这个功能的来历:**后端两个接口一直都在,App 侧从来没接过** ——
//   App 用户买了票之后没有任何取消/退款入口。这是端点对账扫出来的
//   (小程序在用、App 没接的接口有 120 条,这是其中最要害的一条)。

import 'dart:convert';
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

  /// 跑一次取消,把实际打到的 path 交出来。
  Future<String> pathFor({required bool paid}) async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    late String captured;
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      captured = options.path;
      return <String, dynamic>{'code': 200, 'msg': '后端说的话'};
    });
    await ActivityApi(client).cancelRegistration(registrationId: 7, paid: paid);
    return captured;
  }

  test('★ 未支付 → /api/registration/cancel', () async {
    expect(await pathFor(paid: false), '/api/registration/cancel');
  });

  test('★ 已支付 → /api/registration/cancel-refund,不是 /cancel', () async {
    expect(
      await pathFor(paid: true),
      '/api/registration/cancel-refund',
      reason: '已支付却调 /cancel:报名取消了、钱不退',
    );
  });

  test('两条路径必须不同 —— 防止以后被合并成一个', () async {
    expect(await pathFor(paid: false), isNot(await pathFor(paid: true)));
  });

  test('★ 提示原文用后端下发的 —— 到账时效不是前端能编的', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter(
      (RequestOptions options) => <String, dynamic>{
        'code': 200,
        'msg': '已取消并退款,预计1-3个工作日',
      },
    );
    final String msg = await ActivityApi(
      client,
    ).cancelRegistration(registrationId: 7, paid: true);
    expect(msg, '已取消并退款,预计1-3个工作日');
  });

  test('后端拒绝时把原因原样抛出(比如「成团后不可退」)', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter(
      (RequestOptions options) => <String, dynamic>{
        'code': 500,
        'msg': '已成团,不能取消',
      },
    );
    await expectLater(
      ActivityApi(client).cancelRegistration(registrationId: 7, paid: true),
      throwsA(predicate((Object e) => e.toString().contains('已成团,不能取消'))),
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
    final Map<String, dynamic> body = onRequest(options);
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
