import '../../l10n/strings.dart';
import 'merchant_directory_strings.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import 'merchant_error_view.dart';
import '../../data/models/merchant_coop.dart';

final recruitingRoutesProvider =
    FutureProvider.autoDispose<List<RecruitingRoute>>((ref) {
      return ref.watch(merchantApiProvider).recruitingRoutes();
    });

final merchantInvitesProvider =
    FutureProvider.autoDispose<List<MerchantInvite>>((ref) {
      return ref.watch(merchantApiProvider).merchantInvites();
    });

/// 合作中心。对齐小程序 `pages/merchant/coop-center`,两档:可承接 / 邀约我的。
class MerchantCoopPage extends ConsumerStatefulWidget {
  const MerchantCoopPage({super.key});

  @override
  ConsumerState<MerchantCoopPage> createState() => _MerchantCoopPageState();
}

class _MerchantCoopPageState extends ConsumerState<MerchantCoopPage> {
  String _active = 'available';
  bool _invitesVisited = false;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantDirectoryCenter)),
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
                    CyTab(key: 'available', label: stringsOf(context).merchantDirectoryAvailable),
                    CyTab(key: 'invites', label: stringsOf(context).merchantDirectoryInvites),
                  ],
                  active: _active,
                  onChanged: (String value) => setState(() {
                    _active = value;
                    if (value == 'invites') _invitesVisited = true;
                  }),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _active == 'available' ? 0 : 1,
                  children: <Widget>[
                    const _AvailableTab(),
                    _invitesVisited
                        ? const _InvitesTab()
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

class _AvailableTab extends ConsumerWidget {
  const _AvailableTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recruitingRoutesProvider);
    final textTheme = Theme.of(context).textTheme;
    return async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (Object e, _) => merchantErrorView(
        context,
        e,
        onRetry: () => ref.invalidate(recruitingRoutesProvider),
      ),
      data: (List<RecruitingRoute> rows) {
        if (rows.isEmpty) {
          return StatusView(
            message: stringsOf(context).merchantDirectoryNoRoutes,
            sub: stringsOf(context).merchantDirectoryNoRoutesHint,
            large: true,
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(recruitingRoutesProvider),
          child: ListView(
            padding: const EdgeInsets.all(CyTokens.pageX),
            children: <Widget>[
              Text(stringsOf(context).merchantDirectoryFindPartnership, style: textTheme.titleMedium),
              const SizedBox(height: CyTokens.space1),
              Text(
                stringsOf(context).merchantDirectoryApplicationHint,
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              ...rows.map(
                (RecruitingRoute r) => CyCell(
                  title: r.hasNameFallback ? stringsOf(context).merchantDirectoryUnnamedRoute : r.name,
                  // ★ 后端没下发截止日就不显示这一行,不编「长期开放」。
                  subtitle: merchantDirectoryRouteDeadline(context, r),
                  // ★ 进的是**商家承接页**,不是玩家版主题详情 ——
                  //   商家点进"可承接路线"想做的是承接,不是买票。
                  onTap: () => context.push('/merchant/recruit/${r.id}'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InvitesTab extends ConsumerWidget {
  const _InvitesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantInvitesProvider);
    return async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (Object e, _) => merchantErrorView(
        context,
        e,
        onRetry: () => ref.invalidate(merchantInvitesProvider),
      ),
      data: (List<MerchantInvite> rows) {
        if (rows.isEmpty) {
          return StatusView(
            message: stringsOf(context).merchantDirectoryNoInvites,
            sub: stringsOf(context).merchantDirectoryNoInvitesHint,
            large: true,
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(merchantInvitesProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(CyTokens.pageX),
            itemCount: rows.length,
            itemBuilder: (_, int i) => MerchantInviteTile(invite: rows[i]),
          ),
        );
      },
    );
  }
}

/// 官方邀约(平台→商家)一行。
///
/// ★ 公开给协作邀请页复用 —— 小程序把「邀约我的」收编进 `pages/coop/list`
///   的「收到的」tab 后,两处渲染的是同一批记录,不能各写一份。
class MerchantInviteTile extends ConsumerStatefulWidget {
  const MerchantInviteTile({super.key, required this.invite});
  final MerchantInvite invite;

  @override
  ConsumerState<MerchantInviteTile> createState() => _MerchantInviteTileState();
}

class _MerchantInviteTileState extends ConsumerState<MerchantInviteTile> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(officialApiProvider)
          .respondInvite(widget.invite.id, accept: accept);
      ref.invalidate(merchantInvitesProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, accept ? stringsOf(context).merchantDirectoryAccepted : stringsOf(context).merchantDirectoryDeclined);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final textTheme = Theme.of(context).textTheme;
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
        children: <Widget>[
          Row(
            children: <Widget>[
              CyTag(label: merchantDirectoryLocalText(context, invite.stateText)),
              const SizedBox(width: CyTokens.space2),
              Text(
                stringsOf(context).merchantDirectoryFromPlatform,
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          Text(invite.hasTitleFallback ? stringsOf(context).merchantDirectoryOfficialActivity : invite.title, style: textTheme.titleMedium),
          if ((invite.eventTitle ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                invite.eventTitle!,
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space1),
          Text(
            invite.rewardText,
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          Text(
            merchantDirectoryInviteDeadline(context, invite),
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textTertiary,
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          // ★ 已处理的只摆徽标(见上方 stateText),不摆按钮 —— 摆了点下去必然失败。
          if (invite.actionable)
            Row(
              children: <Widget>[
                Expanded(
                  child: CyNativeButton(
                    onPressed: _busy ? null : () => _respond(false),
                    label: stringsOf(context).merchantDirectoryReject,
                    role: CyNativeButtonRole.secondary,
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: CyNativeButton(
                    onPressed: _busy ? null : () => _respond(true),
                    label: stringsOf(context).merchantDirectoryAccept,
                    loading: _busy,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
