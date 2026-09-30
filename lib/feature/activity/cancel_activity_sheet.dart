import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../auth/auth_controller.dart';
import 'activity_controller.dart';

/// 主办方能不能看到「取消活动并退款」。
///
/// ★★ 判不准就当**不是**主办方:这个动作会给所有已报名用户全额退款、
///   活动同时下架,且不可撤销。宁可让真主办方少一个入口(他还能从后台取消),
///   也不能让判不准的人看到它。
bool canCancelActivity({required int? hostMemberId, required int? myMemberId}) {
  if (hostMemberId == null || myMemberId == null) return false;
  if (hostMemberId <= 0 || myMemberId <= 0) return false;
  return hostMemberId == myMemberId;
}

/// 取消活动。填理由 → 二次确认 → 调接口 → **原样显示后端那句话**。
///
/// ★★★ 后端在返回的 msg 里区分了三种情况,而且注释写明了不能合并的理由:
///   · 有自动退的 → 「已为 N 笔订单全额退款(原路退回,预计1-3个工作日)」
///   · 一笔没退的 → 「无可自动退款的已付款报名」
///   · 含已核销票 → 追加「另有 M 笔订单含已核销的票,无法自动退款,平台将人工跟进」
///   ⇒ 前端**绝不能**自己写一句「已取消」把它盖掉:主办方需要知道
///     到底退了几笔、有没有需要人工跟进的。
Future<bool?> showCancelActivitySheet(
  BuildContext context, {
  required int activityId,
}) {
  return showCupertinoSheet<bool>(
    context: context,
    showDragHandle: true,
    topGap: 0.26,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _CancelSheet(
              activityId: activityId,
              scrollController: scrollController,
            ),
  );
}

class _CancelSheet extends ConsumerStatefulWidget {
  const _CancelSheet({
    required this.activityId,
    required this.scrollController,
  });
  final int activityId;
  final ScrollController scrollController;

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;

  /// 预览回来的已付款人数。**null = 还不知道**(加载中或算不出),
  /// 此时不许弹确认、不许发取消(9-18 拍板,对齐小程序 openCancel)。
  int? _paidPlayers;
  bool _previewLoading = true;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final int n = await ref
          .read(activityApiProvider)
          .cancelPreview(activityId: widget.activityId);
      if (!mounted) return;
      setState(() {
        _paidPlayers = n;
        _previewLoading = false;
        _previewError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewLoading = false;
        _previewError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String reason = _reason.text.trim();
    // 理由**必填**,而且会展示给已报名用户 —— 后端空值直接拒,
    // 让用户按下去再被拒没有意义。
    if (reason.isEmpty || _busy) return;
    // 人数还没算出来(或算失败了)就弹确认,等于让主办方在不知道退款
    // 规模的情况下点「不可撤销」—— 对齐小程序:提示等待/重试,不发请求。
    final int? paidPlayers = _paidPlayers;
    if (paidPlayers == null) {
      setState(() => _previewError = '还没算出将退款的人数，请稍候或关闭后重试。');
      return;
    }

    final bool ok = await cyConfirm(
      context,
      title: '取消这场活动并退款？',
      content:
          '将给 $paidPlayers 位已付款玩家全额退款，不可撤销。活动同时下架。\n'
          '· 已报名未核销的玩家全额退款，款项原路退回\n'
          '· 活动下架，玩家不能再报名或进入\n'
          '· 此操作不可撤销，取消后无法恢复这场活动',
      confirmText: '取消并退款',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final String msg = await ref
          .read(activityApiProvider)
          .cancelActivity(activityId: widget.activityId, reason: reason);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      // ★ 原样显示后端那句话 —— 它区分了退了几笔 / 有没有要人工跟进的。
      //   用 dialog 而不是 toast:这句话主办方必须看清,不能一晃而过。
      await cyConfirm(
        context,
        title: '活动已取消',
        content: msg,
        confirmText: '知道了',
        showCancel: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: const CupertinoNavigationBar(middle: Text('取消活动')),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Text(
              '将为所有未核销报名全额退款，并同步下架活动，操作不可撤销。',
              style: CyType.footnote.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: CyTokens.space2),
            // 三态:人数在算(载)/算不出(错,原文说明原因)/算好了(不占屏)。
            if (_previewLoading)
              Row(
                key: const Key('cancel-activity-preview-loading'),
                children: <Widget>[
                  const CupertinoActivityIndicator(),
                  const SizedBox(width: CyTokens.space2),
                  Text(
                    '正在计算将退款的人数…',
                    style: CyType.footnote.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              )
            else if (_previewError != null)
              Text(
                _previewError!,
                key: const Key('cancel-activity-preview-error'),
                style: CyType.footnote.copyWith(
                  color: CyTokens.statusDanger,
                ),
              ),
            const SizedBox(height: CyTokens.space3),
            CupertinoTextField(
              key: const Key('cancel-activity-reason'),
              controller: _reason,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              placeholder: '填写取消原因（会展示给已报名用户）',
              placeholderStyle: CyType.body.copyWith(
                color: palette.textPlaceholder,
              ),
              style: CyType.body.copyWith(color: palette.textPrimary),
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: BoxDecoration(
                color: palette.inputBgEmpty,
                border: Border.all(color: palette.borderSubtle),
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              key: const Key('cancel-activity-submit'),
              minimumSize: const Size.fromHeight(44),
              color: CyTokens.statusDanger,
              disabledColor: palette.bgSubtle,
              foregroundColor: (_busy || _reason.text.trim().isEmpty)
                  ? palette.textPlaceholder
                  : palette.textInverse,
              onPressed: (_busy || _reason.text.trim().isEmpty)
                  ? null
                  : _submit,
              child: _busy
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : const Text('确认取消并退款'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主办方入口。不是主办方时**整块不存在**(不是禁用)。
class CancelActivityEntry extends ConsumerWidget {
  const CancelActivityEntry({
    super.key,
    required this.activityId,
    required this.hostMemberId,
    this.inline = false,
  });

  final int activityId;
  final int? hostMemberId;
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? me = ref.watch(authControllerProvider).user?.id;
    if (!canCancelActivity(hostMemberId: hostMemberId, myMemberId: me)) {
      return const SizedBox.shrink();
    }
    final Widget button = CyNativeButton(
      key: const Key('cancel-activity-entry'),
      width: double.infinity,
      role: CyNativeButtonRole.destructive,
      label: '取消活动并退款',
      onPressed: () async {
        final bool? done = await showCancelActivitySheet(
          context,
          activityId: activityId,
        );
        if (done == true) {
          ref.invalidate(activityDetailProvider(activityId));
        }
      },
    );
    if (inline) return button;
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space3),
      child: button,
    );
  }
}
