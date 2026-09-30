import 'package:flutter/cupertino.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/category.dart';
import '../../data/models/topic_template.dart';

/// 「主题」tab 的货架内容。
///
/// 1:1 对齐小程序 `pages/template/index`(master@90e66d70)的**主题分支**:
/// `rebuildLists()`(index.js:407-431)算置顶排序与四条文案,wxml 的四态 +
/// banner + 置顶列表 + 「其他模板」三段结构。**不发请求、不判角色** ——
/// 状态与数据都由页面给(和 [TemplateSquareView] 同一条纪律),这样
/// 「迟到响应不许画到别的 tab 上」那条口径可以在页面层单测,不靠渲染猜。
///
/// ★ 一个列表 + 置顶排序,**不硬筛**:选中品类置顶、其余落到「其他模板」继续显示。
///   快照注释写明理由 —— 玩法约 27 个 ÷ 9 个品类 ≈ 每类 3 个,硬筛下去大部分
///   品类只剩一两张甚至空,比「点了没反应」更糟。
class TemplateTopicShelf extends StatelessWidget {
  const TemplateTopicShelf({
    super.key,
    required this.rows,
    required this.categories,
    required this.selectedCategoryId,
    required this.loading,
    required this.listLoaded,
    required this.error,
    required this.onCategorySelected,
    required this.onRetry,
    required this.onUse,
  });

  /// 货架全量(`/api/template/topic-template/list` 原始回包,已装饰)。
  /// ★ 传**全量**而不是切好的两段:置顶/其余是这里的派生结果,页面不用维护。
  final List<TopicTemplate> rows;

  /// 分类行数据源:仍走 `/api/template/homeData` 的 `categoryList`
  /// (快照注释:另外四段是同一张表的四刀切,不再消费)。
  final List<Category> categories;

  /// 选中的品类。**null = 「推荐」**(不是「全部」)。
  final int? selectedCategoryId;

  /// 当前 tab 是否有请求在途。骨架/刷新条都看它,再叠 [listLoaded] 分首次与已有内容。
  final bool loading;

  /// 当前 tab 是否已拿到过数据。★ 四态的闸门位:迟到响应只进缓存不动它,
  /// 空缓存就不会被渲染成假空态。
  final bool listLoaded;

  /// 当前 tab 的错误文案。null = 无错误。
  final String? error;

  final ValueChanged<int?> onCategorySelected;
  final VoidCallback onRetry;

  /// 用模板(整包复制成我的草稿)。卡片本体就是入口 —— 快照的用户裁决:
  /// 货架卡只负责查看/使用,配置留给落地后的编辑器。
  final ValueChanged<TopicTemplate> onUse;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);

    // ===== rebuildLists():置顶排序 + 文案 =====
    final List<TopicTemplate> hit = <TopicTemplate>[];
    final List<TopicTemplate> miss = <TopicTemplate>[];
    for (final TopicTemplate row in rows) {
      (row.matchesCategory(selectedCategoryId) ? hit : miss).add(row);
    }
    final bool picked = selectedCategoryId != null;
    // 品类名从同一份 categoryList 里取 —— chips 就是它渲染的,选中项必然能解析到。
    final String catName = picked
        ? categories
              .where((Category c) => c.id == selectedCategoryId)
              .map((Category c) => c.name)
              .firstWhere((String name) => true, orElse: () => '')
        : '';
    final TopicTemplate? banner = hit.isNotEmpty
        ? hit.first
        : (miss.isNotEmpty ? miss.first : null);
    // ★ 无品类时「推荐」不叫「全部」:activeCat=0 走的是运营编排,不是全量 ——
    //   叫「全部」会让用户以为看到了所有模板,找不到的东西会被当成不存在。
    final String bannerTitle = picked ? '$catName · 精选' : '推荐';
    final List<TopicTemplate> topList = picked
        ? hit
        : hit.skip(1).toList(growable: false);
    final List<TopicTemplate> tailList = picked
        ? const <TopicTemplate>[]
        : miss;
    final String topTitle = picked ? '$catName · ${hit.length} 个' : '全部主题';
    const String emptyTitle = '还没有可复用的主题模板';
    const String emptySub = '新的整包主题开放后会出现在这里,也可以先去「游戏」里挑单个玩法';

    final bool firstLoad = loading && !listLoaded;
    final bool failed = error != null && !listLoaded;
    // ★ 空态必须把 banner 计入:单条数据时 banner 吃掉唯一内容、两个列表全空,
    //   只看列表会让空态与 banner 大卡同屏(template-tab-failure-state-contract)。
    final bool empty =
        listLoaded && banner == null && topList.isEmpty && tailList.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // L2 分类行。第一项是「推荐」不是「全部」——同 bannerTitle 的理由。
        if (categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              key: const Key('topic-category-row'),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                CyChip(
                  key: const Key('topic-category-recommend'),
                  label: '推荐',
                  selected: !picked,
                  onTap: () => onCategorySelected(null),
                ),
                for (final Category category in categories) ...<Widget>[
                  const SizedBox(width: CyTokens.space2),
                  CyChip(
                    key: Key('topic-category-${category.id}'),
                    label: category.name,
                    selected: selectedCategoryId == category.id,
                    onTap: () => onCategorySelected(category.id),
                  ),
                ],
              ],
            ),
          ),

        // ===== 四态:互斥,只有「正在同步」允许与内容同屏 =====
        if (firstLoad)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
            child: CySkeleton(type: CySkeletonType.card, count: 3),
          ),
        if (failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space6),
            child: StatusView(message: error!, large: true, onRetry: onRetry),
          ),
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space6),
            child: StatusView(
              key: const Key('topic-empty'),
              message: emptyTitle,
              sub: emptySub,
              large: true,
              retryLabel: '刷新试试',
              onRetry: onRetry,
            ),
          ),
        if (loading && listLoaded)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              0,
              CyTokens.pageX,
              CyTokens.space2,
            ),
            child: Text(
              '正在同步最新内容…',
              style: CyType.caption1.copyWith(color: palette.textSecondary),
            ),
          ),

        // ===== Banner:一张头牌 =====
        if (banner != null) ...<Widget>[
          _TopicSectionHeading(bannerTitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            child: _TopicBannerCard(
              key: const Key('topic-banner-card'),
              template: banner,
              onTap: () => onUse(banner),
            ),
          ),
        ],

        // ===== 置顶列表:选中品类在前,其余不筛掉 =====
        if (topList.isNotEmpty) ...<Widget>[
          _TopicSectionHeading(topTitle),
          _TopicRowList(
            key: const Key('topic-top-list'),
            rows: topList,
            onUse: onUse,
          ),
        ],

        if (tailList.isNotEmpty) ...<Widget>[
          _TopicSectionHeading(
            '其他模板',
            trailing: Text(
              '不筛掉，继续显示',
              style: CyType.caption1.copyWith(color: palette.textTertiary),
            ),
          ),
          _TopicRowList(
            key: const Key('topic-tail-list'),
            rows: tailList,
            onUse: onUse,
          ),
        ],
        const SizedBox(height: CyTokens.space8 * 2),
      ],
    );
  }
}

