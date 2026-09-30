import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';

/// R10 过渡期提现弹窗里显示的微信号。真源 `utils/withdraw-cs.js` 的
/// `WITHDRAW_CS_WECHAT_ID` —— 全仓 6 个提现入口的弹窗都从这里取号。
const String kWithdrawalContactWechatId = '18000000000';

/// 弹窗标题、正文副句、复制 toast —— 逐字对齐真源 `withdraw-cs.js`
/// (`showWithdrawCsPopup` / `WITHDRAW_CS_TIP` / `copyWithdrawCsWechat`)。
const String _kDialogTitle = '联系平台客服提现';
const String _kDialogTip = '添加客服微信，核对金额后线下处理';
const String _kCopiedToast = '已复制微信号';
const String _kCopyFailedToast = '复制失败，请手动添加客服微信';

/// R10:所有「提现」入口的统一出口 —— 中间弹窗显示微信号 + 「返回」「复制」。
///
/// ★ 文案逐字对齐小程序真源 `chengyinhub-xcx/utils/withdraw-cs.js`
///   (标题 / 正文 / 两枚按钮 / 复制成功提示),那边是 6 个入口共用的同一份话术;
///   两端口径不一致时以真源为准。
/// ★ 这里**不发任何提现请求**:过渡期不再走银行卡提现 / 转零钱,
///   也不做提现风险确认;双方按微信号线下结算。
///   标题/正文/复制提示 1:1 对齐真源 `utils/withdraw-cs.js`
///   (B1 真跑报告 P2-1:此前 App 侧三处自造文案)。
/// ★ 弹窗形态走共用件 `cyConfirm`(对照表 `wx.showModal` → `cyConfirm`):
///   iOS 26+ 由系统 Liquid Glass alert 呈现,iOS 13–25 回退
///   [CupertinoAlertDialog] —— 回退形态与迁移前逐字一致,行为不变。
Future<void> showWithdrawalContactDialog(BuildContext context) async {
  final bool confirmed = await cyConfirm(
    context,
    title: _kDialogTitle,
    content: '客服微信号：$kWithdrawalContactWechatId\n$_kDialogTip',
    confirmText: '复制',
    cancelText: '返回',
  );
  if (!context.mounted || !confirmed) return;
  // 真源 `copyWithdrawCsWechat` 有 fail 分支(setClipboardData 是异步
  // 平台调用,可能失败);App 此前只处理成功半边 → 复制没写成时
  // 用户以为复制好了。⚠️ 失败 toast 里**别拼微信号**:11 位号会被
  // 真源 safeUserMessage 当手机号过滤成「操作失败」,号本就在正文上。
  try {
    await Clipboard.setData(
      const ClipboardData(text: kWithdrawalContactWechatId),
    );
  } catch (_) {
    if (!context.mounted) return;
    CyNativeNotice.show(context, _kCopyFailedToast);
    return;
  }
  if (!context.mounted) return;
  // 真源是裸 toast(不带 error icon),这里同样不加错误涂装。
  CyNativeNotice.show(context, _kCopiedToast);
}
