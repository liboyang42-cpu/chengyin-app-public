import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/feature/auth/phone_login_sheet.dart';

/// 可手动完成的 AuthApi，用于测试在途锁行为。
class _CompletableAuthApi extends AuthApi {
  _CompletableAuthApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  int sendCalls = 0;
  final List<Completer<Map<String, dynamic>>> _pending = [];

  Completer<Map<String, dynamic>> get latestPending => _pending.last;

  @override
  Future<Map<String, dynamic>> sendSmsCode(String phone) async {
    sendCalls += 1;
    final c = Completer<Map<String, dynamic>>();
    _pending.add(c);
    return c.future;
  }
}

Widget _host(AuthApi api) {
  return ProviderScope(
    overrides: <dynamic>[authApiProvider.overrideWithValue(api)].cast(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showPhoneLoginSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester, AuthApi api) async {
  await tester.pumpWidget(_host(api));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(CupertinoTextField).first, '13800138000');
}

void main() {
  testWidgets('连点5次「获取验证码」→ 仅1条 POST /api/sms/send（在途锁）', (
    WidgetTester tester,
  ) async {
    final api = _CompletableAuthApi();
    await _openSheet(tester, api);

    // 连点5次，API 不返回（Completer pending），验证只有1次进入网络层。
    for (int i = 0; i < 5; i++) {
      await tester.tap(find.text('获取验证码'));
      // 不 pumpAndSettle，保证在途窗口内
    }
    await tester.pump();

    expect(api.sendCalls, 1, reason: '在途锁应阻止第2~5次进入 API');

    // 清理：完成 pending future，避免内存泄漏
    api.latestPending.complete({'code': 200, 'msg': 'ok'});
    await tester.pumpAndSettle();
  });

  testWidgets('在途期间按钮不可再点（onPressed=null）', (WidgetTester tester) async {
    final api = _CompletableAuthApi();
    await _openSheet(tester, api);

    await tester.tap(find.text('获取验证码'));
    await tester.pump(); // 触发 setState rebuild

    // 按钮已变为「发送中…」且禁用
    expect(find.text('发送中…'), findsOneWidget);

    // 尝试再点（按钮应 disabled，不触发新请求）
    final button = tester.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('发送中…'),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(button.onPressed, isNull, reason: '在途期间按钮 onPressed 应为 null');

    api.latestPending.complete({'code': 200, 'msg': 'ok'});
    await tester.pumpAndSettle();
  });

  testWidgets('成功后按钮显示「重新发送」且无冷却可再点（对齐真源 smsSent 口径）', (
    WidgetTester tester,
  ) async {
    final api = _CompletableAuthApi();
    await _openSheet(tester, api);

    await tester.tap(find.text('获取验证码'));
    await tester.pump();

    // 完成第1次 API
    api.latestPending.complete({'code': 200, 'msg': 'ok'});
    await tester.pumpAndSettle();

    // 成功后按钮显示「重新发送」
    expect(find.text('重新发送'), findsOneWidget);

    // 点「重新发送」可再次发送（真源无冷却）
    await tester.tap(find.text('重新发送'));
    await tester.pump();

    expect(api.sendCalls, 2, reason: '成功后可重新发送，真源无冷却倒计时');

    api.latestPending.complete({'code': 200, 'msg': 'ok'});
    await tester.pumpAndSettle();
  });

  testWidgets('失败后在途锁释放，可重试（对齐真源失败 smsSending=false 口径）', (
    WidgetTester tester,
  ) async {
    final api = _CompletableAuthApi();
    await _openSheet(tester, api);

    await tester.tap(find.text('获取验证码'));
    await tester.pump();

    // 第1次 API 失败
    api.latestPending.completeError(Exception('短信服务未配置'));
    await tester.pumpAndSettle();

    // 失败后按钮应恢复为「获取验证码」（smsSent 不翻 true）
    expect(find.text('获取验证码'), findsOneWidget);

    // 重试
    await tester.tap(find.text('获取验证码'));
    await tester.pump();

    expect(api.sendCalls, 2, reason: '失败后在途锁释放可重试');

    api.latestPending.complete({'code': 200, 'msg': 'ok'});
    await tester.pumpAndSettle();
  });
}
