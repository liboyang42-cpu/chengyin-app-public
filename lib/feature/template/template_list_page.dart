import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/merchant_access_provider.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/category.dart';
import '../../data/models/publish_draft.dart'
    show PublishTemplate, PublishTemplateHomeData;
import '../../data/models/template.dart';
import '../../data/models/topic_template.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../publish/publish_chooser_sheet.dart';
import 'template_topic_shelf.dart';

@immutable
class TemplateSquareQuery {
  const TemplateSquareQuery({this.categoryId, this.packType});

  final int? categoryId;

  /// 模板形态:0 单节点玩法 / 1 剧情包 / 2 店铺 IP 包。
  /// ★ null = 看全部形态,不是「只看单节点」。
  final int? packType;

  @override
  bool operator ==(Object other) =>
      other is TemplateSquareQuery &&
      other.categoryId == categoryId &&
      other.packType == packType;

  @override
  int get hashCode => Object.hash(categoryId, packType);
}

@immutable
class TemplateSquareData {
  const TemplateSquareData({
    this.total = 0,
    this.categories = const <Category>[],
    this.banner = const <PlayTemplate>[],
    required this.latest,
    required this.recommended,
    this.mustPlay = const <PlayTemplate>[],
    this.hot = const <PlayTemplate>[],
  });

  final int total;
  final List<Category> categories;
  final List<PlayTemplate> banner;
  final List<PlayTemplate> recommended;
  final List<PlayTemplate> latest;
  final List<PlayTemplate> mustPlay;
  final List<PlayTemplate> hot;
}

/// 「游戏」tab 的数据源。★ 与页面的关系:**页面触发加载、容器持有缓存**
/// (seq + tab 双闸要求响应只写缓存、由页面决定画不画)。
///
/// ★ 不能写成 `autoDispose`:用户切去主题 tab 时这里**没有监听者**,
///   autoDispose 会当场把元素连同在途的请求一起回收 —— 切回来变成重拉,
///   真源 `_gameLoaded` 的缓存语义(加载过一次就不再打接口)随之失效,
///   在途响应也会死成「was disposed during loading state」。
///   非 autoDispose(`FutureProvider.family` 的默认)由容器持有,跨 tab 存活;
///   显式重新加载只走 `ref.invalidate`(`_switchTab` 失败后重进、
///   `_buildGameTab` 的「重试」)。
final templateSquareProvider = FutureProvider.family<TemplateSquareData, TemplateSquareQuery>((
      ref,
      TemplateSquareQuery query,
    ) async {
      // ★ 选了分类**或**形态就走列表接口;都没选才走首页分区聚合接口
      //   (那个接口不认筛选,拿它当筛选结果会显示成「筛了但没变」)。
      if (query.categoryId != null || query.packType != null) {
        final (List<PlayTemplate> rows, List<Category> categories) = await (
          ref.watch(templateApiProvider).list(
            categoryId: query.categoryId,
            packType: query.packType,
          ),
          ref.watch(categoryApiProvider).list(type: '4'),
        ).wait;
        return TemplateSquareData(
          total: rows.length,
          categories: categories,
          banner: rows.take(5).toList(growable: false),
          latest: rows.take(6).toList(growable: false),
          recommended: rows.take(6).toList(growable: false),
          mustPlay: rows.take(3).toList(growable: false),
          hot: rows.take(8).toList(growable: false),
        );
      }
      final PublishTemplateHomeData home = await ref
          .watch(publishApiProvider)
          .templateHomeSections();
      return TemplateSquareData(
        total: home.total,
        categories: home.categories,
        banner: home.banner.map(_playTemplateFromHome).toList(growable: false),
        latest: home.latest.map(_playTemplateFromHome).toList(growable: false),
        recommended: home.recommended
            .map(_playTemplateFromHome)
            .toList(growable: false),
        mustPlay: home.mustPlay
            .map(_playTemplateFromHome)
            .toList(growable: false),
        hot: home.hot.map(_playTemplateFromHome).toList(growable: false),
      );
    });

PlayTemplate _playTemplateFromHome(PublishTemplate template) => PlayTemplate(
  id: template.id,
  title: template.title,
  description: template.raw['description']?.toString(),
  imgUrl: template.imgUrl.trim().isEmpty ? null : template.imgUrl,
  players: template.players == '--' ? null : template.players,
  duration: template.duration <= 0 ? null : template.duration,
  categoryId: (template.raw['categoryId'] as num?)?.toInt(),
);

/// 主题模板广场。默认根对齐小程序 `pages/template`，发布仍经过统一 chooser。
class TemplateListPage extends ConsumerStatefulWidget {
  const TemplateListPage({super.key});

  @override
  ConsumerState<TemplateListPage> createState() => _TemplateListPageState();
}

class _TemplateListPageState extends ConsumerState<TemplateListPage> {
  /// 一级 tab。**默认「主题」**——真源 `data.tab = 'topic'`(index.js:56),
  /// 商家与玩家同一口径。
  String _tab = 'topic';

