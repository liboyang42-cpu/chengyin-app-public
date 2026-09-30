import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/topic_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('收藏列表沿用小程序 pageNum/pageSize 并读取 data.rows', () async {
    final _StubAdapter adapter = _StubAdapter(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{'id': 91, 'name': '第二页的路线'},
        ],
      },
    });
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = adapter;

    final rows = await TopicApi(client).likeList(pageNum: 2, pageSize: 10);

    expect(rows.single.id, 91);
    expect(adapter.request.path, '/api/topic/like_list');
    final FormData form = adapter.request.data! as FormData;
    expect(Map<String, String>.fromEntries(form.fields), <String, String>{
      'pageNum': '2',
      'pageSize': '10',
    });
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> reply;
  late RequestOptions request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(reply),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
