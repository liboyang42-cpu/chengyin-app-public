import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/official_api.dart';
import '../../data/models/official_event.dart';
import '../auth/login_gate.dart';
import 'official_controller.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 官方活动承接邀约收件箱。对齐小程序 `pages/activity/official-inbox`。
class OfficialInboxPage extends ConsumerWidget {
  const OfficialInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(partyInboxProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('承接邀约')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) =>
                // ★ 游客从 events 页「承接邀约 ›」进来必撞 HTTP 401
                //   (`/api/official/v2/party-inbox` 要登录态)。真源该入口对
                //   所有人可见(小程序静默 wx.login,不存在游客 401),入口照留,
                //   落点分流成登录引导 —— 死路(B1 报告 ofc-01)变可恢复。
                isUnauthorizedError(e)
                ? StatusView(
                    message: '登录后查看承接邀约',
                    sub: '这一步需要登录,登录完会自动回到这一页。',
                    icon: CupertinoIcons.lock,
                    large: true,
                    retryLabel: '去登录',
                    onRetry: () async {
                      if (!await requireLogin(context, ref)) return;
                      ref.invalidate(partyInboxProvider);
                    },
                  )
                : StatusView(
                    message: '承接邀约没能加载出来',
                    sub: officialErrorSub(e),
                    large: true,
                    onRetry: () => ref.invalidate(partyInboxProvider),
                  ),
            data: (List<PartyInviteItem> rows) {
              if (rows.isEmpty) {
                return const StatusView(
                  message: '还没有承接邀约',
                  sub: '官方发起活动并邀请你承接时,会出现在这里',
                  large: true,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async => ref.invalidate(partyInboxProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CyTokens.space3),
                  itemBuilder: (_, int i) => _InviteCard(item: rows[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.item});
  final PartyInviteItem item;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _busy = false;

  /// 官方主办邀约:走 organizer-invites(**需要官方发布白名单**)。
  Future<void> _respondOrganizer(bool accept) => _run(
    () => ref
        .read(officialApiProvider)
        .respondInvite(widget.item.partyId, accept: accept),
  );

  /// 商家/俱乐部承接邀约:走 `parties/{id}/{ACTION}`。
  ///
  /// ★★ 这两条**必须按 partyType 分开**。原来所有行都走 organizer-invites,
  ///   而那条要官方发布白名单 —— 商家点「接受」拿到的是「无官方发布权限」,
  ///   一个点了必然失败的按钮,而收件箱本来就是发给商家看的。
  ///   反向也不行:后端 respondParty 对 OFFICIAL 直接回
  ///   「官方主办关系只能由专用受控命令处理」。两条路严格互斥。
  Future<void> _respondParty(OfficialPartyAction action) => _run(
    () =>
        ref.read(officialApiProvider).respondParty(widget.item.partyId, action),
  );

  Future<void> _run(Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      await call();
      ref.invalidate(partyInboxProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, '已提交');
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
    final PartyInviteItem item = widget.item;
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 字号走 iOS 梯级(T2),不再吃 Material `TextTheme` 的 Roboto 尺寸。
          Text(
            item.title,
            style: CyType.headline.copyWith(color: palette.textPrimary),
          ),
          if ((item.eventTitle ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                item.eventTitle!,
                style: CyType.caption1.copyWith(color: palette.textSecondary),
              ),
            ),
          const SizedBox(height: CyTokens.space3),
          ..._actions(context),
        ],
      ),
    );
  }

  /// 只露**当前状态下真能做**的动作。
  ///
  /// 后端每个动作都有前置状态(ACCEPT/DECLINE 只认 INVITED,
  /// WITHDRAW 只认 ACCEPTED/ACTIVE)。摆出不能做的那个 = 点下去必报错。
  List<Widget> _actions(BuildContext context) {
    final PartyInviteItem item = widget.item;

    if (item.partyType == 'OFFICIAL') {
      if (!item.organizerActionable) return <Widget>[_state(context)];
      return <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: CyNativeButton(
                onPressed: _busy ? null : () => _respondOrganizer(false),
                label: '拒绝',
                role: CyNativeButtonRole.secondary,
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            Expanded(
              child: CyNativeButton(
                onPressed: _busy ? null : () => _respondOrganizer(true),
                label: '接受',
                loading: _busy,
              ),
            ),
          ],
        ),
      ];
    }

    final List<OfficialPartyAction> actions = item.actions;
    if (actions.isEmpty) return <Widget>[_state(context)];

    return <Widget>[
      Row(
        children: <Widget>[
          for (int i = 0; i < actions.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: CyTokens.space2),
            Expanded(
              child: actions[i] == OfficialPartyAction.accept
                  ? CyNativeButton(
                      onPressed: _busy ? null : () => _respondParty(actions[i]),
                      label: _label(actions[i]),
                      loading: _busy,
                    )
                  : CyNativeButton(
                      onPressed: _busy ? null : () => _respondParty(actions[i]),
                      label: _label(actions[i]),
                      role: CyNativeButtonRole.secondary,
                    ),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _state(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Text(
      _stateText(widget.item.status),
      style: CyType.caption1.copyWith(color: palette.textTertiary),
    );
  }

  static String _label(OfficialPartyAction a) {
    switch (a) {
      case OfficialPartyAction.accept:
        return '接受';
      case OfficialPartyAction.decline:
        return '拒绝';
      case OfficialPartyAction.withdraw:
        // 不是"拒绝",是**已经接了又退出**。措辞必须区分,
        // 否则用户会以为自己在拒绝一个还没接的邀约。
        return '退出承接';
    }
  }

  /// 没有可做动作时说清**为什么**,而不是一律「已处理」。
  static String _stateText(String? status) {
    switch (status) {
      case 'ACCEPTED':
        return '已接受,等待活动开始';
      case 'ACTIVE':
        return '进行中';
      case 'INVITED':
        return '待处理';
      default:
        return '已处理';
    }
  }
}