  // ===== 「主题」tab:货架。页面触发加载、页面持有缓存 =====
  // 真源把这三样挂在实例上不进 data(那边是死数据字段门禁的要求):
  // 它们只喂 rebuildLists 算置顶/其余。
  List<TopicTemplate> _topicRows = const <TopicTemplate>[];
  bool _topicLoaded = false;
  int _topicSeq = 0;

  /// 「主题」tab 选中的品类。★ null = 「推荐」。
  int? _topicCategoryId;

  /// 「主题」tab 的屏幕状态(真源的 listLoaded / loading / errorMsg)。
  /// ★ 只有主题 tab 用这一对:**游戏 tab 的状态在它自己的 AsyncValue 里**
  ///   (见 `_buildGameTab`),两个 tab 各渲染各的,「迟到响应画到别的 tab 上」
  ///   在 App 这边结构上就不可能发生 —— 真源要靠 tab 闸挡的正是这一类。
  bool _listLoaded = false;
  bool _loading = false;
  String? _error;

  // ===== 「游戏」tab:玩法模板(既有五段,数据走 templateSquareProvider)=====
  /// 「游戏」tab 自己的筛选轴。★ 与真源有一处**有理由的偏离**:真源切 tab 会把
  /// `activeCat` 清回 0,因为两 tab 共用一行 chips;App 这边游戏 tab 的分类/形态
  /// 是**服务端筛选**(换一个值就是换一个 family key = 一次新请求),清掉既不必要
  /// 也让「切回来还是原样」失效 —— 所以它只归游戏 tab 自己管。
  int? _categoryId;
  int? _packType;

  TemplateSquareQuery get _gameQuery =>
      TemplateSquareQuery(categoryId: _categoryId, packType: _packType);

  /// 分类行。数据源仍是 `/api/template/homeData` 的 categoryList
  /// (真源 onShow → getHome;另外四段是同一张表的四刀切,不再消费)。
  List<Category> _categories = const <Category>[];

