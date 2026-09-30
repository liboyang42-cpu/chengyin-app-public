import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/widgets/status_view.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 协作域页内守卫。这一域在小程序里是商家工作台(靠微信静默登录 + roleGuard,
/// 不存在游客),App 有真游客 —— 所以整族 fail-closed:未登录先登录再进。
///
/// 为什么不在路由表加前缀:路由层是共用文件(PR #183 在改),这一域的守卫
/// 先在页内做,口径与 `/club/:id/settlement`、经营团队邀请一致。

/// 登录失效判据。**只认 401** —— 把断网/500 当成「要登录」会把断网的人反复
/// 推去登录页,登完还是失败。App 里 401 的唯一来路就是 token 失效,后端也回
/// 「登录状态已失效,请重新登录」。
///
/// 归一化放共享层是 #183 的事(网络层已冻结);这里是本线的最小实现。
bool isCoopUnauthorized(Object err) =>
    err is DioException && err.response?.statusCode == 401;

/// 读接口失败的副文案:后端给了中文原话就用它(业务拒绝、权限态都走这条路);
/// 只有 dio 自己的英文栈(带 MDN 链接那种)才换成一句人话。
String coopErrorSub(Object err, {String fallback = '网络不稳定,请稍后重试'}) {
  if (err is! DioException) {
    return err.toString().replaceFirst('Exception: ', '');
  }
  final Object? data = err.response?.data;
  final String msg = data is Map ? (data['msg']?.toString().trim() ?? '') : '';
  return msg.isEmpty ? fallback : msg;
}

/// 未登录 → 整页登录引导;已登录 → null(调用方继续走业务分支,**一个请求都不发**)。
///
/// ★ 判据带 `auth.initialized`:启动恢复没跑完时**不知道**用户是不是登录过,
///   这时说「请登录」会误伤持 token 的冷启动 —— 与 app_router 停在 /splash
///   是同一条理由。真机上路由层在 initialized 之前只渲染 /splash。
Widget? coopLoginGate(
  BuildContext context,
  WidgetRef ref, {
  required String navTitle,
  required String message,
}) {
  final AuthState auth = ref.watch(authControllerProvider);
  if (!auth.initialized || auth.isLoggedIn) return null;
  return coopLoginView(context, ref, navTitle: navTitle, message: message);
}

/// 未登录 / 登录失效时的整页引导屏(写法同活动详情、经营团队邀请)。
Widget coopLoginView(
  BuildContext context,
  WidgetRef ref, {
  required String navTitle,
  required String message,
  VoidCallback? refetch,
}) {
  return CupertinoPageScaffold(
    // ⚠️ 这里是**跟随路由 Theme** 取底色的普通写法,不是「显式给浅色底」:
    // `CyPalette.of(context)` 随所在路由被包的 Theme 明/暗而变,没包 `_merchantLight`
    // 的路由(含 4 条按角色路由的游客/玩家)渲染出来就是**暗底**(b1 报告 P2-4
    // 修此前注释漂移;coop 域整体明暗口径属 P1-1,待设计拍板,勿在此擅动)。
    backgroundColor: CyPalette.of(context).bgPage,
    navigationBar: CupertinoNavigationBar(middle: Text(navTitle)),
    child: coopLoginStatus(context, ref, message: message, refetch: refetch),
  );
}

/// 登录引导那**一块**(页面自己有壳时用,如附近的错误分支)。
Widget coopLoginStatus(
  BuildContext context,
  WidgetRef ref, {
  required String message,
  VoidCallback? refetch,
}) {
  return StatusView(
    icon: CupertinoIcons.lock,
    message: message,
    sub: '这一步需要登录,登录完会自动回到这一页。',
    large: true,
    retryLabel: '去登录',
    onRetry: () async {
      if (!await requireLogin(context, ref)) return;
      refetch?.call();
    },
  );
}
