import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_native_button.dart';
import '../playkit_fullscreen.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_misc_data.dart';

/// `cy-playkit-bingo` · 九宫格 · 走到一处点亮一格,连成线换奖。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-bingo/`。
///
/// 它是**主题级的格子**,不是一次玩完的玩法 —— 所以这一屏只**呈现**进度:
/// 点亮发生在别的节点,由服务端记账(真源注释原文)。点一格看它要怎么亮;
/// 已亮的不再弹,那一格的事已经做完了。
///
/// ## 本地 kind,不做服务端动作
/// bingo 在真源 `KIT_TYPES` 里、但**没有** `ACTION_OF` 条目 —— 与
/// `walk` / `stickerBook` / `gameTimer` 同列:服务端不下发它,由本地流程点名。
/// 所以这一屏不抛 `PlayKitAction`,只把「玩家点了哪一格」交给宿主([onCellTap])。
///
/// ## 与真源的已知差异(§7.2 accepted,「iOS 27 原生化」)
/// * 说明弹层:真源是页内一块 `bg__panel`;App 改用底部浮层承载同一段话
///   (入场走淡入,减动效下不播;摘除是直接消失 —— 淡出要延迟卸载,不值当)。
/// * 棋盘道具色(黑白相间棋子 + 实心投影当侧壁 + 点亮变青 + 连线变粉)保留;
///   圆角/字阶走 iOS 梯级,字重 800 → w700。
/// * 限时条与判定屏是**台面 chrome**,宿主的活 —— 不在玩法组件里抢一份。
class PlayKitBingoView extends StatefulWidget {
  const PlayKitBingoView({
    super.key,
    required this.data,
    this.title = '',
    this.cellSpecs = const <Map<String, Object?>>[],
    this.labels = const <String>[],
    this.filledPositions = const <int>[],
    this.lineReward = '',
    this.fullReward = '',
    this.onCellTap,
  });

  final PlayKitFullscreenContext data;

  /// 商家填的棋盘名。空则回落到卡片的标题。
  final String title;

  /// 九个格子,每格 `{ t, how }` —— `how` 是「怎么点亮」。
  final List<Map<String, Object?>> cellSpecs;

  /// 兼容只给名字的老写法。
  final List<String> labels;

  /// 已点亮的位序(0–8,行优先)。
  final List<int> filledPositions;

  final String lineReward;
  final String fullReward;

  /// 点了一格(未点亮的)。交付给本地流程;本组件不发服务端动作。
  final ValueChanged<int>? onCellTap;

  @override
  State<PlayKitBingoView> createState() => _PlayKitBingoViewState();
}

/// 皮肤 `skin-bingo`(`style/play-surface.wxss:24`)与 `playkit-bingo/index.wxss`
/// 的逐值道具色:淡蓝底 + 黑白棋子 + 青(点亮)/ 粉(连线)。这是一套玩法皮肤,
/// 不是界面色 —— 同类先例:`playkit_countdown_view.dart` 的白台面。
const Color _kBingoSurface = Color(0xFFCFE2F5);
const Color _kBingoInk = Color(0xFF111114);
const Color _kBingoSub = Color(0xFF4D6076);
const Color _kBingoDone = Color(0xFF3FD2D2);
const Color _kBingoDoneInk = Color(0xFF00363A);
const Color _kBingoLine = Color(0xFFFC7EBD);
const Color _kBingoLineInk = Color(0xFF5C0030);
const Color _kBingoPaper = Color(0xFFFFFFFF);

class _PlayKitBingoViewState extends State<PlayKitBingoView> {
  PlayKitBingoCell? _panel;

  /// 正按着哪一格(真源 hover-class 的 App 等价)。
  int? _pressedCell;

  String get _title {
    final String trimmed = widget.title.trim();
    return trimmed.isEmpty ? widget.data.card.title : trimmed;
  }

  List<PlayKitBingoCell> get _cells => buildBingoCells(
    cellSpecs: widget.cellSpecs,
    labels: widget.labels,
    filledPositions: widget.filledPositions,
  );

  void _onCell(PlayKitBingoCell cell) {
    // 已亮的不再弹 —— 那一格的事已经做完了(真源 onCell)。
    if (cell.filled) return;
    playKitHaptic(context, PlayKitHaptic.selection);
    setState(() => _panel = cell);
    widget.onCellTap?.call(cell.index);
  }