  bool _using = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    // 真源 onShow → loadTab(this.data.tab):首屏只拉当前 tab 那一条
    //(游戏 tab 的请求由它自己的 ref.watch 触发,首屏在主题 tab 上不会发)。
    _loadTopic();
  }

  Future<void> _loadCategories() async {
    // 这条接口自己吞异常(拿不到就回空),与真源「品类拉不到不阻断」同口径:
    // 列表来自另外一个接口,没有分类行页面照常可用。
    final PublishTemplateHomeData home = await ref
        .read(publishApiProvider)
        .templateHomeSections();
    if (!mounted) return;
    setState(() => _categories = home.categories);
  }

  /// 主题模板货架:`/api/template/topic-template/list`。
  ///
  /// ★ success / fail / 收尾三处都是 **seq + tab 双闸**,照抄真源
  ///   `getTopicTemplates()`(index.js:601-650)。理由(那边注释原文):
  ///   数据回来时用户可能已经切走 —— **缓存照收,屏幕状态只归当前 tab 管**,
  ///   否则会把还没加载的 tab 标成已加载、把空缓存渲染成假空态。
  Future<void> _loadTopic() async {
    final int seq = ++_topicSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<TopicTemplate> rows = await ref
          .read(templateApiProvider)
          .topicTemplateList();
      if (!mounted || seq != _topicSeq) return;
      _topicRows = rows;
      _topicLoaded = true;
      if (_tab == 'topic') {
        setState(() {
          _listLoaded = true;
          _error = null;
        });
      }
    } catch (error) {
      if (!mounted || seq != _topicSeq) return;
      // 失败半边同样只归当前 tab 管:主题在途/已切走时,这条迟到失败
      // 不许把错误文案画到别的 tab 上,也不许进缓存。
      if (_tab == 'topic') {
        setState(() => _error = _messageOf(error, '主题模板加载失败'));
      }
    } finally {
      // tab 闸防掐掉另一 tab 在途的骨架屏;切去已加载 tab 的 loading
      // 由 _switchTab 显式清。
      if (mounted && seq == _topicSeq && _tab == 'topic') {
        setState(() => _loading = false);
      }
    }
  }

  /// 真源 `switchTab()`(index.js:444-468)。
  ///
  /// ⚠️ 「切到未加载的 tab 先清屏」在 App 这边**不用逐个清 banner/topList/
  ///   tailList**:主题 tab 的屏幕内容一律由 `_listLoaded` 派生,置 false 就等于
  ///   清屏,少一处「将来加了新列表字段却忘了清」的位置。
  void _switchTab(String tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      // chips 换轴,选中回到「推荐」(轴都变了,沿用旧选中没有意义)。
      if (tab == 'topic') _topicCategoryId = null;
      _error = null;
      _listLoaded = _topicLoaded;
      // 另一个 tab 的请求可能仍在途,它的收尾只归自己的 tab 管;
      // 这里不显式清就会留下一个游离的 loading:true。
      _loading = false;
    });
    if (tab == 'topic' && !_topicLoaded) {
      _loadTopic();
      return;
    }
    // 失败不进缓存:真源失败时 `_gameLoaded` 保持 false,切回游戏 tab 会重新加载。
    // App 这边游戏数据在 provider 的 AsyncValue 里(保活),所以显式作废一次。
    if (tab == 'game' && ref.read(templateSquareProvider(_gameQuery)).hasError) {
      ref.invalidate(templateSquareProvider(_gameQuery));
    }
  }

  void _retryTopic() {
    setState(() => _error = null);
    _loadTopic();
  }

  /// 用模板:整包复制成我的草稿,再进专业编辑器。
  ///
  /// 真源 `jumpDetail → goTopicConfig`(index.js:665-690):`/use` 带上模板 id,
  /// 拿回 `data.topicId` 后跳简易发布器。App 侧对应 `/publish/pro?id=`
  /// (与广场「改编同款」同一条落地链路,不新造第二条)。
  Future<void> _useTopic(TopicTemplate item) async {
    if (_using) return;
    if (item.previewOnly) {
      // 预览模板的数据还没落库,复制/配置都会被后端拒 —— 直说,别等用户点完才报错。
      CyNativeNotice.show(context, '这是预览模板，落库后才能配置');
      return;
    }
    setState(() => _using = true);
    try {
      final int copiedTopicId = await ref
          .read(squareApiProvider)
          .remixTopicTemplate(item.id);
      if (!mounted) return;
      context.push('/publish/pro?id=$copiedTopicId');
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _using = false);
    }
  }

  /// 铃铛进消息页。★ `/im` 在整页需登录表里:游客直接 push 会撞 redirect
  /// 兜底,把 shell 根 `/feed` 当 imperative push 再压一层 —— #379 真点
  /// P1 里「俱乐部 tab 点消息后脱钩」同族 bug(那条走的是 club 铃铛)。
  /// 与本页其它动作入口同口径:先 requireLogin,登完再继续。
  Future<void> _openInbox() async {
    if (!await requireLogin(context, ref) || !mounted) return;
    context.push('/im');
  }

  String _messageOf(Object error, String fallback) {
    final String message = error
        .toString()
        .replaceFirst('Exception: ', '')
        .trim();
    return message.isEmpty ? fallback : message;
  }

  Future<void> _openPublish() async {
    if (!await requireLogin(context, ref) || !mounted) return;
    // ★ 商家视角下「发布主题」这件事的权限位是 access/me 的 project:manage,
    //   不是全局 role —— 核销员/财务岗本来就发不了。真源(pages/template 的
    //   applyMerchantPublishAccess)在拿不到身份时也是 fail-closed 压成 false,
    //   点下去就是这一句 toast;不让他进发布器再撞 403。
    //   按钮**照旧显示**(真源 F8 只压发布,没藏按钮),所以闸挂在动作上。
    if (ref.read(authControllerProvider).user?.isMerchantView ?? false) {
      final bool canManage = await ref
          .read(merchantAccessProvider.future)
          .then((access) => access.canManageProjects, onError: (_) => false);
      if (!mounted) return;
      if (!canManage) {
        CyNativeNotice.show(context, '当前身份不可发布主题');
        return;
      }
    }
    await showPublishChooser(context);
  }

  Widget _tabsRow() => Padding(
    padding: const EdgeInsets.fromLTRB(
      CyTokens.pageX,
      0,
      CyTokens.pageX,
      CyTokens.space2,
    ),
    // cy-tabs 的 segmented 变体:两 tab 等分宽度,接通用的原生玻璃。
    // 真源用的是 variant="attached"(与下方面板连体),App 没有那个变体 ——
    // 形态走仓内既有的分段变体,语义(一级切换、切换即换内容面)与真源一致。
    child: CyTabs(
      key: const Key('template-tabs'),
      variant: CyTabsVariant.segmented,
      tabs: const <CyTab>[
        CyTab(key: 'topic', label: '主题'),
        CyTab(key: 'game', label: '游戏'),
      ],
      active: _tab,
      onChanged: _switchTab,
      fill: true,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bool merchant =
        ref.watch(authControllerProvider).user?.isMerchantView ?? false;
    final String avatarUrl =
        ref.watch(authControllerProvider).user?.avatar ?? '';
    final Widget body = Builder(
      builder: (BuildContext context) => _tab == 'topic'
          ? _buildTopicTab(context, avatarUrl)
          : _buildGameTab(context, avatarUrl),
    );
    if (!merchant) {
      // ★ 玩家视角**不许**包 CupertinoTheme:根上还挂着
      //   `primaryContrastingColor`(白底白字那个修复),覆盖掉会退回去。
      return Theme(data: Theme.of(context), child: body);
    }
    final ThemeData light = AppTheme.merchantLight();
    return Theme(
      data: light,
      // ★ 只换 Material `Theme` 不够:`ThemeData.cupertinoOverrideTheme` 在
      //   `CupertinoApp` 下不生效(根已有 CupertinoTheme 时,`Theme.build`
      //   把**祖先那份**转发布)—— 本页 `CupertinoPageScaffold` 等 Cupertino
      //   控件会留在根暗色。路由层同机制收口见 `app_router.dart` 的商家浅色
      //   包装(`_merchantLight`,PR #198 补齐 Cupertino 那一半)。
      child: CupertinoTheme(
        data: CupertinoThemeData(
          brightness: light.brightness,
          primaryColor: light.colorScheme.primary,
          scaffoldBackgroundColor: light.scaffoldBackgroundColor,
          barBackgroundColor: light.scaffoldBackgroundColor,
        ),
        child: body,
      ),
    );
  }

  Widget _buildTopicTab(BuildContext context, String avatarUrl) {
    return _TemplateChrome(
      avatarUrl: avatarUrl,
      onProfileTap: () => context.go('/profile'),
      onInboxTap: _openInbox,
      onSearchTap: () => context.push('/search'),
      onPublish: _openPublish,
      tabBar: _tabsRow(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: TemplateTopicShelf(
            rows: _topicRows,
            categories: _categories,
            selectedCategoryId: _topicCategoryId,
            loading: _loading,
            listLoaded: _listLoaded,
            error: _error,
            onCategorySelected: (int? value) =>
                setState(() => _topicCategoryId = value),
            onRetry: _retryTopic,
            onUse: _useTopic,
          ),
        ),
      ],
    );
  }

  Widget _buildGameTab(BuildContext context, String avatarUrl) {
    // ★ 首屏不会走到这里(默认 tab 是主题),所以游戏那条接口只在用户真的
    //   点开游戏 tab 时才发 —— 与真源 `loadTab(this.data.tab)` 同口径。
    //   数据在 provider 里跨 tab 存活(见 templateSquareProvider 注释):
    //   切走再切回来是缓存,不会重拉。
    final AsyncValue<TemplateSquareData> game = ref.watch(
      templateSquareProvider(_gameQuery),
    );
    return _TemplateChrome(
      avatarUrl: avatarUrl,
      onProfileTap: () => context.go('/profile'),
      onInboxTap: _openInbox,
      onSearchTap: () => context.push('/search'),
      onPublish: _openPublish,
      tabBar: _tabsRow(),
      slivers: <Widget>[
        ...game.when(
          // ★ 显式 false:invalidate(=重试/失败后重进)要**看得见地**回到骨架屏。
          //   Riverpod 的 when 默认 skipLoadingOnRefresh: true,会把上一次的
          //   错误卡继续留在屏上,用户点了重试却像没反应。
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                child: CySkeleton(type: CySkeletonType.list, count: 3),
              ),
            ),
          ],
          error: (Object error, StackTrace _) => <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: StatusView(
                message: _messageOf(error, '玩法模板加载失败'),
                large: true,
                onRetry: () =>
                    ref.invalidate(templateSquareProvider(_gameQuery)),
              ),
            ),
          ],
          data: (TemplateSquareData data) => _squareSlivers(
            context: context,
            total: data.total,
            banner: data.banner,
            recommended: data.recommended,
            latest: data.latest,
            mustPlay: data.mustPlay,
            hot: data.hot,
            categories: data.categories,
            selectedCategoryId: _categoryId,
            selectedPackType: _packType,
            onCategorySelected: (int? value) =>
                setState(() => _categoryId = value),
            onPackTypeSelected: (int? value) => setState(() => _packType = value),
            onTemplateTap: (int id) => context.push('/template/$id'),
          ),
        ),
      ],
    );
  }
}

