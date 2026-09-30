import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import '../router/route_paths.dart';
import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';
import 'cy_native_button.dart';

/// 统一的「空 / 错误」占位视图。
/// scrollable=true 时用 ListView 包裹,以便配合 RefreshIndicator 仍可下拉。
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.message,
    this.sub,
    this.icon,
    this.iconSize,
    this.large = false,
    this.scrollable = false,
    this.controller,
    this.onRetry,
    this.retryLabel = '重试',
  });

  final String message;

  /// 副标题,对应小程序 .cy-empty-sub —— 主标说"没有什么",
  /// 副标说"怎么才会有",缺了用户不知道下一步做什么。
  final String? sub;
  final IconData? icon;
  final double? iconSize;

  /// 对应 size="lg":整页留白时用,图标 64;嵌在卡片里用普通尺寸 48。
  final bool large;
  final bool scrollable;

  /// 可滚动时使用的外部控制器(如 DraggableScrollableSheet 提供的)。
  final ScrollController? controller;
  final VoidCallback? onRetry;

  /// 重试按钮文案。默认「重试」;需要登录这类场景要写清下一步做什么。
  final String retryLabel;

  /// 用户是不是**退不出去了**。见下面那个按钮处的两条判据。
  static bool _isStranded(BuildContext context) {
    if (Navigator.of(context).canPop()) return false;
    // ⚠️ StatusView 是核心组件,**也会在没有 GoRouter 的地方被用**
    //   (大量 widget 测试就是 `MaterialApp(home: ...)`)。
    //   `GoRouterState.of` 在那种上下文里直接抛 GoError。
    //   拿不到路由信息时一律**不显示** —— 那种上下文里 go('/') 也走不通,
    //   显示一个按不动的按钮比不显示更坏。
    final GoRouter? router = GoRouter.maybeOf(context);
    if (router == null) return false;
    final String here;
    try {
      here = router.state.uri.path;
    } on StateError {
      // 未匹配路由走 errorBuilder 时 match list 是空的,`router.state`
      // 直接抛 StateError(B1 报告 P2 错误页实拍)。router 在、go('/')
      // 走得通,而那种进法没有上一页 → 正是要给「回首页」出口的情形。
      // (同 PR#188 的 matches.isEmpty 先判:一条路由都没匹配上 = 被困,
      //  这一屏恰恰最该给出口。)
      return true;
    }
    final String trimmed = here.replaceAll(RegExp(r'/+$'), '');
    // 五个一级 Tab 本身都不算被困。
    return trimmed.isNotEmpty && !kPrimaryTabRoutes.contains(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          // cy-empty:size=lg 时图标 64,否则 48。
          Icon(
            icon,
            size: iconSize ?? (large ? 64 : 48),
            color: CyPalette.of(context).textDisabled,
          ),
          SizedBox(height: CyTokens.space3),
        ],
        Semantics(
          container: true,
          liveRegion: true,
          label: sub == null ? message : '$message。$sub',
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message,
                  textAlign: TextAlign.center,
                  // 真源 `.cy-empty-title`/`.cy-error-title` = font-body + w600;
                  // 梯级上对应 Headline(17 semibold,手册 T2/T3)。旧写法从
                  // Material `bodyMedium` 换算 typeBody(14),既不在梯级、
                  // 也丢了真源的 600 字重(a5-ios27-search-2 登记的 P4 批差)。
                  // `large` 档对齐真源 `--lg`(标题升 section-title → Title3)。
                  style: (large ? CyType.title3 : CyType.headline).copyWith(
                    color: CyPalette.of(context).textPrimary,
                  ),
                ),
                if (sub != null) ...<Widget>[
                  SizedBox(height: CyTokens.space1_5),
                  Text(
                    sub!,
                    textAlign: TextAlign.center,
                    // 真源 sub = font-caption(11,梯级外)→ Caption1(12),
                    // 与 CyTag/CyCell 副标同一收敛口径;`--lg` 档真源升 font-body。
                    style: (large ? CyType.body : CyType.caption1).copyWith(
                      color: CyPalette.of(context).textSecondary,
                      height: CyTokens.leadingNormal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (onRetry != null) ...<Widget>[
          SizedBox(height: CyTokens.space4),
          // ★ 小程序 `.cy-error-retry` 是**实心药丸按钮**(btn-solid 底 +
          //   radius-pill + btn-h 高,components/cy/error/index.wxss)。
          //   用 TextButton 渲成裸文字,在浅色页上就是一行飘着的粗体字 ——
          //   看不出可以点,也和小程序对不上(2026-08-19 浅色错误态基准图实拍)。
          CyNativeButton(label: retryLabel, onPressed: onRetry),
        ],
        // ★★ 冷启动深链的「困死」出口。
        //
        //   App 有 37 条带路径参数的路由,每一条都可能被深链直接打开。
        //   那种进法**没有上一页**:Navigator.canPop() 为 false,
        //   AppBar 连返回钮都不渲染。这时错误态只给「重试」,
        //   而重试解决不了「这个 id 根本不存在」——人就卡在这一屏。
        //
        //   小程序那边早就写死了这条(merchant/profile/index.wxml:19):
        //   「冷启动进来的没有上一页,只给『返回』等于把人困死;
        //     所以回首页恒在,返回按栈深出。」
        //
        //   ⚠️ 两条都要满足才出现:
        //     ① 真的退不出去(canPop 为 false)—— 正常从列表点进来的有返回钮,
        //        再加一个「回首页」是多余的噪音;
        //     ② **不在首页本身**。tab 根页(/feed 等)的 canPop 同样是 false,
        //        只判第一条的话,首页出错会显示「回首页」——而它已经在首页。
        if (_isStranded(context)) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          CupertinoButton(
            key: const Key('status-go-home'),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
            onPressed: () => GoRouter.of(context).go(kHomeRoute),
            child: const Text('回首页'),
          ),
        ],
      ],
    );

    if (scrollable) {
      return ListView(
        controller: controller,
        children: <Widget>[
          const SizedBox(height: 120),
          Center(child: content),
        ],
      );
    }
    return Center(
      child: Padding(padding: EdgeInsets.all(CyTokens.space6), child: content),
    );
  }
}

