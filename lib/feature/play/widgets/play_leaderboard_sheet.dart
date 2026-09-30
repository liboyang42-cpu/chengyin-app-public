import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_native_sheet.dart';
import '../../../core/widgets/cy_widgets.dart';
import '../../../core/widgets/status_view.dart';
import '../../../data/api/play_leaderboard_api.dart';
import '../../../data/models/play_leaderboard.dart';

Future<void> showPlayLeaderboardSheet({
  required BuildContext context,
  int? activityId,
  int? topicId,
  PlayLeaderboardGateway? api,
}) => showCyNativeSheet<void>(
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  context,
  // 真源 topGap .3(约 70% 屏高)介于两档之间:用可拖双档,半屏起、可上拖全屏。
  detents: CyNativeSheetDetents.both,
  builder: (BuildContext sheetContext) =>
      PlayLeaderboardSheet(activityId: activityId, topicId: topicId, api: api),
);

/// 玩家通关层里的同行者榜。数据错误与空榜是两个不同状态。
class PlayLeaderboardSheet extends ConsumerStatefulWidget {
  const PlayLeaderboardSheet({
    super.key,
    this.activityId,
    this.topicId,
    this.api,
    this.scrollController,
  });

  final int? activityId;
  final int? topicId;
  final PlayLeaderboardGateway? api;
  final ScrollController? scrollController;

  @override
  ConsumerState<PlayLeaderboardSheet> createState() =>
      _PlayLeaderboardSheetState();
}

class _PlayLeaderboardSheetState extends ConsumerState<PlayLeaderboardSheet> {
  PlayLeaderboard? _leaderboard;
  String? _error;
  bool _loading = true;
  int _requestGeneration = 0;

  PlayLeaderboardGateway get _api =>
      widget.api ?? ref.read(playLeaderboardApiProvider);

