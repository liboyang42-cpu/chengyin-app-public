import 'coop_invite_detail_strings.dart';
import 'coop_strings.dart';
import '../../l10n/strings.dart';
import '../auth/auth_controller.dart';
import '../../core/network/request_session_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/coop_api.dart';
import '../../data/models/coop_invite_row.dart';
import '../../data/models/merchant_coop.dart';
import 'coop_guard.dart';
// ⚠️ 供给申报 / 评价 / 取消理由这三件交互件与列表页**共用一份实现**,不复制第二份:
//   涉资(申报供给)与评分(互评)的口径漂一次就是两条链路两套行为。它们当前住在
//   `coop_list_page.dart` 里(列表卡的按钮先用到的那一批)。等「一张卡最多两个按钮」
//   那批把列表卡的动作收口过来之后,这三个件应当整体搬进本文件。
import 'coop_list_page.dart'
    show CoopPerkPickSheet, CoopReasonDialog, CoopReviewSheet;

/// 协作邀约详情。对齐小程序 `pages/coop/invite-detail`(Figma 02d-1 ~ 02d-5)。
///
/// 为什么要有这一页:列表只给一行状态字。「已拒绝 / 已过期 / 已顶替」都要能看到
/// **对方给的理由**和当时的**条款快照** —— 那两样只有详情页装得下。
///
/// ★ 取数刻意走 `/api/coop/list` 再按 inviteId 挑出来,而不是从上一页把整行带过来:
///   带过来的是**打开列表那一刻**的状态,对方在这中间接受/撤回了都看不出来。
///   详情是要据此做决定的页,必须问服务端要一次新的。(小程序同此)
@immutable
class CoopInviteDetailKey {
  const CoopInviteDetailKey({required this.inviteId, required this.sent});

  final int inviteId;

  /// true = 我发出的那一侧(sent)/ false = 我收到的那一侧(received)。
  final bool sent;

  @override
  bool operator ==(Object other) =>
      other is CoopInviteDetailKey &&
      other.inviteId == inviteId &&
      other.sent == sent;

  @override
  int get hashCode => Object.hash(inviteId, sent);
}

