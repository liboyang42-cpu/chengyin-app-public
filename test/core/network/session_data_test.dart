import 'dart:async';

import 'package:chengyin_app/core/network/session_data.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/merchant/merchant_subscription_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => _state(1);
  static AuthState _state(int? id, {bool loading = false}) => AuthState(
    initialized: true, loading: loading,
    user: id == null ? null : User(id: id, nickname: 'user', avatar: '', role: 'merchant'),
  );
  void switchTo(int? id, {bool loading = false}) => state = _state(id, loading: loading);
}

class _Api implements MerchantApi {
  final reads = <Completer<List<Map<String, dynamic>>>>[];
  @override
  Future<List<Map<String, dynamic>>> mySubscriptions() {
    final result = Completer<List<Map<String, dynamic>>>();
    reads.add(result);
    return result.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('API data dependencies rekey while authentication transport remains stable', () {
    final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(_Auth.new)]);
    addTearDown(container.dispose);
    final oldApi = container.read(merchantApiProvider);
    final authApi = container.read(authApiProvider);
    final dio = container.read(dioClientProvider);
    final tokens = container.read(tokenStoreProvider);
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(2);
    expect(identical(container.read(merchantApiProvider), oldApi), isFalse);
    expect(identical(container.read(authApiProvider), authApi), isTrue);
    expect(identical(container.read(dioClientProvider), dio), isTrue);
    expect(identical(container.read(tokenStoreProvider), tokens), isTrue);
  });

  test('live subscription listener reloads for B and rejects delayed A', () async {
    final api = _Api();
    final container = ProviderContainer(retry: (_, _) => null, overrides: [
      authControllerProvider.overrideWith(_Auth.new), merchantApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final listener = container.listen(merchantSubscriptionsProvider, (_, _) {}, fireImmediately: true);
    addTearDown(listener.close);
    expect(api.reads, hasLength(1));
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(2);
    final current = container.read(merchantSubscriptionsProvider.future);
    expect(api.reads, hasLength(2));
    api.reads[1].complete([{'owner': 2}]);
    expect(await current, [{'owner': 2}]);
    api.reads[0].complete([{'owner': 1}]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(merchantSubscriptionsProvider).requireValue, [{'owner': 2}]);
  });

  test('previous A value is suppressed while a live listener waits for B', () async {
    final api = _Api();
    final container = ProviderContainer(retry: (_, _) => null, overrides: [
      authControllerProvider.overrideWith(_Auth.new), merchantApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final listener = container.listen(merchantSubscriptionsProvider, (_, _) {}, fireImmediately: true);
    addTearDown(listener.close);
    final first = container.read(merchantSubscriptionsProvider.future);
    api.reads.single.complete([{'owner': 1}]);
    await first;
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(2);
    final next = container.read(merchantSubscriptionsProvider.future);
    final rendered = container.read(merchantSubscriptionsProvider).when(
      skipLoadingOnReload: false, skipLoadingOnRefresh: false,
      data: (_) => 'private-data', error: (_, _) => 'error', loading: () => 'loading',
    );
    expect(rendered, 'loading');
    api.reads.last.complete([{'owner': 2}]);
    expect(await next, [{'owner': 2}]);
  });

  test('loading or signed-out account cannot fetch private subscription data', () async {
    final api = _Api();
    final container = ProviderContainer(retry: (_, _) => null, overrides: [
      authControllerProvider.overrideWith(_Auth.new), merchantApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier) as _Auth;
    auth.switchTo(1, loading: true);
    await expectLater(container.read(merchantSubscriptionsProvider.future), throwsA(isA<SessionDataUnavailable>()));
    auth.switchTo(null);
    await expectLater(container.read(merchantSubscriptionsProvider.future), throwsA(isA<SessionDataUnavailable>()));
    expect(api.reads, isEmpty);
  });
}
