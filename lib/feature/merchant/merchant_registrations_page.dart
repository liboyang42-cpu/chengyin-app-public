import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_apply.dart';

/// 我的主题报名。App 侧此前完全没有这一页 ——
/// 商家看不到自己报过哪些主题、有没有被驳回、为什么被驳。
///
/// ★★ 两个状态字段管的不是一件事,合并会同时错两处:
///   · **能不能改** 看 status(0待审/2驳回);
///   · **能不能取消** 看 auditStatus(已中标一律不能取消)。
///   合成一个的话:已中标的会给出取消按钮(点了必报错),
///   或者被驳回的给不出修改按钮 —— 而那正是 update 接口存在的理由。
final merchantRegistrationsProvider = FutureProvider.autoDispose
    .family<List<TopicRegistration>, RegistrationListFilter>((ref, filter) {
      return ref.read(merchantApiProvider).myTopicRegistrations(filter: filter);
    });

class MerchantRegistrationsPage extends ConsumerStatefulWidget {
  const MerchantRegistrationsPage({super.key});

  @override
  ConsumerState<MerchantRegistrationsPage> createState() =>
      _MerchantRegistrationsPageState();
}

class _MerchantRegistrationsPageState
    extends ConsumerState<MerchantRegistrationsPage> {
  RegistrationListFilter _filter = RegistrationListFilter.all;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(merchantRegistrationsProvider(_filter));
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantCatalogRegistrations)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyTabs(
                variant: CyTabsVariant.chip,
                tabs: RegistrationListFilter.values
                    .map(
                      (RegistrationListFilter f) =>
                          CyTab(key: f.wire, label: switch (f) {
RegistrationListFilter.all => stringsOf(context).merchantCatalogAll,
RegistrationListFilter.ongoing => stringsOf(context).merchantCatalogOngoing,
RegistrationListFilter.reviewing => stringsOf(context).merchantCatalogReviewing,
RegistrationListFilter.rejected => stringsOf(context).merchantCatalogRejected,
RegistrationListFilter.finished => stringsOf(context).merchantCatalogFinished
}),
                    )
                    .toList(),
                active: _filter.wire,
                onChanged: (String key) => setState(() {
                  _filter = RegistrationListFilter.values.firstWhere(
                    (RegistrationListFilter f) => f.wire == key,
                  );
                }),
              ),
              Expanded(
                child: async.when(
                  loading: () => const CySkeleton(),
                  error: (Object e, StackTrace st) => StatusView(
                    icon: CupertinoIcons.exclamationmark_triangle,
                    message: stringsOf(context).merchantCatalogListError,
                    sub: e.toString().replaceFirst('Exception: ', ''),
                    large: true,
                    onRetry: () =>
                        ref.invalidate(merchantRegistrationsProvider(_filter)),
                  ),
                  data: (List<TopicRegistration> rows) {
                    if (rows.isEmpty) {
                      return StatusView(
                        icon: CupertinoIcons.tray,
                        message: _filter == RegistrationListFilter.all
                            ? stringsOf(context).merchantCatalogListEmpty
                            : stringsOf(context).merchantCatalogFilterEmpty,
                        sub: _filter == RegistrationListFilter.all
                            ? stringsOf(context).merchantCatalogListEmptyHint
                            : stringsOf(context).merchantCatalogFilterEmptyHint,
                        large: true,
                      );
                    }
                    return RefreshIndicator.adaptive(
                      onRefresh: () async => ref.invalidate(
                        merchantRegistrationsProvider(_filter),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(CyTokens.space4),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: CyTokens.space3),
                        itemBuilder: (_, int i) => _Card(
                          row: rows[i],
                          onChanged: () => ref.invalidate(
                            merchantRegistrationsProvider(_filter),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends ConsumerStatefulWidget {
  const _Card({required this.row, required this.onChanged});
  final TopicRegistration row;
  final VoidCallback onChanged;

  @override
  ConsumerState<_Card> createState() => _CardState();
}

class _CardState extends ConsumerState<_Card> {
  bool _busy = false;

  Future<void> _cancel() async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).merchantCatalogCancelTitle,
      content: stringsOf(context).merchantCatalogCancelHint,
      confirmText: stringsOf(context).merchantCatalogCancel,
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final String msg = await ref
          .read(merchantApiProvider)
          .cancelTopicRegistration(widget.row.id);
      widget.onChanged();
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
    } on MerchantApiException catch (e) {
      if (!mounted) return;
      // 后端的拒绝话术自带原因(已中标 / 主题已开始),照原文显示。
      CyNativeNotice.show(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TopicRegistration r = widget.row;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
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
                  (r.topicName?.isNotEmpty ?? false) ? r.topicName! : stringsOf(context).merchantCatalogApplication,
                  style: t.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _statusText(context, r),
                style: t.labelSmall?.copyWith(color: _statusColor(r, p)),
              ),
            ],
          ),
          if ((r.addressName ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              r.addressName!,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
          // ★ 驳回原因是这一页最有用的一行:没有它,商家只知道"没过",
          //   不知道改什么 —— 于是只能取消重报,而那正是 update 要解决的。
          if (r.isRejected) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CyTokens.space2),
              decoration: BoxDecoration(
                color: p.bgSubtle,
                borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              ),
              child: Text(
                (r.reason?.isNotEmpty ?? false)
                    ? stringsOf(context).merchantCatalogReason(r.reason!)
                    // 后端没给原因时说实话,别编一句。
                    : stringsOf(context).merchantCatalogMissingListReason,
                style: t.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              // ★ 已中标的**不给取消按钮**(闸在 service,给了就是点下去必报错)。
              if (r.canCancel)
                Expanded(
                  child: CyNativeButton(
                    onPressed: _busy ? null : _cancel,
                    label: stringsOf(context).merchantCatalogCancel,
                    role: CyNativeButtonRole.secondary,
                  ),
                ),
              if (r.canCancel && r.canEdit)
                const SizedBox(width: CyTokens.space2),
              if (r.canEdit)
                Expanded(
                  child: CyNativeButton(
                    key: Key('registration-edit-${r.id}'),
                    onPressed: _busy ? null : _edit,
                    label: stringsOf(context).merchantCatalogEdit,
                  ),
                ),
              if (!r.canCancel && !r.canEdit)
                Expanded(
                  child: Text(
                    r.isWon ? stringsOf(context).merchantCatalogWonLocked : stringsOf(context).merchantCatalogLocked,
                    style: t.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 去改这条报名。
  ///
  /// ★★ 这里以前是个只弹提示的假入口,理由是「App 侧没有完整的报名编辑表单,
  ///   接了会拿半截数据覆盖后端」。核到服务端后这条前提只对了一半:
  ///   可写字段其实只有**九个**(白名单在 MerchantRegistrationEditServiceImpl),
  ///   而且 mapper 是逐字段增量更新,没发的字段不会被清空。
  ///   真正的实害是「表单缺一项 = 商家永远改不了那一项」——
  ///   所以现在给的是一张按那份白名单做的完整表单,见
  ///   merchant_registration_edit_page.dart。
  ///
  /// 回来时刷新列表:状态可能从「已驳回」变回「审核中」。
  Future<void> _edit() async {
    await context.push('/merchant/registration/${widget.row.id}/edit');
    if (!mounted) return;
    widget.onChanged();
  }

  static String _statusText(BuildContext context, TopicRegistration r) {
    if (r.isWon) return stringsOf(context).merchantCatalogWon;
    switch (r.status) {
      case 0:
        return stringsOf(context).merchantCatalogReviewing;
      case 1:
        return stringsOf(context).merchantCatalogApproved;
      case 2:
        return stringsOf(context).merchantCatalogRejected;
      default:
        // 状态没拿到就说没拿到,别默认成"审核中" ——
        // 那会让界面给出它其实没有的操作。
        return stringsOf(context).merchantCatalogUnknown;
    }
  }

  static Color _statusColor(TopicRegistration r, CyPalette p) {
    if (r.isWon) return p.statusSuccess;
    if (r.isRejected) return p.statusDanger;
    return p.textSecondary;
  }
}
