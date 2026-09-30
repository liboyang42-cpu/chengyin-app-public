// 圈层供给复核的请求契约(真源 github/master):
//   `pages/topic/merchantinfo/merchantinfo.js:457-505` 两条都发 `{ offerId }` ——
//   后端读的也是 `body.getOfferId()`(ApiCoopController.reconfirmCurrentCircleSupply
//   / pauseOwnCircleSupply)。
//   ⚠️ 发错键(比如拿申请 id 当 id 发)后端绑不到参数,只回「缺少供给记录」——
//   界面看着毫无差别,这类错只能靠契约门守。

import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('无变化重新确认走 reconfirm-current,键是 offerId', () async {
    final ({CoopApi coop, List<RequestOptions> sent}) harness = _build(<Object>[
      _ok(null),
    ]);

    await harness.coop.reconfirmCircleSupply(55);

    final RequestOptions request = harness.sent.single;
    expect(request.path, '/api/coop/offer/circle-supply/reconfirm-current');
    expect(request.method, 'POST');
    expect(request.data, <String, dynamic>{'offerId': 55});
  });

  test('暂停供给走 pause,键是 offerId;后端原话照原文抛出', () async {
    final ({CoopApi coop, List<RequestOptions> sent}) harness = _build(<Object>[
      _ok(null),
      <String, dynamic>{'code': 500, 'msg': '这份供给已暂停,不能重复操作'},
    ]);

    await harness.coop.pauseCircleSupply(55);
    expect(harness.sent.single.path, '/api/coop/offer/circle-supply/pause');
    expect(harness.sent.single.data, <String, dynamic>{'offerId': 55});

    // 失败话术必须原样透传 —— 换成「操作失败」用户不知道发生了什么。
    await expectLater(
      harness.coop.pauseCircleSupply(55),
      throwsA(
        predicate(
          (Object e) => e.toString().contains('这份供给已暂停,不能重复操作'),
        ),
      ),
    );
  });
}

Map<String, dynamic> _ok(Object? data) => <String, dynamic>{
  'code': 200,
  'data': data,
};

({CoopApi coop, List<RequestOptions> sent}) _build(List<Object> replies) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  final List<RequestOptions> sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _QueueAdapter((RequestOptions request) {
    sent.add(request);
    return replies.removeAt(0) as Map<String, dynamic>;
  });
  return (coop: CoopApi(client), sent: sent);
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.handler);

  final Map<String, dynamic> Function(RequestOptions request) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(handler(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
