import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/account_api.dart';
import '../../data/models/deregistration.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../auth/auth_controller.dart';
import '../legal/legal_doc_page.dart';
import '../legal/legal_docs.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'account_login_gate.dart';

/// 账号注销页(苹果 Guideline 5.1.1(v) 硬要求:App 内必须能发起删除账号)。
///
/// 三种落点,由后端 status 决定,客户端不自行推断:
///   · 冷静期中  → 展示到期时间 + 撤销入口
///   · 有阻断项  → 原样展示后端下发的 blockers 文案,不放行
///   · 可申请    → 须知同意 → 预检 → 短信验证 → 二次确认 → 提交
///
/// ⚠️ 后端 apply 的三道闸(consent AGREE 且版本匹配 / 已绑手机号 + 验证码 /
/// requestId 幂等)不在前端复刻判据,只按顺序满足并原样展示失败原因。
class DeregisterPage extends ConsumerStatefulWidget {
  const DeregisterPage({super.key});

  @override
  ConsumerState<DeregisterPage> createState() => _DeregisterPageState();
}

enum _Step { loading, notice, verify, blocked, pending }

class _DeregisterPageState extends ConsumerState<DeregisterPage> {
  _Step _step = _Step.loading;
  DeregistrationStatus? _status;
  String? _error;
  bool _agreed = false;
  bool _busy = false;
  // 真源 scene-settings-deregister 的 smsSending/smsSent 两标志只驱动**文案
  // 与颜色**(三态:获取验证码/发送中…/重新发送);在途锁本身仍走 _busy。
  bool _smsSending = false;
  bool _smsSent = false;

  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();

  /// 整个注销流程共用一个 requestId,保证 consent 与 apply 的幂等口径一致。
  late String _requestId = AccountApi.newRequestId();

  @override
  void initState() {
    super.initState();
    // 游客不发注定 401 的 status 请求 —— 页内先给登录门(B1 报告 P1-2),
    // 门后「去登录」成功再进 _loadStatus。
    if (ref.read(authControllerProvider).isLoggedIn) _loadStatus();
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        // 401 不再吐英文 DioException(B1 报告 P1-1 同口径):
        // 后端中文原话照说,英文栈换成能行动的中文。
        setState(
          () => _error = accountFailureCopy(e, strings: stringsOf(context), networkFallback: stringsOf(context).accountActionError),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadStatus() async {
    await _run(() async {
      final s = await ref.read(accountApiProvider).deregisterStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _step = s.isPending ? _Step.pending : _Step.notice;
      });
    });
    if (mounted && _error != null) setState(() => _step = _Step.notice);
  }

  /// 预检 → 通过则记录同意 → 进入短信验证步。
  /// consent 必须先于 apply 落库,否则后端 apply 直接拒。
  Future<void> _precheckThenAgree() async {
    await _run(() async {
      final api = ref.read(accountApiProvider);
      final pre = await api.deregisterPrecheck();
      if (!mounted) return;
      if (!pre.isEligible) {
        setState(() {
          _status = pre;
          _step = _Step.blocked;
        });
        return;
      }
      await api.agreeCancellationNotice(_requestId);
      if (!mounted) return;
      setState(() => _step = _Step.verify);
    });
  }

