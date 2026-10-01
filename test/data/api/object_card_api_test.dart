import 'dart:async';
import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/network/request_session_scope.dart';
import 'package:chengyin_app/data/api/object_card_api.dart';
import 'package:chengyin_app/data/models/object_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedTokens extends TokenStore {
  _DelayedTokens() : super(const FlutterSecureStorage());
  final started = Completer<void>();
  final result = Completer<String?>();
  @override
  Future<String?> read() {
    started.complete();
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
  });

  test('account switch during token read cancels object-card dispatch', () async {
    final tokens = _DelayedTokens();
    final client = DioClient(tokens);
    var sent = 0;
    client.dio.httpClientAdapter = _Adapter((_) {
      sent++;
      return {'code': 200, 'data': {'list': [], 'total': 0}};
    });
    var current = true;
    final request = RequestSessionScope.run(RequestSessionScope(() => current),
      () => ObjectCardApi(client).list());
    final result = expectLater(request, throwsA(isA<DioException>()
      .having((e) => e.type, 'stale dispatch', DioExceptionType.cancel)));
    await tokens.started.future;
    current = false;
    tokens.result.complete('synthetic-token-for-next-account');
    await result;
    expect(sent, 0);
  });

  test('list sends scalar form parameters, no client ownership, latest 40', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    late RequestOptions sent;
    client.dio.httpClientAdapter = _Adapter((request) {
      sent = request;
      return {'code': '200', 'data': {'list': [], 'total': 0}};
    });
    final result = await ObjectCardApi(client).list(category: '电子产品');
    expect(result.total, 0);
    expect(sent.path, '/api/object-card/list');
    expect(sent.method, 'POST');
    expect(sent.contentType, Headers.formUrlEncodedContentType);
    expect(Uri.splitQueryString(sent.data as String), {
      'pageNum': '1', 'pageSize': '40', 'category': '电子产品',
    });
  });

  test('malformed/non-success envelopes never become a genuine empty collection', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    for (final body in <Map<String, dynamic>>[
      {'code': 500, 'data': {'list': [], 'total': 0}},
      {'code': 200},
      {'code': 200, 'data': {'list': [], 'total': '0'}},
      {'code': 200, 'data': {'list': [], 'total': -1}},
      {'code': 200, 'data': {'list': [{'id': 1}], 'total': 1}},
    ]) {
      client.dio.httpClientAdapter = _Adapter((_) => body);
      await expectLater(ObjectCardApi(client).list(), throwsFormatException);
    }
  });

  test('server frames and UGC are preserved, absent frames fall back to photo', () {
    final card = ObjectCard.fromJson({
      'id': 7, 'title': 'My 中文 card', 'caption': '原文',
      'frames': ['server-b.webp', 'server-a.webp'],
      'sourceUrl': 'photo', 'cutoutUrl': 'sticker',
      'cutoutBox': [0.1, 0.2, 0.3, 0.4],
      'category': '电子产品', 'place': '主题 · 节点', 'genStatus': 'READY',
    });
    expect(card.frames, ['server-b.webp', 'server-a.webp']);
    expect(card.thumbnail, 'sticker');
    expect(card.cutoutBox, [0.1, 0.2, 0.3, 0.4]);
    expect(ObjectCard.fromJson({
      'id': 2, 'title': 'Invalid crop', 'cutoutBox': [0.9, 0, 0.5, 1],
    }).cutoutBox, isNull);
    expect(card.title, 'My 中文 card');
    expect(card.caption, '原文');
    expect(card.place, '主题 · 节点');
    expect(card.generating, isFalse);
    for (final status in ['QUEUED', 'GENERATING', 'FAILED', 'NONE']) {
      final fallback = ObjectCard.fromJson({
        'id': 1, 'title': '', 'sourceUrl': 'photo', 'frames': [], 'genStatus': status,
      });
      expect(fallback.frames, ['photo']);
      expect(fallback.generating, ['QUEUED', 'GENERATING'].contains(status));
    }
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(reply(options)), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  void close({bool force = false}) {}
}