/// 模板形态筛选项。与后端 pack_type 逐一对应。
///
/// ★ 「全部」是 null 不是 0 —— 0 是「单节点玩法」这个真实形态,
///   拿它当全部会让剧情包与 IP 包在默认视图里凭空消失。
/// ⚠️ 首项不叫「全部」:分类行里已经有一个「全部」了,两行各一个用户分不清
///   点的是哪条轴(既有的广场对齐测试也正是这样红的 —— 它找到两个「全部」)。
///   叫「全部形态」把轴名带上,一眼看得出。
const List<(int?, String)> _kPackTypes = <(int?, String)>[
  (null, '全部形态'),
  (0, '单节点玩法'),
  (1, '剧情包'),
  (2, '店铺 IP 包'),
];

/// 形态筛选 chip。触达区不小于 44pt。
class _PackTypeChip extends StatelessWidget {
  const _PackTypeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      minimumSize: const Size(0, 44),
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      color: selected ? palette.brandSoft : palette.bgSurfaceSubtle,
      onPressed: onTap,
      child: Text(
        label,
        style: textTheme.bodySmall?.copyWith(
          color: selected ? palette.textPrimary : palette.textSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// 页面外壳:头像栏 + 搜索行 +(可选)tab 行 + 内容 slivers + 发布钮。
///
/// ★ 为什么抽出来:加了「主题 / 游戏」两 tab 之后,两个 tab 共用同一副外壳,
///   而**加载态与失败态也必须在这副外壳里面渲染** —— 否则骨架屏/错误卡上
///   看不到 tab 行,用户切不回另一个 tab(真源的四态就在 `.tpl-panel` 内,同理)。
///   外壳只此一份,各 tab 只提供自己的内容 slivers。
class _TemplateChrome extends StatelessWidget {
  const _TemplateChrome({
    required this.avatarUrl,
    required this.onProfileTap,
    required this.onInboxTap,
    required this.onSearchTap,
    required this.onPublish,
    required this.slivers,
    this.tabBar,
  });

  final String avatarUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onInboxTap;
  final VoidCallback onSearchTap;
  final VoidCallback onPublish;
  final List<Widget> slivers;
  final Widget? tabBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Padding(
        // 五项 Liquid Glass Tab Bar 是 shell 的前景层，页内 Scaffold
        // 不知道它的高度。预留一个 tab 区，避免「发布」被盖在第五项下面。
        padding: const EdgeInsets.only(bottom: 96),
        child: CyNativeButton(
          key: const Key('template-publish-fab'),
          onPressed: onPublish,
          label: '发布',
          // iOS 原生 platform view 无法从中文标题反推 Flutter 内在宽度；
          // 显式宽度避免系统按钮把「发布」压成省略号。
          width: 112,
          role: CyNativeButtonRole.secondary,
          icon: const CyNativeButtonIcon(
            sfSymbol: 'paperplane',
            fallback: CupertinoIcons.paperplane,
          ),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          key: const Key('template-scroll'),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: _TemplateHeader(
                avatarUrl: avatarUrl,
                onProfileTap: onProfileTap,
                onInboxTap: onInboxTap,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space4,
                  CyTokens.pageX,
                  CyTokens.space2,
                ),
                child: CupertinoButton(
                  key: const Key('template-search-target'),
                  onPressed: onSearchTap,
                  padding: EdgeInsets.zero,
                  child: IgnorePointer(
                    child: CySearchField(
                      value: '',
                      placeholder: '搜索节点玩法与主题',
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
            if (tabBar != null) SliverToBoxAdapter(child: tabBar),
            ...slivers,
          ],
        ),
      ),
    );
  }
}

/// 「游戏」tab 的内容面(五段:主题推荐 / 最新主题 / 推荐交互模板 /
/// 交互模板精选 / 热门节点榜)。
///
/// ★ 抽成函数的理由与 [_TemplateChrome] 同源:页面要在**同一副外壳**下渲染
///   两个 tab,而这一屏的内容此前是 `TemplateSquareView.build` 的私有 slivers。
///   `TemplateSquareView` 仍是它自己的公开 seam(既有对齐测试逐条钉着它),
///   这里只是把它和页面共用的那一份画法抽出来,避免两处各写一遍五行区块。
List<Widget> _squareSlivers({
  required BuildContext context,
  required int total,
  required List<PlayTemplate> banner,
  required List<PlayTemplate> recommended,
  required List<PlayTemplate> latest,
  required List<PlayTemplate> mustPlay,
  required List<PlayTemplate> hot,
  required List<Category> categories,
  required int? selectedCategoryId,
  required int? selectedPackType,
  required ValueChanged<int?> onCategorySelected,
  required ValueChanged<int?> onPackTypeSelected,
  required ValueChanged<int> onTemplateTap,
}) {
  return <Widget>[
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 形态筛选。★ 放在分类之上:先决定「要整套还是要一个节点」,
                  //   再挑题材。反过来的话,选完题材还要在混着两种形态的结果里翻。
                  SizedBox(
                    height: 44,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.pageX,
                      ),
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        for (final (int? value, String label) in _kPackTypes)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: CyTokens.space2,
                            ),
                            child: _PackTypeChip(
                              key: Key('template-pack-type-${value ?? 'all'}'),
                              label: label,
                              selected: selectedPackType == value,
                              onTap: () => onPackTypeSelected(value),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: CyTokens.space8 * 2 + CyTokens.space2,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.pageX,
                      ),
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                    _CategoryButton(
                      label: '全部',
                      initial: '全',
                      selected: selectedCategoryId == null,
                      onTap: () => onCategorySelected(null),
                    ),
                    for (final Category category in categories) ...<Widget>[
                      const SizedBox(width: CyTokens.space3),
                      _CategoryButton(
                        key: Key('template-category-${category.id}'),
                        label: category.name,
                        initial: category.name.isEmpty
                            ? '类'
                            : category.name.substring(0, 1),
                        selected: selectedCategoryId == category.id,
                        onTap: () => onCategorySelected(category.id),
                      ),
                    ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (banner.isEmpty &&
                latest.isEmpty &&
                recommended.isEmpty &&
                mustPlay.isEmpty &&
                hot.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: const StatusView(
                  message: '暂无可用节点玩法',
                  sub: '稍后再来探索新的城市路线',
                  large: true,
                ),
              )
            else ...<Widget>[
              if (banner.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(child: _SectionHeader('主题推荐')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    key: const Key('template-recommended-rail'),
                    height:
                        CyTokens.space8 * 5 + CyTokens.space6 + CyTokens.space1,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.pageX,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: banner.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: CyTokens.space4),
                      itemBuilder: (BuildContext context, int index) {
                        final PlayTemplate template = banner[index];
                        return _RecommendedCard(
                          template: template,
                          onTap: () => _showTemplatePreview(
                            context,
                            template,
                            onTemplateTap,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (latest.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(child: _SectionHeader('最新主题')),
                SliverList.builder(
                  itemCount: latest.length,
                  itemBuilder: (BuildContext context, int index) {
                    final PlayTemplate template = latest[index];
                    return _LatestRow(
                      template: template,
                      onTap: () => _showTemplatePreview(
                        context,
                        template,
                        onTemplateTap,
                      ),
                    );
                  },
                ),
              ],
              if (recommended.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(
                  child: _SectionHeader('推荐交互模板', chevron: true),
                ),
                SliverList.builder(
                  itemCount: recommended.length,
                  itemBuilder: (BuildContext context, int index) {
                    final PlayTemplate template = recommended[index];
                    return _InteractionRow(
                      template: template,
                      onTap: () => _showTemplatePreview(
                        context,
                        template,
                        onTemplateTap,
                      ),
                    );
                  },
                ),
              ],
              if (mustPlay.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(
                  child: _SectionHeader('交互模板精选', chevron: true),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: CyTokens.space8 * 3,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.pageX,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: mustPlay.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: CyTokens.space4),
                      itemBuilder: (BuildContext context, int index) {
                        final PlayTemplate template = mustPlay[index];
                        return _MustPlayCard(
                          template: template,
                          onTap: () => _showTemplatePreview(
                            context,
                            template,
                            onTemplateTap,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (hot.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(child: _HotHeader()),
                SliverToBoxAdapter(
                  child: _HotStats(
                    total: total,
                    categoryCount: categories.length,
                  ),
                ),
                SliverList.builder(
                  itemCount: hot.length,
                  itemBuilder: (BuildContext context, int index) {
                    final PlayTemplate template = hot[index];
                    return _HotRow(
                      rank: index + 1,
                      template: template,
                      onTap: () => _showTemplatePreview(
                        context,
                        template,
                        onTemplateTap,
                      ),
                    );
                  },
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: CyTokens.space8 * 2),
              ),
            ],
  ];
}

/// 模板广场的公开 widget seam：只表达布局、顺序与点击，不自行发请求或判断角色。
class TemplateSquareView extends StatelessWidget {
  const TemplateSquareView({
    super.key,
    required this.avatarUrl,
    required this.total,
    required this.banner,
    required this.recommended,
    required this.latest,
    required this.mustPlay,
    required this.hot,
    required this.categories,
    required this.selectedCategoryId,
    required this.selectedPackType,
    required this.onProfileTap,
    required this.onInboxTap,
    required this.onSearchTap,
    required this.onCategorySelected,
    required this.onPackTypeSelected,
    required this.onTemplateTap,
    required this.onPublish,
    this.tabBar,
  });

  final String avatarUrl;
  final int total;
  final List<PlayTemplate> banner;
  final List<PlayTemplate> recommended;
  final List<PlayTemplate> latest;
  final List<PlayTemplate> mustPlay;
  final List<PlayTemplate> hot;
  final List<Category> categories;
  final int? selectedCategoryId;

  /// 当前选中的模板形态。★ null = 全部形态。
  final int? selectedPackType;
  final VoidCallback onProfileTap;
  final VoidCallback onInboxTap;
  final VoidCallback onSearchTap;
  final ValueChanged<int?> onCategorySelected;
  final ValueChanged<int?> onPackTypeSelected;
  final ValueChanged<int> onTemplateTap;
  final VoidCallback onPublish;

  /// 「主题 / 游戏」两级 tab 行。**从页面注入**而不是在这里建:
  /// 两 tab 的加载态(seq + tab 双闸)由页面持有,这一层只负责画。
  final Widget? tabBar;

  @override
  Widget build(BuildContext context) {
    return _TemplateChrome(
      avatarUrl: avatarUrl,
      onProfileTap: onProfileTap,
      onInboxTap: onInboxTap,
      onSearchTap: onSearchTap,
      onPublish: onPublish,
      tabBar: tabBar,
      slivers: _squareSlivers(
        context: context,
        total: total,
        banner: banner,
        recommended: recommended,
        latest: latest,
        mustPlay: mustPlay,
        hot: hot,
        categories: categories,
        selectedCategoryId: selectedCategoryId,
        selectedPackType: selectedPackType,
        onCategorySelected: onCategorySelected,
        onPackTypeSelected: onPackTypeSelected,
        onTemplateTap: onTemplateTap,
      ),
    );
  }
}

Future<void> _showTemplatePreview(
  BuildContext context,
  PlayTemplate template,
  ValueChanged<int> onTemplateTap,
) => showCupertinoSheet<void>(
  context: context,
  showDragHandle: true,
  topGap: 0.18,
  scrollableBuilder:
      (BuildContext sheetContext, ScrollController scrollController) =>
          _TemplatePreview(
            key: const Key('template-preview-sheet'),
            template: template,
            scrollController: scrollController,
            onClose: () => Navigator.of(sheetContext).pop(),
            onOpenDetail: () {
              Navigator.of(sheetContext).pop();
              onTemplateTap(template.id);
            },
          ),
);

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({
    super.key,
    required this.template,
    required this.scrollController,
    required this.onClose,
    required this.onOpenDetail,
  });

  final PlayTemplate template;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final List<String> materials = (template.requiredMaterials ?? '')
        .split(RegExp(r'[、,，;；\n]'))
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                      child: SizedBox(
                        width: double.infinity,
                        height: CyTokens.space8 * 4,
                        child: _TemplateCover(template: template),
                      ),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    Text(
                      template.title,
                      // Material 基座 headlineSmall(24)不在 iOS 梯级上(手册 T2);
                      // T3 强调用 bold(700)。预览弹层标题取 Title2 22。
                      style: CyType.title2.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (template.metaLine.isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        template.metaLine,
                        style: CyType.subhead.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                    if ((template.description ?? '').trim().isNotEmpty)
                      _PreviewSection(
                        title: '游戏简介',
                        child: Text(template.description!.trim()),
                      ),
                    if (materials.isNotEmpty)
                      _PreviewSection(
                        title: '所需材料',
                        icon: CupertinoIcons.cube_box,
                        child: Wrap(
                          spacing: CyTokens.space2,
                          runSpacing: CyTokens.space2,
                          children: <Widget>[
                            for (final String material in materials)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CyTokens.space3,
                                  vertical: CyTokens.space1_5,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.bgSurfaceSubtle,
                                  borderRadius: BorderRadius.circular(
                                    CyTokens.radiusPill,
                                  ),
                                ),
                                child: Text(material),
                              ),
                          ],
                        ),
                      ),
                    if ((template.usageLocation ?? '').trim().isNotEmpty)
                      _PreviewSection(
                        title: '推荐场景',
                        icon: CupertinoIcons.location,
                        child: Text(template.usageLocation!.trim()),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                CyTokens.space4,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: CupertinoButton(
                      minimumSize: const Size.fromHeight(44),
                      color: palette.actionSecondaryBg,
                      foregroundColor: palette.textPrimary,
                      onPressed: onClose,
                      child: const Text('返回'),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space3),
                  Expanded(
                    child: CupertinoButton(
                      key: const Key('template-preview-open-detail'),
                      minimumSize: const Size.fromHeight(44),
                      color: palette.actionPrimaryBg,
                      foregroundColor: palette.actionPrimaryFg,
                      onPressed: onOpenDetail,
                      child: const Text('查看此模板'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: CyTokens.typeBody),
                const SizedBox(width: CyTokens.space2),
              ],
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          child,
        ],
      ),
    );
  }
}

class _TemplateHeader extends StatelessWidget {
  const _TemplateHeader({
    required this.avatarUrl,
    required this.onProfileTap,
    required this.onInboxTap,
  });

  final String avatarUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onInboxTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        0,
      ),
      child: Row(
        children: <Widget>[
          CupertinoButton(
            key: const Key('template-profile-target'),
            padding: EdgeInsets.zero,
            onPressed: onProfileTap,
            child: ClipOval(
              child: SizedBox.square(
                dimension: CyTokens.btnH,
                child: avatarUrl.trim().isEmpty
                    ? ColoredBox(
                        color: palette.bgSurfaceSubtle,
                        child: Icon(
                          CupertinoIcons.person_crop_circle,
                          color: palette.textSecondary,
                        ),
                      )
                    : Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: palette.bgSurfaceSubtle,
                          child: Icon(
                            CupertinoIcons.person_crop_circle,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const Spacer(),
          Semantics(
            container: true,
            excludeSemantics: true,
            label: '通知',
            button: true,
            onTap: onInboxTap,
            child: CupertinoButton(
              key: const Key('template-inbox-target'),
              padding: EdgeInsets.zero,
              onPressed: onInboxTap,
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: CyTokens.btnH,
                  child: Icon(CupertinoIcons.bell, color: palette.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    super.key,
    required this.label,
    required this.initial,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String initial;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: CupertinoButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: CyTokens.space6 * 2,
          child: Column(
            children: <Widget>[
              Container(
                width: CyTokens.space8,
                height: CyTokens.space8,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.bgSurfaceSubtle,
                ),
                child: Text(
                  initial,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: CyTokens.space1),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? palette.textPrimary : palette.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: CyTokens.space1),
              Container(
                width: CyTokens.space5,
                height: CyTokens.space1 / 2,
                color: selected
                    ? palette.textPrimary
                    : palette.bgPage.withValues(alpha: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.chevron = false});

  final String title;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        CyTokens.space3,
      ),
      child: Row(
        children: <Widget>[
          // 区块标题走共用件(标题3 20 + Semibold + Semantics header,手册 §6 P2 / L2)。
          CySectionTitle(title),
          if (chevron) ...<Widget>[
            const SizedBox(width: CyTokens.space1),
            Icon(
              CupertinoIcons.chevron_right,
              size: CyTokens.typeLabel,
              color: CyPalette.of(context).textTertiary,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.template, required this.onTap});

  final PlayTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width - CyTokens.space6 * 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              child: SizedBox(
                width: double.infinity,
                height: CyTokens.space8 * 4 - CyTokens.space2,
                child: _TemplateCover(template: template),
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        template.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if ((template.description ?? '').trim().isNotEmpty)
                        Text(
                          template.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                    vertical: CyTokens.space2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.actionPrimaryBg,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                  child: Text(
                    '去参与',
                    // 17 处显式 TextStyle 里唯一漏字号的胶囊文字:原来吃
                    // Material 默认 14(不在 iOS 阶梯上)→ Footnote 13(T2);
                    // T3 强调用 Semibold。
                    style: CyType.footnote.copyWith(
                      color: palette.actionPrimaryFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestRow extends StatelessWidget {
  const _LatestRow({required this.template, required this.onTap});

  final PlayTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.pageX,
          vertical: CyTokens.space2,
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              child: SizedBox(
                width: CyTokens.space8 + CyTokens.space7,
                height: CyTokens.space6 * 2,
                child: _TemplateCover(template: template),
              ),
            ),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    template.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (template.metaLine.isNotEmpty) ...<Widget>[
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      template.metaLine,
                      style: CyType.subhead.copyWith(
                        color: palette.textSecondary,
                      ),
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

class _InteractionRow extends StatelessWidget {
  const _InteractionRow({required this.template, required this.onTap});

  final PlayTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.pageX,
          vertical: CyTokens.space2,
        ),
        child: Row(
          children: <Widget>[
            _TemplateInitial(template: template),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    template.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (template.metaLine.isNotEmpty)
                    Text(
                      template.metaLine,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space3,
                vertical: CyTokens.space1_5,
              ),
              decoration: BoxDecoration(
                color: palette.actionSecondaryBg,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              ),
              child: const Text('查看'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MustPlayCard extends StatelessWidget {
  const _MustPlayCard({required this.template, required this.onTap});

  final PlayTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: CyTokens.space8 * 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                child: SizedBox(
                  width: double.infinity,
                  child: _TemplateCover(template: template),
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              template.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CyType.subhead.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              template.metaLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotHeader extends StatelessWidget {
  const _HotHeader();

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space6,
        CyTokens.pageX,
        CyTokens.space3,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: CyTokens.space1,
            height: CyTokens.space5,
            decoration: BoxDecoration(
              color: palette.textPrimary,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          const CySectionTitle('热门节点榜'),
        ],
      ),
    );
  }
}

class _HotStats extends StatelessWidget {
  const _HotStats({required this.total, required this.categoryCount});

  final int total;
  final int categoryCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _HotStat(value: '$total个', label: '公共玩法'),
          ),
          Expanded(
            child: _HotStat(value: '$categoryCount个', label: '分类'),
          ),
          const Expanded(child: _HotStat(label: '近期上新')),
        ],
      ),
    );
  }
}

class _HotStat extends StatelessWidget {
  const _HotStat({this.value, required this.label});

  final String? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      children: <Widget>[
        if (value != null)
          Text(
            value!,
            // T3:强调用 Semibold(600),不用 w800 堆重;字号落梯级 Callout 16。
            style: CyType.callout.copyWith(fontWeight: FontWeight.w600),
          ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _HotRow extends StatelessWidget {
  const _HotRow({
    required this.rank,
    required this.template,
    required this.onTap,
  });

  final int rank;
  final PlayTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.pageX,
          vertical: CyTokens.space3,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: CyTokens.space7,
              child: Text(
                rank.toString().padLeft(2, '0'),
                // T3:Semibold 取代 w800;字号落梯级 Callout 16。
                style: CyType.callout.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _TemplateInitial(template: template),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    template.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (template.metaLine.isNotEmpty)
                    Text(
                      template.metaLine,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            Text(
              '查看',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateInitial extends StatelessWidget {
  const _TemplateInitial({required this.template});

  final PlayTemplate template;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final String title = template.title.trim();
    return Container(
      width: CyTokens.space8 + CyTokens.space5,
      height: CyTokens.space8 + CyTokens.space5,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Text(
        title.isEmpty ? '模' : title.substring(0, 1),
        // T3:Semibold 取代 w800;字号落梯级 Title2 22。
        style: CyType.title2.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TemplateCover extends StatelessWidget {
  const _TemplateCover({required this.template});

  final PlayTemplate template;

  @override
  Widget build(BuildContext context) {
    final String imageUrl = (template.imgUrl ?? '').trim();
    if (imageUrl.isEmpty) return const _CoverUnavailable();
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _CoverUnavailable(),
    );
  }
}

class _CoverUnavailable extends StatelessWidget {
  const _CoverUnavailable();

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ColoredBox(
      color: palette.bgSurfaceSubtle,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(CupertinoIcons.photo, color: palette.textTertiary),
            const SizedBox(height: CyTokens.space1),
            Text(
              '封面暂不可用',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