class _TopicSectionHeading extends StatelessWidget {
  const _TopicSectionHeading(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        CyTokens.space2,
      ),
      child: CySectionTitle(title, trailing: trailing),
    );
  }
}

/// 头牌卡:封面 + meta 角标 + 标题 + 副标。
class _TopicBannerCard extends StatelessWidget {
  const _TopicBannerCard({
    super.key,
    required this.template,
    required this.onTap,
  });

  final TopicTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 0),
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                child: _TopicCover(template: template, height: 175),
              ),
              if (template.metaText.isNotEmpty)
                Positioned(
                  left: CyTokens.space3,
                  bottom: CyTokens.space3,
                  child: CyTag(label: template.metaText),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            template.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CyType.callout.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          if (template.displaySubtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              template.displaySubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CyType.caption1.copyWith(color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 置顶列表 / 其他模板:同一套行卡,两处复用。
class _TopicRowList extends StatelessWidget {
  const _TopicRowList({super.key, required this.rows, required this.onUse});

  final List<TopicTemplate> rows;
  final ValueChanged<TopicTemplate> onUse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: Column(
        children: <Widget>[
          for (final TopicTemplate row in rows)
            _TopicRow(
              key: Key('topic-row-${row.id}'),
              template: row,
              onTap: () => onUse(row),
            ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({super.key, required this.template, required this.onTap});

  final TopicTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final String status = template.statusText;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 0),
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space1_5),
        child: Row(
          children: <Widget>[
            // 行内小图几何 = 画板05 的 88×66pt(cml-pic 176rpx×132rpx)。
            ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              child: _TopicCover(template: template, width: 88, height: 66),
            ),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    template.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CyType.subhead.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (template.metaText.isNotEmpty ||
                      status.isNotEmpty) ...<Widget>[
                    const SizedBox(height: CyTokens.space1),
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            template.metaText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CyType.caption1.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        // 状态标与 meta 不是一个层级:「实验模板」不是尺寸信息,
                        // 用 CyTag 分隔,不混进 meta 的点分串里。
                        if (status.isNotEmpty) ...<Widget>[
                          const SizedBox(width: CyTokens.space2),
                          CyTag(label: status),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面。空 URL / 加载失败都落到同一块明确的失败态 ——
/// 不拿别的业务内容图冒充模板封面(快照的 cover-error 口径)。
class _TopicCover extends StatelessWidget {
  const _TopicCover({required this.template, this.width, this.height});

  final TopicTemplate template;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 88pt 行内小图里「图标+六字」太挤(二轮 critic),占位只留图标;
    // 175pt 大卡有呼吸空间,保留文字说明失败对象。
    final bool compact = (width ?? double.infinity) < 120;
    return CyNetImage(
      template.imgUrl,
      width: width,
      height: height,
      fallback: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: palette.bgSurfaceSubtle,
          child: Center(
            child:
                compact
                    ? Icon(
                      CupertinoIcons.photo,
                      color: palette.textTertiary,
                      size: CyTokens.space5,
                    )
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          CupertinoIcons.photo,
                          color: palette.textTertiary,
                          size: CyTokens.space5,
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          '封面暂不可用',
                          style: CyType.caption1.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}