  Future<void> _sendCode() async {
    if (_busy)
      return; // 显式在途锁，对齐真源 deregister-flow.js:116 if (smsSending) return
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = stringsOf(context).accountPhoneRequired);
      return;
    }
    // 真源 sendSms 起手就把 smsSent 归零:重发失败要退回「获取验证码」。
    setState(() {
      _smsSending = true;
      _smsSent = false;
    });
    await _run(() async {
      await ref.read(authApiProvider).sendSmsCode(phone);
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).smsCodeSent);
      setState(() {
        _smsSending = false;
        _smsSent = true;
      });
    });
    if (mounted) setState(() => _smsSending = false);
  }

  Future<void> _confirmAndApply() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = stringsOf(context).accountCodeRequired);
      return;
    }
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).accountDeleteConfirmTitle,
      content: stringsOf(context).accountDeleteConfirmBody,
      cancelText: stringsOf(context).accountDeleteReconsider,
      confirmText: stringsOf(context).accountDeleteConfirm,
      danger: true,
    );
    if (!ok) return;

    await _run(() async {
      final s = await ref
          .read(accountApiProvider)
          .deregisterApply(smscode: _code.text.trim(), requestId: _requestId);
      if (!mounted) return;
      setState(() {
        _status = s;
        _step = s.isBlocked ? _Step.blocked : _Step.pending;
      });
      if (!s.isBlocked) {
        // ★ 后端 apply() 会 revokeAll 吊销所有会话:此刻本地 token 已失效。
        //   不清理的话,这页上的「撤销申请」会直接 401,而用户完全不知情
        //   —— 表现成「点了没反应」,却以为注销还能撤回。
        await ref.read(authControllerProvider.notifier).logout();
        if (!mounted) return;
        CyNativeNotice.show(context, stringsOf(context).accountDeleteSubmitted);
      }
    });
  }

  Future<void> _cancelApply() async {
    await _run(() async {
      final s = await ref.read(accountApiProvider).deregisterCancel();
      if (!mounted) return;
      setState(() {
        _status = s;
        _step = _Step.notice;
        _agreed = false;
        // 撤销后重开流程,换一个幂等标识,避免与上一轮申请撞 requestId。
        _requestId = AccountApi.newRequestId();
      });
      CyNativeNotice.show(context, stringsOf(context).accountDeleteCancelled);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: DefaultTextStyle.merge(
        // 保留 App 现有字体层级;仅由 Cupertino 接管容器和交互。
        // 真机仍使用 iOS 系统字体,widget test 也能读到中文字形。
        style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
        child: SafeArea(
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).accountDeleteAccount),
              Expanded(
                child: !ref.watch(authControllerProvider).isLoggedIn
                    ? AccountLoginGate(
                        key: const Key('deregister-login-gate'),
                        message: stringsOf(context).accountDeleteLogin,
                        sub: stringsOf(context).accountDeleteLoginHint,
                        onSignedIn: _loadStatus,
                      )
                    : _step == _Step.loading
                    ? const LoadingView()
                    : _buildStep(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        if (_error != null) _ErrorBanner(message: _error!),
        switch (_step) {
          _Step.pending => _PendingCard(
            status: _status,
            busy: _busy,
            onCancel: _cancelApply,
          ),
          _Step.blocked => _BlockedCard(
            status: _status,
            busy: _busy,
            onRecheck: _loadStatus,
          ),
          _Step.verify => _buildVerify(),
          _ => _buildNotice(),
        },
      ],
    );
  }

  Widget _buildNotice() {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(stringsOf(context).legalDraftCancellationNoticeTitle, style: textTheme.titleMedium),
        const SizedBox(height: CyTokens.space3),
        const _NoticeBody(),
        // 上面四条是摘要,不是须知全文。合规上「我已阅读并同意」必须真的**能读到
        // 全文**,所以照小程序 scene-settings-deregister 的做法给一条明链;
        // 勾选框文案保持纯文本(点它就该切换勾选,不该跳走)。
        const _NoticeLink(),
        const SizedBox(height: CyTokens.space2),
        Semantics(
          container: true,
          button: true,
          enabled: !_busy,
          checked: _agreed,
          label: stringsOf(context).accountDeletionConsentSemantics,
          onTap: _busy ? null : () => setState(() => _agreed = !_agreed),
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : () => setState(() => _agreed = !_agreed),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: <Widget>[
                    CupertinoCheckbox(
                      value: _agreed,
                      onChanged: _busy
                          ? null
                          : (bool? v) => setState(() => _agreed = v ?? false),
                    ),
                    const SizedBox(width: CyTokens.space2),
                    Expanded(child: Text(stringsOf(context).accountDeletionConsentText)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        CyNativeButton(
          onPressed: (_agreed && !_busy) ? _precheckThenAgree : null,
          label: _busy ? stringsOf(context).accountChecking : stringsOf(context).accountNext,
          loading: _busy,
        ),
      ],
    );
  }

  Widget _buildVerify() {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(stringsOf(context).accountSmsVerification, style: textTheme.titleMedium),
        const SizedBox(height: CyTokens.space2),
        Text(
          stringsOf(context).accountBoundPhoneExplanation,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: CyTokens.space4),
        CyField(
          label: stringsOf(context).accountBoundPhone,
          child: CupertinoTextField(
            key: const Key('deregister-phone-field'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.telephoneNumber],
            clearButtonMode: OverlayVisibilityMode.editing,
            maxLength: 11,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            placeholder: stringsOf(context).accountBoundPhoneHint,
            padding: const EdgeInsets.all(CyTokens.space3),
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: CyField(
                label: stringsOf(context).verificationCode,
                child: CupertinoTextField(
                  key: const Key('deregister-code-field'),
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  clearButtonMode: OverlayVisibilityMode.editing,
                  maxLength: 6,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  placeholder: stringsOf(context).accountCodeHint,
                  padding: const EdgeInsets.all(CyTokens.space3),
                  onSubmitted: (_) {
                    if (!_busy) _confirmAndApply();
                  },
                ),
              ),
            ),
            const SizedBox(width: CyTokens.space3),
            // 真源 `.deregister-code-send`:行尾下划线文字动作(font-label 12pt、
            // text-title 色、左内衬 space-3、min-height=btnH),不是灰胶囊;
            // 在途换 textDisabled 色不降透明度(共用纪律)。
            CupertinoButton(
              key: const Key('deregister-send-code'),
              minimumSize: const Size(44, CyTokens.btnH),
              padding: const EdgeInsets.only(left: CyTokens.space3),
              onPressed: _busy ? null : _sendCode,
              child: Text(
                _smsSending ? stringsOf(context).sendingCode : (_smsSent ? stringsOf(context).resendCode : stringsOf(context).getCode),
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: _smsSending
                      ? CyTokens.textDisabled
                      : CyTokens.textPrimary,
                  decoration: TextDecoration.underline,
                  decorationColor: _smsSending
                      ? CyTokens.textDisabled
                      : CyTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        CyNativeButton(
          onPressed: _busy ? null : _confirmAndApply,
          label: _busy ? stringsOf(context).accountSubmitting : stringsOf(context).accountDeleteSubmit,
          role: CyNativeButtonRole.destructive,
          loading: _busy,
        ),
      ],
    );
  }
}

/// `.deregister-link`:text-title + 下划线的行内明链,点进《账号注销须知》全文。
class _NoticeLink extends StatelessWidget {
  const _NoticeLink();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
        alignment: Alignment.centerLeft,
        onPressed: () =>
            context.push(LegalDocPage.routeOf(LegalDocType.cancellationNotice)),
        child: Text(
          stringsOf(context).accountViewDeletionNotice,
          style: const TextStyle(
            fontSize: CyTokens.typeBody,
            color: CyTokens.textPrimary,
            decoration: TextDecoration.underline,
            decorationColor: CyTokens.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _NoticeBody extends StatelessWidget {
  const _NoticeBody();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    // ★「七日」是从定稿的《账号注销须知》里取的(legal_docs.dart 第二节标题即
    //   「二、申请与七日冷静期」)。原文案只说「有冷静期」——而「几天内还能反悔」
    //   正是用户决定要不要按下这一步时最需要的那个数,含糊等于没说。
    final strings = stringsOf(context);
    final List<String> points = <String>[
      strings.accountDeleteNoticeIrreversible,
      strings.accountDeleteNoticeCoolingOff,
      strings.accountDeleteNoticeOutstanding,
      strings.accountDeleteNoticeRoles,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < points.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: CyTokens.space1_5),
          // 用 Row 而不是把「· 」拼进字符串:拼进去时第二行会顶格,
          // 四条并排在一起就分不清哪一行属于哪一条。这里让符号独占一列,
          // 正文整体悬挂缩进。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: CyTokens.space4,
                child: Text('·', style: style, textAlign: TextAlign.center),
              ),
              Expanded(child: Text(points[i], style: style)),
            ],
          ),
        ],
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.status,
    required this.busy,
    required this.onCancel,
  });
  final DeregistrationStatus? status;
  final bool busy;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.hourglass_top, color: AppColors.primary),
                    const SizedBox(width: CyTokens.space2),
                    Text(stringsOf(context).accountDeletionPending, style: textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: CyTokens.space3),
                Text(
                  status?.executeAfter != null
                      ? stringsOf(context).accountDeletionScheduled(status!.executeAfter!)
                      : stringsOf(context).accountCoolingOff,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: CyTokens.space2),
                Text(
                  // ★ 不能写「账号保持正常使用」——后端 apply() 里有
                  //   appSessionRegistryService.revokeAll(memberId),提交即吊销所有会话,
                  //   用户会被踢下线。小程序文案是「账号功能已冻结」,以它为准。
                  //   (账号本身没被停用:markMemberPending 只改 deregister_status,
                  //    不动 status/del_flag,而登录只看后两者 ⇒ 仍可重新登录来撤销。)
                  stringsOf(context).accountDeletionFrozen,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space4),
        CyNativeButton(
          onPressed: busy ? null : onCancel,
          label: busy ? stringsOf(context).processing : stringsOf(context).accountCancelDeletion,
          loading: busy,
        ),
      ],
    );
  }
}

