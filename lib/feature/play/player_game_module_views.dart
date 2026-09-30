import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../data/models/game_session.dart';
import 'player_game_module_controller.dart';

/// 章节卡右上角那枚身份胶囊(小程序 `pcard__role`)。
/// 点开「本局线索」;这一局还没有玩家投影时不占位。
class PlayerGameRoleChip extends ConsumerWidget {
  const PlayerGameRoleChip({super.key, required this.activityId});

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerGameModuleState state = ref.watch(
      playerGameModuleProvider(activityId),
    );
    if (!state.chipVisible) return const SizedBox.shrink();
    return CupertinoButton(
      key: const Key('play-role-chip'),
      // 44×44 最小触达(iOS HIG;a5-ios27-game-2 记旧值 44×32 不足)。
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
      onPressed: () =>
          showPlayerGameModuleSheet(context: context, activityId: activityId),
      child: Text(
        state.chipLabel,
        // 真源这枚胶囊的 aria 说的是点下去看到什么,不是它长什么字。
        semanticsLabel: '查看本局角色线索',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: CupertinoColors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 身份卡宿主:进页拉一次玩家投影,首入本场弹一次「今晚的身份」。
///
/// 小程序的记住范围是按 activityId 记本机(`role_seen_<id>`),且**没确认过就还会再弹** ——
/// 「首入一次」省的是打扰,不是确认。这里照抄同一条判据。
class PlayerGameRoleCardHost extends ConsumerStatefulWidget {
  const PlayerGameRoleCardHost({super.key, required this.activityId});

  final int activityId;

  @override
  ConsumerState<PlayerGameRoleCardHost> createState() =>
      _PlayerGameRoleCardHostState();
}

class _PlayerGameRoleCardHostState
    extends ConsumerState<PlayerGameRoleCardHost> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(playerGameModuleProvider(widget.activityId).notifier).load(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlayerGameModuleState state = ref.watch(
      playerGameModuleProvider(widget.activityId),
    );
    final PlayerGameRole? role = state.projection?.role;
    if (_dismissed || role == null || role.code.isEmpty) {
      return const SizedBox.shrink();
    }
    return _RoleCardGate(
      activityId: widget.activityId,
      role: role,
      onDismiss: () => setState(() => _dismissed = true),
    );
  }
}

class _RoleCardGate extends ConsumerStatefulWidget {
  const _RoleCardGate({
    required this.activityId,
    required this.role,
    required this.onDismiss,
  });

  final int activityId;
  final PlayerGameRole role;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_RoleCardGate> createState() => _RoleCardGateState();
}

class _RoleCardGateState extends ConsumerState<_RoleCardGate> {
  bool _loading = true;
  bool _seen = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readSeen());
  }

  Future<void> _readSeen() async {
    bool seen = false;
    try {
      seen = await ref
          .read(playerGameRoleSeenStoreProvider)
          .seen(widget.activityId);
    } catch (_) {
      seen = false;
    }
    if (!mounted) return;
    setState(() {
      _seen = seen;
      _loading = false;
    });
    if (widget.role.confirmed) {
      unawaited(_markSeen());
    }
  }

  Future<void> _markSeen() async {
    try {
      await ref
          .read(playerGameRoleSeenStoreProvider)
          .markSeen(widget.activityId);
    } catch (_) {
      // 记不住就下次再弹一次;不因为存储失败挡住确认。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final bool confirmed = widget.role.confirmed;
    if (confirmed && _seen) return const SizedBox.shrink();
    if (confirmed) unawaited(_markSeen());
    return _RoleCard(
      activityId: widget.activityId,
      role: widget.role,
      onDismiss: widget.onDismiss,
    );
  }
}

class _RoleCard extends ConsumerWidget {
  const _RoleCard({
    required this.activityId,
    required this.role,
    required this.onDismiss,
  });

