import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_search_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../auth/login_gate.dart';
import 'search_controller.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 搜索结果独立页。对齐小程序 search2/result:顶部搜索框 + 类别 tabs +
/// 结果卡片列表。数据源 searchResultsProvider 并发打主题/活动/俱乐部/商家四个接口。
class SearchResultPage extends ConsumerStatefulWidget {
  const SearchResultPage({
    super.key,
    this.keyword = '',
    this.categoryId,
    this.startDate,
    this.endDate,
    this.minPrice,
    this.maxPrice,
  });

  final String keyword;
  final int? categoryId;

  /// 来时的日期/价格筛选(URL 带入),结果页客户端兜底过滤消费。
  final String? startDate;
  final String? endDate;
  final double? minPrice;
  final double? maxPrice;

  @override
  ConsumerState<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends ConsumerState<SearchResultPage> {
  /// 搜索框里当前的字。初值来自路由参数(从搜索页带过来的词)。
  /// ⚠️ 别叫 `_query` —— 那个名字已经是下面那个 `SearchQuery` getter。
  late String _input;
  SearchResultType? _activeType;

  @override
  void initState() {
    super.initState();
    _input = widget.keyword;
  }

  @override
  void dispose() {
    super.dispose();
  }

  SearchQuery get _query => SearchQuery(
    keyword: _input,
    categoryId: widget.categoryId,
    startDate: widget.startDate,
    endDate: widget.endDate,
    minPrice: widget.minPrice,
    maxPrice: widget.maxPrice,
  );

  void _onSubmit(String v) {
    ref.invalidate(searchResultsProvider(_query));
    setState(() => _activeType = null);
  }

  void _openResult(SearchResultRow row) {
    final String? route = searchResultRoute(row);
    if (route != null) {
      context.push(route);
      return;
    }
    // 商家结果没绑会员主体时无法打开公开主页，与小程序一样明示拦住。
    CyNativeNotice.show(context, '这条结果暂不可打开');
  }

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(searchResultsProvider(_query));

    // 逐请求失败计数(对齐小程序 result/index.js finish()):部分失败但仍有
    // 结果时照常出结果,只补一条 toast;全失败/零结果走下面的错误态。
    ref.listen(searchResultsProvider(_query), (
      AsyncValue<SearchResultBundle>? previous,
      AsyncValue<SearchResultBundle> next,
    ) {
      final data = next.value;
      if (data != null && data.hasFailure && data.rows.isNotEmpty) {
        CyNativeNotice.show(context, '部分搜索没有完成，结果可能不全');
      }
    });

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.pageX,
                  vertical: CyTokens.space3,
                ),
                child: CySearchField(
                  value: _input,
                  placeholder: '搜索主题、活动、俱乐部、商家',
                  onChanged: (String v) => setState(() => _input = v),
                  onSubmitted: _onSubmit,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: CyTokens.pageX),
                child: bundle.when(
                  loading: () => const SizedBox.shrink(),
                  error: (Object err, StackTrace st) => const SizedBox.shrink(),
                  // 药丸型 tabs 按手册 §4 #24 保留自绘(内容层),不收敛成
                  // 原生分段;几何照小程序 search2/result 的 44pt 行。
                  data: (SearchResultBundle data) => SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.only(right: CyTokens.pageX),
                      children: <Widget>[
                        _TypeChip(
                          label: '全部',
                          selected: _activeType == null,
                          onTap: () => setState(() => _activeType = null),
                        ),
                        for (final SearchResultType t
                            in SearchResultType.values)
                          _TypeChip(
                            label: '${_labelOf(t)} ${data.counts[t] ?? 0}',
                            selected: _activeType == t,
                            onTap: () => setState(() => _activeType = t),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: bundle.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(CyTokens.space3),
                    child: CySkeleton(
                      // 真源 pages/search2/result 结果流用 feed-card 档。
                      type: CySkeletonType.feedCard,
                      count: 3,
                    ),
                  ),
                  error: (Object err, StackTrace st) => StatusView(
                    message: '没能完成搜索',
                    sub: '网络请求失败,重试会重新拉取一次',
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: () {
                      ref.invalidate(searchResultsProvider(_query));
                      setState(() => _activeType = null);
                    },
                  ),
                  data: (SearchResultBundle data) {
                    final rows = _activeType == null
                        ? data.rows
                        : data.rows
                              .where(
                                (SearchResultRow r) => r.type == _activeType,
                              )
                              .toList();
                    final Widget body;
                    if (rows.isEmpty) {
                      // 小程序 finish() 的 searchError 三档:全失败/部分失败
                      // 且一个结果都没有才报错,报错文案逐字对齐。
                      if (data.hasFailure && data.isEmpty) {
                        return StatusView(
                          message: data.allFailed
                              ? '搜索服务暂时不可用，请重试'
                              : '部分搜索没有完成，请重试后再确认结果',
                          icon: Icons.cloud_off,
                          onRetry: () {
                            ref.invalidate(searchResultsProvider(_query));
                            setState(() => _activeType = null);
                          },
                        );
                      }
                      body = StatusView(
                        message: '没有找到匹配内容',
                        sub: data.loginGated
                            ? '有结果需要登录才能搜到,点上方「去登录」'
                            : '换个关键词，或看看地图附近有什么',
                        icon: CupertinoIcons.tray,
                      );
                    } else {
                      body = ListView.separated(
                        padding: EdgeInsets.all(CyTokens.space3),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: CyTokens.space3),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          // 主题走海报信息层级(对齐 search2/result 的
                          // .topic-result-card),其余类型是横排 .result-card。
                          return row.type == SearchResultType.topic
                              ? _TopicPosterCard(
                                  row: row,
                                  onTap: () => _openResult(row),
                                )
                              : _ResultCard(
                                  row: row,
                                  onTap: () => _openResult(row),
                                );
                        },
                      );
                    }
                    return Column(
                      children: <Widget>[
                        if (data.loginGated) _LoginGatedHint(),
                        Expanded(child: body),
                      ],
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

  String _labelOf(SearchResultType t) => switch (t) {
    SearchResultType.topic => '主题',
    SearchResultType.activity => '活动',
    SearchResultType.club => '俱乐部',
    SearchResultType.merchant => '商家',
  };
}

String? searchResultRoute(SearchResultRow row) => switch (row.type) {
  SearchResultType.topic => '/topic/${row.id}',
  SearchResultType.activity => '/activity/${row.id}',
  SearchResultType.club => '/club/${row.id}',
  SearchResultType.merchant =>
    row.memberId == null || row.memberId! <= 0 ? null : '/user/${row.memberId}',
};

/// 有结果源要登录(游客态)时的提示 —— 少给结果得说清为什么,并给出下一步。
class _LoginGatedHint extends ConsumerWidget {
  const _LoginGatedHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      key: const Key('search-login-gated-hint'),
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.space2,
        CyTokens.space1,
      ),
      child: Row(
        children: <Widget>[
          const Expanded(child: Text('登录后能搜到更多结果')),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: () => requireLogin(context, ref),
            child: const Text('去登录'),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: CyTokens.space2),
      child: CyChip(label: label, selected: selected, onTap: onTap),
    );
  }
}