/// 这条邀约**不在当前这一侧的列表里**。
///
/// ★ 与「加载失败」是两回事:撤回 / 被顶替之后它会从这一侧消失,那是事实不是故障,
///   两者的出口也不一样(一个是回列表,一个才是重试)。
class CoopInviteAbsent implements Exception {
  const CoopInviteAbsent(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 详情要用的两样东西:那一行,以及席位占用表。
///
/// slots 在响应顶层而不在行里,所以不能只返回 [CoopInviteRow]。
@immutable
class CoopInviteDetail {
  const CoopInviteDetail({required this.row, this.slots});

  final CoopInviteRow row;
  final Map<String, dynamic>? slots;
}

final coopInviteDetailProvider = FutureProvider.autoDispose
    .family<CoopInviteDetail, CoopInviteDetailKey>((ref, key) async {
      // ★ 一次响应的三半(sent / received / slots)从同一个 Map 里取,
      //   不为 slots 再打一次同样的请求(见 `CoopApi.inviteList`)。
      final Map<String, dynamic> data = await ref
          .watch(coopApiProvider)
          .inviteList();
      final CoopInviteList list = CoopInviteList.fromJson(data);
      final List<CoopInviteRow> rows = key.sent ? list.sent : list.received;
      final CoopInviteRow? hit = rows
          .where((CoopInviteRow r) => r.id == key.inviteId)
          .firstOrNull;
      if (hit == null) {
        // 找不到不等于出错:可能已经被移出这一侧(比如撤回后从收件箱消失)。
        throw const CoopInviteAbsent('这条邀约不在当前列表里了');
      }
      return CoopInviteDetail(row: hit, slots: list.slots);
    });

/// 状态大字的语气。已接受是唯一的正向终态,其余终态一律中性 ——
/// **不用红色**:「已拒绝」是一个事实,不是错误。(小程序 TONE 同此)
enum _Tone { pending, accepted, closed }

_Tone _toneOf(int? status) {
  switch (status) {
    case 0:
      return _Tone.pending;
    case 1:
      return _Tone.accepted;
    default:
      return _Tone.closed;
  }
}

Color _toneColor(_Tone tone, CyPalette palette) {
  switch (tone) {
    case _Tone.pending:
      return palette.statusWarning;
    case _Tone.accepted:
      return palette.statusSuccess;
    case _Tone.closed:
      return palette.textTertiary;
  }
}

class CoopInviteDetailPage extends ConsumerStatefulWidget {
  const CoopInviteDetailPage({super.key, this.inviteId, this.box = 'received'});

  /// 路由上的**原始**邀约编号。缺编号与编号非法要分开说,所以这里不先解析成 int。
  final String? inviteId;

  /// received = 别人发来的 / sent = 我发出的。决定去服务端哪一侧找这一行,
  /// 以及底部给哪些动作(接受/拒绝是受邀方的,撤回是发起方的)。
  final String box;

  @override
  ConsumerState<CoopInviteDetailPage> createState() =>
      _CoopInviteDetailPageState();
}

class _CoopInviteDetailPageState extends ConsumerState<CoopInviteDetailPage> {
  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  late final RequestSessionScope _requestScope;

  final TextEditingController _draft = TextEditingController();
  String _draftError = '';
  bool _submitting = false;
  bool _busy = false;
  String _actionError = '';

  bool get _sent => widget.box == 'sent';

  /// 能用的邀约编号。null = 缺编号 / 编号非法,两种都要在下面对应文案上分开。
  int? get _inviteId {
    final int? id = int.tryParse((widget.inviteId ?? '').trim());
    return (id == null || id <= 0) ? null : id;
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title = stringsOf(context).coopDetail;
    final String needLogin = stringsOf(context).coopLoginDetail;
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final CyPalette palette = CyPalette.of(context);
    final int? id = _inviteId;
    final Widget body;
    if (id == null) {
      // 编号缺 / 非法都是「打不开」:这时候连请求都不该发。
      body = _unopenable(
        (widget.inviteId ?? '').trim().isEmpty
            ? stringsOf(context).coopMissingInvite
            : stringsOf(context).coopInvalidInvite,
      );
    } else {
      final CoopInviteDetailKey key = CoopInviteDetailKey(
        inviteId: id,
        sent: _sent,
      );
      body = ref
          .watch(coopInviteDetailProvider(key))
          .when(
            loading: () =>
                const CySkeleton(type: CySkeletonType.card, count: 3),
            error: (Object e, _) => e is CoopInviteAbsent
                ? _unopenable(
                    stringsOf(context).coopInviteMoved,
                    title: stringsOf(context).coopInviteMissingFromList,
                  )
                : isCoopUnauthorized(e)
                ? coopLoginStatus(
                    context,
                    ref,
                    message: needLogin,
                    refetch: () =>
                        ref.invalidate(coopInviteDetailProvider(key)),
                  )
                : StatusView(
                    message: stringsOf(context).coopDetailLoadFailed,
                    sub: coopErrorSub(e, context: context),
                    large: true,
                    onRetry: () =>
                        ref.invalidate(coopInviteDetailProvider(key)),
                  ),
            data: _content,
          );
    }
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(top: false, child: body),
      ),
    );
  }

  /// 打不开一条邀约时的出口:**回协作邀请列表**,不是「重试」——
  /// 编号缺/非法、邀约已被撤回,重试多少次结果都一样。
  Widget _unopenable(String sub, {String? title}) {
    return StatusView(
      message: title ?? stringsOf(context).coopCannotOpenInvite,
      sub: sub,
      large: true,
      retryLabel: stringsOf(context).coopBackToInvitations,
      onRetry: _backToList,
    );
  }

