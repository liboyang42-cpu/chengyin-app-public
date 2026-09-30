import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';

/// 一个滑动露出的操作 —— 对应 UIKit 的 `UIContextualAction`。
///
/// UIKit 那边 `UIContextualAction` 可设的只有 `style` / `title` / `image` /
/// `backgroundColor`，本类刻意不对开更多：多出来的字段只会变成「比系统更像
/// 系统」的自定义控件。
class CyContextualAction {
  const CyContextualAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
    this.isEnabled = true,
    this.semanticLabel,
  });

  final String id;

  /// `UIContextualAction.title`。
  final String label;

  /// VoiceOver 读的那一份。系统中 cell 会先读出行内容，所以动作本身只叫
  /// 「删除」；本仓列表行动作要保持「取消收藏某某」这种自解释说法，
  /// 不给视觉文案加长。缺省用 [label]。
  final String? semanticLabel;

  /// `UIContextualAction.image`。iOS 的滑动按钮是图标在上、文案在下；
  /// 同组动作要么全带图标要么全不带（设计规则手册 L7），所以必填。
  final IconData icon;

  final VoidCallback onPressed;

  /// `UIContextualAction.Style.destructive` —— 底用系统语义红，不用品牌红。
  final bool destructive;

  final bool isEnabled;

  /// 图标框高。两个读数：a11y 给系统钮内 image 元素 20.33pt；像素量同一个
  /// `square.and.arrow.up` 字形，系统墨迹 15.33×19.33、20.33 号下本组件墨迹
  /// 14.33×18.67（小 5~7%）。取 21.33 让两轴都落进 ±0.3pt。
  static const double iconSize = 21.33;

  /// 标签字号。实测墨迹：系统 4 字标签宽 49.33 / 高 11.34，本组件 12pt 下
  /// 45.67 / 10.33 —— 横纵两个方向独立推算都是 13pt（墨迹/字号 ≈ 0.95 / 0.86）。
  static const double labelFontSize = 13;

  /// 标签排版尺寸 —— 钮宽（胶囊档）与钮下方那块溢出绘制共用这一份。
  static Size labelSize(String label, TextDirection textDirection) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: labelFontSize,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    return Size(painter.width, painter.height);
  }

  /// ★ iOS 27.0 系统左滑实测常量（iPhone 402pt @3x 模拟器，浅/暗两态，
  /// 测量脚本与截图见 `out/native-swipe-bridge.md`）。这些是**系统度量**，
  /// 不走 `CyTokens`（那套是小程序 brand spacing，跟 iOS 无关）。
  ///
  /// 行高 → 钮尺寸的规则（两个实测点拟合）：
  ///   行高 62 → 钮 60×33.33 的胶囊；行高 ≥ 102 → 钮 50.67 的正圆，
  ///   且行高再长也不变（102/142/182/222 四档读数完全一致）。
  static const double circleSide = 50.67;

  /// 钮高度 = 行高 − 这条（标签块 + 上下留白）；封顶 [circleSide]。
  static const double heightBudgetLoss = 28.67;

  /// 钮底 → 标签墨迹。
  static const double labelGap = 6.67;

  /// 矮行里胶囊比高度多出来的那段直边。
  static const double pillStretch = 26.67;
}

/// iOS 列表行的滑动操作 —— `UISwipeActionsConfiguration` 的对应物。
///
/// ★ 为什么不是平台视图：iOS 27 SDK 里 `UIContextualAction : NSObject`，它
///   只是「动作的描述」，按钮由 UIKit 私有滑动 machinery 绘制，外部拿不到
///   那个 view；`UISwipeActionsConfiguration` 也只被 `UITableView` /
///   `UICollectionViewListCell` / `UICollectionLayoutList` /
///   `UITabBarControllerSidebar` 消费 —— 想让系统画按钮，就得让系统的列表
///   接管整行内容。所以这里是 Flutter 侧按系统观感实现，行内容仍由各页自己
///   画，主题 token / 动态字体 / golden 测试都还在一条路上。
///   判定过程与实测证据见 `out/native-swipe-bridge.md`。
///
/// 与系统对齐的语义：
///   * 滑动只**露出**不执行：[performsFirstActionWithFullSwipe] 默认 `false`
///     （系统同名属性默认 `true`，本仓取 `false` —— 破坏性动作不许被一次
///     误滑直接执行，真要执行必须再点一次）。
///   * 同一时刻只开一行：由父级持有 [openKey]。
///   * 收起时不常驻操作钮，但把动作挂成 accessibility custom action，
///     VoiceOver 不展开也读得到（iOS 就是这样暴露 swipe actions 的）。
class CySwipeActionsRow extends StatefulWidget {
  const CySwipeActionsRow({
    super.key,
    required this.child,
    required this.rowKey,
    required this.openKey,
    required this.onOpenChanged,
    this.trailing = const <CyContextualAction>[],
    this.leading = const <CyContextualAction>[],
    this.performsFirstActionWithFullSwipe = false,
    this.enabled = true,
  }) : assert(leading.length <= 3),
       assert(trailing.length <= 3);