/// 居中加载。
///
/// ⚠️ 列表/详情类页面优先用 [CySkeleton] —— 小程序用的是骨架屏,
/// 转圈只留给"没有结构可画"的场景(如提交中)。
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '正在加载',
      child: const ExcludeSemantics(
        child: Center(child: CupertinoActivityIndicator()),
      ),
    );
  }
}

/// 骨架屏形态。
enum CySkeletonType {
  /// 列表卡片:封面块 + 两行文字
  card,

  /// 详情:hero 大图 + 标题 + 多行
  detail,

  /// Feed 卡片:封面 + 三行正文 + 标签。
  feedCard,

  /// 列表行:44pt 圆头像 + 50%/80% 两行 + 行分隔线。
  /// 对应真源 `cy-skeleton type="list"`(`components/cy/skeleton` 缺省档)。
  list,

  /// 金额:资金 hero / 余额行,只画结构不给伪数值。
  /// 对应真源 `type="amount"`(单块,不随 count 重复)。
  amount,

  /// 表单区:字段标签 + 输入框同构,加载完成整页不跳位。
  /// 对应真源 `type="form-section"`。
  formSection,

  /// 票券:票面 + 撕线 + 票根,与票夹最终卡片同构。
  /// 对应真源 `type="ticket"`(真源调用点一律 count=1,居中单票)。
  ticket,

  /// 商家指标:两列网格,标签 / 主数 / 趋势三层。
  /// 对应真源 `type="merchant-metric"`。
  merchantMetric,

  /// 路线时间轴:节点圆点 + 连接线 + 标题两行。
  /// 对应真源 `type="route-timeline"`。
  routeTimeline,

  /// 地图卡:地图画布 + 地点标题 + 两行元信息。
  /// 对应真源 `type="map-card"`。
  mapCard,

  /// 帖文鱼骨:头像 + 三条长短不一正文线 + 媒体块 + 操作行。
  /// 对应真源 `type="post-card"`,几何须与帖子真卡同构。
  postCard,
}

/// 骨架屏,对应小程序 `components/cy/skeleton`。
///
/// ★ 小程序原注释:「**只画结构,不渲染伪金额或"加载中"文案**」。
///   照做——不要在骨架里放占位数字或文字,用户会当成真数据读。
///   (小程序那份骨架屏同样不写可见文案,`loading-label` 落的是
///   `aria-role="status" aria-live="polite" aria-label` —— 就是 [label]。)
class CySkeleton extends StatefulWidget {
  const CySkeleton({
    super.key,
    this.type = CySkeletonType.card,
    this.count = 3,
    this.label,
  });