  void _backToList() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // 冷启动深链没有上一页:直接回列表,并停在对我有意义的那一档。
    context.go(_sent ? '/coop/list?tab=sent' : '/coop/list');
  }

  Widget _content(CoopInviteDetail detail) {
    final CoopInviteRow r = detail.row;
    final _Tone tone = _toneOf(r.status);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space6,
      ),
      children: <Widget>[
        if (_actionError.isNotEmpty) _inlineNote(_actionError, isError: true),
        _header(r, tone),
        _cover(r, tone),
        _meta(r),
        _termsCard(r, detail.slots),
        _messageCard(r),
        if (r.status == 1 && !r.legacyReadonly) _opsCard(r),
        _actionBar(r),
      ],
    );
  }

  // ------------------------------------------------------------ 顶部与元信息

  Widget _header(CoopInviteRow r, _Tone tone) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String peer = (r.partnerName ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(
        top: CyTokens.space4,
        bottom: CyTokens.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              coopInvitationStatus(context, r.status),
              style: text.titleLarge?.copyWith(
                fontSize: CyTokens.typePageTitle,
                fontWeight: FontWeight.w700,
                color: _toneColor(tone, palette),
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          Text(
            _sent ? stringsOf(context).coopDetailSentPeer(peer.isEmpty ? stringsOf(context).coopDetailPeer : peer) : stringsOf(context).coopDetailReceivedPeer(peer.isEmpty ? stringsOf(context).coopDetailPeer : peer),
            style: text.bodySmall?.copyWith(color: palette.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 封面。★ 取不到图就留一块兜底底色(小程序 `cover` 块恒在,没有图也不塌),
  ///   终态压暗一档 —— 与可操作的状态分开,但条款仍完整显示。
  Widget _cover(CoopInviteRow r, _Tone tone) {
    return Opacity(
      opacity: tone == _Tone.closed ? 0.55 : 1,
      child: AspectRatio(
        aspectRatio: 2,
        child: CyNetImage(
          r.coverUrl,
          width: double.infinity,
          height: double.infinity,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        ),
      ),
    );
  }

  Widget _meta(CoopInviteRow r) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String countdown = coopDetailCountdown(context, r, DateTime.now());
    final String contact = r.partnerContact;
    final String peerPhone = r.partnerPhone ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (coopDetailTopic(context, r).isNotEmpty)
            Text(
              coopDetailTopic(context, r),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          if (countdown.isNotEmpty)
            _metaLine(countdown, palette, text, top: CyTokens.space1),
          _metaLine(coopDetailInviteType(context, r), palette, text, top: CyTokens.space1),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  stringsOf(context).coopContactDetails,
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: Text(
                    // 联系方式给不给由后端定(§3.8 只在已接受时下发)。
                    // 没下发就**照实说明**,不留空、也不假装有。
                    contact.isNotEmpty
                        ? contact
                        : (r.status == 0 ? stringsOf(context).coopDetailContactPending : stringsOf(context).coopDetailContactWithheld),
                    style: text.labelMedium?.copyWith(
                      fontWeight: contact.isNotEmpty
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: contact.isNotEmpty
                          ? palette.textPrimary
                          : palette.textTertiary,
                    ),
                  ),
                ),
                if (peerPhone.isNotEmpty)
                  CupertinoButton(
                    key: const Key('coop-detail-copy-phone'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                    ),
                    onPressed: () => _copyPhone(peerPhone),
                    child: Text(
                      stringsOf(context).coopCopy,
                      style: text.bodySmall?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaLine(
    String value,
    CyPalette palette,
    TextTheme text, {
    required double top,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Text(
        value,
        style: text.bodySmall?.copyWith(color: palette.textTertiary),
      ),
    );
  }

  Future<void> _copyPhone(String phone) async {
    try {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).coopCopied);
    } catch (_) {
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).coopCopyFailed, isError: true);
    }
  }

  // ------------------------------------------------------------ 条款与留言

  Widget _termsCard(CoopInviteRow r, Map<String, dynamic>? slots) {
    final String slot = coopDetailSlot(context, r, slots);
    return _card(<Widget>[
      _cardTitle(stringsOf(context).coopDetailTerms),
      _kv(stringsOf(context).coopDetailSupplyTier, coopDetailInviteType(context, r)),
      _kv(stringsOf(context).coopDetailRevenue, coopDetailTerms(context, r) ?? '—'),
      if (slot.isNotEmpty) _kv(stringsOf(context).coopDetailSlots, slot),
      _kv(
        stringsOf(context).coopDetailDeposit,
        // 保证金单独给强调色:它是唯一一条要掏钱的。
        coopDetailDeposit(context, r).isEmpty ? stringsOf(context).coopNone : coopDetailDeposit(context, r),
        strong: coopDetailDeposit(context, r).isNotEmpty,
        strongColor: CyPalette.of(context).statusDanger,
      ),
    ]);
  }

  Widget _messageCard(CoopInviteRow r) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String message = (r.message ?? '').trim();
    final String reason = (r.handleReason ?? '').trim();
    final String? label = _draftLabel(r);
    return _card(<Widget>[
      _cardTitle(stringsOf(context).coopMessage),
      if (message.isNotEmpty) _bubble(message, stringsOf(context).coopPeerTime(r.timeText)),
      // 对方处理时给的理由:「已拒绝 / 已撤回」最该被看见的就是这句。
      if (reason.isNotEmpty) _bubble(reason, stringsOf(context).coopDecisionReason, raised: true),
      if (message.isEmpty && reason.isEmpty)
        Text(
          stringsOf(context).coopNoMessage,
          style: text.bodySmall?.copyWith(color: palette.textTertiary),
        ),
      if (label != null) ...<Widget>[
        Text(
          label,
          style: text.bodySmall?.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: CyTokens.space2),
        CupertinoTextField(
          key: const Key('coop-detail-draft'),
          controller: _draft,
          maxLength: 100,
          maxLines: 4,
          placeholder: _draftPlaceholder(r),
          placeholderStyle: TextStyle(color: palette.textTertiary),
          onChanged: (_) => setState(() => _draftError = ''),
          padding: const EdgeInsets.all(CyTokens.space3),
          decoration: BoxDecoration(
            color: palette.bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          ),
        ),
        if (_draftError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 小程序那份内联错误件带一个固定标题。别省成一行红字:
                // 标题说的是**该做什么**,下面那句才说为什么。
                Text(
                  stringsOf(context).coopWithdrawReasonRequired,
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.statusDanger,
                  ),
                ),
                Text(
                  _draftError,
                  style: text.bodySmall?.copyWith(color: palette.statusDanger),
                ),
              ],
            ),
          ),
      ] else if (r.status != 0 && r.status != 1)
        Text(
          stringsOf(context).coopExpiredNoMessage,
          style: text.bodySmall?.copyWith(color: palette.textTertiary),
        ),
    ]);
  }

  /// 只给**真的发得出去**的输入框。三种输入态里 App 支持两档:
  /// 回复(收件箱待确认,选填,随接受/拒绝一起发出)与撤回理由(发件箱待确认,必填)。
  ///
  /// ⚠️ 小程序还有第三档「已接受的留言(选填)」,但那份 draft 在整页里**没有任何
  ///   提交点**(只有 `_post` 读它,而已接受态的四个动作都不走 `_post`)——
  ///   收了话却发不出去。App 不复制这个假输入:已接受后要和对方说话,走「联系合作方」。
  String? _draftLabel(CoopInviteRow r) {
    if (r.legacyReadonly) return null;
    if (r.status == 0 && !_sent) return stringsOf(context).coopReplyOptional;
    if (r.status == 0 && _sent) return stringsOf(context).coopWithdrawReason;
    return null;
  }

  String _draftPlaceholder(CoopInviteRow r) =>
      (_sent && r.status == 0) ? stringsOf(context).coopWithdrawReasonPlaceholder : stringsOf(context).coopDecisionReasonPlaceholder;

  Widget _bubble(String value, String footNote, {bool raised = false}) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: CyTokens.space2),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: raised ? palette.bgSurfaceStrong : palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: text.bodySmall),
          if (footNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                footNote,
                style: text.bodySmall?.copyWith(color: palette.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- 已接受的合作操作

  /// 已接受卡上搬来的履约动作,按「列表行」收纳在此(联系合作方 / 申报供给 /
  /// 评价 / 发件箱的取消合作)。底部动作条只留 ≤2 并排 —— 不把动作堆成弹窗按钮。
  Widget _opsCard(CoopInviteRow r) {
    // 评价的两侧口径与小程序一致:收件箱评发起方;发件箱只有商家对象可评
    // (俱乐部没有 memberId 语义)。
    final bool canReview = !_sent || r.toType == 'merchant';
    return _card(<Widget>[
      _cardTitle(stringsOf(context).coopActions),
      _opRow(
        key: const Key('coop-detail-contact'),
        label: stringsOf(context).coopContactPartner,
        onTap: _busy ? null : () => _contact(r),
      ),
      _opRow(
        key: const Key('coop-detail-perk'),
        label: stringsOf(context).coopDetailSupply,
        onTap: _busy ? null : () => _openPerkPick(r),
      ),
      if (canReview)
        _opRow(
          key: const Key('coop-detail-review'),
          label: stringsOf(context).coopReview,
          onTap: _busy ? null : () => _review(r),
        ),
      // 信誉与评价同一把闸:问的都是会员语义的 memberId,
      // 发件箱里的俱乐部对象没有这个语义(见上面 canReview 注释)。
      if (canReview)
        _opRow(
          key: const Key('coop-detail-peer-credit'),
          label: stringsOf(context).coopPartnerReputation,
          onTap: _busy ? null : () => _openPeerCredit(r),
        ),
      // 取消合作是涉资动作(锁价前可取消并退保证金):锁价后按后端 termsFrozen
      // 置灰,只做说明不发请求。★ 只在发件箱给 —— 小程序同此。
      if (_sent && !r.termsFrozen)
        _opRow(
          key: const Key('coop-detail-cancel'),
          label: stringsOf(context).coopCancelCooperation,
          danger: true,
          onTap: _busy ? null : () => _cancelAccepted(r),
        ),
      if (_sent && r.termsFrozen)
        _opRow(
          label: stringsOf(context).coopCancelCooperation,
          hint: stringsOf(context).coopDetailLockedHint,
          onTap: () => setState(() {
            _actionError = stringsOf(context).coopDetailLockedError;
          }),
        ),
    ]);
  }

  Widget _opRow({
    Key? key,
    required String label,
    String? hint,
    bool danger = false,
    VoidCallback? onTap,
  }) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return CupertinoButton(
      key: key,
      minimumSize: const Size.fromHeight(48),
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      onPressed: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: danger ? palette.statusDanger : palette.textPrimary,
              ),
            ),
          ),
          if (hint != null)
            Text(
              hint,
              style: text.bodySmall?.copyWith(color: palette.textTertiary),
            )
          else
            Icon(
              CupertinoIcons.chevron_forward,
              size: 18,
              color: palette.textTertiary,
            ),
        ],
      ),
    );
  }

  Future<void> _contact(CoopInviteRow r) => RequestSessionScope.run(
    _requestScope,
    () => _contactScoped(r),
  );

  Future<void> _contactScoped(CoopInviteRow r) async {
    setState(() {
      _busy = true;
      _actionError = '';
    });
    try {
      final int conversationId = await ref.read(coopApiProvider).contact(r.id);
      if (!mounted) return;
      context.push('/im/chat/$conversationId');
    } catch (e) {
      // 后端的五道闸文案很具体(「仅已合作可联系」…),原样透出。
      if (!mounted) return;
      setState(
        () => _actionError = coopErrorSub(e, context: context),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPerkPick(CoopInviteRow r) async {
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.18,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              CoopPerkPickSheet(
                inviteId: r.id,
                scrollController: scrollController,
              ),
    );
  }

  Future<void> _review(CoopInviteRow r) async {
    // 被评对象与卡片搬迁前一致:收件箱评发起方(fromId),发件箱只对商家评(toId)。
    final int? toId = _sent
        ? (r.toType == 'merchant' ? r.toId : null)
        : r.fromId;
    final int? topicId = r.topicId;
    if (toId == null || topicId == null) {
      CyNativeNotice.show(context, stringsOf(context).coopReviewUnavailable);
      return;
    }
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.26,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              CoopReviewSheet(
                topicId: topicId,
                toId: toId,
                scrollController: scrollController,
              ),
    );
  }

  /// 合作方信誉:履约率(`/api/coop/credit`)+ 评价摘要(`/api/coop/review/summary`)。
  Future<void> _openPeerCredit(CoopInviteRow r) async {
    // 被查对象与 [_review] 的被评对象一致:收件箱查发起方(fromId),
    // 发件箱只有商家对象有 memberId 语义(查 toId)。
    final int? peerId = _sent
        ? (r.toType == 'merchant' ? r.toId : null)
        : r.fromId;
    if (peerId == null) return;
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.42,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              CoopPeerCreditSheet(
                peerId: peerId,
                scrollController: scrollController,
              ),
    );
  }

  /// 取消一个**已接受**的合作。★ 后端拒空理由,所以这里也不放空的过去;
  /// 锁价后后端拒单方取消,不发请求只说明(由 [_opsCard] 分流)。
  Future<void> _cancelAccepted(CoopInviteRow r) async {
    final String? reason = await showCupertinoDialog<String>(
      context: context,
      builder: (BuildContext c) => CoopReasonDialog(
        action: CoopHandleAction.cancel,
        // 撤回/取消前必须把退保证金的界说清 —— 用户是据此决定要不要取消的。
        content: stringsOf(context).coopDetailCancelTerms,
        placeholder: stringsOf(context).coopCancellationReason,
        confirmText: stringsOf(context).coopSubmitCancellation,
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _post(r, CoopHandleAction.cancel, reason.trim());
  }

  // ---------------------------------------------------------------- 底部动作

  Widget _actionBar(CoopInviteRow r) {
    if (r.legacyReadonly) {
      return _deadNote(stringsOf(context).coopLegacyReadOnly);
    }
    // 待确认:收件箱给两个(拒绝次要 / 接受实心),发件箱只能撤回(单动作不给实心)。
    if (r.status == 0 && !_sent) {
      return Row(
        children: <Widget>[
          Expanded(
            child: CyNativeButton(
              key: const Key('coop-detail-reject'),
              label: stringsOf(context).coopReject,
              role: CyNativeButtonRole.destructive,
              onPressed: _submitting ? null : () => _reject(r),
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: CyNativeButton(
              key: const Key('coop-detail-accept'),
              label: stringsOf(context).coopAccept,
              loading: _submitting,
              onPressed: _submitting ? null : () => _accept(r),
            ),
          ),
        ],
      );
    }
    if (r.status == 0 && _sent) {
      return CyNativeButton(
        key: const Key('coop-detail-withdraw'),
        label: stringsOf(context).coopWithdrawInvite,
        role: CyNativeButtonRole.secondary,
        width: double.infinity,
        loading: _submitting,
        onPressed: _submitting ? null : () => _withdraw(r),
      );
    }
    if (r.status == 1) {
      // 欠保证金时给唯一实心入口(搬走的动作在上面那组列表行里)。
      if (r.depositOwed) {
        return CyNativeButton(
          key: const Key('coop-detail-deposit'),
          label: stringsOf(context).coopDetailPayDeposit,
          width: double.infinity,
          onPressed: _goDeposit,
        );
      }
      return _deadNote(stringsOf(context).coopDetailOngoing);
    }
    return _deadNote(stringsOf(context).coopExpiredNoActions);
  }

  Widget _deadNote(String text) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
      ),
    );
  }

  Widget _inlineNote(String text, {bool isError = false}) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space3),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isError ? palette.statusDanger : palette.textSecondary,
        ),
      ),
    );
  }

  /// 保证金是**涉资链路**(建单 + 微信支付 + 服务端回读),只在「我的合作」列表里
  /// 有一份 —— 这里不复制第二份,把人带回那条链路(发件箱的邀约回列表仍停在
  /// 「我发出的」,否则会找不到那张卡)。小程序 `goDeposit` 同此。
  void _goDeposit() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(_sent ? '/coop/list?tab=sent' : '/coop/list');
  }

  // ------------------------------------------------------------------ 三个决策

  Future<void> _accept(CoopInviteRow r) async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopAccept,
      content: stringsOf(context).coopDetailAcceptTerms,
      confirmText: stringsOf(context).coopAccept,
      cancelText: stringsOf(context).coopThinkAgain,
    );
    if (!ok) return;
    await _post(r, CoopHandleAction.accept, _draft.text.trim());
  }

  Future<void> _reject(CoopInviteRow r) async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopRejectInvitation,
      content: stringsOf(context).coopDetailRejectTerms,
      confirmText: stringsOf(context).coopReject,
      cancelText: stringsOf(context).coopThinkAgain,
      danger: true,
    );
    if (!ok) return;
    await _post(r, CoopHandleAction.reject, _draft.text.trim());
  }

  /// 撤回必须带理由:对方拿着这句话才知道下一步该怎么改。
  /// 长说明落在字段旁边(`_draftError`),提示只做一句短话。
  Future<void> _withdraw(CoopInviteRow r) async {
    final String reason = _draft.text.trim();
    if (reason.isEmpty) {
      setState(() => _draftError = stringsOf(context).coopReasonHelps);
      CyNativeNotice.show(context, stringsOf(context).coopWriteWithdrawReason, isError: true);
      return;
    }
    setState(() => _draftError = '');
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopWithdrawInvite,
      content: stringsOf(context).coopWithdrawInviteHint,
      confirmText: stringsOf(context).coopWithdrawInvite,
      cancelText: stringsOf(context).coopThinkAgain,
      danger: true,
    );
    if (!ok) return;
    await _post(r, CoopHandleAction.cancel, reason);
  }

  /// 三个决策都走 `POST /api/coop/handle`(理由的字段名按动作分岔,见 [CoopApi])。
  ///
  /// ★ 回执不等于状态:提交成功后**重新问服务端要一次**,拿它回的状态渲染,
  ///   不本地假设成功后的样子(小程序同此)。
  Future<void> _post(
    CoopInviteRow r,
    CoopHandleAction action,
    String reason,
  ) => RequestSessionScope.run(
    _requestScope,
    () => _postScoped(r, action, reason),
  );

  Future<void> _postScoped(
    CoopInviteRow r,
    CoopHandleAction action,
    String reason,
  ) async {
    setState(() {
      _submitting = true;
      _actionError = '';
    });
    try {
      await ref
          .read(coopApiProvider)
          .handleInvite(
            inviteId: r.id,
            action: action,
            reason: reason.isEmpty ? null : reason,
          );
      if (!mounted) return;
      _draft.clear();
      ref.invalidate(
        coopInviteDetailProvider(
          CoopInviteDetailKey(inviteId: r.id, sent: _sent),
        ),
      );
      CyNativeNotice.show(context, stringsOf(context).coopSubmitted);
    } catch (e) {
      if (!mounted) return;
      // 后端的话原样透出 —— 「历史商家节点邀约仅供查看，不能再处理」这类
      // 判据由它说,换成笼统的「提交失败」用户不知道该怎么办。
      CyNativeNotice.show(
        context,
        coopErrorSub(e, context: context),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // -------------------------------------------------------------------- 小件

  /// 卡片。★ 底色 / 描边都从 [CyPalette] 取 —— 写死 token 会在商家浅色页上
  /// 变成「白底黑卡」(门禁 light_pages_no_static_colors 抓的就是这个)。
  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _cardTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _kv(
    String label,
    String value, {
    bool strong = false,
    Color? strongColor,
  }) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            label,
            style: text.bodySmall?.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: strong ? (strongColor ?? palette.textPrimary) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 合作方信誉浮层:履约率(`/api/coop/credit`)+ 评价摘要(`/api/coop/review/summary`)。
///
/// ★ 两条端点**打开才拉**:详情页顺手拉的话,「只想看看详情」的用户也要
///   多付两次往返 —— 信誉只有真想看的人才需要。
class CoopPeerCreditSheet extends ConsumerStatefulWidget {
  const CoopPeerCreditSheet({
    super.key,
    required this.peerId,
    required this.scrollController,
  });

  final int peerId;
  final ScrollController scrollController;

  @override
  ConsumerState<CoopPeerCreditSheet> createState() =>
      _CoopPeerCreditSheetState();
}

class _CoopPeerCreditSheetState extends ConsumerState<CoopPeerCreditSheet> {
  bool _loading = true;
  Map<String, dynamic> _credit = const <String, dynamic>{};
  Map<String, dynamic> _summary = const <String, dynamic>{};
  String? _creditError;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _creditError = null;
      _summaryError = null;
    });
    final CoopApi api = ref.read(coopApiProvider);
    // 一次并行拉两条:它们是两块独立数据,串行只会让浮层多转一圈。
    // 失败**各归各的**——整页一个 Future.wait 的话,一条挂了就整块错误态,
    // 另一条已到达的数据被白白丢弃(b1 报告 P2-2)。
    final Future<void> creditLoad = api
        .creditSummary(memberId: widget.peerId)
        .then((Map<String, dynamic> data) {
          if (!mounted) return;
          // mybiz 把同族的 credit 嵌在 `credit` 键里下发;两种形态都认,字段名不变。
          setState(
            () => _credit = data['credit'] as Map<String, dynamic>? ?? data,
          );
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(() => _creditError = coopErrorSub(e, context: context));
        });
    final Future<void> summaryLoad = api
        .reviewSummary(widget.peerId)
        .then((Map<String, dynamic> data) {
          if (!mounted) return;
          setState(
            () => _summary =
                data['summary'] as Map<String, dynamic>? ??
                const <String, dynamic>{},
          );
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(() => _summaryError = coopErrorSub(e, context: context));
        });
    await Future.wait(<Future<void>>[creditLoad, summaryLoad]);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final Object? rate = _credit['fulfillmentRate'];
    final int violations = (_credit['violationCount'] as num?)?.toInt() ?? 0;
    final Object? avg = _summary['avg'];
    final int reviewCount = (_summary['count'] as num?)?.toInt() ?? 0;
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).coopPartnerReputation)),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(CyTokens.pageX),
          children: <Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              stringsOf(context).coopReputationSource,
              style: text.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: CyTokens.space3),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_creditError != null && _summaryError != null) ...<Widget>[
              // 两条都挂才是整块错误态;只挂一条时好的一半照常上屏。
              Text(
                stringsOf(context).coopDetailBothErrors(_creditError!, _summaryError!),
                key: const Key('coop-peer-credit-error'),
                // 错误文案在浅色语境(商家视角)下要用浅色那档红,
                // 不能用 CyTokens 的暗色编译期常量。
                style: text.bodySmall?.copyWith(color: palette.statusDanger),
              ),
              const SizedBox(height: CyTokens.space2),
              // 成件按钮(内容宽、左对齐),不是居中裸文字 —— 居中一行
              // 文字是 hero 排版,iOS 动作按钮跟内容走。
              CyNativeButton(
                key: const Key('coop-peer-credit-retry'),
                label: stringsOf(context).retry,
                role: CyNativeButtonRole.secondary,
                onPressed: _load,
              ),
            ] else if (_credit.isEmpty &&
                _summary.isEmpty &&
                _creditError == null &&
                _summaryError == null)
              // 空态要说清「查了,没有」,不能拿「—」占位充数 ——
              // 破折号分不清「没记录」和「数据坏了」。
              Text(
                stringsOf(context).coopNoReputation,
                key: const Key('coop-peer-credit-empty'),
                style: text.bodySmall?.copyWith(color: palette.textSecondary),
              )
            else
              // 两行在**一个**分组卡里:label 左 / 值右,行间发丝线 ——
              // iOS KV 列表质感,不是两块各抱一个圆角小条。
              // 挂掉的那一行就地显示错误 + 重试,不连坐另一半。
              Container(
                decoration: BoxDecoration(
                  color: palette.bgSurface,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  // 暗端=1px 描边,浅端(商家)=白卡+投影,取 token 分工。
                  border: Border.all(
                    color: palette.cardBorder,
                    width: palette.cardBorder == Colors.transparent ? 0 : 1,
                  ),
                  boxShadow: palette.cardShadow,
                ),
                child: Column(
                  children: <Widget>[
                    if (_creditError != null)
                      _failedRow(
                        label: stringsOf(context).coopPerformanceRate,
                        keyPrefix: 'coop-peer-credit-fulfill',
                        error: _creditError!,
                      )
                    else
                      _statRow(
                        label: stringsOf(context).coopPerformanceRate,
                        value: rate == null ? '—' : '$rate%',
                        note: violations > 0 ? stringsOf(context).coopDetailViolations(violations) : null,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: CyTokens.space3),
                      child: Container(height: 1, color: palette.borderSubtle),
                    ),
                    if (_summaryError != null)
                      _failedRow(
                        label: stringsOf(context).coopReviews,
                        keyPrefix: 'coop-peer-credit-review',
                        error: _summaryError!,
                      )
                    else
                      _statRow(
                        label: stringsOf(context).coopReviews,
                        value: reviewCount == 0
                            ? stringsOf(context).coopNoReviews
                            : (avg is num
                                  ? stringsOf(context).coopDetailRating(avg.toDouble().toStringAsFixed(1))
                                  : '—'),
                        note: reviewCount == 0 ? null : stringsOf(context).coopDetailReviewCount(reviewCount),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 单条拉挂时那一行的样子:label 照常,值位换成「说人话」的错误 + 就地重试。
  Widget _failedRow({
    required String label,
    required String keyPrefix,
    required String error,
  }) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      alignment: Alignment.center,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
          Flexible(
            child: Text(
              error,
              key: Key('$keyPrefix-error'),
              textAlign: TextAlign.right,
              style: text.bodySmall?.copyWith(color: palette.statusDanger),
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          CyNativeButton(
            key: Key('$keyPrefix-retry'),
            label: stringsOf(context).retry,
            role: CyNativeButtonRole.secondary,
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _statRow({
    required String label,
    required String value,
    String? note,
  }) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      alignment: Alignment.center,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
          Text(
            value,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(width: CyTokens.space2),
            Text(
              note,
              style: text.bodySmall?.copyWith(color: palette.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
