import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../map/map_controller.dart';

/// 主办方侧:我发布的这条路线下,商家的章节承接申请。
///
/// ★ 「谁发布谁审核」—— 这三条接口(owner-list / audit / invitable+invite)
///   都只有**主题原发布者**能调。不是发布者时:
///     · owner-list 抛业务错误(照原文显示);
///     · invitable **返回空列表**而不是报错 —— 所以空名单**不能**说成
///       「没有可邀请的商家」,那句话我们并不知道是不是真的。
final topicChapterApplicationsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, int topicId) {
      return ref
          .watch(merchantApiProvider)
          .chapterApplicationsForTopic(topicId);
    });

/// 可邀请的商家。定位是**选填**:取不到就不传,服务端明确「不当错误」,
/// 只是不再按距离排序 —— 所以这里绝不能因为定位失败就把功能拦住。
final invitableMerchantsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, int topicId) async {
      double? lat;
      double? lng;
      try {
        final loc = await ref.watch(currentMapLocationProvider.future);
        lat = loc.latitude;
        lng = loc.longitude;
      } catch (_) {
        // 拒授权 / 取不到:照样出名单,只是不排距离。
      }
      return ref
          .watch(merchantApiProvider)
          .invitableMerchants(topicId, latitude: lat, longitude: lng);
    });

/// 主办方侧:我发布的这条路线下**待审的商家点位**。
///
/// ★ 与章节申请是两条不同的链路(小程序 `merchantinfo.js:1377` 也是分开拉的):
///   申请审的是「这家能不能接这一章」,点位审的是「这家交上来的内容对不对」。
final pendingChapterNodesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, int topicId) {
      return ref.watch(merchantApiProvider).pendingChapterNodes(topicId);
    });

class TopicChapterApplicationsPage extends ConsumerStatefulWidget {
  const TopicChapterApplicationsPage({super.key, required this.topicId});

  final int topicId;

  @override
  ConsumerState<TopicChapterApplicationsPage> createState() =>
      _TopicChapterApplicationsPageState();
}

