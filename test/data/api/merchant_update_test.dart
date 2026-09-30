// 商家资料读写。
//
// ★ `/api/merchant/info` 与 `/update` **两条都没接** ——
//   商家在 App 里既看不到自己的资料,也改不了。
//
// 两条容易写错的语义:
//   ① 后端**只认六个白名单字段**,传别的会被忽略 ——
//      界面把不可改的字段做成可编辑,是在骗用户;
//   ② logo 走**异步**内容安全送检 —— **返回成功不等于已过审**,
//      提示只能说「已提交」,不能说「已生效」。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({MerchantApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: MerchantApi(c), sent: sent);
  }

  test('★ 客户端的可改字段不许超出后端白名单', () {
    // ⚠️ 第一版我在这儿写了 `expect(allowed.length, 6)` —— **又一个空壳断言**
    //    (本轮第二次)。它只证明我数了六个,不证明代码里就是这六个。
    //    改成真去读 updateMerchant 的参数表,和后端白名单逐一比对。
    //
    // 后端 ApiMerchantController:536-541 只 set 这六个,传别的**静默忽略**。
    // 客户端多给一个参数 = 界面上多一个"改了也不生效"的输入框。
    const Set<String> backendWhitelist = <String>{
      'logo',
      'name',
      'description',
      'derivatives',
      'website',
      'preference',
    };

    final String api = File(
      'lib/data/api/merchant_api.dart',
    ).readAsStringSync();
    final int at = api.indexOf('Future<String> updateMerchant(');
    expect(at, greaterThan(0));
    final int close = api.indexOf('}) async {', at);
    final String params = api.substring(at, close);

    final Set<String> declared = RegExp(
      r'String\?\s+(\w+),',
    ).allMatches(params).map((RegExpMatch m) => m.group(1)!).toSet();

    expect(declared, isNotEmpty, reason: '没解析到参数 —— 断言写法失效了');
    expect(
      declared.difference(backendWhitelist),
      isEmpty,
      reason:
          '这些字段后端不认,传了会被静默忽略:'
          '${declared.difference(backendWhitelist)}',
    );
  });

  test('传了哪几个就只发哪几个 —— 不给后端塞 null', () async {
    final r = build(<String, dynamic>{'code': 200, 'msg': '已提交'});
    await r.api.updateMerchant(name: '静安咖啡', website: 'https://x.cn');
    final Map<String, dynamic> sent = (r.sent.single.data as Map)
        .cast<String, dynamic>();
    expect(
      sent.keys.toSet(),
      <String>{'name', 'website'},
      reason:
          '没改的字段不该出现在请求体里 —— '
          '塞 null 可能把后端已有的值覆盖成空',
    );
  });

  test('★ 内容安全拒绝时原样透传 —— 那句话会说清哪段文字有问题', () async {
    final r = build(<String, dynamic>{'code': 500, 'msg': '简介包含违规内容,请修改后重新提交'});
    await expectLater(
      r.api.updateMerchant(description: 'x'),
      throwsA(predicate((Object e) => e.toString().contains('简介包含违规内容'))),
    );
  });

  test('★ 成功文案用后端原话 —— logo 是异步送检,不能自己说「已生效」', () async {
    final r = build(<String, dynamic>{'code': 200, 'msg': '已提交,审核通过后生效'});
    expect(await r.api.updateMerchant(logo: 'https://x/y.png'), '已提交,审核通过后生效');
  });

  test('info 与 update 是两条不同的路径', () async {
    final r1 = build(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{},
    });
    await r1.api.merchantInfo();
    final r2 = build(<String, dynamic>{'code': 200, 'msg': 'ok'});
    await r2.api.updateMerchant(name: 'x');
    expect(r1.sent.single.path, '/api/merchant/info');
    expect(r2.sent.single.path, '/api/merchant/update');
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
