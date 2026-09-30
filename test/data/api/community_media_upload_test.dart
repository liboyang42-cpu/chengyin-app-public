import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class UploadAdapter implements HttpClientAdapter {
  final bodies = <FormData>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    bodies.add(options.data as FormData);
    await stream?.drain<void>();
    return ResponseBody.fromString(
      jsonEncode({
        'code': '200',
        'url': 'https://media.test/image.jpg',
        'byteSize': 3,
        'mimeType': 'image/jpeg',
        'uploadReceipt': 'receipt',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'community upload accepts the shared numeric-string business code',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'community-upload-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/image.jpg',
      ).writeAsBytes([1, 2, 3]);
      final client = DioClient(TokenStore(const FlutterSecureStorage()));
      final adapter = UploadAdapter();
      client.dio.httpClientAdapter = adapter;
      final result = await PlayApi(client).uploadCommunityImage(file.path);
      expect(result.valid, isTrue);
      expect(
        Map.fromEntries(adapter.bodies.single.fields)['bizType'],
        'COMMUNITY_POST',
      );
    },
  );
}