  /// 行内容。
  final Widget child;

  /// 本行身份（一般用数据 id）。
  final Object rowKey;

  /// 当前展开的是哪一行；不是本行就收起。
  final Object? openKey;

  /// 展开/收起上报，父级据此更新 [openKey]。
  final ValueChanged<Object?> onOpenChanged;

  /// 左滑（从右向左）露出的动作，最右那个最先被碰到。
  final List<CyContextualAction> trailing;

  /// 右滑（从左向右）露出的动作。
  final List<CyContextualAction> leading;

  /// 划到底是否直接执行第一个动作。默认 `false`：必须点。
  final bool performsFirstActionWithFullSwipe;

  final bool enabled;

  /// 钮高（= 圆/胶囊的短边）。行高不够时按行高缩。
  static double pillHeight(double rowHeight) {
    final double h = rowHeight - CyContextualAction.heightBudgetLoss;
    return h < 24
        ? 24
        : (h > CyContextualAction.circleSide
              ? CyContextualAction.circleSide
              : h);
  }

  /// 钮与钮、首尾钮与行边之间的缝（实测两值相同）。
  static double spacing(double rowHeight) =>
      pillHeight(rowHeight) >= CyContextualAction.circleSide ? 10.67 : 10;

  /// 面板完全展开要滑多远 = `缝 × (n+1) + Σ 钮宽`，不超过行宽。
  static double panelWidth(
    List<CyContextualAction> actions, {
    required double rowHeight,
    double? rowWidth,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    if (actions.isEmpty) return 0;
    final double s = spacing(rowHeight);
    final double cap = rowWidth == null
        ? double.infinity
        : (rowWidth - s * (actions.length + 1)) / actions.length;
    double total = 0;
    for (final CyContextualAction a in actions) {
      total += actionWidth(
        a,
        rowHeight: rowHeight,
        cap: cap,
        textDirection: textDirection,
      );
    }
    final double natural = total + s * (actions.length + 1);
    return rowWidth == null || natural < rowWidth ? natural : rowWidth;
  }

  /// 单个钮的宽：正圆档恒等于直径（长文案溢出，不加宽）；胶囊档
  /// `max(高 + [CyContextualAction.pillStretch], 文案宽)`。
  static double actionWidth(
    CyContextualAction action, {
    required double rowHeight,
    double? cap,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final double h = pillHeight(rowHeight);
    final bool circle = h >= CyContextualAction.circleSide;
    final double base = circle ? h : h + CyContextualAction.pillStretch;
    double w = base;
    if (!circle) {
      final double labelWidth = CyContextualAction.labelSize(
        action.label,
        textDirection,
      ).width;
      w = base > labelWidth ? base : labelWidth;
    }
    if (cap != null && w > cap) w = cap < base ? base : cap;
    return w;
  }

  @override
  State<CySwipeActionsRow> createState() => _CySwipeActionsRowState();
}

class _CySwipeActionsRowState extends State<CySwipeActionsRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );

  bool _dragging = false;
  bool _hapticFired = false;

  /// 行高 —— 钮的直径/胶囊比例全靠它。列表里传进来的 maxHeight 是 infinity，
  /// 所以不能问外层约束，只能问 Stack 自己量出来的高度（Stack 尺寸 = 行内容）。
  double _rowHeight = 62;

  @override
  void initState() {
    super.initState();
    _offset.addListener(_repaint);
  }

  @override
  void didUpdateWidget(CySwipeActionsRow old) {
    super.didUpdateWidget(old);
    if (!_dragging && widget.openKey != widget.rowKey) _animateTo(0);
  }

  @override
  void dispose() {
    _offset.removeListener(_repaint);
    _offset.dispose();
    super.dispose();
  }

  void _repaint() => setState(() {});

  void _animateTo(double target) {
    if ((_offset.value - target).abs() < 0.5) {
      _offset.value = target;
      return;
    }
    _offset.animateTo(
      target,
      // Reduce Motion：位置照样到位，只是不走过场动画。
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : CyMotion.standard,
      curve: Curves.easeOut,
    );
  }

  bool get _isOpen => _offset.value.abs() > 0.5;

  void close() {
    _animateTo(0);
    widget.onOpenChanged(null);
  }

  double _leadingWidth(double rowWidth) => CySwipeActionsRow.panelWidth(
    widget.leading,
    rowHeight: _rowHeight,
    rowWidth: rowWidth,
    textDirection: Directionality.of(context),
  );