  @override
  Widget build(BuildContext context) {
    final List<PlayKitBingoCell> cells = _cells;
    final int filledCount = cells
        .where((PlayKitBingoCell c) => c.filled)
        .length;
    final bool full = filledCount == 9;
    final List<bool> filled = <bool>[
      for (final PlayKitBingoCell cell in cells) cell.filled,
    ];
    final String ribbon = bingoRibbon(
      full: full,
      lines: bingoLineCount(filled),
      lineReward: widget.lineReward,
      fullReward: widget.fullReward,
    );
    return ColoredBox(
      color: _kBingoSurface,
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space4,
                vertical: CyTokens.space3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Semantics(
                    // 副标题只留给读屏器:屏幕上已经摆着能点的东西了,
                    // 再写一句怎么点,等于承认那个东西自己说不清楚(真源注释)。
                    label: '$_title，本周任务',
                    child: ExcludeSemantics(
                      child: Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _kBingoInk,
                          fontSize: CyTokens.typePageTitle,
                          fontWeight: FontWeight.w700,
                          height: CyTokens.leadingTight,
                        ),
                      ),
                    ),
                  ),
                  if (ribbon.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space3,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          // 真源 `.bg__ribbon`:奖励是一条**横幅**,不是胶囊 ——
                          // 硬角(6rpx)+ 黑描边(4rpx)+ 实心侧影(0 8rpx 0 #000),
                          // 和九宫格同一套厚度语言;字色 #111114(不是连线的 5C0030)。
                          color: _kBingoLine,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: _kBingoInk, width: 2),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: _kBingoInk, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Text(
                          ribbon,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _kBingoInk,
                            fontSize: CyTokens.typeBody,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space4),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: CyTokens.space2,
                            crossAxisSpacing: CyTokens.space2,
                          ),
                      itemCount: cells.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _cell(cells[index]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space4),
                    child: Text(
                      '已完成 $filledCount / 9',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _kBingoInk,
                        fontSize: CyTokens.typeButton,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: CyTokens.space2),
                    child: Text(
                      '每一格都要到店扫码或把那个游戏玩完才会亮。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _kBingoSub,
                        fontSize: CyTokens.typeCaption,
                        height: CyTokens.leadingNormal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_panel != null)
              Positioned(
                left: CyTokens.space4,
                right: CyTokens.space4,
                bottom: CyTokens.space4,
                child: TweenAnimationBuilder<double>(
                  // 真源 `.bg__panel` 本身没有入场动画;淡入是 App 按 iOS 浮层
                  // 惯例自加的(§7.2「iOS 27 原生化」)。减动效下不播,摘除仍瞬删。
                  key: ValueKey<PlayKitBingoCell?>(_panel),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : CyMotion.fadeSwap,
                  builder: (BuildContext context, double t, Widget? child) =>
                      Opacity(opacity: t, child: child),
                  child: _panelCard(_panel!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(PlayKitBingoCell cell) {
    final Color background = cell.inLine
        ? _kBingoLine
        : cell.filled
        ? _kBingoDone
        : (cell.dark ? _kBingoInk : _kBingoPaper);
    final Color foreground = cell.inLine
        ? _kBingoLineInk
        : cell.filled
        ? _kBingoDoneInk
        : (cell.dark ? _kBingoPaper : _kBingoInk);
    final IconData glyph = cell.filled
        ? CupertinoIcons.check_mark
        : cell.isScan
        ? CupertinoIcons.qrcode
        : CupertinoIcons.play_fill;
    return Semantics(
      button: !cell.filled,
      label:
          '${cell.title}，${cell.how}'
          '${cell.filled ? '，已点亮' : ''}',
      child: GestureDetector(
        key: Key('playkit-bingo-cell-${cell.index}'),
        behavior: HitTestBehavior.opaque,
        // 真源格子的 hover-class 是全局 `.cy-pressed`(压淡 .88 + 缩 .98):
        // 按下去没反应的话,九宫格读起来像一张图,不是一块棋盘。
        onTapDown: (TapDownDetails _) =>
            setState(() => _pressedCell = cell.index),
        onTapCancel: () => setState(() => _pressedCell = null),
        onTap: () {
          setState(() => _pressedCell = null);
          _onCell(cell);
        },
        child: Opacity(
          opacity: _pressedCell == cell.index ? 0.88 : 1,
          child: AnimatedContainer(
            alignment: Alignment.center,
            transform: _pressedCell == cell.index
                ? (Matrix4.identity()..scaleByDouble(0.98, 0.98, 1, 1))
                : Matrix4.identity(),
            // 真源 `.bg--reduced .bg__cell { transition: none }`:减动效下换色瞬切。
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : CyMotion.fast,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              border: Border.all(color: _kBingoInk, width: 2),
              // 厚度在每一格上:实心投影当侧壁,再压一层柔影(真源 .bg__cell)。
              // 填过的格子被**按下去**:厚度收掉一半,一眼看出这格已经踩实了。
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _kBingoInk,
                  offset: Offset(0, cell.filled ? 2 : 4),
                ),
                const BoxShadow(
                  color: Color(0x47000000),
                  blurRadius: 9,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            padding: const EdgeInsets.all(CyTokens.space1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(glyph, size: 16, color: foreground),
                const SizedBox(height: CyTokens.space1),
                Text(
                  cell.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: CyTokens.typeLabel,
                    fontWeight: FontWeight.w700,
                    height: CyTokens.leadingTight,
                  ),
                ),
                Text(
                  cell.how,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.72),
                    fontSize: CyTokens.typeMicro,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelCard(PlayKitBingoCell cell) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: _kBingoPaper,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: _kBingoInk, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            cell.title,
            style: const TextStyle(
              color: _kBingoInk,
              fontSize: CyTokens.typeButton,
              fontWeight: FontWeight.w700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              cell.isScan
                  ? 'GPS 可以伪造，进店这件事只认扫码。到店后扫这个点位的静态码。'
                  : '这一格装的是「${cell.how}」。玩完它才会亮。',
              style: const TextStyle(
                color: _kBingoSub,
                fontSize: CyTokens.typeBody,
                height: CyTokens.leadingNormal,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: CyNativeButton(
              key: const Key('playkit-bingo-panel-ok'),
              label: '知道了',
              role: CyNativeButtonRole.secondary,
              width: double.infinity,
              onPressed: () => setState(() => _panel = null),
            ),
          ),
        ],
      ),
    );
  }
}
