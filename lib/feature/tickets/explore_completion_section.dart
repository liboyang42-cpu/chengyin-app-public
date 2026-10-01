import '../orders/registration_order_strings.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../data/models/explore_completion.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 探店日完局面。**纯读**,不发奖。
///
/// ★★★ 后端对非探索票的订单是 fail-closed:返「该订单没有探店日完局面」。
///   所以这里**出错就整块收起**(返回 SizedBox.shrink),
///   既不渲染错误卡、也不渲染「图鉴 0/0」的空壳 ——
///   吞成空态渲染出来,就等于把后端那道 fail-closed 又打开了。
///   (小程序 scene-member-order-detail 的 emptyCompletion 同解:
///    「业务失败也不留半个空壳:整块收起,玩家看到的仍是原来的订单详情」。)
final exploreCompletionProvider = FutureProvider.autoDispose
    .family<ExploreCompletion, int>((Ref ref, int registrationId) async {
      final data = await ref
          .watch(registrationApiProvider)
          .exploreCompletion(registrationId);
      return ExploreCompletion.fromJson(data);
    });

class ExploreCompletionSection extends ConsumerWidget {
  const ExploreCompletionSection({super.key, required this.registrationId});

  final int registrationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(exploreCompletionProvider(registrationId));
    return async.when(
      // 加载中也不占位:这是订单详情的**附加块**,不是主体。
      // 给它一个骨架会让每张非探索票的订单详情都先闪一下再消失。
      loading: () => const SizedBox.shrink(),
      error: (Object e, _) => const SizedBox.shrink(),
      data: (ExploreCompletion c) => _Body(completion: c),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.completion});
  final ExploreCompletion completion;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _following = false;
  bool _followed = false;
  bool _joining = false;
  bool _joined = false;

  /// 真源 joinStateText:公开团直进「已加入俱乐部」、私密团进待审
  /// 「申请已提交，等待主理人审核」—— 两种回执都要说清,
  /// 不许把 pending 显示成已入群。
  bool? _joinSucceeded;

  Future<void> _follow(ExploreRevisit r) async {
    if (_following) return;
    setState(() => _following = true);
    try {
      await ref
          .read(registrationApiProvider)
          .toggleFollow(r.clubLeaderMemberId!);
      // ★ 只有服务端确认才置位 —— 乐观置位会让失败的关注在屏幕上变成"已关注"。
      if (!mounted) return;
      setState(() => _followed = true);
      // 真源 followClub 成功只 toast「已关注」,不常驻状态文字。
      CyNativeNotice.show(context, stringsOf(context).ticketCompletionFollowed);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        localizedOrderError(context, e),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _join(ExploreRevisit r) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      final String? state = await ref.read(clubApiProvider).join(r.clubId);
      if (!mounted) return;
      final bool joined = state == 'joined';
      setState(() {
        _joined = joined;
        _joinSucceeded = joined;
      });
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        localizedOrderError(context, e),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    final ExploreCompletion c = widget.completion;
    final ExploreRevisit? r = c.revisit;
    final strings = stringsOf(context);
    final String? progress = c.requiredChapterCount > 0
        ? strings.ticketCompletionProgress(c.redeemedChapterCount, c.requiredChapterCount) : null;
    final String? empty = c.awardsCredited ? null : c.completed
        ? strings.ticketCompletionPendingAwards
        : strings.ticketCompletionVisitAll(c.requiredChapterCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: CyTokens.space5),
        Wrap(
          spacing: CyTokens.space3,
          children: <Widget>[
            Text(stringsOf(context).ticketCompletionAlbum, style: textTheme.titleMedium),
            if (progress != null)
              Text(
                progress,
                style: textTheme.labelMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
          ],
        ),
        if (c.stamps.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: c.stamps
                .map((ExploreStamp s) => _StampChip(stamp: s))
                .toList(),
          ),
        ],
        const SizedBox(height: CyTokens.space4),
        Text(stringsOf(context).ticketCompletionAwards, style: textTheme.titleSmall),
        const SizedBox(height: CyTokens.space2),
        if (empty != null)
          Text(
            empty,
            style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          )
        else
          ...c.awards.map((ExploreAward a) => _AwardRow(award: a)),
        if (r != null) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          // 真源批5 第三卡标题原话「下次再来」(旧文案「再来一次」是自造)。
          Text(stringsOf(context).ticketCompletionRevisit, style: textTheme.titleSmall),
          const SizedBox(height: CyTokens.space2),
          Text(
            r.hasServerClubName ? r.clubName : strings.ticketCompletionHostClub,
            style: textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CyTokens.space1),
          Wrap(
            children: <Widget>[
              // 关注是**自愿**的,不与任何权益交换(小程序注释原话)。
              // 真源 revisit-actions 只有这两颗钮:关注主办俱乐部 / 加入俱乐部,
              // 没有"看俱乐部"入口 —— 旧钮是自造的,一并收掉。
              if (r.canFollow && !_followed)
                CupertinoButton(
                  key: const Key('explore-follow-club'),
                  onPressed: _following ? null : () => _follow(r),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                  ),
                  child: Text(_following ? stringsOf(context).ticketCompletionFollowing : stringsOf(context).ticketCompletionFollow),
                ),
              if (r.canJoin && !_joined)
                CupertinoButton(
                  key: const Key('explore-join-club'),
                  onPressed: _joining ? null : () => _join(r),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                  ),
                  child: Text(_joining ? stringsOf(context).ticketCompletionSubmitting : stringsOf(context).ticketCompletionJoin),
                ),
            ],
          ),
          if (_joinSucceeded != null)
            Text(
              _joinSucceeded! ? stringsOf(context).ticketCompletionJoined : stringsOf(context).ticketCompletionJoinPending,
              style: textTheme.labelMedium?.copyWith(
                color: palette.textTertiary,
              ),
            ),
          // 真源 revisit-next:没有下期也占行,钮上写的就是那句
          // 「下一期开售后会在这里出现」;goNextEdition 对无下期的点击原地不动。
          CupertinoButton(
            key: const Key('explore-next-edition'),
            onPressed: r.hasNextEdition
                ? () => context.push('/topic/${r.nextEditionTarget!.topicId}')
                : null,
            minimumSize: const Size(44, 44),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
            child: Text(_nextEditionText(context, r), style: textTheme.bodyMedium),
          ),
        ],
      ],
    );
  }
}

