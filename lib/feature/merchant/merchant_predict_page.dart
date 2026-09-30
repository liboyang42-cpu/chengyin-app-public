import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/network/dio_client.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_predict_api.dart';
import '../../data/models/merchant_predict.dart';

/// 竞猜待答的取数:身份闸 + 待答列表。
///
/// ★ 顺序是小程序定的(`pages/merchant/predict/index.js:loadAccess → loadInbox`):
///   先问身份,**不是**先拉列表再靠 UI 藏 —— 结算会发券,后端要的是
///   `merchant:project:manage`;前端这一闸只是别让人白跑一趟。
///
/// [PredictInboxDenied] 不是错误:身份正常但没这个权限,页面给的是
/// 「当前岗位不能结算竞猜」那一屏,不是「加载失败」。
sealed class PredictInboxState {
  const PredictInboxState();
}

class PredictInboxReady extends PredictInboxState {
  const PredictInboxReady(this.rounds);

  final List<PredictRound> rounds;
}

class PredictInboxDenied extends PredictInboxState {
  const PredictInboxDenied();
}

final predictInboxProvider = FutureProvider.autoDispose<PredictInboxState>((
  ref,
) async {
  final Map<String, dynamic> access = await ref
      .watch(pageParityApiProvider)
      .merchantAccess();
  if (access['active'] != true || access['canManageProjects'] != true) {
    return const PredictInboxDenied();
  }
  final List<Map<String, dynamic>> rows = await ref
      .watch(merchantPredictApiProvider)
      .inbox();
  return PredictInboxReady(
    rows.map(shapePredictRound).toList(growable: false),
  );
});

/// 竞猜待答(商家侧)。对齐小程序 `pages/merchant/predict/index`。
///
/// 三条不能省的(小程序逐字):
///   · **有期限** —— 超过 48 小时不给答案,那一轮由平台作废、谁都拿不到奖。
///     每张卡都写「还剩几天」,最后一天要红。
///   · **只能结一次**,而且会按商家配的规则发券 —— 所以二次确认,
///     并把后果写进确认框。
///   · **服务端说了算** —— 结没结成功只认接口回执;失败留在原地可重试,
///     不拿本地状态冒充成功(更不许把没结掉的卡片从列表里拿掉)。
class MerchantPredictPage extends ConsumerStatefulWidget {
  const MerchantPredictPage({super.key, this.confirmPresenter});

  /// 测试缝:确认弹窗的呈现器(真机走系统 Liquid Glass alert)。
  final CyNativeConfirmPresenter? confirmPresenter;

  @override
  ConsumerState<MerchantPredictPage> createState() =>
      _MerchantPredictPageState();
}

class _MerchantPredictPageState extends ConsumerState<MerchantPredictPage> {
  /// 展开选答案的那一行(rid);空 = 都收起。
  String _openRid = '';
  String _pickedKey = '';
  bool _submitting = false;

