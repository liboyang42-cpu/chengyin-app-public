import '../../l10n/strings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/status_view.dart';
import '../auth/login_gate.dart';

/// 后端用 **HTTP 401** 表态「你没登录」——与 403(登录了但角色不够)是两回事。
///
/// 只认 401:403 / 断网 / 超时 / 业务失败都不该把用户推去登录。
/// (实测生产:club 域接口对无 token 的请求返
/// `{"code":401,"msg":"登录状态已失效，请重新登录"}`。)
bool clubLoginRequired(Object error) =>
    error is DioException && error.response?.statusCode == 401;

/// 游客撞上 401 时的就地登录门(同 `ActivityDetailPage` 的既有口径)。
///
/// 这里用通用错误态是**误导**:游客从没登录过,却被告知「检查网络后重试」
/// 或「你没有…权限」;而「重试」按多少次都还是 401,是条死路。
/// 登录成功后由 [onSignedIn] 就地把原数据重新取一遍,人留在原页。
class ClubLoginGate extends ConsumerWidget {
  const ClubLoginGate({
    super.key,
    required this.message,
    required this.onSignedIn,
  });

  final String message;
  final VoidCallback onSignedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StatusView(
      message: message,
      sub: stringsOf(context).clubMainLoginHint,
      icon: CupertinoIcons.lock,
      large: true,
      retryLabel: stringsOf(context).clubMainSignIn,
      onRetry: () async {
        if (!await requireLogin(context, ref)) return;
        onSignedIn();
      },
    );
  }
}
