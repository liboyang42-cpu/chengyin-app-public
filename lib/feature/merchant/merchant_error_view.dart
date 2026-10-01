import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/status_view.dart';
import '../../core/widgets/localized_error_status.dart';
import '../../l10n/error_presentation.dart';
import '../../data/api/merchant_api.dart';
import '../../l10n/strings.dart';

/// 商家域的错误分流 —— **四种态,界面各不相同**。
///
/// 集中在这里而不是每页各写一遍:分流写歪的后果很具体,而且每页歪法不一样。
///
/// | 态 | 判据 | 界面 |
/// |---|---|---|
/// | 账户互斥 | 已是俱乐部主理人 | 说清原因,**什么按钮都不给**(永远不会变) |
/// | 审核中 | 申请已交、尚未通过 | 说「审核通过后可用」,**不给申请入口**(他已经申请过了) |
/// | 还不是商家 | 没有商家记录 | 给「去申请入驻」 |
/// | 真故障 | 其余 | 给「重试」 |
Widget merchantErrorView(
  BuildContext context,
  Object error, {
  required VoidCallback onRetry,

  /// 这一页在加载**什么**。
  ///
  /// ★ 这个视图是商家域共用的,它自己不知道在为哪一页服务 ——
  ///   所以名字由调用方给。不给的话退回「内容」,仍然比只说
  ///   「加载失败」强:一屏上常有多块内容各自加载,不说是哪一块,
  ///   用户不知道现在看到的还能不能信。
  String? what,
}) {
  if (error is MerchantApiException) {
    if (error.isClubLeaderConflict) {
      return StatusView(message: stringsOf(context).merchantHomeConflict, sub: error.message, large: true);
    }
    if (error.isPendingReview) {
      return StatusView(
        message: stringsOf(context).merchantHomeReview,
        sub: stringsOf(context).merchantHomeReviewHint,
        large: true,
      );
    }
    if (error.isNotMerchant) {
      return StatusView(
        message: stringsOf(context).merchantHomeNotMerchant,
        sub: stringsOf(context).merchantHomeApplyHint,
        large: true,
        onRetry: () => context.push('/merchant/apply'),
        retryLabel: stringsOf(context).merchantHomeApply,
      );
    }
  }
  return LocalizedErrorStatus(
    error: error,
    fallback: stringsOf(context).merchantHomeLoadError(what ?? stringsOf(context).merchantHomeContent),
    originalApiMessage: error is MerchantApiException ? error.message : legacyApiMessage(error),
    onRetry: onRetry,
  );
}

/// 岗位没有这项权限 —— 说清是哪项权限,以及**出路在哪**。
///
/// ★★ 这条不是故障:重试一万次权限也不会自己长出来。所以这里的按钮
///   不能写成「重试(再打一次同一个 403)」,只能是「重新确认」——
///   它重读的是 `access/me`,店主动了岗,这一按就真的会变。
///   真源文案(`pages/merchant/marketing`)：title「你的岗位还没有营销数据权限」
///   / sub「请联系店主开通」/ action「重新确认」。
Widget merchantDeniedView({
  required String title,
  String? sub,
  String? retryLabel,
  VoidCallback? onRetry,
}) => Builder(
  builder: (context) => StatusView(
    icon: CupertinoIcons.lock,
    message: title,
    sub: sub ?? stringsOf(context).merchantHomeContactOwner,
    large: true,
    onRetry: onRetry,
    retryLabel: retryLabel ?? stringsOf(context).merchantHomeRecheck,
  ),
);