  /// 本页会话内已结掉的行。结完从列表里拿掉 —— 不重新拉整页,
  /// 别让人刚点完又看见它还在。
  final Set<String> _settledRids = <String>{};

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(kMerchantHomeRoute);
  }

  void _open(PredictRound round) {
    if (_submitting) return;
    setState(() {
      _openRid = round.rid;
      _pickedKey = '';
    });
  }

  void _cancelPick() {
    if (_submitting) return;
    setState(() {
      _openRid = '';
      _pickedKey = '';
    });
  }

  Future<void> _askSettle(PredictRound round) async {
    if (_submitting) return;
    final PredictOption? picked = round.optionOf(_pickedKey);
    if (picked == null) return;
    // 二次确认:把后果写全 —— 结算是一次性的,而且会按配的规则发券,
    // 这两件事点下去都撤不回来。
    final bool confirmed = await cyConfirm(
      context,
      title: '公布答案「${picked.label}」?',
      content: '押中的人会按你配的规则拿到奖励。这一轮只能公布一次,公布后不能改。',
      confirmText: '公布并结算',
      cancelText: '再想想',
      nativePresenter: widget.confirmPresenter,
    );
    if (!confirmed || !mounted || _submitting) return;
    setState(() => _submitting = true);
    try {
      final int winners = await ref
          .read(merchantPredictApiProvider)
          .settle(
            nodeId: round.nodeId,
            playDay: round.playDay,
            settledOption: picked.key,
          );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _settledRids.add(round.rid);
        _openRid = '';
        _pickedKey = '';
      });
      CyNativeNotice.show(
        context,
        winners > 0 ? '已公布 · $winners 人猜中' : '已公布 · 无人猜中',
      );
    } on MerchantPredictApiException catch (error) {
      if (!mounted) return;
      // 失败要说人话并且留在原地 —— 这一轮还没结,人得能再试。
      setState(() => _submitting = false);
      CyNativeNotice.show(context, error.message, isError: true);
    }
  }

  List<PredictRound> _visibleRounds(List<PredictRound> rows) => rows
      .where((PredictRound row) => !_settledRids.contains(row.rid))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PredictInboxState> inbox = ref.watch(
      predictInboxProvider,
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _goBack,
          child: const Icon(CupertinoIcons.back, size: 24),
        ),
        middle: const Text('竞猜待答'),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: inbox.when(
            loading: () =>
                const CySkeleton(type: CySkeletonType.list, count: 3),
            error: (Object error, StackTrace _) => StatusView(
              message: '待答列表加载失败',
              sub: friendlyOrBackendMessage(error, fallback: '待答列表没能加载，请稍后重试'),
              icon: Icons.cloud_off,
              scrollable: true,
              retryLabel: '重新加载',
              onRetry: () => ref.invalidate(predictInboxProvider),
            ),
            data: (PredictInboxState state) {
              switch (state) {
                case PredictInboxDenied():
                  return const StatusView(
                    message: '当前岗位不能结算竞猜',
                    sub: '结算会按规则发券,需要项目管理权限。请联系店主调整经营团队权限',
                    icon: Icons.lock_outline,
                    scrollable: true,
                  );
                case PredictInboxReady(:final List<PredictRound> rounds):
                  final List<PredictRound> visible = _visibleRounds(rounds);
                  if (visible.isEmpty) {
                    return const StatusView(
                      message: '没有等你给答案的竞猜',
                      sub: '玩家押完之后,那一轮会出现在这里等你公布答案',
                      icon: Icons.how_to_vote_outlined,
                      scrollable: true,
                    );
                  }
                  return _ReadyList(
                    rounds: visible,
                    openRid: _openRid,
                    pickedKey: _pickedKey,
                    submitting: _submitting,
                    onOpen: _open,
                    onCancelPick: _cancelPick,
                    onPick: (String key) => setState(() => _pickedKey = key),
                    onAskSettle: _askSettle,
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _ReadyList extends StatelessWidget {
  const _ReadyList({
    required this.rounds,
    required this.openRid,
    required this.pickedKey,
    required this.submitting,
    required this.onOpen,
    required this.onCancelPick,
    required this.onPick,
    required this.onAskSettle,
  });

  final List<PredictRound> rounds;
  final String openRid;
  final String pickedKey;
  final bool submitting;
  final ValueChanged<PredictRound> onOpen;
  final VoidCallback onCancelPick;
  final ValueChanged<String> onPick;
  final ValueChanged<PredictRound> onAskSettle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space3,
        CyTokens.pageX,
        CyTokens.space6,
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: CyTokens.space3),
          child: Text(
            '共 ${rounds.length} 轮等你给答案',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ),
        for (final PredictRound round in rounds)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space3),
            child: _PredictCard(
              round: round,
              open: openRid == round.rid,
              pickedKey: openRid == round.rid ? pickedKey : '',
              submitting: submitting,
              onOpen: () => onOpen(round),
              onCancelPick: onCancelPick,
              onPick: onPick,
              onAskSettle: () => onAskSettle(round),
            ),
          ),
      ],
    );
  }
}

