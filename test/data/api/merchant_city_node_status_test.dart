import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
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

  test('据点上架/下线都透传 status，并回读后端文案', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      final Map<String, String> fields = Map<String, String>.fromEntries(
        (options.data as FormData).fields,
      );
      return <String, dynamic>{
        'code': 200,
        'data': fields['status'] == '1' ? '已上架' : '已下线',
      };
    });
    final MerchantApi api = MerchantApi(client);

    expect(await api.setNodeStatus(7, online: true), '已上架');
    expect(await api.setNodeStatus(7, online: false), '已下线');

    final List<Map<String, String>> fields = sent
        .map(
          (RequestOptions options) => Map<String, String>.fromEntries(
            (options.data as FormData).fields,
          ),
        )
        .toList();
    expect(fields[0], <String, String>{'poiId': '7', 'status': '1'});
    expect(fields[1], <String, String>{'poiId': '7', 'status': '0'});
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> Function(RequestOptions options) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Uint8List bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(reply(options))),
    );
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
