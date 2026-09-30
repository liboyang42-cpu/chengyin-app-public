import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/cy_native_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/category.dart';
import 'search_controller.dart';
import 'search_filter_sheet.dart';
import '../../core/analytics/tracker.dart';
import 'city_node_search_page.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 搜索页。对齐小程序 search2 索引页:搜索输入 + 历史 + 猜你想搜 + 类别 +
/// 地图入口;搜索动作跳转独立结果页 /search/result(结果不再铺在本页下方)。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  /// 搜索框里当前的字。点历史词/热词会写它,所以是页面状态不是框内私有状态。
  String _input = '';
  Timer? _debounce;
  List<String> _history = <String>[];
  bool _historyFailed = false;
  int _activeHotKey = -1;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final list = await ref.read(searchHistoryStoreProvider).read();
      if (mounted) {
        setState(() {
          _history = list;
          _historyFailed = false;
        });
      }
    } catch (_) {
      // ★ 本地读取也会失败(keychain/存储不可用)。原先这里裸抛:异常没人接,
      //   历史区直接消失 —— 用户看到的是「你没有历史」,而不是「没读出来」。
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final notifier = ref.read(searchFilterProvider.notifier);
      notifier.state = notifier.state.copyWith(keyword: v);
    });
  }

  void _toast(String text) {
    CyNativeNotice.show(context, text);
  }

  /// 所有搜索出口(回车/热词/历史词/类别/筛选)汇到这一处,历史只在这里写。
  void _navigate({required String keyword}) {
    final kw = keyword.trim();
    final categoryId = ref.read(searchFilterProvider).categoryId;
    if (kw.isEmpty && categoryId == null) {
      _toast('请输入关键词或选择类别');
      return;
    }
    // ★ 只在**真的发起搜索**时记 —— 上面那条提前 return 的不算,
    //   否则「搜索量」里混着一堆什么都没搜的空点击。
    // ⚠️ 关键词**不进 properties**:后端有敏感信息校验,而且搜索词
    //   本身就可能是人名/手机号。只记有没有搜、带没带类别。
    ref
        .read(trackerProvider)
        .track(
          'search_submit',
          pagePath: '/search',
          properties: <String, dynamic>{
            'hasKeyword': kw.isNotEmpty,
            'hasCategory': categoryId != null,
          },
        );
    if (kw.isNotEmpty) {
      ref.read(searchHistoryStoreProvider).push(kw).then((List<String> list) {
        if (mounted) setState(() => _history = list);
      });
    }
    final filter = ref.read(searchFilterProvider);
    final query = <String, String>{
      'keyword': kw,
      if (categoryId != null) 'categoryId': '$categoryId',
      // 日期/价格是客户端兜底筛选:随跳转带进结果页(对齐小程序 search2/index.js 的 URL 拼参)。
      if (filter.dateRange != null) 'startDate': _day(filter.dateRange!.start),
      if (filter.dateRange != null) 'endDate': _day(filter.dateRange!.end),
      if (filter.minPrice != null) 'minPrice': '${filter.minPrice}',
      if (filter.maxPrice != null) 'maxPrice': '${filter.maxPrice}',
    };
    final uri = Uri(path: '/search/result', queryParameters: query).toString();
    context.push(uri);
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void _setKeyword(String keyword) {
    setState(() => _input = keyword);
    final notifier = ref.read(searchFilterProvider.notifier);
    notifier.state = notifier.state.copyWith(keyword: keyword);
  }

  void _onHotKeyTap(int index, String keyword) {
    setState(() => _activeHotKey = index);
    _setKeyword(keyword);
    _navigate(keyword: keyword);
  }

  void _onHistoryTap(String keyword) {
    _setKeyword(keyword);
    _navigate(keyword: keyword);
  }

  Future<void> _onClearHistory() async {
    await ref.read(searchHistoryStoreProvider).clear();
    if (mounted) setState(() => _history = <String>[]);
  }

  void _onCategoryTap(Category cat) {
    final notifier = ref.read(searchFilterProvider.notifier);
    notifier.state = notifier.state.copyWith(categoryId: cat.id);
    _navigate(keyword: _input);
  }

  void _goMap() {
    context.push(
      searchMapLocation(
        keyword: _input,
        categoryId: ref.read(searchFilterProvider).categoryId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        trailing: CupertinoButton(
          // ★ 按**调性**找店的入口。搜索只能按店名匹配,
          //   而用户通常不知道店名,知道的是自己想要什么样的店。
          key: const Key('search-discover-merchants'),
          onPressed: () => context.push('/merchant/discover'),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
          child: const Text('发现商家'),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.only(bottom: CyTokens.space6),
            children: <Widget>[
              const CyPageTitle('搜索'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CySearchField(
                        value: _input,
                        autofocus: true,
                        placeholder: '搜索主题、活动、俱乐部、商家',
                        onChanged: (String v) {
                          setState(() => _input = v);
                          _onChanged(v);
                        },
                        onSubmitted: (String v) => _navigate(keyword: v),
                      ),
                    ),
                    const SizedBox(width: CyTokens.space3),
                    CyNativeButton(
                      role: CyNativeButtonRole.secondary,
                      label: '筛选',
                      onPressed: () => showSearchFilterSheet(
                        context,
                        ref,
                        onSearch: () => _navigate(keyword: _input),
                      ),
                      icon: const CyNativeButtonIcon(
                        sfSymbol: 'line.3.horizontal.decrease',
                        fallback: CupertinoIcons.slider_horizontal_3,
                      ),
                    ),
                  ],
                ),
              ),
              if (_historyFailed)
                _Section(
                  title: '搜索历史',
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '历史没能读出来',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: CyPalette.of(context).textSecondary,
                              ),
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('search-history-retry'),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space2,
                        ),
                        onPressed: _loadHistory,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              else if (_history.isNotEmpty)
                _Section(
                  title: '搜索历史',
                  trailing: CupertinoButton(
                    onPressed: _onClearHistory,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                    ),
                    // .history-clear:次级动作(label 字号、w400、tertiary),
                    // 不抢主搜索的视觉权重。
                    child: const Text(
                      '清空',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        fontWeight: FontWeight.w400,
                        color: CyTokens.textTertiary,
                      ),
                    ),
                  ),
                  child: _ChipWrap(
                    items: _history,
                    onTap: (int _, String kw) => _onHistoryTap(kw),
                  ),
                ),
              _Section(
                title: '猜你想搜',
                child: _ChipWrap(
                  items: _kHotKeys,
                  highlightIndex: _activeHotKey,
                  onTap: _onHotKeyTap,
                ),
              ),
              _CategorySection(onTap: _onCategoryTap),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.pageX,
                  vertical: CyTokens.space5,
                ),
                child: CyNativeButton(
                  width: double.infinity,
                  role: CyNativeButtonRole.secondary,
                  onPressed: _goMap,
                  icon: const CyNativeButtonIcon(
                    sfSymbol: 'map',
                    fallback: CupertinoIcons.map,
                  ),
                  label: '在地图上搜城市节点',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 运营硬编码热搜词(对齐 search2/index.js hotkeys)。
const List<String> _kHotKeys = <String>[
  '交友',
  '盗墓笔记',
  '旅游',
  '美食',
  '运动',
  '读书',
  '电影',
  '音乐',
];

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space5,
        CyTokens.pageX,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CySectionTitle(title, trailing: trailing),
          SizedBox(height: CyTokens.space3),
          child,
        ],
      ),
    );
  }
}

