import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/network/session_data.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/profile/profile_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => _state(1);
  static AuthState _state(int? id) => AuthState(
    initialized: true,
    user: id == null ? null : User(id: id, nickname: 'Owner $id', avatar: '', role: 'player'),
  );
  void switchTo(int? id) => state = _state(id);
}

class _Api extends Fake implements AuthApi {
  final reads = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> userInfo() {
    final result = Completer<Map<String, dynamic>>();
    reads.add(result);
    return result.future;
  }
}

Map<String, dynamic> _response(int id) => {
  'code': 200,
  'appUser': {'id': id, 'nickname': 'Owner $id', 'avatar': '', 'role': 'player'},
};

void main() {
  test('private user profile reloads for B and rejects delayed A', () async {
    final api = _Api();
    final container = ProviderContainer(retry: (_, _) => null, overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      authApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final listener = container.listen(userInfoProvider, (_, _) {}, fireImmediately: true);
    addTearDown(listener.close);
    expect(api.reads, hasLength(1));
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(2);
    final current = container.read(userInfoProvider.future);
    expect(api.reads, hasLength(2));
    api.reads[1].complete(_response(2));
    expect((await current).id, 2);
    api.reads[0].complete(_response(1));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(userInfoProvider).requireValue.id, 2);
    expect(identical(container.read(authApiProvider), api), isTrue,
      reason: 'Authentication transport remains stable; only data is scoped');
  });

  test('signed-out user profile never calls the private API', () async {
    final api = _Api();
    final container = ProviderContainer(retry: (_, _) => null, overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      authApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(null);
    await expectLater(container.read(userInfoProvider.future),
      throwsA(isA<SessionDataUnavailable>()));
    expect(api.reads, isEmpty);
  });
}