  final CySkeletonType type;

  /// 重复几块(amount / ticket 真源不随 count 重复结构密度,由调用方按页传)。
  final int count;

  /// 读屏软件听到的加载文案(对应小程序 `loading-label`)。不显示在画面上。
  final String? label;

  @override
  State<CySkeleton> createState() => _CySkeletonState();
}

class _CySkeletonState extends State<CySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _c
        ..stop()
        ..value = 0;
    } else {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? label = widget.label;
    // 真源 `.sk` 统一 `padding: space-3 pageX`,各档再自己覆一层:
    // post-card 整块清零(横向缩进画在每一行里,否则鱼骨比真卡窄一格)、
    // amount 上下收到 space-2、map-card 去顶衬。
    final EdgeInsets outerPadding = switch (widget.type) {
      CySkeletonType.postCard => EdgeInsets.zero,
      CySkeletonType.amount => EdgeInsets.symmetric(
        vertical: CyTokens.space2,
        horizontal: CyTokens.pageX,
      ),
      CySkeletonType.mapCard => EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space3,
      ),
      _ => EdgeInsets.all(CyTokens.pageX),
    };
    final Widget skeleton = AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.5 + _c.value * 0.3,
        child: Padding(
          padding: outerPadding,
          // ★ 用 ListView 而不是 Column:骨架高度 = count × 卡片高,
          //   小屏或 count 偏大时 Column 会 RenderFlex overflow(真机画黄黑条纹)。
          //   ListView 超出即裁切,任何 count / 任何屏高都不会溢出。
          //   physics 设 NeverScrollable —— 加载态不该让用户滚动骨架。
          child: switch (widget.type) {
            CySkeletonType.detail => SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: const _SkDetail(),
            ),
            CySkeletonType.amount => SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: const _SkAmount(),
            ),
            CySkeletonType.ticket => Center(
              // 真源 .sk-ticket-list 是 flex 居中,票面 78% 宽。
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < widget.count; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == widget.count - 1 ? 0 : CyTokens.space4,
                      ),
                      child: const _SkTicket(),
                    ),
                ],
              ),
            ),
            CySkeletonType.formSection => ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.count,
              // 真源 .sk-form-field margin-bottom space-4。
              itemBuilder: (_, _) => const Padding(
                padding: EdgeInsets.only(bottom: CyTokens.space4),
                child: _SkFormField(),
              ),
            ),
            CySkeletonType.merchantMetric => ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              // 真源两列网格:两卡一行,行距=列距 space-3。
              itemCount: (widget.count + 1) ~/ 2,
              itemBuilder: (_, int row) => Padding(
                padding: EdgeInsets.only(
                  bottom: row == (widget.count + 1) ~/ 2 - 1
                      ? 0
                      : CyTokens.space3,
                ),
                child: _SkMetricRow(
                  first: row * 2,
                  second: row * 2 + 1 < widget.count ? row * 2 + 1 : null,
                ),
              ),
            ),
            CySkeletonType.routeTimeline => ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.count,
              itemBuilder: (_, int i) =>
                  _SkRouteRow(isLast: i == widget.count - 1),
            ),
            CySkeletonType.mapCard => ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.count,
              // 真源 .sk-map-card margin-bottom space-4。
              itemBuilder: (_, _) => const Padding(
                padding: EdgeInsets.only(bottom: CyTokens.space4),
                child: _SkMapCard(),
              ),
            ),
            CySkeletonType.postCard => ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.count,
              // 真源 .sk-post 行与行零间隙,内衬 18pt 已在每行里画。
              itemBuilder: (_, _) => const _SkPostCard(),
            ),
            CySkeletonType.list => ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.count,
              // 真源 .sk-row 行与行之间没有间隙,只有一条 0.5pt 分隔线首尾相接
              // —— 不像 card 那样垫 space3。
              itemBuilder: (_, _) => const _SkRow(),
            ),
            _ => ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.count,
              itemBuilder: (_, _) => Padding(
                padding: EdgeInsets.only(bottom: CyTokens.space3),
                child: widget.type == CySkeletonType.feedCard
                    ? const _SkFeedCard()
                    : const _SkCard(),
              ),
            ),
          },
        ),
      ),
    );
    if (label == null) return skeleton;
    // 对齐小程序骨架屏的 aria-role="status" aria-live="polite" aria-label。
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: skeleton,
    );
  }
}