  @override
  void initState() {
    super.initState();
    _load(showLoading: false);
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    final int generation = ++_requestGeneration;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final PlayLeaderboard result = await _api.fetch(
        activityId: widget.activityId,
        topicId: widget.topicId,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _leaderboard = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error is PlayLeaderboardException
            ? error.message
            : '网络不太好，榜单没拉到';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPopupSurface(
      // 原生 sheet 承载时不画自带底,透出系统材质(S3);回退路径维持真源底。
      isSurfacePainted: !isCyNativeSheet(context),
      child: SafeArea(
        top: false,
        child: Material(
          key: const Key('play-board-root'),
          color: isCyNativeSheet(context)
              ? CupertinoColors.transparent
              : palette.bgPage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space3,
                  CyTokens.space2,
                  CyTokens.space2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '同行者榜',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CyNativeIconButton(
                      key: const Key('play-board-close'),
                      label: '关闭同行者榜',
                      icon: const CyNativeButtonIcon(
                        sfSymbol: 'xmark.circle.fill',
                        fallback: CupertinoIcons.xmark_circle_fill,
                      ),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      // 真源 `pages/play/index.wxml` 的 `.board__loading`:`<cy-skeleton type="list" count="3">`
      // —— 骨架与最终行同构(D4 加载不跳版),不是转圈。
      return Semantics(
        container: true,
        liveRegion: true,
        label: '正在加载同行者榜',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.pageX - CyTokens.space3,
            ),
            child: const CySkeleton(type: CySkeletonType.list, count: 3),
          ),
        ),
      );
    }
    if (_error != null) {
      // 与同域 `play_operating_system_sheet.dart` 的错误态同一件共用件、
      // 同一个警示形状:只有一行白字 + 一个实心胶囊,读起来跟「空态」没有区别
      // (V5:状态不能只靠颜色/文字)。
      return StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: '同行者榜加载失败',
        sub: _error,
        onRetry: _load,
      );
    }
    final PlayLeaderboard? leaderboard = _leaderboard;
    if (leaderboard != null && leaderboard.entries.isEmpty) {
      // 真源 `.board__empty`(上下 32rpx=16pt 留白)之后紧跟 `.board__me`:
      // 「我」这一格永远是**跟在内容下面的列表项**,不是钉在 sheet 底的页脚。
      return ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          0,
          CyTokens.pageX,
          CyTokens.space4,
        ),
        children: <Widget>[
          const Expanded(
            // 小程序的空榜是一句整话(board__empty),不拆主副。
            child: StatusView(message: '这一场还没人上榜,你走一关就是第一名'),
          ),
          _MyProgressRow(entry: leaderboard.me),
        ],
      );
    }
    if (leaderboard != null) {
      // sheet 高 70% 屏(topGap .3),榜常只有三五条:把「我」钉在底部会在
      // 列表和页脚之间留一大块死黑,且真源 `.board__me` 是 `margin-top: 28rpx`
      // 跟在最后一行**下面**的内容。所以 me 行进列表当最后一项。
      return ListView.separated(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space2,
          CyTokens.pageX,
          CyTokens.space4,
        ),
        itemCount: leaderboard.entries.length + 1,
        // 真源 `.board__row` 每行都有 border-bottom(含最后一行),
        // 所以「我」上面那道发丝线是跟着来的,不用特判。
        separatorBuilder: (BuildContext context, int index) =>
            Container(height: 1, color: CyPalette.of(context).borderSubtle),
        itemBuilder: (BuildContext context, int index) =>
            index < leaderboard.entries.length
            ? _LeaderboardRow(
                entry: leaderboard.entries[index],
                first: index == 0,
              )
            : _MyProgressRow(entry: leaderboard.me),
      );
    }
    return const SizedBox.shrink();
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.first});

  final PlayLeaderboardEntry entry;
  final bool first;

  // 榜首展示号:真源 `.board__rank.is-first` = 48rpx(24pt)+ `--cy-gold`
  // (= `--cy-color-rare` #F59F00,`style/tokens.wxss:313`「稀有徽章 / 榜首(仅图形与大字)」)。
  // 生成物无 rare token,按同域既有口径(仓内先例:`p3/growth/leaderboard_page.dart`
  // `_Podium._rings`、本族 `playkit_walk_view.dart` 台面琥珀)落逐值常量并注来源。
  static const Color _kRankGold = Color(0xFFF59F00);

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      container: true,
      readOnly: true,
      label: '第 ${entry.rank} 名，${entry.displayName}，完成 ${entry.score} 关',
      child: ExcludeSemantics(
        child: Container(
          // 真源 `.board__row.is-first` 上下 32rpx(其余 26rpx)—— 榜首多给一档呼吸位。
          padding: EdgeInsets.symmetric(
            horizontal: CyTokens.space2,
            vertical: first ? CyTokens.space4 : CyTokens.space3,
          ),
          child: Row(
            children: <Widget>[
              // 真源 `.board__rank` 是 56rpx(28pt)定宽列,`.board__row` 的
              // `gap:24rpx` = 12pt 落到每个子件之间。
              SizedBox(
                width: 28,
                child: Text(
                  '${entry.rank}',
                  textAlign: TextAlign.center,
                  // 真源 `.board__rank`:斜体 + subtitle 档;`.is-first` 再放大到 48rpx 并转金。
                  style: TextStyle(
                    color: first ? _kRankGold : palette.textSecondary,
                    fontSize: first ? 24 : CyTokens.typeCardTitle,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              // 真源 `.board__avatar` = 64rpx(32pt)。
              CyAvatar(
                url: entry.avatarUrl,
                fallback: entry.displayName,
                size: 32,
              ),
              const SizedBox(width: CyTokens.space3),
              // 真源 `.board__row` 是一行 flex:`nick{flex:1}` 之后
              // `.board__score` 与 `.board__crown` 各自贴右。此前把分数折到
              // 昵称下面,行高被撑成两行、右侧留空,和榜内其它行的读法不一致。
              Expanded(
                child: Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${entry.score} 关',
                // 真源 `.board__score`:label 档 + text-body。
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: CyTokens.typeLabel,
                ),
              ),
              if (first) ...<Widget>[
                const SizedBox(width: CyTokens.space2),
                // 真源 `.board__crown` = `--cy-gold`(与榜首名次同色),
                // 里面是 `<cy-icon name="star" size="32"/>` —— 32rpx = 16pt。
                Icon(
                  CupertinoIcons.star_fill,
                  size: 16,
                  color: _kRankGold,
                  semanticLabel: '当前第一名',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MyProgressRow extends StatelessWidget {
  const _MyProgressRow({required this.entry});

  final PlayLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final String rank = entry.rank?.toString() ?? '—';
    final String progress = entry.rank == null
        ? '${entry.score} 关 · 继续走进榜'
        : '${entry.score} 关';
    final String semanticRank = entry.rank == null
        ? '暂未上榜'
        : '第 ${entry.rank} 名';
    return Semantics(
      key: const Key('play-board-me'),
      container: true,
      readOnly: true,
      label:
          '我的进度，$semanticRank，完成 ${entry.score} 关'
          '${entry.rank == null ? '，继续走进榜' : ''}',
      child: ExcludeSemantics(
        child: Container(
          // 真源 `.board__me`:padding 28rpx(14pt) 四周、`margin-top: 28rpx`、
          // 整条 brand 底 + pill 圆角。
          padding: const EdgeInsets.all(CyTokens.space3_5),
          decoration: BoxDecoration(
            color: palette.actionPrimaryBg,
            borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          ),
          margin: const EdgeInsets.only(top: CyTokens.space3_5),
          // 真源是 `display:flex; gap:24rpx` + `.board__me-score{margin-left:auto}`
          // —— 名次、昵称、分数**同一行**,分数顶到右端。此前把分数堆到
          // 「我」下面,胶囊右半空着,读起来像两行卡片而不是一行进度。
          child: Row(
            children: <Widget>[
              Text(
                rank,
                // 真源 `.board__me-rank`:subtitle 档斜体(与榜内名次同款观感)。
                style: TextStyle(
                  color: palette.actionPrimaryFg,
                  fontSize: CyTokens.typeCardTitle,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Text(
                '我',
                style: TextStyle(
                  color: palette.actionPrimaryFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: Text(
                  progress,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: palette.actionPrimaryFg,
                    fontSize: CyTokens.typeLabel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