class _PredictCard extends StatelessWidget {
  const _PredictCard({
    required this.round,
    required this.open,
    required this.pickedKey,
    required this.submitting,
    required this.onOpen,
    required this.onCancelPick,
    required this.onPick,
    required this.onAskSettle,
  });

  final PredictRound round;
  final bool open;
  final String pickedKey;
  final bool submitting;
  final VoidCallback onOpen;
  final VoidCallback onCancelPick;
  final ValueChanged<String> onPick;
  final VoidCallback onAskSettle;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      round.nodeName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      round.roundText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              _DeadlineBadge(round: round),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          Text(
            round.question,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            round.betText,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          if (open) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              '选出正确答案',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            for (final PredictOption option in round.options)
              Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2),
                child: _OptionRow(
                  option: option,
                  selected: option.key == pickedKey,
                  onTap: submitting ? null : () => onPick(option.key),
                ),
              ),
            const SizedBox(height: CyTokens.space1),
            Row(
              children: <Widget>[
                Expanded(
                  child: _PredictActionButton(
                    label: '先不给',
                    primary: false,
                    enabled: !submitting,
                    loading: false,
                    onPressed: onCancelPick,
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Expanded(
                  child: _PredictActionButton(
                    label: '就是这个',
                    primary: true,
                    // ★ 没选选项就点不动 —— 而且**看得出来**点不动。
                    enabled: pickedKey.isNotEmpty && !submitting,
                    loading: submitting,
                    onPressed: onAskSettle,
                  ),
                ),
              ],
            ),
          ] else
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: submitting ? null : onOpen,
              child: Row(
                children: <Widget>[
                  Text(
                    round.optionText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '给答案',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.brand,
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: palette.brand,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeadlineBadge extends StatelessWidget {
  const _DeadlineBadge({required this.round});

  final PredictRound round;

  @override
  Widget build(BuildContext context) {
    // 今天不给答案,明天这一轮就作废 —— 这一档要红。
    final Color tone = round.expired
        ? CyPalette.of(context).statusDanger
        : CyPalette.of(context).statusWarning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2_5,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(
        round.deadlineText,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: CyTokens.typeMicro,
          fontWeight: FontWeight.w600,
          color: tone,
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    this.onTap,
  });

  final PredictOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: option.label,
      child: ExcludeSemantics(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: CyTokens.space2,
            ),
            decoration: BoxDecoration(
              color: selected ? palette.brandSoft : palette.bgSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(
                color: selected ? palette.brand : palette.borderSubtle,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    option.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(CupertinoIcons.checkmark, size: 16, color: palette.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「先不给 / 就是这个」两个动作键。
///
/// 为什么不用 [CyNativeButton]:它的禁用态底色与启用态**完全相同**
/// (`disabledColor: colors.background`),而这一屏的主键在「没选选项」时
/// 恰恰是禁用的 —— 看起来能点、点下去没反应,正是这一页最不能出的错。
/// 这里按原型口径(**换色不降透明度**)给禁用态:中性底 + 占位色字。
class _PredictActionButton extends StatelessWidget {
  const _PredictActionButton({
    required this.label,
    required this.primary,
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool primary;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool active = enabled && !loading;
    final Color background = active
        ? (primary ? palette.actionPrimaryBg : palette.actionSecondaryBg)
        : palette.bgSubtle;
    final Color foreground = active
        ? (primary ? palette.actionPrimaryFg : palette.textPrimary)
        : palette.textPlaceholder;
    final Widget content = loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CupertinoActivityIndicator(color: foreground),
              const SizedBox(width: CyTokens.space2),
              Text(label),
            ],
          )
        : Text(label);
    return Semantics(
      container: true,
      button: true,
      enabled: active,
      label: label,
      value: loading ? '正在处理' : null,
      liveRegion: loading,
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: active ? onPressed : null,
          color: background,
          disabledColor: background,
          foregroundColor: foreground,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          minimumSize: const Size(44, CyTokens.btnH),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.btnPadX),
          child: content,
        ),
      ),
    );
  }
}
