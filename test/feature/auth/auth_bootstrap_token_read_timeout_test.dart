import 'dart:async';

import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 钥匙串读永不返回,模拟 securityd 卡死(冷启动报告 §5-A 的无超时死点)。
class _HangingTokenStore extends TokenStore {
  _HangingTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> read() => Completer<String?>().future;
}

void main() {
  test('token 读超时后落入既有降级:有界等待、按游客放行', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: <dynamic>[
          tokenStoreProvider.overrideWithValue(_HangingTokenStore()),
        ].cast(),
      );
      addTearDown(container.dispose);

      var bootstrapDone = false;
      unawaited(
        container
            .read(authControllerProvider.notifier)
            .bootstrap()
            .then((_) => bootstrapDone = true),
      );

      // 超时前:bootstrap 未完成,路由应仍停在 splash。
      async.elapse(const Duration(seconds: 4));
      expect(bootstrapDone, isFalse);
      expect(container.read(authControllerProvider).initialized, isFalse);

      // 越过 5s 有界超时:与「钥匙串不可读」同一路径按游客放行,不卡死。
      async.elapse(const Duration(seconds: 2));
      expect(bootstrapDone, isTrue);
      final state = container.read(authControllerProvider);
      expect(state.initialized, isTrue);
      expect(state.user, isNull);
      expect(state.loading, isFalse);
    });
  });
}