/// 历史词 / 热词的药丸 chips。
class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.items,
    required this.onTap,
    this.highlightIndex = -1,
  });

  final List<String> items;
  final void Function(int index, String keyword) onTap;

  /// 当前高亮的热词下标(仅热词用,历史词不参与)。
  final int highlightIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CyTokens.space2_5,
      runSpacing: CyTokens.space2_5,
      children: <Widget>[
        for (var i = 0; i < items.length; i++)
          CyChip(
            label: items[i],
            selected: i == highlightIndex,
            onTap: () => onTap(i, items[i]),
          ),
      ],
    );
  }
}

/// 类别:两列图标+名字卡片。零类别整块隐藏(用户原话「类别没有就不显示」),
/// 加载中/加载失败仍要有反馈,只有「确定没有」这一态才隐藏。
class _CategorySection extends ConsumerWidget {
  const _CategorySection({required this.onTap});

  final void Function(Category cat) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(searchCategoriesProvider);
    // 小程序 .type-list 块(wxml 59-63):wx:if 包住**整块**,零类别时连标题
    // 一起隐藏;加载中/错误时「类别」标题常驻,骨架/错误挂在标题下方。
    return categories.when(
      loading: () => _categoryBlock(
        // CySkeleton 内部是纵向 ListView,嵌在外层 ListView 里必须给有界高度。
        SizedBox(
          height: 360, // 2 张卡片骨架 ≈ 350pt,取整留余量
          child: CySkeleton(type: CySkeletonType.card, count: 2),
        ),
      ),
      error: (Object err, StackTrace st) => _categoryBlock(
        Padding(
          padding: EdgeInsets.symmetric(vertical: CyTokens.space3),
          child: StatusView(
            message: '类别没能加载出来',
            sub: '网络请求失败,重试会重新拉取一次',
            icon: CupertinoIcons.exclamationmark_triangle,
            onRetry: () => ref.invalidate(searchCategoriesProvider),
          ),
        ),
      ),
      data: (List<Category> list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return _categoryBlock(
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: CyTokens.space1_5,
            crossAxisSpacing: CyTokens.space1_5,
            childAspectRatio: 3.4,
            children: <Widget>[
              for (final Category cat in list)
                _CategoryItem(category: cat, onTap: () => onTap(cat)),
            ],
          ),
        );
      },
    );
  }

  Widget _categoryBlock(Widget child) => Padding(
    padding: EdgeInsets.fromLTRB(
      CyTokens.pageX,
      CyTokens.space5,
      CyTokens.pageX,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const CySectionTitle('类别'),
        SizedBox(height: CyTokens.space3),
        child,
      ],
    ),
  );
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasIcon = category.icon != null && category.icon!.isNotEmpty;
    return Semantics(
      button: true,
      label: category.name,
      onTap: onTap,
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: onTap,
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          child: Container(
            padding: const EdgeInsets.all(
              CyTokens.space2_5,
            ), // .item padding 10rpx
            decoration: BoxDecoration(
              color: CyTokens.bgSurfaceSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
            ),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  child: Container(
                    width: 34, // 68rpx
                    height: 36, // 72rpx
                    color: CyTokens.bgElevated,
                    alignment: Alignment.center,
                    child: hasIcon
                        ? Image.network(
                            category.icon!,
                            fit: BoxFit.cover,
                            width: 34,
                            height: 36,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.category_outlined,
                              size: 18,
                              color: CyTokens.textTertiary,
                            ),
                          )
                        : Icon(
                            Icons.category_outlined,
                            size: 18,
                            color: CyTokens.textTertiary,
                          ),
                  ),
                ),
                SizedBox(width: CyTokens.space2_5),
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: CyTokens.typeLabel,
                      fontWeight: FontWeight.w700,
                      color: CyTokens.textPrimary,
                    ),
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