/// 结果卡片:封面(或兜底图标)+ 类型标签 + 标题 + 摘要 + 标签。
/// 尺寸对齐 search2/result 的 .result-card:封面 120rpx 方,min-height 152rpx。
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.row, required this.onTap});

  final SearchResultRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${row.typeLabel} ${row.title}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: onTap,
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76), // 152rpx
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: CyTokens.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(color: CyTokens.borderStrong, width: 1),
            ),
            child: Row(
              children: <Widget>[
                _Cover(row: row),
                const SizedBox(width: CyTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        row.typeLabel,
                        maxLines: 1,
                        style: textTheme.labelSmall?.copyWith(
                          fontSize: CyTokens.typeMicro,
                          height: 1.2,
                          color: CyTokens.textSecondary,
                        ),
                      ),
                      SizedBox(height: CyTokens.space1),
                      Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          fontSize: CyTokens.typeCardTitle,
                          fontWeight: FontWeight.w600,
                          color: CyTokens.textPrimary,
                        ),
                      ),
                      SizedBox(height: CyTokens.space1_5),
                      Text(
                        row.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: CyTokens.typeCaption,
                          color: CyTokens.textTertiary,
                        ),
                      ),
                      if (row.tags.isNotEmpty) ...<Widget>[
                        SizedBox(height: CyTokens.space2),
                        Wrap(
                          spacing: CyTokens.space1,
                          children: <Widget>[
                            for (final String tag in row.tags) _Tag(label: tag),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  // 进下级的 disclosure 用系统 chevron(手册 L3):P3 已把共用层
                  // CyCell 的 Material 图标换成它,颜色交给系统语义色
                  // (手册 §3.6 分工:disclosure 箭头用系统色,不吃恒暗端 token)。
                  padding: const EdgeInsets.only(left: CyTokens.space2),
                  child: const CupertinoListTileChevron(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 主题结果卡:海报信息层级,对齐 search2/result 的 `.topic-result-card`
/// —— 封面 360rpx 高 + 底部压深 scrim + 左下角「主题」胶囊,正文在封面下方。
/// 字段与非主题卡相同(封面/类型/标题/摘要/标签),只有层级不同。
class _TopicPosterCard extends StatelessWidget {
  const _TopicPosterCard({required this.row, required this.onTap});

  final SearchResultRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasCover = row.cover != null && row.cover!.isNotEmpty;
    return Semantics(
      button: true,
      label: '${row.typeLabel} ${row.title}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: onTap,
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            child: Container(
              decoration: BoxDecoration(
                color: CyTokens.bgSurface,
                border: Border.all(color: CyTokens.borderStrong, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: 180, // 360rpx
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ColoredBox(
                          color: CyTokens.bgSurfaceSubtle,
                          child: hasCover
                              ? Image.network(
                                  row.cover!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.route_outlined,
                                    size: 26, // cy-icon route size=52rpx
                                    color: CyTokens.textTertiary,
                                  ),
                                )
                              : const Icon(
                                  Icons.route_outlined,
                                  size: 26,
                                  color: CyTokens.textTertiary,
                                ),
                        ),
                        // --cy-comp-cover-scrim: to top, .82 → .28@55% → 透明
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: <Color>[
                                Color(0xD1000000),
                                Color(0x47000000),
                                Color(0x00000000),
                              ],
                              stops: <double>[0, 0.55, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: CyTokens.space3,
                          bottom: CyTokens.space3,
                          child: Container(
                            height: 24, // min-height 48rpx
                            padding: const EdgeInsets.symmetric(
                              horizontal: CyTokens.space2,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: CyTokens.overlay,
                              borderRadius: BorderRadius.circular(
                                CyTokens.radiusPill,
                              ),
                            ),
                            child: Text(
                              row.typeLabel,
                              // 真源写的是 text-inverse,但暗端口径它是近黑
                              // (#0A0A0A)——压在 .56 黑遮罩上不可读;取
                              // textPrimary 提亮,属「为可读性的适配」(同首轮 §4)。
                              style: TextStyle(
                                fontSize: CyTokens.typeMicro,
                                color: CyTokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(CyTokens.space3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          row.title,
                          style: TextStyle(
                            fontSize: CyTokens.typeCardTitle,
                            fontWeight: FontWeight.w700,
                            height: CyTokens.leadingTight,
                            color: CyTokens.textPrimary,
                          ),
                        ),
                        SizedBox(height: CyTokens.space1),
                        Text(
                          row.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: CyTokens.typeCaption,
                            color: CyTokens.textTertiary,
                          ),
                        ),
                        if (row.tags.isNotEmpty) ...<Widget>[
                          SizedBox(height: CyTokens.space2),
                          Wrap(
                            spacing: CyTokens.space1,
                            children: <Widget>[
                              for (final String tag in row.tags)
                                _Tag(label: tag),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.row});

  final SearchResultRow row;

  @override
  Widget build(BuildContext context) {
    final hasCover = row.cover != null && row.cover!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      child: Container(
        width: 60, // 120rpx
        height: 60,
        color: CyTokens.bgSurfaceSubtle,
        alignment: Alignment.center,
        child: hasCover
            ? Image.network(
                row.cover!,
                fit: BoxFit.cover,
                width: 60,
                height: 60,
                errorBuilder: (_, _, _) => _CoverFallback(row: row),
              )
            : _CoverFallback(row: row),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.row});

  final SearchResultRow row;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (row.type) {
      SearchResultType.topic => Icons.landscape_outlined,
      SearchResultType.activity => Icons.event_outlined,
      SearchResultType.club => Icons.people_outline,
      SearchResultType.merchant => Icons.storefront_outlined,
    };
    return Icon(icon, size: 20, color: CyTokens.textTertiary);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: CyTokens.space2,
        vertical: 1, // 2rpx,让 micro 字号在药丸里视觉居中
      ),
      decoration: BoxDecoration(
        color: CyTokens.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: CyTokens.typeMicro,
          color: CyTokens.textSecondary,
        ),
      ),
    );
  }
}