class _TopicChapterApplicationsPageState
    extends ConsumerState<TopicChapterApplicationsPage> {
  String _active = 'applications';
  bool _invitableVisited = false;
  bool _nodesVisited = false;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantOwnerReviewTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  CyTokens.space2,
                ),
                child: CyTabs(
                  variant: CyTabsVariant.segmented,
                  tabs: <CyTab>[
                    CyTab(key: 'applications', label: stringsOf(context).merchantOwnerReviewApplications),
                    CyTab(key: 'nodes', label: stringsOf(context).merchantOwnerReviewNodes),
                    CyTab(key: 'invitable', label: stringsOf(context).merchantOwnerReviewInvitable),
                  ],
                  active: _active,
                  onChanged: (String value) => setState(() {
                    _active = value;
                    if (value == 'invitable') _invitableVisited = true;
                    if (value == 'nodes') _nodesVisited = true;
                  }),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: switch (_active) {
                    'nodes' => 1,
                    'invitable' => 2,
                    _ => 0,
                  },
                  children: <Widget>[
                    _ApplicationsTab(topicId: widget.topicId),
                    _nodesVisited
                        ? _PendingNodesTab(topicId: widget.topicId)
                        : const SizedBox.shrink(),
                    _invitableVisited
                        ? _InvitableTab(topicId: widget.topicId)
                        : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicationsTab extends ConsumerWidget {
  const _ApplicationsTab({required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Map<String, dynamic>>> async = ref.watch(
      topicChapterApplicationsProvider(topicId),
    );
    return async.when(
      loading: () => const CySkeleton(),
      error: (Object e, StackTrace _) => StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: stringsOf(context).merchantOwnerReviewListError,
        sub: e.toString().replaceFirst('Exception: ', ''),
        large: true,
        onRetry: () =>
            ref.invalidate(topicChapterApplicationsProvider(topicId)),
      ),
      data: (List<Map<String, dynamic>> rows) {
        if (rows.isEmpty) {
          return StatusView(
            key: Key('owner-applications-empty'),
            icon: CupertinoIcons.tray,
            message: stringsOf(context).merchantOwnerReviewListEmpty,
            sub: stringsOf(context).merchantOwnerReviewListEmptyHint,
            large: true,
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async =>
              ref.invalidate(topicChapterApplicationsProvider(topicId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(CyTokens.pageX),
            itemCount: rows.length,
            itemBuilder: (_, int i) =>
                _ApplicationRow(topicId: topicId, row: rows[i]),
          ),
        );
      },
    );
  }
}

class _ApplicationRow extends ConsumerStatefulWidget {
  const _ApplicationRow({required this.topicId, required this.row});

  final int topicId;
  final Map<String, dynamic> row;

  @override
  ConsumerState<_ApplicationRow> createState() => _ApplicationRowState();
}

class _ApplicationRowState extends ConsumerState<_ApplicationRow> {
  bool _busy = false;

  int get _id => (widget.row['id'] as num?)?.toInt() ?? 0;

  /// 0 待审核 / 1 已通过 / 2 已拒绝。★ **缺席保持 null** ——
  /// 兜 0 会把"没拿到"渲成"待审核",于是摆出一对通过/拒绝按钮。
  int? get _status => (widget.row['status'] as num?)?.toInt();

  Future<void> _audit(bool approve) async {
    final strings = stringsOf(context);
    String? reason;
    if (!approve) {
      reason = await _askReason();
      if (reason == null || !mounted) return;
    } else {
      final bool ok = await cyConfirm(
        context,
        title: stringsOf(context).merchantOwnerReviewApproveTitle,
        content: stringsOf(context).merchantResidualPolicyApprove,
        confirmText: stringsOf(context).merchantOwnerReviewApprove,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    String text;
    bool isError = false;
    try {
      await ref
          .read(merchantApiProvider)
          .auditChapterApplication(
            applicationId: _id,
            approve: approve,
            reason: reason,
          );
      text = approve ? strings.merchantOwnerReviewApproved : strings.merchantOwnerReviewDeclined;
    } on MerchantApiException catch (e) {
      text = e.message;
      isError = true;
    } catch (e) {
      text = e.toString().replaceFirst('Exception: ', '');
      isError = true;
    } finally {
      ref.invalidate(topicChapterApplicationsProvider(widget.topicId));
      ref.invalidate(invitableMerchantsProvider(widget.topicId));
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    CyNativeNotice.show(context, text, isError: isError);
  }

  /// 拒绝必须给理由 —— 只说「已拒绝」,商家不知道改什么就只能反复重投。
  Future<String?> _askReason() => askOwnerRejectReason(
    context,
    title: stringsOf(context).merchantOwnerReviewReasonTitle,
    placeholder: stringsOf(context).merchantOwnerReviewReasonHint,
    confirmLabel: stringsOf(context).merchantOwnerReviewDeclineConfirm,
  );

  String get _statusText {
    switch (_status) {
      case 0:
        return stringsOf(context).merchantOwnerReviewPending;
      case 1:
        return stringsOf(context).merchantOwnerReviewApproved;
      case 2:
        return stringsOf(context).merchantOwnerReviewDeclined;
      default:
        return stringsOf(context).merchantOwnerReviewUnknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> r = widget.row;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final bool invited = (r['source'] as num?)?.toInt() == 1;
    final String remark = (r['auditRemark'] ?? '').toString().trim();
    final String message = (r['message'] ?? '').toString().trim();

    return Container(
      key: Key('owner-application-$_id'),
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  (r['merchantName'] ?? '').toString().trim().isEmpty
                      ? stringsOf(context).merchantOwnerReviewUnnamedMerchant
                      : r['merchantName'].toString().trim(),
                  style: t.titleSmall,
                ),
              ),
              Text(
                _statusText,
                style: t.labelSmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            (r['chapterName'] ?? '').toString().trim().isEmpty
                ? stringsOf(context).merchantOwnerReviewUnnamedChapter
                : r['chapterName'].toString().trim(),
            style: t.bodySmall?.copyWith(color: p.textSecondary),
          ),
          // 邀请来的和自己申请来的要分开说 —— 前者是我自己邀的,已经预先批准。
          if (invited)
            Text(
              stringsOf(context).merchantOwnerReviewInvited,
              style: t.bodySmall?.copyWith(color: p.textTertiary),
            ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(stringsOf(context).merchantOwnerReviewMessage(message), style: t.bodySmall),
            ),
          if (remark.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(stringsOf(context).merchantOwnerReviewRemark(remark), style: t.bodySmall),
            ),
          // ★ 只有**待审核**的才摆按钮。已通过/已拒绝的再点必被服务端拒;
          //   状态未知的更不能摆 —— 我们连它在哪一档都不知道。
          if (_status == 0) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: CyNativeButton(
                    key: Key('owner-reject-$_id'),
                    onPressed: _busy ? null : () => _audit(false),
                    label: stringsOf(context).merchantOwnerReviewDecline,
                    role: CyNativeButtonRole.secondary,
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: CyNativeButton(
                    key: Key('owner-approve-$_id'),
                    onPressed: _busy ? null : () => _audit(true),
                    label: stringsOf(context).merchantOwnerReviewApprove,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 驳回/婉拒必须给理由 —— 只说「已拒绝」,商家不知道改什么就只能反复重投。
/// 章节申请与商家点位共用这一张半屏(小程序侧也是同一个可编辑 modal)。
Future<String?> askOwnerRejectReason(
  BuildContext context, {
  required String title,
  required String placeholder,
  required String confirmLabel,
}) async {
  final TextEditingController c = TextEditingController();
  final String? r = await showCupertinoSheet<String>(
    context: context,
    showDragHandle: true,
    topGap: 0.36,
    scrollableBuilder:
        (BuildContext ctx, ScrollController scrollController) =>
            StatefulBuilder(
              builder: (BuildContext ctx, StateSetter setSheetState) {
                final CyPalette p = CyPalette.of(ctx);
                final TextTheme t = Theme.of(ctx).textTheme;
                return CupertinoPageScaffold(
                  backgroundColor: p.bgPage,
                  resizeToAvoidBottomInset: true,
                  navigationBar: CupertinoNavigationBar(
                    middle: Text(title),
                    leading: CupertinoButton(
                      key: const Key('owner-reject-cancel'),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(stringsOf(context).merchantOwnerReviewCancel),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: ListView(
                      controller: scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        CyTokens.pageX,
                        CyTokens.space4,
                        CyTokens.pageX,
                        CyTokens.space4 + MediaQuery.viewInsetsOf(ctx).bottom,
                      ),
                      children: <Widget>[
                        CyField(
                          label: stringsOf(context).merchantOwnerReviewReasonLabel,
                          child: Semantics(
                            label: stringsOf(context).merchantOwnerReviewReasonSemantics,
                            textField: true,
                            child: CupertinoTextField(
                              key: const Key('owner-reject-reason'),
                              controller: c,
                              autofocus: true,
                              minLines: 3,
                              maxLines: 5,
                              maxLength: 200,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              textCapitalization: TextCapitalization.sentences,
                              placeholder: placeholder,
                              placeholderStyle: t.bodyMedium?.copyWith(
                                color: p.textPlaceholder,
                              ),
                              style: t.bodyMedium?.copyWith(
                                color: p.textPrimary,
                              ),
                              padding: const EdgeInsets.all(CyTokens.space3),
                              decoration: BoxDecoration(
                                color: p.inputBgEmpty,
                                border: Border.all(color: p.borderSubtle),
                                borderRadius: BorderRadius.circular(
                                  CyTokens.radiusMd,
                                ),
                              ),
                              onChanged: (_) => setSheetState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: CyTokens.space3),
                        CupertinoButton(
                          key: const Key('owner-reject-confirm'),
                          minimumSize: const Size.fromHeight(44),
                          color: CyPalette.of(context).statusDanger,
                          disabledColor: p.bgSubtle,
                          foregroundColor: c.text.trim().isEmpty
                              ? p.textPlaceholder
                              : p.textInverse,
                          onPressed: c.text.trim().isEmpty
                              ? null
                              : () => Navigator.of(ctx).pop(c.text.trim()),
                          child: Text(confirmLabel),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
  );
  c.dispose();
  return r;
}

/// 主办方侧:商家交上来(或改过)的点位,等我过一道内容准入。
class _PendingNodesTab extends ConsumerWidget {
  const _PendingNodesTab({required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Map<String, dynamic>>> async = ref.watch(
      pendingChapterNodesProvider(topicId),
    );
    return async.when(
      loading: () => const CySkeleton(),
      error: (Object e, StackTrace _) => StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: stringsOf(context).merchantOwnerReviewNodesError,
        sub: e.toString().replaceFirst('Exception: ', ''),
        large: true,
        onRetry: () => ref.invalidate(pendingChapterNodesProvider(topicId)),
      ),
      data: (List<Map<String, dynamic>> rows) {
        if (rows.isEmpty) {
          // ★ 与「可邀请」同理:读到的空列表不能说成「确实没人交」——
          //   服务端对非发布者也可能是空。
          return StatusView(
            key: Key('owner-pending-nodes-empty'),
            icon: CupertinoIcons.location,
            message: stringsOf(context).merchantOwnerReviewNodesEmpty,
            sub: stringsOf(context).merchantOwnerReviewNodesEmptyHint,
            large: true,
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async =>
              ref.invalidate(pendingChapterNodesProvider(topicId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(CyTokens.pageX),
            itemCount: rows.length,
            itemBuilder: (_, int i) =>
                _PendingNodeRow(topicId: topicId, row: rows[i]),
          ),
        );
      },
    );
  }
}

class _PendingNodeRow extends ConsumerStatefulWidget {
  const _PendingNodeRow({required this.topicId, required this.row});

  final int topicId;
  final Map<String, dynamic> row;

  @override
  ConsumerState<_PendingNodeRow> createState() => _PendingNodeRowState();
}

class _PendingNodeRowState extends ConsumerState<_PendingNodeRow> {
  bool _busy = false;

  int get _id => (widget.row['id'] as num?)?.toInt() ?? 0;

  Future<void> _audit(bool approve) async {
    final strings = stringsOf(context);
    String? reason;
    if (approve) {
      // ★ 「准入,非背书」是小程序的原话(merchantinfo.js:1464 的 modal 文案)——
      //   只说「确认通过」会让主办方以为平台替商家做了担保。
      final bool ok = await cyConfirm(
        context,
        title: stringsOf(context).merchantOwnerReviewNodeApproveTitle,
        content: stringsOf(context).merchantResidualPolicyNodeApprove,
        confirmText: stringsOf(context).merchantOwnerReviewApproveConfirm,
      );
      if (!ok || !mounted) return;
    } else {
      reason = await askOwnerRejectReason(
        context,
        title: stringsOf(context).merchantOwnerReviewNodeRejectTitle,
        placeholder: stringsOf(context).merchantOwnerReviewNodeReasonHint,
        confirmLabel: stringsOf(context).merchantOwnerReviewRejectConfirm,
      );
      if (reason == null || !mounted) return;
    }
    setState(() => _busy = true);
    String text;
    bool isError = false;
    try {
      await ref
          .read(merchantApiProvider)
          .auditChapterNode(nodeId: _id, approve: approve, reason: reason);
      text = approve ? strings.merchantOwnerReviewNodeApproved : strings.merchantOwnerReviewNodeRejected;
    } on MerchantApiException catch (e) {
      // 「承接已失效或未生效,不能编辑节点内容」这类是状态态,不是重试能解决的。
      text = e.message;
      isError = true;
    } catch (e) {
      text = e.toString().replaceFirst('Exception: ', '');
      isError = true;
    } finally {
      ref.invalidate(pendingChapterNodesProvider(widget.topicId));
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    CyNativeNotice.show(context, text, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> r = widget.row;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final String name = (r['name'] ?? '').toString().trim();
    final String address = (r['address'] ?? '').toString().trim();
    final String description = (r['description'] ?? '').toString().trim();

    return Container(
      key: Key('owner-node-$_id'),
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name.isEmpty ? stringsOf(context).merchantOwnerReviewUnnamedNode : name,
            style: t.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                address,
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                description,
                style: t.bodySmall?.copyWith(color: p.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              Expanded(
                child: CyNativeButton(
                  key: Key('owner-node-reject-$_id'),
                  onPressed: _busy ? null : () => _audit(false),
                  label: stringsOf(context).merchantOwnerReviewReject,
                  role: CyNativeButtonRole.secondary,
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              Expanded(
                child: CyNativeButton(
                  key: Key('owner-node-approve-$_id'),
                  onPressed: _busy ? null : () => _audit(true),
                  label: stringsOf(context).merchantOwnerReviewApprove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvitableTab extends ConsumerWidget {
  const _InvitableTab({required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Map<String, dynamic>>> async = ref.watch(
      invitableMerchantsProvider(topicId),
    );
    return async.when(
      loading: () => const CySkeleton(),
      error: (Object e, StackTrace _) => StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: stringsOf(context).merchantOwnerReviewInvitableError,
        sub: e.toString().replaceFirst('Exception: ', ''),
        large: true,
        onRetry: () => ref.invalidate(invitableMerchantsProvider(topicId)),
      ),
      data: (List<Map<String, dynamic>> rows) {
        if (rows.isEmpty) {
          // ★★ 措辞刻意留了余地:服务端对「不是本主题发布者」也返回空列表,
          //   所以这里说不出「确实没有可邀请的商家」这句话。
          return StatusView(
            key: Key('owner-invitable-empty'),
            icon: Icons.person_search_outlined,
            message: stringsOf(context).merchantOwnerReviewInvitableEmpty,
            sub: stringsOf(context).merchantOwnerReviewInvitableEmptyHint,
            large: true,
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async =>
              ref.invalidate(invitableMerchantsProvider(topicId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(CyTokens.pageX),
            itemCount: rows.length,
            itemBuilder: (_, int i) =>
                _InvitableRow(topicId: topicId, row: rows[i]),
          ),
        );
      },
    );
  }
}

class _InvitableRow extends ConsumerStatefulWidget {
  const _InvitableRow({required this.topicId, required this.row});

  final int topicId;
  final Map<String, dynamic> row;

  @override
  ConsumerState<_InvitableRow> createState() => _InvitableRowState();
}

class _InvitableRowState extends ConsumerState<_InvitableRow> {
  bool _busy = false;

  Future<void> _invite() async {
    final strings = stringsOf(context);
    final Map<String, dynamic> r = widget.row;
    final int chapterId = (r['chapterId'] as num?)?.toInt() ?? 0;
    final int memberId = (r['memberId'] as num?)?.toInt() ?? 0;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).merchantOwnerReviewInviteTitle,
      // ★ 邀请 = **预先批准的申请**,比"发个消息"重得多:对方收到就能直接
      //   填供给和点位,不再走一轮审核,而且当场占掉一个名额。
      content:
          '邀请等于预先批准:对方可以直接填供给和点位,不再经过你审核,'
          '同时占掉这一章的一个名额。',
      confirmText: stringsOf(context).merchantOwnerReviewInviteConfirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    String text;
    bool isError = false;
    try {
      await ref
          .read(merchantApiProvider)
          .inviteChapterMerchant(
            chapterId: chapterId,
            merchantMemberId: memberId,
          );
      text = strings.merchantOwnerReviewInviteSuccess;
    } on MerchantApiException catch (e) {
      // 「该商家已有本章节的申请」「名额已满」「不能邀请自己」—— 照原文显示。
      text = e.message;
      isError = true;
    } catch (e) {
      text = e.toString().replaceFirst('Exception: ', '');
      isError = true;
    } finally {
      ref.invalidate(invitableMerchantsProvider(widget.topicId));
      ref.invalidate(topicChapterApplicationsProvider(widget.topicId));
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    CyNativeNotice.show(context, text, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> r = widget.row;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final num? distance = r['distance'] as num?;
    final String address = (r['address'] ?? '').toString().trim();

    return Container(
      key: Key(
        'owner-invitable-${(r['memberId'] ?? 0)}-${(r['chapterId'] ?? 0)}',
      ),
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CyNetImage(
            (r['logo'] ?? '').toString(),
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text((r['name'] ?? stringsOf(context).merchantOwnerReviewUnnamedMerchant).toString(), style: t.titleSmall),
                Text(
                  (r['chapterName'] ?? stringsOf(context).merchantOwnerReviewUnnamedChapter).toString(),
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
                // ★ 地址和距离**拿不到就不显示这一行**。
                //   距离尤其不能兜 0 —— 「0 米」会让人以为就在隔壁。
                if (address.isNotEmpty)
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                if (distance != null)
                  Text(
                    stringsOf(context).merchantOwnerReviewDistance(distance.round()),
                    style: t.bodySmall?.copyWith(color: p.textTertiary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          CyNativeButton(
            key: Key('owner-invite-${(r['memberId'] ?? 0)}'),
            onPressed: _busy ? null : _invite,
            label: stringsOf(context).merchantOwnerReviewInvite,
            role: CyNativeButtonRole.secondary,
          ),
        ],
      ),
    );
  }
}