class _SkBar extends StatelessWidget {
  const _SkBar({
    super.key,
    required this.height,
    this.widthFactor = 1,
    this.radius,
  });
  final double height;
  final double widthFactor;

  /// 真源个别档覆写 `.sk-bar` 的默认 radius-sm(如票面铺满块 radius 0)。
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(radius ?? CyTokens.radiusSm),
        ),
      ),
    );
  }
}

class _SkRow extends StatelessWidget {
  const _SkRow();

  @override
  Widget build(BuildContext context) {
    // 真源 components/cy/skeleton `.sk-row`(type="list" 缺省档):
    // 44pt 圆头像 + 50%/80% 两条 14pt 文字条,行上下内衬 12pt,
    // 底部 1rpx=0.5pt 与列表行同色细分隔线。
    return Container(
      padding: EdgeInsets.symmetric(vertical: CyTokens.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CyPalette.of(context).borderSubtle,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: const <Widget>[
          _SkAvatar(),
          SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SkBar(height: 14, widthFactor: 0.5),
                SizedBox(height: CyTokens.space2),
                _SkBar(height: 14, widthFactor: 0.8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkAvatar extends StatelessWidget {
  const _SkAvatar();

  @override
  Widget build(BuildContext context) {
    // 真源 .sk-avatar:88rpx=44pt 圆。
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CyPalette.of(context).bgSurfaceSubtle,
      ),
    );
  }
}

class _SkCard extends StatelessWidget {
  const _SkCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          _SkBar(height: 96),
          SizedBox(height: CyTokens.space3),
          _SkBar(height: 14, widthFactor: 0.7),
          SizedBox(height: CyTokens.space2),
          _SkBar(height: 12, widthFactor: 0.4),
        ],
      ),
    );
  }
}

class _SkFeedCard extends StatelessWidget {
  const _SkFeedCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      child: ColoredBox(
        color: CyPalette.of(context).bgSurface,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SkBar(height: 180),
            Padding(
              padding: EdgeInsets.all(CyTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SkBar(height: 14, widthFactor: 0.7),
                  SizedBox(height: CyTokens.space2),
                  _SkBar(height: 14),
                  SizedBox(height: CyTokens.space2),
                  _SkBar(height: 14, widthFactor: 0.85),
                  SizedBox(height: CyTokens.space3),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 60, child: _SkBar(height: 20)),
                      SizedBox(width: CyTokens.space2),
                      SizedBox(width: 44, child: _SkBar(height: 20)),
                    ],
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

class _SkDetail extends StatelessWidget {
  const _SkDetail();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        _SkBar(height: 180),
        SizedBox(height: CyTokens.space4),
        _SkBar(height: 18, widthFactor: 0.7),
        SizedBox(height: CyTokens.space2),
        _SkBar(height: 14, widthFactor: 0.4),
        SizedBox(height: CyTokens.space5),
        _SkBar(height: 12),
        SizedBox(height: CyTokens.space2),
        _SkBar(height: 12),
        SizedBox(height: CyTokens.space2),
        _SkBar(height: 12, widthFactor: 0.6),
      ],
    );
  }
}

// ———— 以下为真源 `components/cy/skeleton` 逐档 1:1 移植(rpx÷2=pt)————

/// 真源 .sk-amount:label 32% 宽 10pt 高,主数 56% 宽 40pt(space-7)高。
/// 只画结构,不渲染伪金额(真源原注释)。
class _SkAmount extends StatelessWidget {
  const _SkAmount();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        _SkBar(
          key: ValueKey<String>('sk-amount-label'),
          height: CyTokens.space2_5,
          widthFactor: 0.32,
        ),
        SizedBox(height: CyTokens.space2),
        _SkBar(
          key: ValueKey<String>('sk-amount-value'),
          height: CyTokens.space7,
          widthFactor: 0.56,
        ),
      ],
    );
  }
}

/// 真源 .sk-form-field:标签 28% 宽 10pt,输入框整宽 44pt(btn-h)高 12pt 圆角。
class _SkFormField extends StatelessWidget {
  const _SkFormField();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        _SkBar(height: CyTokens.space2_5, widthFactor: 0.28),
        SizedBox(height: CyTokens.space2),
        _SkBar(
          key: ValueKey<String>('sk-form-input'),
          height: CyTokens.btnH,
          radius: CyTokens.radiusMd,
        ),
      ],
    );
  }
}

