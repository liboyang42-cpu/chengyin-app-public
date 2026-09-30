import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/main.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(
      id: 7,
      nickname: '深链验收',
      avatar: '',
      role: 'player',
      userType: 1,
    ),
  );
}

String _concretePath(String route) {
  return route.replaceAllMapped(RegExp(r':[^/]+'), (Match match) {
    return match.group(0) == ':type' ? 'ticket' : '1';
  });
}

DioClient _stubClient() {
  const storage = FlutterSecureStorage();
  final client = DioClient(TokenStore(storage));
  client.dio.httpClientAdapter = _StubAdapter();
  return client;
}

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'code': 200,
        'data': null,
        'rows': <dynamic>[],
        'total': 0,
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final entries =
      (jsonDecode(File('tool/page_parity_manifest.json').readAsStringSync())
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
  final routes = <String>{
    ...entries
        .map((Map<String, dynamic> entry) => entry['route'] as String?)
        .whereType<String>()
        .where((String route) => route.isNotEmpty),
    // 小程序当前隐藏了未接通的商城入口；App 已接通真实积分商城，
    // 因此三个额外深链也纳入运行时构造门禁。
    '/mall',
    '/cart',
    '/product/:id',
    // 小程序把「附近的队伍」做在 subpackageRoam/nearby 上(那条已由 /roam/nearby
    // 占用),App 侧是独立路由 —— 入口卡指到它,所以单独纳入运行时构造门禁。
    '/team/nearby',
  }.toList(growable: false);

  for (final route in routes) {
    testWidgets('$route 可在运行时构造', (WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final container = ProviderContainer(
        retry: (int _, Object _) => null,
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_FixedAuth.new),
          dioClientProvider.overrideWithValue(_stubClient()),
        ].cast(),
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      final path = _concretePath(route);
      router.go(path);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ChengyinApp(),
        ),
      );
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        path,
        reason: '$route 未停在对应一级至四级页面',
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '$route 的页面构造发生异常');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });
  }
}