  double _trailingWidth(double rowWidth) => CySwipeActionsRow.panelWidth(
    widget.trailing,
    rowHeight: _rowHeight,
    rowWidth: rowWidth,
    textDirection: Directionality.of(context),
  );

  void _onDragStart(DragStartDetails _) {
    if (!widget.enabled) return;
    _dragging = true;
    _hapticFired = false;
  }

  void _onDragUpdate(DragUpdateDetails d, double rowWidth) {
    if (!widget.enabled || !_dragging) return;
    final double next = (_offset.value + d.delta.dx).clamp(
      -_trailingWidth(rowWidth),
      _leadingWidth(rowWidth),
    );
    // 越过阈值才「咬合」一下 —— 拖动每帧都震会变成噪音。
    final bool past = next.abs() > 12;
    if (past && !_hapticFired) {
      _hapticFired = true;
      HapticFeedback.selectionClick();
    }
    _offset.value = next;
  }

  void _onDragEnd(DragEndDetails _, double rowWidth) {
    if (!widget.enabled || !_dragging) return;
    _dragging = false;
    final double v = _offset.value;
    final double lead = _leadingWidth(rowWidth);
    final double trail = _trailingWidth(rowWidth);
    final double target;
    if (v > 0 && widget.leading.isNotEmpty) {
      target = v > lead / 2 ? lead : 0;
    } else if (v < 0 && widget.trailing.isNotEmpty) {
      target = v < -trail / 2 ? -trail : 0;
    } else {
      target = 0;
    }
    _offset.value = target;
    widget.onOpenChanged(target.abs() > 0.5 ? widget.rowKey : null);
    if (widget.performsFirstActionWithFullSwipe && target.abs() > 0.5) {
      final List<CyContextualAction> side = target > 0
          ? widget.leading
          : widget.trailing;
      // 系统的「first action」是手指最先碰到那个，也就是贴着边的那个。
      final CyContextualAction? first = side.isEmpty ? null : side.last;
      if (first != null) _run(first);
    }
  }

  void _run(CyContextualAction action) {
    close();
    if (action.isEnabled) action.onPressed();
  }