  final int activityId;
  final PlayerGameRole role;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerGameModuleState state = ref.watch(
      playerGameModuleProvider(activityId),
    );
    final PlayerGameModuleController controller = ref.read(
      playerGameModuleProvider(activityId).notifier,
    );
    final bool confirmed = role.confirmed;
    final bool unknown = state.writeStatus == PlayerGameWriteStatus.unknown;
    final String cta = confirmed
        ? '接下身份，出发'
        : switch (state.writeStatus) {
            PlayerGameWriteStatus.submitting => '正在确认…',
            PlayerGameWriteStatus.unknown => '核对结果',
            _ => '确认身份',
          };
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Semantics(
            label: '关闭身份卡',
            button: true,
            child: GestureDetector(
              key: const Key('play-role-card-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              // 遮罩走统一弹层底(token 为 rgba(0,0,0,.56);真源 `.mask` 是 .62)。
              child: const ColoredBox(color: CyTokens.overlay),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // 真源 `pages/play/index.wxss` `.rolecard` 显式材质值
                // `rgba(10,10,11,.92)` —— 恒暗玻璃卡(与 cy-sheet 同规),无对应档位 token,
                // 按真源逐字保留。
                color: const Color(0xEB0A0A0B),
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(CyTokens.space5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 真源 `.rolecard__tag` color:--cy-text-secondary(= v2 text-tertiary)。
                    const Text(
                      '今晚的身份',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CyTokens.textTertiary,
                        fontSize: 13,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Icon(
                      _roleIcon(role.code),
                      size: 44,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Text(
                      role.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    // 真源 `.rolecard__desc` color:--cy-text-body(= v2 text-secondary)。
                    Text(
                      role.publicBrief.isNotEmpty
                          ? role.publicBrief
                          : '这是服务端为你冻结的本局身份。只会显示你被授权查看的线索。',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CyTokens.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (unknown ||
                        state.writeStatus == PlayerGameWriteStatus.error)
                      Padding(
                        padding: const EdgeInsets.only(top: CyTokens.space3),
                        child: Text(
                          state.writeMessage,
                          key: const Key('play-role-card-write'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CyTokens.statusWarning,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    const SizedBox(height: CyTokens.space5),
                    // 主 CTA 走统一档(真源 `.rolecard__cta` = `--cy-brand` 底 +
                    // `--cy-bg-page` 字,暗色端即近白底深字;原自绘蓝 #2F6BFF 无真源依据)。
                    CupertinoButton(
                      key: const Key('play-role-card-cta'),
                      padding: const EdgeInsets.symmetric(
                        vertical: CyTokens.space3,
                      ),
                      color: CyTokens.actionPrimaryBg,
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      onPressed: () {
                        if (confirmed) {
                          onDismiss();
                          return;
                        }
                        if (state.writeStatus ==
                            PlayerGameWriteStatus.submitting) {
                          return;
                        }
                        if (state.writeStatus ==
                            PlayerGameWriteStatus.unknown) {
                          unawaited(controller.reconcile());
                          return;
                        }
                        unawaited(controller.confirmRole());
                      },
                      child: Text(
                        cta,
                        // 已确认时这个键的动作就是收起身份卡(真源 rolecard 同义)。
                        semanticsLabel: confirmed ? '关闭身份卡' : null,
                        style: const TextStyle(
                          color: CyTokens.actionPrimaryFg,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (state.writeStatus == PlayerGameWriteStatus.unknown &&
                        state.canRetry)
                      CupertinoButton(
                        key: const Key('play-role-card-retry'),
                        onPressed: () => unawaited(controller.retryPending()),
                        child: const Text(
                          '重试原操作',
                          semanticsLabel: '用原请求号重试身份确认',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

IconData _roleIcon(String code) => switch (code.toUpperCase()) {
  'NAVIGATOR' => CupertinoIcons.compass,
  'OBSERVER' => CupertinoIcons.search,
  'RECORDER' => CupertinoIcons.camera,
  'NEGOTIATOR' => CupertinoIcons.chat_bubble_2,
  'DECODER' => CupertinoIcons.viewfinder,
  _ => CupertinoIcons.star,
};

/// 「本局线索」半屏。任意 Flutter 内容走 B1 原生 sheet(测试环境自动回退)。
Future<void> showPlayerGameModuleSheet({
  required BuildContext context,
  required int activityId,
}) {
  return showCyNativeSheet<void>(
    context,
    detents: CyNativeSheetDetents.both,
    builder: (BuildContext sheetContext) =>
        _PlayerGameModuleSheet(activityId: activityId),
  );
}

class _PlayerGameModuleSheet extends ConsumerWidget {
  const _PlayerGameModuleSheet({required this.activityId});

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerGameModuleState state = ref.watch(
      playerGameModuleProvider(activityId),
    );
    final PlayerGameModuleController controller = ref.read(
      playerGameModuleProvider(activityId).notifier,
    );
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: isCyNativeSheet(context)
          ? CupertinoColors.transparent
          : palette.bgElevated,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space2,
                CyTokens.space2,
                0,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '本局线索',
                      style: TextStyle(
                        fontSize: CyTokens.typeCardTitle,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('play-game-module-close'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    // 清除钮是系统语义灰,交给系统色自适应(原 #8E8E93 是 systemGray 硬编码)。
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 26,
                      color: CupertinoColors.systemGrey,
                      semanticLabel: '关闭本局线索',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _GameModuleBody(
                state: state,
                controller: controller,
                palette: palette,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameModuleBody extends StatelessWidget {
  const _GameModuleBody({
    required this.state,
    required this.controller,
    required this.palette,
  });

  final PlayerGameModuleState state;
  final PlayerGameModuleController controller;
  final CyPalette palette;

  @override
  Widget build(BuildContext context) {
    if (state.enabled && state.projection != null) {
      return _ready(context, state.projection!);
    }
    if (state.error.isNotEmpty) {
      return _messageBlock(
        context,
        key: const Key('play-game-module-error'),
        icon: CupertinoIcons.exclamationmark_triangle,
        text: state.error,
        actionLabel: '重新同步',
        actionSemantics: '重新同步本局状态',
        onAction: () => unawaited(controller.load()),
      );
    }
    return const Center(child: CupertinoActivityIndicator());
  }

  Widget _messageBlock(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String text,
    required String actionLabel,
    String? actionSemantics,
    required VoidCallback onAction,
  }) => Center(
    key: key,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 30, color: palette.statusWarning),
          const SizedBox(height: CyTokens.space3),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              height: 1.5,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          CupertinoButton(
            onPressed: onAction,
            child: Text(actionLabel, semanticsLabel: actionSemantics),
          ),
        ],
      ),
    ),
  );

  Widget _ready(BuildContext context, PlayerGameProjection projection) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space6,
      ),
      children: <Widget>[
        if (state.stale)
          _Notice(
            key: const Key('play-game-module-stale'),
            text:
                '同步失败，正在显示旧数据。旧数据更新于 ${projection.snapshotAt.isEmpty ? '—' : projection.snapshotAt}',
            actionLabel: '重试同步',
            actionSemantics: '重试同步本局状态',
            onAction: () => unawaited(controller.load()),
            palette: palette,
          ),
        _Section(
          title: '我的身份',
          palette: palette,
          children: <Widget>[
            Text(
              projection.role.name.isEmpty ? '待俱乐部分配' : projection.role.name,
              style: TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            if (projection.snapshotAt.isNotEmpty)
              Text(
                '状态更新于 ${projection.snapshotAt}',
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: palette.textTertiary,
                ),
              ),
          ],
        ),
        if (state.writeStatus != PlayerGameWriteStatus.idle)
          _WriteBar(state: state, controller: controller, palette: palette),
        if (projection.teamActions.isNotEmpty)
          _Section(
            title: '队伍协作',
            palette: palette,
            children: <Widget>[
              for (final PlayerGameTeamAction action in projection.teamActions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${action.displayName.isEmpty ? '队友' : action.displayName} · ${action.roleCode}',
                          style: TextStyle(
                            fontSize: CyTokens.typeBody,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        action.statusLabel,
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                '这里只显示协作状态，不公开队友精确位置。',
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
        if (projection.leaderboard != null)
          _Section(
            title: '本局榜单',
            palette: palette,
            children: <Widget>[
              if (projection.leaderboard!.entries.isEmpty)
                Text(
                  '本局榜单已开启\n暂时还没有有效协作记录',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    height: 1.5,
                    color: palette.textTertiary,
                  ),
                )
              else
                for (final PlayerGameLeaderboardEntry entry
                    in projection.leaderboard!.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${entry.rank}',
                            style: TextStyle(
                              fontSize: CyTokens.typeBody,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.displayName.isEmpty
                                ? '队伍'
                                : entry.displayName,
                            style: TextStyle(
                              fontSize: CyTokens.typeBody,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.score} 次协作',
                          style: TextStyle(
                            fontSize: CyTokens.typeLabel,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        for (final (int index, PlayerGameNode node) in projection.nodes.indexed)
          _PlayerNodeCard(
            index: index,
            node: node,
            state: state,
            controller: controller,
            palette: palette,
          ),
        if (projection.ending != null)
          _Section(
            title: '本局结局',
            palette: palette,
            children: <Widget>[
              Text(
                projection.ending!.title,
                style: TextStyle(
                  fontSize: CyTokens.typeCardTitle,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              Text(
                projection.ending!.summary,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  height: 1.5,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.text,
    required this.actionLabel,
    this.actionSemantics,
    required this.onAction,
    required this.palette,
  });

  final String text;
  final String actionLabel;
  final String? actionSemantics;
  final VoidCallback onAction;
  final CyPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          CupertinoIcons.exclamationmark_triangle,
          size: 18,
          color: palette.statusWarning,
        ),
        const SizedBox(width: CyTokens.space2),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
        ),
        CupertinoButton(
          // 44pt 最小触达(旧值 44×32;a5-ios27-game-2)。
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: onAction,
          child: Text(
            actionLabel,
            semanticsLabel: actionSemantics,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _WriteBar extends StatelessWidget {
  const _WriteBar({
    required this.state,
    required this.controller,
    required this.palette,
  });

  final PlayerGameModuleState state;
  final PlayerGameModuleController controller;
  final CyPalette palette;

  @override
  Widget build(BuildContext context) {
    final Color tone = switch (state.writeStatus) {
      PlayerGameWriteStatus.error => palette.statusDanger,
      PlayerGameWriteStatus.unknown => palette.statusWarning,
      PlayerGameWriteStatus.confirmed => palette.statusSuccess,
      _ => palette.textSecondary,
    };
    return Padding(
      key: const Key('play-game-module-write'),
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (state.writeStatus == PlayerGameWriteStatus.submitting)
                const Padding(
                  padding: EdgeInsets.only(right: CyTokens.space2, top: 2),
                  child: CupertinoActivityIndicator(radius: 8),
                ),
              Expanded(
                child: Text(
                  state.writeMessage,
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    height: 1.4,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          if (state.writeStatus == PlayerGameWriteStatus.unknown)
            Row(
              children: <Widget>[
                CupertinoButton(
                  key: const Key('play-game-module-reconcile'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () => unawaited(controller.reconcile()),
                  child: const Text(
                    '核对结果',
                    semanticsLabel: '核对这次操作的服务端结果',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                if (state.canRetry)
                  CupertinoButton(
                    key: const Key('play-game-module-retry'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => unawaited(controller.retryPending()),
                    child: const Text(
                      '重试原操作',
                      semanticsLabel: '用原请求号重试这次操作',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    required this.palette,
  });

  final String title;
  final List<Widget> children;
  final CyPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            fontWeight: FontWeight.w600,
            color: palette.textTertiary,
          ),
        ),
        const SizedBox(height: CyTokens.space1_5),
        ...children,
      ],
    ),
  );
}

class _PlayerNodeCard extends ConsumerWidget {
  const _PlayerNodeCard({
    required this.index,
    required this.node,
    required this.state,
    required this.controller,
    required this.palette,
  });

  final int index;
  final PlayerGameNode node;
  final PlayerGameModuleState state;
  final PlayerGameModuleController controller;
  final CyPalette palette;

  bool get _paused => node.status == 'PAUSED' || node.stationStatus == 'PAUSED';

  bool get _fallbackDone =>
      node.status == 'FALLBACK_COMPLETED' ||
      node.completionStatus == 'FALLBACK_COMPLETED';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerTaskEvidence evidence =
        state.evidence[node.nodeId] ?? const PlayerTaskEvidence();
    final String revealed = state.revealedAnswers[node.nodeId] ?? '';
    final bool blocked = state.writeBlocked;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '节点 ${index + 1}',
                  style: TextStyle(
                    fontSize: CyTokens.typeCardTitle,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                _fallbackDone ? '兜底完成 · 不计正常榜单分' : node.status,
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
          if (_paused) ...<Widget>[
            Text(
              node.fallback != null ? '本站暂停 · 已启用替代行动' : '本站暂停',
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: palette.statusWarning,
              ),
            ),
            if (node.pause?.reason.isNotEmpty == true)
              _hintText('原因 · ${node.pause!.reason}'),
            if (node.pause?.resumeEta.isNotEmpty == true)
              _hintText('预计恢复 · ${node.pause!.resumeEta}'),
            if (node.fallback != null) ...<Widget>[
              _hintText(node.fallback!.playerMessage),
              _hintText(
                '前往 ${node.fallback!.targetNodeName} · ${node.fallback!.planCode} v${node.fallback!.planVersion}',
              ),
            ],
            _hintText('如需退款请联系平台客服'),
          ],
          if (node.clue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                node.clue,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  height: 1.5,
                  color: palette.textPrimary,
                ),
              ),
            )
          else if (node.status == 'LOCKED')
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                '完成前置节点后才会下发本角色线索',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: palette.textTertiary,
                ),
              ),
            ),
          if (revealed.isNotEmpty)
            _hintText(
              '答案 · $revealed',
              key: Key('play-node-answer-${node.nodeId}'),
            ),
          if (node.task != null)
            _TaskBlock(
              node: node,
              evidence: evidence,
              state: state,
              controller: controller,
              palette: palette,
              blocked: blocked,
            ),
          if (node.choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Column(
                children: <Widget>[
                  for (final PlayerGameChoice choice in node.choices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space2),
                      child: SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          key: Key(
                            'play-node-choice-${node.nodeId}-${choice.id}',
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: CyTokens.space3,
                            horizontal: CyTokens.space3,
                          ),
                          color: palette.bgSurfaceSubtle,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusMd,
                          ),
                          onPressed: blocked
                              ? null
                              : () => unawaited(
                                  controller.submitChoice(
                                    node.nodeId,
                                    choice.id,
                                  ),
                                ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  choice.label,
                                  style: TextStyle(
                                    fontSize: CyTokens.typeBody,
                                    color: palette.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                CupertinoIcons.chevron_forward,
                                size: 16,
                                color: palette.textTertiary,
                              ),
                            ],
                          ),
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

  Widget _hintText(String text, {Key? key}) => Padding(
    padding: const EdgeInsets.only(top: CyTokens.space1),
    child: Text(
      text,
      key: key,
      style: TextStyle(
        fontSize: CyTokens.typeLabel,
        height: 1.4,
        color: palette.textSecondary,
      ),
    ),
  );
}

/// 本站任务:提示 / 凭证 / 提交状态 / 提交键。凭证三种输入类型各走各的采集器。
class _TaskBlock extends ConsumerWidget {
  const _TaskBlock({
    required this.node,
    required this.evidence,
    required this.state,
    required this.controller,
    required this.palette,
    required this.blocked,
  });

  final PlayerGameNode node;
  final PlayerTaskEvidence evidence;
  final PlayerGameModuleState state;
  final PlayerGameModuleController controller;
  final CyPalette palette;
  final bool blocked;

  PlayerGameTask get task => node.task!;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerGameHint? hint = node.hint;
    final PlayerGameSubmission? submission = node.submission;
    final bool resubmittable =
        submission == null || submission.status == 'REJECTED';
    final bool canSubmit =
        state.projection?.availableActions.contains('PLAYER_SUBMIT') == true;
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '本站任务',
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              fontWeight: FontWeight.w600,
              color: palette.textTertiary,
            ),
          ),
          Text(
            task.prompt,
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              height: 1.5,
              color: palette.textPrimary,
            ),
          ),
          if (hint != null) ...<Widget>[
            for (final PlayerGameHintText text in hint.revealedTexts)
              _line('提示 ${text.level} · ${text.text}'),
            if (hint.nextLevel != null && hint.nextImpactLabel.isNotEmpty)
              CupertinoButton(
                key: Key('play-node-hint-${node.nodeId}'),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: blocked
                    ? null
                    : () => _requestHint(context, hint.nextLevel!),
                child: Text('查看第 ${hint.nextLevel} 级提示'),
              ),
            if (hint.revealAvailable && hint.revealImpactLabel.isNotEmpty) ...[
              _line(hint.revealImpactLabel),
              CupertinoButton(
                key: Key('play-node-reveal-${node.nodeId}'),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: blocked ? null : () => _requestReveal(context),
                child: const Text('揭示答案 · 记为兜底完成、不计正常榜单分'),
              ),
            ],
          ],
          // 凭证采集区与提交状态各自独立(真源 index.wxml:1741-1762 的
          // 三种输入块不按 submission 收口;只有提交键才要求
          // 无提交或已被驳回,:1771)。核验期间仍能看见/改动已填的现场内容。
          switch (task.inputType) {
            'TEXT' => _textEvidence(),
            'SCAN' => _captureButton(
              key: Key('play-node-scan-${node.nodeId}'),
              label: '扫描现场任务码',
              action: evidence.ready ? '重新扫码' : '开始扫码',
              actionSemantics: '扫描本站现场任务码',
              onTap: () => _scan(context, ref),
            ),
            'PHOTO' => _captureButton(
              key: Key('play-node-photo-${node.nodeId}'),
              label: '上传现场照片凭证',
              action: evidence.ready ? '重新选择照片' : '拍照或选择图片',
              actionSemantics: '拍摄或选择本站任务照片',
              onTap: () => _photo(context, ref),
            ),
            _ => Text(
              '任务凭证类型尚未配置，请联系主办方',
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: palette.statusDanger,
              ),
            ),
          },
          if (evidence.statusText.isNotEmpty) _line(evidence.statusText),
          if (submission != null) ...<Widget>[
            _line(submission.statusLabel),
            if (submission.status == 'PENDING')
              _line('核验编号 ${submission.submissionId}'),
            if (submission.status == 'REJECTED' &&
                submission.decisionReason.isNotEmpty)
              _line(
                '驳回原因：${submission.decisionReason}',
                key: Key('play-node-reject-${node.nodeId}'),
              ),
          ],
          if (resubmittable && canSubmit)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  key: Key('play-node-submit-${node.nodeId}'),
                  padding: const EdgeInsets.symmetric(
                    vertical: CyTokens.space3,
                  ),
                  color: blocked || !evidence.ready
                      ? palette.bgSurfaceSubtle
                      : palette.actionPrimaryBg,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  onPressed: blocked || !evidence.ready
                      ? null
                      : () => unawaited(
                          controller.submitTask(
                            node.nodeId,
                            task.taskCode,
                            evidence.evidenceUrls,
                          ),
                        ),
                  child: Text(
                    task.completionPolicy == 'EVIDENCE_ONLY'
                        ? '记录现场证据'
                        : (task.verificationRequired ? '提交并等待商家核验' : '提交本站任务'),
                    style: TextStyle(
                      fontSize: CyTokens.typeButton,
                      fontWeight: FontWeight.w600,
                      color: blocked || !evidence.ready
                          ? palette.textDisabled
                          : palette.actionPrimaryFg,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(String text, {Key? key}) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      text,
      key: key,
      style: TextStyle(
        fontSize: CyTokens.typeLabel,
        height: 1.4,
        color: palette.textSecondary,
      ),
    ),
  );

  Widget _textEvidence() => Padding(
    padding: const EdgeInsets.only(top: CyTokens.space1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _line('填写文字凭证'),
        // 真源给这个输入框的读屏名点明了它是**本站**任务的凭证,
        // 只念 placeholder 会漏掉这层归属。
        Semantics(
          label: '填写本站任务文字凭证',
          textField: true,
          child: _TextEvidenceField(
            nodeId: node.nodeId,
            initialText: evidence.text,
            palette: palette,
            onChanged: (String text) {
              final String trimmed = text.trim();
              controller.setEvidence(
                node.nodeId,
                PlayerTaskEvidence(
                  type: 'TEXT',
                  text: text,
                  evidenceUrls: trimmed.isEmpty
                      ? const <String>[]
                      : <String>['text:${Uri.encodeComponent(trimmed)}'],
                  statusText: trimmed.isEmpty ? '' : '文字凭证已填写',
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _captureButton({
    required Key key,
    required String label,
    required String action,
    String? actionSemantics,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(top: CyTokens.space1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _line(label),
        CupertinoButton(
          key: key,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: blocked ? null : onTap,
          child: Text(action, semanticsLabel: actionSemantics),
        ),
      ],
    ),
  );

  Future<void> _requestHint(BuildContext context, int level) async {
    final bool confirmed = await cyConfirm(
      context,
      title: '查看第 $level 级提示',
      content: node.hint?.nextImpactLabel,
      confirmText: '查看提示',
      cancelText: '继续想想',
    );
    if (!confirmed) return;
    await controller.submitHint(node.nodeId, level);
  }

  Future<void> _requestReveal(BuildContext context) async {
    final bool confirmed = await cyConfirm(
      context,
      title: '揭示答案',
      content: node.hint?.revealImpactLabel,
      confirmText: '查看答案',
      cancelText: '继续想想',
    );
    if (!confirmed) return;
    await controller.submitReveal(node.nodeId);
    final String revealed = controller.revealedAnswerFor(node.nodeId);
    if (revealed.isNotEmpty && context.mounted) {
      CyNativeNotice.show(context, '答案已揭示：$revealed');
    }
  }

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final String? value = await Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(builder: (_) => const _ScanEvidencePage()),
    );
    final String code = (value ?? '').trim();
    if (code.isEmpty) return;
    controller.setEvidence(
      node.nodeId,
      PlayerTaskEvidence(
        type: 'SCAN',
        evidenceUrls: <String>['scan:${Uri.encodeComponent(code)}'],
        statusText: '已识别本站任务码',
      ),
    );
  }

  Future<void> _photo(BuildContext context, WidgetRef ref) async {
    final CyImagePickSource? source = await cyChooseImageSource(context);
    if (source == null) return;
    final bool cam = source == CyImagePickSource.camera;
    final XFile? file = await ImagePicker().pickImage(
      source: cam ? ImageSource.camera : ImageSource.gallery,
    );
    if (file == null) return;
    try {
      final String url = await ref.read(playApiProvider).uploadImage(file.path);
      final String trimmed = url.trim();
      if (!trimmed.toLowerCase().startsWith('https://')) return;
      controller.setEvidence(
        node.nodeId,
        PlayerTaskEvidence(
          type: 'PHOTO',
          evidenceUrls: <String>[trimmed],
          statusText: '已上传 1 张现场照片',
        ),
      );
    } catch (error) {
      if (context.mounted) {
        CyNativeNotice.show(context, '上传失败，请重新选择照片', isError: true);
      }
    }
  }
}

/// 文字凭证输入框:输入控制器归自己,换投影/重建时不重置光标。
class _TextEvidenceField extends StatefulWidget {
  const _TextEvidenceField({
    required this.nodeId,
    required this.initialText,
    required this.palette,
    required this.onChanged,
  });

  final int nodeId;
  final String initialText;
  final CyPalette palette;
  final ValueChanged<String> onChanged;

  @override
  State<_TextEvidenceField> createState() => _TextEvidenceFieldState();
}

class _TextEvidenceFieldState extends State<_TextEvidenceField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoTextField(
    key: Key('play-node-text-${widget.nodeId}'),
    controller: _controller,
    placeholder: '输入你在现场观察或确认到的内容',
    maxLength: 300,
    maxLines: 3,
    style: TextStyle(
      fontSize: CyTokens.typeBody,
      color: widget.palette.textPrimary,
    ),
    placeholderStyle: TextStyle(color: widget.palette.textPlaceholder),
    decoration: BoxDecoration(
      color: widget.palette.bgSurfaceSubtle,
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    ),
    onChanged: (String value) {
      widget.onChanged(value.length > 300 ? value.substring(0, 300) : value);
    },
  );
}

/// 扫现场任务码:只取码,不给相机加任何业务判断(判据在服务端)。
class _ScanEvidencePage extends StatefulWidget {
  const _ScanEvidencePage();

  @override
  State<_ScanEvidencePage> createState() => _ScanEvidencePageState();
}

class _ScanEvidencePageState extends State<_ScanEvidencePage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final Barcode barcode in capture.barcodes) {
      final String code = (barcode.rawValue ?? '').trim();
      if (code.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('扫描现场任务码')),
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MobileScanner(controller: _controller, onDetect: _onDetect),
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: CyTokens.space6),
            child: Text(
              '对准现场任务码',
              style: TextStyle(color: CupertinoColors.white, fontSize: 14),
            ),
          ),
        ),
      ],
    ),
  );
}
