import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions options) reply;
  final List<RequestOptions> sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('编辑与置顶携带乐观锁版本和独立幂等键', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{'code': 200, 'msg': 'ok'},
    );
    client.dio.httpClientAdapter = adapter;
    final ClubApi api = ClubApi(client);

    await api.updatePost(
      postId: 7,
      content: '新版正文',
      images: <String>['a.jpg', 'b.jpg'],
      version: 3,
      requestId: 'edit-ticket-7-v3',
    );
    await api.setPostPinned(
      postId: 7,
      pinned: true,
      version: 4,
      requestId: 'pin-ticket-7-v4',
    );

    expect(adapter.sent[0].path, '/api/club/post/update');
    final Map<String, dynamic> update =
        adapter.sent[0].data as Map<String, dynamic>;
    expect(update, containsPair('version', 3));
    expect(update, containsPair('images', 'a.jpg;b.jpg'));
    expect(update['requestId'], 'edit-ticket-7-v3');
    expect(adapter.sent[1].path, '/api/club/post/pin');
    final Map<String, dynamic> pin =
        adapter.sent[1].data as Map<String, dynamic>;
    expect(pin, containsPair('pinned', true));
    expect(pin, containsPair('version', 4));
    expect(pin['requestId'], 'pin-ticket-7-v4');
    expect(pin['requestId'], isNot(update['requestId']));
  });

  test('公开历史解析版本、正文和图片且不依赖 editorMemberId', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 11,
            'snapshotVersion': 2,
            'content': '旧正文',
            'images': 'a.jpg;b.jpg',
            'createTime': '2026-09-09 10:00:00',
            'editorMemberId': 999,
          },
        ],
      },
    );
    client.dio.httpClientAdapter = adapter;

    final List<ClubPostRevision> rows = await ClubApi(client).postHistory(7);

    expect(adapter.sent.single.path, '/api/club/post/history');
    expect(adapter.sent.single.data, <String, dynamic>{'id': 7});
    expect(rows.single.snapshotVersion, 2);
    expect(rows.single.images, <String>['a.jpg', 'b.jpg']);
  });
}