/// 真源 .sk-ticket:票宽 78%、高 360pt(720rpx),左侧色带 4pt,
/// 票面铺满封面 + 底部两行文案,撕线(虚线)下接 66pt 票根。
class _SkTicket extends StatelessWidget {
  const _SkTicket();

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.78,
        child: SizedBox(
          key: const ValueKey<String>('sk-ticket'),
          height: 360,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ColoredBox(
                    color: palette.bgElevated,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Stack(
                            children: <Widget>[
                              // .sk-ticket-cover 铺满票面,覆写 radius 0。
                              Positioned.fill(
                                child: ColoredBox(
                                  color: palette.bgSurfaceSubtle,
                                ),
                              ),
                              Positioned(
                                left: CyTokens.space4,
                                right: CyTokens.space4,
                                bottom: CyTokens.space4,
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    _SkBar(
                                      key: ValueKey<String>('sk-ticket-title'),
                                      height: CyTokens.space3_5,
                                      widthFactor: 0.62,
                                    ),
                                    SizedBox(height: CyTokens.space2),
                                    _SkBar(
                                      key: ValueKey<String>('sk-ticket-time'),
                                      height: CyTokens.space2_5,
                                      widthFactor: 0.38,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // .sk-ticket-stub:66pt(132rpx)票根,顶部 2rpx 虚线撕口。
                        Container(
                          key: const ValueKey<String>('sk-ticket-stub'),
                          height: 66,
                          color: palette.bgElevated,
                          child: CustomPaint(
                            painter: _SkDashedTopLine(palette.borderStrong),
                            child: Padding(
                              padding: EdgeInsets.all(CyTokens.space4),
                              // 真源两条 bar 各按票根内容宽的 28%/24% 摆两端;
                              // Row 主轴无界,FSB 需先经 LayoutBuilder 换成确定宽。
                              child: LayoutBuilder(
                                builder:
                                    (BuildContext context, BoxConstraints c) =>
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: <Widget>[
                                            SizedBox(
                                              width: c.maxWidth * 0.28,
                                              child: _SkBar(
                                                key: const ValueKey<String>(
                                                  'sk-ticket-label',
                                                ),
                                                height: CyTokens.space3,
                                              ),
                                            ),
                                            SizedBox(
                                              width: c.maxWidth * 0.24,
                                              child: _SkBar(
                                                key: const ValueKey<String>(
                                                  'sk-ticket-action',
                                                ),
                                                height: CyTokens.space3,
                                              ),
                                            ),
                                          ],
                                        ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // .sk-ticket-band:左侧 4pt 色带,通高,z-index 压在票面上。
                Positioned(
                  key: const ValueKey<String>('sk-ticket-band'),
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: CyTokens.space1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.bgSurfaceSubtle,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(CyTokens.radiusLg),
                      ),
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

/// 真源 .sk-metric-grid 两列网格的一行。
class _SkMetricRow extends StatelessWidget {
  const _SkMetricRow({required this.first, required this.second});

  final int first;
  final int? second;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _SkMetricCard(index: first)),
        SizedBox(width: CyTokens.space3),
        Expanded(
          child: second == null
              ? const SizedBox()
              : _SkMetricCard(index: second!),
        ),
      ],
    );
  }
}

/// 真源 .sk-metric-card:卡衬 16pt、圆角 16;标签 54%×10、主数 76%×32、趋势 46%×10。
class _SkMetricCard extends StatelessWidget {
  const _SkMetricCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey<String>('sk-metric-$index'),
      padding: EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          _SkBar(height: CyTokens.space2_5, widthFactor: 0.54),
          SizedBox(height: CyTokens.space3),
          _SkBar(height: CyTokens.space6, widthFactor: 0.76),
          SizedBox(height: CyTokens.space2),
          _SkBar(height: CyTokens.space2_5, widthFactor: 0.46),
        ],
      ),
    );
  }
}

/// 真源 .sk-route-row:64pt 行高起,轨道 16pt 宽(12pt 圆点 + 垂到行底的 2pt 连接线,
/// 末行不画线),文案两行 60%/85%、行底衬 16pt。
class _SkRouteRow extends StatelessWidget {
  const _SkRouteRow({required this.isLast});

  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: CyTokens.space4,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[
                  if (!isLast)
                    Positioned(
                      key: const ValueKey<String>('sk-route-line'),
                      left: (CyTokens.space4 - 2) / 2,
                      top: CyTokens.space3,
                      bottom: 0,
                      width: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          color: palette.bgSurfaceSubtle,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusPill,
                          ),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      key: const ValueKey<String>('sk-route-dot'),
                      width: CyTokens.space3,
                      height: CyTokens.space3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.bgSurfaceSubtle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: CyTokens.space3),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: CyTokens.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    _SkBar(height: CyTokens.space3_5, widthFactor: 0.6),
                    SizedBox(height: CyTokens.space2),
                    _SkBar(height: CyTokens.space3_5, widthFactor: 0.85),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 真源 .sk-map-card:画布整宽 260pt(520rpx --cy-map-h)、圆角 0,
/// 文案衬 12/16/16,两行 60%/40%。
class _SkMapCard extends StatelessWidget {
  const _SkMapCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      child: ColoredBox(
        color: CyPalette.of(context).bgSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const <Widget>[
            _SkBar(
              key: ValueKey<String>('sk-map-canvas'),
              height: 260,
              radius: 0,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                CyTokens.space4,
                CyTokens.space3,
                CyTokens.space4,
                CyTokens.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SkBar(height: CyTokens.space3_5, widthFactor: 0.6),
                  SizedBox(height: CyTokens.space2),
                  _SkBar(height: CyTokens.space3_5, widthFactor: 0.4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 真源 .sk-post 鱼骨。几何必须与 cy-post-card 真卡逐 rpx 一致
/// (头像 44pt=88rpx、间距 10pt、上下内衬 18pt=36rpx),
/// 否则加载完成整栏横向弹一下 —— 真源注释刻意不跟 Figma 骨架稿的原因。
class _SkPostCard extends StatelessWidget {
  const _SkPostCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(CyTokens.pageX, 18, CyTokens.pageX, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          _SkPostAvatar(),
          SizedBox(width: CyTokens.space2_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 线必须长短不一 —— 等长看起来像表格不像文字(真源注释)。
                _SkBar(
                  key: ValueKey<String>('sk-post-l1'),
                  height: CyTokens.space2_5,
                  widthFactor: 0.31,
                  radius: CyTokens.space1_5,
                ),
                SizedBox(height: CyTokens.space2),
                _SkBar(
                  key: ValueKey<String>('sk-post-l2'),
                  height: CyTokens.space2_5,
                  widthFactor: 0.89,
                  radius: CyTokens.space1_5,
                ),
                SizedBox(height: CyTokens.space2),
                _SkBar(
                  key: ValueKey<String>('sk-post-l3'),
                  height: CyTokens.space2_5,
                  widthFactor: 0.70,
                  radius: CyTokens.space1_5,
                ),
                SizedBox(height: CyTokens.space3),
                _SkBar(
                  key: ValueKey<String>('sk-post-media'),
                  height: 230,
                  radius: CyTokens.radiusLg,
                ),
                SizedBox(height: CyTokens.space3),
                Row(
                  children: <Widget>[
                    SizedBox(
                      key: ValueKey<String>('sk-post-act-0'),
                      width: 44,
                      child: _SkBar(height: CyTokens.space3_5),
                    ),
                    SizedBox(width: 22),
                    SizedBox(
                      key: ValueKey<String>('sk-post-act-1'),
                      width: 44,
                      child: _SkBar(height: CyTokens.space3_5),
                    ),
                    SizedBox(width: 22),
                    SizedBox(
                      key: ValueKey<String>('sk-post-act-2'),
                      width: 44,
                      child: _SkBar(height: CyTokens.space3_5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 真源 .sk-post-avatar:44pt 圆(88rpx),与真卡头像同径。
class _SkPostAvatar extends StatelessWidget {
  const _SkPostAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('sk-post-avatar'),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CyPalette.of(context).bgSurfaceSubtle,
      ),
    );
  }
}

/// 票券撕口的 2rpx 虚线(真源 border-top: 2rpx dashed --cy-color-border-strong)。
class _SkDashedTopLine extends CustomPainter {
  _SkDashedTopLine(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const double dash = 4;
    const double gap = 4;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + dash, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_SkDashedTopLine oldDelegate) =>
      oldDelegate.color != color;
}
