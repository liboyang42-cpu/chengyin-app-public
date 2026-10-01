import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({CouponApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: CouponApi(client), sent: sent);
  }

  Future<CouponPublishReceipt> publish(CouponApi api) => api.publishWithReceipt(
    name: '原始名称', startTime: DateTime(2026, 9, 1),
    endTime: DateTime(2026, 9, 30), publishCount: 10, couponType: 1,
  );

  test('missing success message is marked; explicit Chinese/English/empty stays server-owned', () async {
    for (final body in <Map<String, dynamic>>[{'code': 200}, {'code': 200, 'msg': null}]) {
      final missing = await publish(build(body).api);
      expect(missing.message, '已发布');
      expect(missing.hasLocalMessage, isTrue);
    }
    for (final message in ['已发布', 'Published', '', '  Server receipt  ']) {
      final receipt = await publish(build({'code': 200, 'msg': message}).api);
      expect(receipt.message, message);
      expect(receipt.hasLocalMessage, isFalse);
    }
  });

  test('missing merchant errors have typed provenance; exact server text is untouched', () async {
    for (final entry in <(CouponLocalFailureKind, Future<Object?> Function(CouponApi), String)>[
      (CouponLocalFailureKind.load, (api) => api.myPublishedList(), '加载失败'),
      (CouponLocalFailureKind.publish, publish, '发布失败'),
      (CouponLocalFailureKind.stop, (api) async { await api.stop(7); return null; }, '停发失败，请稍后重试'),
      (CouponLocalFailureKind.stop, (api) async { await api.stopIssuing(7); return null; }, '停发失败，请稍后重试'),
    ]) {
      await expectLater(entry.$2(build({'code': 500}).api), throwsA(
        isA<CouponLocalFailure>().having((e) => e.kind, 'kind', entry.$1)
            .having((e) => e.message, 'message', entry.$3),
      ));
      for (final message in [entry.$3, 'Server rejected request', '']) {
        await expectLater(entry.$2(build({'code': 500, 'msg': message}).api), throwsA(
          predicate<Object>((error) => error is! CouponLocalFailure && error.toString() == 'Exception: $message'),
        ));
      }
    }
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
