// 协作域页内守卫的两条底线(b1 模拟器真跑报告 P1-2 / P1-3):
//   ① 未登录 → 整页「登录后查看」引导,**一个请求都不发**(不是填完表单才 401);
//   ② 401 → 认成登录失效给「去登录」,不把 dio 的英文栈(带 MDN 链接)画上屏。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coop/coop_pool_page.dart';

class _Auth extends AuthController {
  _Auth(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

/// 游客:**恢复已完成**(真机上路由层在 initialized 之前只渲染 /splash)。
final AuthState _guest = const AuthState(initialized: true);
final AuthState _loggedIn = AuthState(
  user: User(id: 7, nickname: '我', avatar: '', role: 'merchant'),
  initialized: true,
);

/// 后端 401 的真实长相:HTTP 401 + 中文 msg(报告里的 curl 实测)。
DioException _unauthorized() {
  final RequestOptions options = RequestOptions(path: '/api/coop/pool/list');
  return DioException(
    requestOptions: options,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: 401,
      data: <String, dynamic>{'code': 401, 'msg': '登录状态已失效,请重新登录'},
    ),
  );
}

Future<void> _pump(WidgetTester tester, AuthState auth, Object? error) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _Auth(auth)),
        coopPoolProvider.overrideWith((Ref ref) async {
          if (error != null) throw error;
          throw StateError('未登录不该取数');
        }),
      ].cast(),
      child: const MaterialApp(home: CoopPoolPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未登录:给「登录后查看」,且不发请求', (WidgetTester tester) async {
    bool requested = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(() => _Auth(_guest)),
          coopPoolProvider.overrideWith((Ref ref) async {
            requested = true;
            throw StateError('未登录不该取数');
          }),
        ].cast(),
        child: const MaterialApp(home: CoopPoolPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看合作池'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(requested, isFalse, reason: '游客进商家协作页,连读请求都不该发');
  });

  testWidgets('401:说登录失效给「去登录」,不画 dio 英文栈', (WidgetTester tester) async {
    await _pump(tester, _loggedIn, _unauthorized());

    expect(find.text('登录后查看合作池'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(
      find.textContaining('DioException'),
      findsNothing,
      reason: '后端回了中文「登录状态已失效」,英文栈 + MDN 链接不该给用户看',
    );
  });

  testWidgets('断网:仍走通用错误态,不当成要登录', (WidgetTester tester) async {
    await _pump(
      tester,
      _loggedIn,
      DioException(
        requestOptions: RequestOptions(path: '/api/coop/pool/list'),
        type: DioExceptionType.connectionError,
      ),
    );

    expect(find.text('合作池没能加载出来'), findsOneWidget);
    expect(find.text('网络异常，请稍后重试'), findsOneWidget);
    expect(find.text('去登录'), findsNothing, reason: '断网被推去登录,登完还是失败');
  });
}
