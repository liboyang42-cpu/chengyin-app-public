// 退出登录。
//
// ★ App 此前**只清本地 token,从不通知服务端**。
//   后端 `/api/logout`(ApiLoginController:166)会 `delLoginAppUser(token)`
//   把这份凭据作废;不调它的话,**token 在服务端一直有效** ——
//   手机丢了、或在别人设备上登录后退出,那份凭据仍然能用。
//
// ⚠️ 同时必须守住反过来的那条:**服务端失败不能阻断本地退出**。
//   用户点了退出就必须退成,否则网络一断人就被困在已登录状态里。
//   这是「尽力而为」不是「必须成功」——两条一起才对,少一条都是 bug。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String api = File('lib/data/api/auth_api.dart').readAsStringSync();
  final String ctrl = File(
    'lib/feature/auth/auth_controller.dart',
  ).readAsStringSync();

  test('★ 退出时必须通知服务端作废 token', () {
    expect(
      api.contains("'/api/logout'"),
      isTrue,
      reason: 'AuthApi 里没有 logout —— token 会在服务端一直有效',
    );
    expect(
      ctrl.contains('authApiProvider).logout()'),
      isTrue,
      reason: 'AuthController.logout 没有调服务端',
    );
  });

  test('★ 服务端失败不许阻断本地退出 —— 网络断了也得能退出去', () {
    // 判据:调用被 try 包住,且 catch 之后仍然执行清理。
    final int at = ctrl.indexOf('authApiProvider).logout()');
    expect(at, greaterThan(0));

    final String before = ctrl.substring(0, at);
    final int tryAt = before.lastIndexOf('try {');
    final int fnAt = before.lastIndexOf('Future<void> logout()');
    expect(tryAt, greaterThan(fnAt), reason: '服务端调用没被 try 包住 —— 一失败用户就退不出去了');

    final String after = ctrl.substring(at);
    final int catchAt = after.indexOf('} catch');
    final int clearAt = after.indexOf('_signOutLocally()');
    expect(catchAt, greaterThan(0), reason: '没有 catch 分支');
    expect(
      clearAt,
      greaterThan(catchAt),
      reason:
          '清本地 token 必须在 catch **之后** —— '
          '放在 try 里的话,服务端一失败就跳过了清理',
    );
  });

  test('★ 清本地这一步不在 try 里 —— 顺序错了等于没修', () {
    // 常见写法是把两步都塞进同一个 try:
    //   try { await api.logout(); await store.clear(); } catch (_) {}
    // 那样服务端一失败,clear 根本不会执行 —— 和完全不改一样。
    final int fnAt = ctrl.indexOf('Future<void> logout()');
    final String body = ctrl.substring(fnAt, fnAt + 900);
    final int catchAt = body.indexOf('} catch');
    final int clearAt = body.indexOf('_signOutLocally()');
    expect(clearAt, greaterThan(catchAt));
  });

  test('★ 401 只做本地失效，不得再请求 logout 造成递归', () {
    final String providers = File('lib/core/providers.dart').readAsStringSync();
    expect(providers, contains('.expireSession()'));
    expect(
      providers.substring(
        providers.indexOf('onUnauthorized:'),
        providers.indexOf('onUnauthorized:') + 220,
      ),
      isNot(contains('.logout()')),
    );
  });

  test('本地状态也要复位成未登录', () {
    expect(ctrl.contains('state = const AuthState(initialized: true)'), isTrue);
  });
}
