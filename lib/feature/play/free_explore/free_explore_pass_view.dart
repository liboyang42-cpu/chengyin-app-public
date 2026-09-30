import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/checkin_models.dart';
import 'free_explore_layout.dart';
import 'widgets/segmented_ring.dart';

/// 屏① 通行证首屏。**只读渲染**,不持有状态 —— 数据由 PlaySessionPage 传进来,
/// 这样它能脱离 Riverpod 直接进 widget test 与 golden。
class FreeExplorePassView extends StatelessWidget {
  const FreeExplorePassView({
    super.key,
    required this.data,
    required this.onTapNode,
    this.completionActions,
  });

  final PlayNodesResult data;
  final ValueChanged<PlayNode> onTapNode;
  final Widget? completionActions;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final String? desc = data.topicDesc;

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              // topicDesc 为 null 时整段不渲染(连同间距)——不留空标题
              if (desc != null && desc.isNotEmpty) ...<Widget>[
                Text(desc, style: t.bodyMedium?.copyWith(height: 1.6)),
                const SizedBox(height: 20),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SegmentedRing(total: data.total, done: data.doneCount),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${data.doneCount}/${data.total} 已核销',
                          style: t.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${data.total} 家商户 · 没有顺序,只去一家也成立',
                          style: t.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('这些商家在等你', style: t.titleMedium),
              const SizedBox(height: 4),
              // 小程序 .fx-lhd__s:卡包的分区副行,说清「不排顺序」这件事。
              Text(
                '没有顺序,去哪家都算',
                style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverGrid(
            // ★ 尺寸恒定:childAspectRatio 固定,**不要**按可用高度算 ——
            //   按屏高等分会让 5/6 章时卡片缩小,那正是本批要防的。
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1 / kFreeExploreTileRatio,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int i) => Hero(
                tag: 'fx-card-${data.nodes[i].nodeId}',
                child: _Tile(
                  key: ValueKey<String>('fx-tile-$i'),
                  index: i,
                  node: data.nodes[i],
                  chapter: data.chapterOf(data.nodes[i]),
                  onTap: () => onTapNode(data.nodes[i]),
                ),
              ),
              childCount: data.nodes.length,
            ),
          ),
        ),
        if (completionActions != null)
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverToBoxAdapter(child: completionActions),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.index,
    required this.node,
    required this.chapter,
    required this.onTap,
  });

  final int index;
  final PlayNode node;
  final PlayChapter? chapter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final String? meta = chapter == null
        ? null
        : <String?>[
            chapter!.meta,
            chapter!.title,
          ].where((String? x) => x != null && x.isNotEmpty).join(' · ');

    final Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (node.imgUrl != null && node.imgUrl!.isNotEmpty)
            Image.network(
              node.imgUrl!.split(',').first,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: AppColors.divider),
            )
          else
            Container(color: AppColors.divider),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xCC000000)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          if (meta != null && meta.isNotEmpty)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  meta,
                  style: t.labelSmall?.copyWith(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );

    // 已核销:整张阴掉。**不加任何文字角标** —— 用户 09-07 定的口径。
    final Widget content = node.done
        ? Opacity(
            key: ValueKey<String>('fx-tile-dim-$index'),
            opacity: 0.45,
            child: card,
          )
        : card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
