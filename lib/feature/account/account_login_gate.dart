import '../../l10n/app_localizations.dart';
import '../../l10n/strings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/widgets/status_view.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 后端用 **HTTP 401** 表态「你没登录」,消息体里带的就是那句中文
/// 「登录状态已失效，请重新登录」(2026-09-18 生产实测,见 #194 同判据)。
/// 只认 401 —— 403/断网/超时都不该把用户推去登录。
bool accountLoginRequired(Object error) => isUnauthorizedError(error);

/// 错误态文案归一(B1 报告 P1-1:错误态直出英文 `DioException … 401 …`)。
///
/// 口径(同 #194/#196/#231):
///  · **401** → 后端原话「登录状态已失效，请重新登录」;
///  · 其余 DioException(断网/5xx…) → 不吐异常原文,给调用方点名的中文兜底;
///  · 业务失败(`Exception(后端中文 msg)`) → 后端中文原话照说,可行动信息不吞。
String accountFailureCopy(Object error, {required String networkFallback, AppLocalizations? strings}) {
  if (accountLoginRequired(error)) return strings?.loginExpired ?? '登录状态已失效，请重新登录';
  if (error is DioException) return networkFallback;
  return error.toString().replaceFirst('Exception: ', '');
}

/// 账号/资料域统一的「需要登录」门(B1 报告 P1-1/P1-2/P1-4)。
///
/// 两种落点共用:
///  ① 游客深链到达页面 —— 路由不再静默弹回首页(参照 roam #208 / 票夹 #231
///    的修法),页面短路掉注定 401 的请求,在这一屏解释并就地弹登录;
///  ② 已登录用户会话失效(服务端 401)—— 错误分支不再吐英文栈,给同一扇门。
/// 登录成功后 [onSignedIn] 就地重拉本页,人留在原页。
class AccountLoginGate extends ConsumerWidget {
  const AccountLoginGate({
    super.key,
    required this.message,
    required this.onSignedIn,
    this.sub,
  });

  final String message;
  final String? sub;
  final VoidCallback onSignedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StatusView(
      message: message,
      sub: sub ?? stringsOf(context).loginGateResume,
      icon: CupertinoIcons.lock,
      large: true,
      retryLabel: stringsOf(context).goSignIn,
      onRetry: () async {
        if (!await requireLogin(context, ref)) return;
        onSignedIn();
      },
    );
  }
}

/// 游客判定:与全 App 单一真源 [authControllerProvider] 同步。
/// 登录成功 → 依赖它的页面重建并自动开始加载真实数据。
bool accountGuest(WidgetRef ref) {
  final AuthState auth = ref.watch(authControllerProvider);
  return !auth.isLoggedIn;
}