class _StampChip extends StatelessWidget {
  const _StampChip({required this.stamp});
  final ExploreStamp stamp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: stamp.collected ? palette.bgElevated : palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        border: Border.all(
          color: stamp.collected ? palette.brand : palette.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            stamp.collected ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: stamp.collected ? palette.brand : palette.textTertiary,
          ),
          const SizedBox(width: CyTokens.space1),
          Text(
            stamp.hasServerTitle ? stamp.title : stringsOf(context).ticketCompletionChapter(stamp.chapterId),
            style: textTheme.bodySmall?.copyWith(
              color: stamp.collected
                  ? palette.textPrimary
                  : palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AwardRow extends StatelessWidget {
  const _AwardRow({required this.award});
  final ExploreAward award;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    final String? amount = award.amountText;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        children: <Widget>[
          if (award.iconUrl.isNotEmpty) ...<Widget>[
            CyNetImage(award.iconUrl, width: 24, height: 24),
            const SizedBox(width: CyTokens.space2),
          ],
          Expanded(child: Text(award.title, style: textTheme.bodyMedium)),
          // ★ 没有数量的奖励不显示数字 —— 见 ExploreAward.amount 的注释。
          //   取色按真源 `.award-amount` = `var(--cy-brand)`(黑白系里 brand
          //   解析成 text-primary),不是 success 绿 —— 到账是事实陈述,
          //   不是需要警示的状态(同页图鉴章收集态也走 brand)。
          if (amount != null)
            Text(
              amount,
              style: textTheme.titleSmall?.copyWith(color: palette.brand),
            ),
        ],
      ),
    );
  }
}

String _nextEditionText(BuildContext context, ExploreRevisit revisit) {
  final strings = stringsOf(context);
  final next = revisit.nextEditionTarget;
  if (next == null) return strings.ticketCompletionNextPending;
  final raw = next.startDate ?? '';
  final date = raw.length <= 5 ? '' : raw.substring(5, raw.length < 10 ? raw.length : 10);
  return strings.ticketCompletionNextStarts(
    next.hasServerName ? next.name : strings.ticketCompletionNext, date);
}