class _BlockedCard extends StatelessWidget {
  const _BlockedCard({
    required this.status,
    required this.busy,
    required this.onRecheck,
  });
  final DeregistrationStatus? status;
  final bool busy;
  final Future<void> Function() onRecheck;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final blockers = status?.blockers ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 阻断态标题用 danger:这是「你现在不能注销」的告知,
        // 与下方中性色的阻断原因列表要有主次,否则整屏一个灰度读不出结论。
        Text(
          stringsOf(context).accountDeletionBlocked,
          style: textTheme.titleMedium?.copyWith(color: AppColors.danger),
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          stringsOf(context).accountDeletionResolveBlockers,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: CyTokens.space3),
        // 文案由服务端下发,原样展示,不在客户端改写或归并。
        // 每条一张 Card 视觉过重(与票卡详情的权益明细同理),
        // 改成一张卡里的紧凑行,统一用 CyCell。
        // ⚠️ 必须判空:原写法是 ...map() 展开,空列表不渲染任何东西;
        //    包成 Card 后不判空会画出一张空卡。
        if (blockers.isNotEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: CyTokens.space1),
              child: Column(
                children: blockers
                    .map(
                      (String b) => CyCell(
                        title: b,
                        showChevron: false,
                        leading: const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        if (blockers.isEmpty)
          Text(stringsOf(context).accountDeletionResultError, style: textTheme.bodyMedium),
        const SizedBox(height: CyTokens.space2),
        CyNativeButton(
          onPressed: busy ? null : onRecheck,
          label: stringsOf(context).accountRecheck,
          role: CyNativeButtonRole.secondary,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space4),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
