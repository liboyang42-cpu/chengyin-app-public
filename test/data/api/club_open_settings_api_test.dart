// 俱乐部开放设置三个开关的**请求契约**门(真源 pages/club/detail/index.js
// togglePublicVisible / toggleMemberPost / toggleMerchantCoop @90e66d70):
//   - 三个开关各走各的可枚举路径字面量,body 是 {id, 字段: 0|1};
//   - 必须发 JSON(裸 FormData 会 415 且照样回 HTTP 200,后端 @RequestBody 的空转);
//   - 回执里没有这个开关的新值 = 「没保存成」,抛异常,不兜底。

import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
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

  test('三个开关各走各的路径字面量，body 是 {id, 字段: 0|1}', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{'publicVisible': 1}),
      _ok(<String, dynamic>{'memberPostAllowed': 1}),
      _ok(<String, dynamic>{'merchantUndertakeOpen': 1}),
    ]);

    final ClubOpenSettingValue pub = await harness.api.setPublicVisible(
      clubId: 7,
      enabled: true,
    );
    final ClubOpenSettingValue post = await harness.api.setMemberPost(
      clubId: 7,
      enabled: true,
    );
    final ClubOpenSettingValue coop = await harness.api.setMerchantCoop(
      clubId: 7,
      enabled: true,
    );

    expect(harness.sent.map((RequestOptions r) => r.path).toList(), <String>[
      '/api/club/open-settings/public-visible',
      '/api/club/open-settings/member-post',
      '/api/club/open-settings/merchant-coop',
    ]);
    for (final RequestOptions request in harness.sent) {
      expect(request.method, 'POST');
      expect(request.contentType, Headers.jsonContentType);
    }
    expect(harness.sent[0].data, <String, dynamic>{
      'id': 7,
      'publicVisible': 1,
    });
    expect(harness.sent[1].data, <String, dynamic>{
      'id': 7,
      'memberPostAllowed': 1,
    });
    expect(harness.sent[2].data, <String, dynamic>{
      'id': 7,
      'merchantUndertakeOpen': 1,
    });
    // 回读值原样交回,key 就是该开关自己的字段名。
    expect(pub.key, 'publicVisible');
    expect(pub.enabled, isTrue);
    expect(post.key, 'memberPostAllowed');
    expect(coop.key, 'merchantUndertakeOpen');
  });

  test('关开关发 0，按回读值渲染', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{'publicVisible': 0}),
    ]);

    final ClubOpenSettingValue saved = await harness.api.setPublicVisible(
      clubId: 7,
      enabled: false,
    );

    expect(harness.sent.single.data, <String, dynamic>{
      'id': 7,
      'publicVisible': 0,
    });
    expect(saved.enabled, isFalse);
  });

  test('回执没有这个开关的新值 = 没保存成，抛异常', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{'memberPostAllowed': 1}),
    ]);

    await expectLater(
      harness.api.setPublicVisible(clubId: 7, enabled: true),
      throwsA(
        isA<ClubApiException>().having(
          (ClubApiException error) => error.message,
          'message',
          '服务端没有回读到这个开关的新值',
        ),
      ),
    );
  });

  test('业务码非 200 按后端原文抛错，不吞', () async {
    final harness = _build(<Object>[
      <String, dynamic>{'code': 403, 'msg': '没有治理权限'},
    ]);

    await expectLater(
      harness.api.setMerchantCoop(clubId: 7, enabled: true),
      throwsA(
        isA<ClubApiException>().having(
          (ClubApiException error) => error.message,
          'message',
          '没有治理权限',
        ),
      ),
    );
  });
}

Map<String, dynamic> _ok(Object data) => <String, dynamic>{
  'code': 200,
  'data': data,
};

({ClubTopicOpsApi api, List<RequestOptions> sent}) _build(
  List<Object> replies,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  final List<RequestOptions> sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _QueueAdapter((RequestOptions request) {
    sent.add(request);
    return replies.removeAt(0) as Map<String, dynamic>;
  });
  return (api: ClubTopicOpsApi(client), sent: sent);
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
