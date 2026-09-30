import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/request_session_scope.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/feature/account/pending_inviter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedReadStore extends TokenStore {
  _DelayedReadStore() : super(const FlutterSecureStorage());
  final started = Completer<void>();
  final result = Completer<String?>();
  @override
  Future<String?> read() {
    started.complete();
    return result.future;
  }
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('{"code":200}', 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('account switch during token read never sends referral under replacement token', () async {
    var userId = 1;
    var generation = 1;
    final storage = <String, String>{};
    final store = _DelayedReadStore();
    final client = DioClient(store);
    final adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    final api = RegistrationApi(client);
    final service = PendingInviter(
      read: (key) async => storage[key],
      write: (key, value) async { storage[key] = value; },
      remove: (key) async { storage.remove(key); },
      currentUserId: () => userId,
      bind: (_) async => fail('Production replay must use scoped binding'),
      bindForUser: (inviter, owner) {
        final captured = generation;
        return api.setInviterForSession(inviter, RequestSessionScope(
            () => generation == captured && userId == owner));
      },
    );
    final replay = service.capture('7');
    await store.started.future;
    userId = 2;
    generation++;
    store.result.complete('token-for-account-2');
    await replay;
    expect(adapter.requests, isEmpty);
    expect(storage['has_inviter_v1_1'], isNull);
    expect(storage['has_inviter_v1_2'], isNull);
    expect(jsonDecode(storage[PendingInviter.pendingKey]!),
        {'inviter': '7', 'owner': 1});
    await service.replay();
    expect(adapter.requests, isEmpty);
  });

  test('unchanged scope pins the dispatched token and preserves inviter protocol', () async {
    final store = _DelayedReadStore();
    final client = DioClient(store);
    final adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    final request = RegistrationApi(client).setInviterForSession(
        '7', RequestSessionScope(() => true));
    await store.started.future;
    store.result.complete('token-for-account-1');
    await request;
    final sent = adapter.requests.single;
    expect(sent.headers['Authorization'], 'token-for-account-1');
    expect(sent.path, '/api/user/setInviter');
    expect(Map<String, String>.fromEntries((sent.data as FormData).fields), {'inviter_id': '7'});
  });
}