  Map<CustomSemanticsAction, VoidCallback> get _customActions {
    final Map<CustomSemanticsAction, VoidCallback> out =
        <CustomSemanticsAction, VoidCallback>{};
    for (final CyContextualAction a in <CyContextualAction>[
      ...widget.leading,
      ...widget.trailing,
    ]) {
      out[CustomSemanticsAction(label: a.semanticLabel ?? a.label)] = () =>
          _run(a);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double rowWidth = constraints.maxWidth;
        final bool revealed = _offset.value.abs() > 0.5;
        final bool showLeading = _offset.value > 0;
        final List<CyContextualAction> shown = showLeading
            ? widget.leading
            : widget.trailing;
        return Semantics(
          // container 挡合并：不加的话这一层会把后代行的 tap 动作并进自己
          // 的节点里，行内容反而变得不可点（语义层）。
          container: true,
          // 收起状态下动作也要能被 VoiceOver 摸到 —— 对应 iOS 把 swipe
          // actions 暴露成 cell 的 accessibility custom actions。
          customSemanticsActions: _customActions,
          child: Stack(
            children: <Widget>[
              // 量行高：Stack 的尺寸由行内容决定，Positioned.fill 拿到的就是它。
              // 只记账不 setState —— 消费方是下一次指针事件。
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double h = constraints.maxHeight;
                    if (h.isFinite && h != _rowHeight) _rowHeight = h;
                    return const SizedBox.shrink();
                  },
                ),
              ),
              Positioned.fill(
                child: revealed
                    ? _Panel(
                        actions: shown,
                        alignment: showLeading
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        rowWidth: rowWidth,
                        rowHeight: _rowHeight,
                        onTap: _run,
                      )
                    : const SizedBox.shrink(),
              ),
              AnimatedBuilder(
                animation: _offset,
                builder: (BuildContext context, Widget? child) =>
                    Transform.translate(
                      offset: Offset(_offset.value, 0),
                      child: child,
                    ),
                child: GestureDetector(
                  // 展开时点行 = 先收起（iOS 行为）。真正挡住民中测试的是下面
                  // 的 IgnorePointer：嵌套 tap 竞技场里内层必胜。
                  onTap: _isOpen ? close : null,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: (DragUpdateDetails d) =>
                      _onDragUpdate(d, rowWidth),
                  onHorizontalDragEnd: (DragEndDetails d) =>
                      _onDragEnd(d, rowWidth),
                  child: ColoredBox(
                    // 行底必须不透明，否则后面的操作钮会透出来。取页面底色
                    // 而不是 surface：滑走之后露出的那条底 = 这一行身后的颜色，
                    // 系统里它等于 cell 自己的底色（实测就是页面底），而本仓
                    // 很多行内容是一张带圆角的卡（surfaceStrong），拿 bgSurface
                    // 会在卡的右缘留下一条既不是卡也不是页底的灰边。
                    color: CyPalette.of(context).bgPage,
                    child: IgnorePointer(
                      ignoring: revealed,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 行底下的动作面板：贴着滑动方向的边，钮浮在页面底色上（系统就是
/// 把行推开、露出底色，不给面板自己铺底）。
class _Panel extends StatelessWidget {
  const _Panel({
    required this.actions,
    required this.alignment,
    required this.rowWidth,
    required this.rowHeight,
    required this.onTap,
  });

  final List<CyContextualAction> actions;
  final Alignment alignment;
  final double rowWidth;
  final double rowHeight;
  final void Function(CyContextualAction) onTap;

  @override
  Widget build(BuildContext context) {
    final double s = CySwipeActionsRow.spacing(rowHeight);
    final double cap = actions.isEmpty
        ? rowWidth
        : (rowWidth - s * (actions.length + 1)) / actions.length;
    final TextDirection textDirection = Directionality.of(context);
    final List<Widget> children = <Widget>[];
    for (final CyContextualAction a in actions) {
      if (children.isNotEmpty) children.add(SizedBox(width: s));
      children.add(
        _Action(
          action: a,
          cap: cap,
          rowHeight: rowHeight,
          textDirection: textDirection,
          onTap: onTap,
        ),
      );
    }
    return Align(
      alignment: alignment,
      child: Padding(
        // 首尾钮到行边的缝，与钮间距同值（实测 10 / 10.67pt）。
        padding: EdgeInsets.symmetric(horizontal: s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.action,
    required this.cap,
    required this.rowHeight,
    required this.textDirection,
    required this.onTap,
  });

  final CyContextualAction action;
  final double cap;
  final double rowHeight;
  final TextDirection textDirection;
  final void Function(CyContextualAction) onTap;

  @override
  Widget build(BuildContext context) {
    // destructive 走系统语义红（实测 iOS 27 浅 #FF383C / 暗 #FF4245，
    // `CupertinoColors.systemRed` 是 #FF3B30 / #FF453A，单通道差 ≤ 12）；
    // normal 实测浅 #C7C7CC / 暗 #48484A，与 `systemGrey3` 的两个值逐通道
    // 完全相等（199,199,204 / 72,72,74），故直接取该语义色，不再用
    // 「systemGrey + 55% 透明」近似（那样暗色会偏亮 6/255）。都不引品牌色、不写 hex。
    final Color background = action.destructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.systemGrey3.resolveFrom(context);
    const Color foreground = CupertinoColors.white;
    final double width = CySwipeActionsRow.actionWidth(
      action,
      rowHeight: rowHeight,
      cap: cap,
      textDirection: textDirection,
    );
    final double height = CySwipeActionsRow.pillHeight(rowHeight);
    final Size labelSize = CyContextualAction.labelSize(
      action.label,
      textDirection,
    );
    return Semantics(
      container: true,
      button: true,
      enabled: action.isEnabled,
      label: action.semanticLabel ?? action.label,
      onTap: action.isEnabled ? () => onTap(action) : null,
      child: ExcludeSemantics(
        child: SizedBox(
          key: Key('swipe-action-${action.id}'),
          width: width,
          child: CupertinoButton(
            // 钮之间那条缝不该吞点击；整槽到行高，触达区 ≥44pt。
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: action.isEnabled ? () => onTap(action) : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                DecoratedBox(
                  key: Key('swipe-action-surface-${action.id}'),
                  decoration: BoxDecoration(
                    color: background,
                    // 实测胶囊圆角 = 高度一半（33.33 高的钮拟合出 16.67）。
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Center(
                      child: Icon(
                        action.icon,
                        size: CyContextualAction.iconSize,
                        color: foreground,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: CyContextualAction.labelGap),
                // 实测系统：文案比钮宽时溢出到圆外照排，不缩不省略。
                // 高度必须自己钉死（Column 给的是无限高，OverflowBox 会把
                // 无限高原样收下）。
                SizedBox(
                  height: labelSize.height,
                  child: OverflowBox(
                    minWidth: width,
                    maxWidth: double.infinity,
                    alignment: Alignment.center,
                    child: Text(
                      action.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: CyContextualAction.labelFontSize,
                        fontWeight: FontWeight.w400,
                        // 实测标签色 = secondaryLabel（浅底上墨迹 #8A8A8E）。
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
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
