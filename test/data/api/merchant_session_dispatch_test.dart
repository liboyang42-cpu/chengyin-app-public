import 'dart:async';
import 'dart:typed_data';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/request_session_scope.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/points_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends TokenStore {
  _Store() : super(const FlutterSecureStorage());
  final started = Completer<void>();
  final value = Completer<String?>();
  @override
  Future<String?> read() { started.complete(); return value.future; }
}
class _Adapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody.fromString('{"code":200,"data":{}}', 200);
  }
  @override
  void close({bool force = false}) {}
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final domain in ['subscriptions', 'capabilities', 'points']) {
    test('$domain rejects switched token before dispatch', () async {
      final store = _Store();
      final client = DioClient(store);
      addTearDown(() => client.dio.close());
      final adapter = _Adapter();
      client.dio.httpClientAdapter = adapter;
      final api = MerchantApi(client);
      var current = true;
      final request = RequestSessionScope.run(RequestSessionScope(() => current), () async {
        if (domain == 'points') { await PointsApi(client).list(); }
        else if (domain == 'capabilities') { await api.commerceCapabilities(); }
        else { await api.mySubscriptions(); }
      });
      final assertion = expectLater(request, throwsA(isA<DioException>()
        .having((error) => error.type, 'type', DioExceptionType.cancel)));
      await store.started.future;
      current = false;
      store.value.complete('B-token');
      await assertion;
      expect(adapter.calls, 0);
    });
  }
}
