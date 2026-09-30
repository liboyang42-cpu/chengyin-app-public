// 开放设置三件套的**报文级**门:`/api/club/open-settings/{public-visible,member-post,merchant-coop}`。
//
// 为什么不能只测 UI:三条端点一度在客户端里被拼成 `'/api/club/open-settings/$pathTail'`,
// 于是全仓 `rg '/api/club/open-settings/member-post'` 一条都搜不到 ——
// 端点裁判(`tool/endpoint_parity.py`)据此判「App 没接」,而 UI 测试全绿。
// 判据只能是实际发出去的路径 + body + 回读。
//
// 口径对齐小程序 `pages/club/detail/index.js`(@90e66d70)的三个 toggle:
// POST + `application/json`,body `{id, 字段: 0|1}`,回读取 `data.<字段>`。

import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/club_api.dart' show ClubApiException;
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('三个开关各走各的端点:路径是字面量,body 是 {id, 字段: 0|1}', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{'publicVisible': 1}),
      _ok(<String, dynamic>{'memberPostAllowed': 0}),
      _ok(<String, dynamic>{'merchantUndertakeOpen': 1}),
    ]);

    final publicVisible = await harness.api.setPublicVisible(
      clubId: 7,
      enabled: true,
    );
    final memberPost = await harness.api.setMemberPost(
      clubId: 7,
      enabled: false,
    );
    final merchantCoop = await harness.api.setMerchantCoop(
      clubId: 7,
      enabled: true,
    );

    expect(harness.sent.map((RequestOptions r) => r.path).toList(), <String>[
      '/api/club/open-settings/public-visible',
      '/api/club/open-settings/member-post',
      '/api/club/open-settings/merchant-coop',
    ]);
    expect(harness.sent.first.data, <String, dynamic>{
      'id': 7,
      'publicVisible': 1,
    });
    expect(harness.sent[1].data, <String, dynamic>{
      'id': 7,
      'memberPostAllowed': 0,
    });
    expect(harness.sent.last.data, <String, dynamic>{
      'id': 7,
      'merchantUndertakeOpen': 1,
    });
    // 裸 FormData 会 415 且照回 HTTP 200 的空转 —— 必须是 JSON。
    for (final RequestOptions request in harness.sent) {
      expect(
        request.headers[Headers.contentTypeHeader],
        contains(Headers.jsonContentType),
      );
    }

    // 渲染用的值只能来自服务端回读,不能是本地取反。
    expect(publicVisible.enabled, isTrue);
    expect(memberPost.enabled, isFalse);
    expect(merchantCoop.enabled, isTrue);
  });

  test('回执里没有这个开关的新值 = 没保存成,不兜底成点成的那个值', () async {
    final harness = _build(<Object>[_ok(<String, dynamic>{})]);

    await expectLater(
      harness.api.setMerchantCoop(clubId: 7, enabled: true),
      throwsA(
        isA<ClubApiException>().having(
          (ClubApiException error) => error.message,
          'message',
          '服务端没有回读到这个开关的新值',
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
    final Object reply = replies.removeAt(0);
    if (reply is Exception) throw reply;
    return reply as Map<String, dynamic>;
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
