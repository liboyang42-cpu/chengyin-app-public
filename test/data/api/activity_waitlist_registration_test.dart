import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
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

  test('公开票种保留 remainingInventory，0 才是明确售罄', () {
    final ActivityTicket soldOut = ActivityTicket.fromJson(<String, dynamic>{
      'id': 11,
      'name': '早鸟票',
      'price': 49,
      'remainingInventory': 0,
    });
    final ActivityTicket unknown = ActivityTicket.fromJson(<String, dynamic>{
      'id': 12,
      'name': '待确认票',
      'price': 49,
    });

    expect(soldOut.remainingInventory, 0);
    expect(soldOut.isSoldOut, isTrue);
    expect(unknown.remainingInventory, isNull);
    expect(unknown.isSoldOut, isFalse);
  });

  test('OFFERED 建单原样携带 offer id/token，普通建单不写空键', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(Map<String, dynamic>.from(options.data as Map));
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'registrationId': sent.length,
          'registrationNo': 'R${sent.length}',
          'payableAmount': 0,
        },
      };
    });
    final ActivityApi api = ActivityApi(client);

    await api.createRegistration(
      ownerId: 7,
      realName: '张三',
      phone: '13800000000',
      ticketId: 11,
      quoteSign: 'signed',
      waitlistOfferId: 19,
      waitlistOfferToken: 'secret-token',
    );
    await api.createRegistration(
      ownerId: 7,
      realName: '张三',
      phone: '13800000000',
      ticketId: 12,
      quoteSign: 'signed-2',
    );

    expect(sent.first['waitlistOfferId'], 19);
    expect(sent.first['waitlistOfferToken'], 'secret-token');
    expect(sent.last.containsKey('waitlistOfferId'), isFalse);
    expect(sent.last.containsKey('waitlistOfferToken'), isFalse);
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);

  final Map<String, dynamic> Function(RequestOptions options) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(onRequest(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
