import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_native_button.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_misc_data.dart';

/// `cy-playkit-random` · 抽卡 · 左滑换一张、右滑翻开。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-random/`。
/// 一副牌摊成扇形叠在中间 ——「这是一副牌」这件事必须先看得见,
/// 不然抽出来那张就没有来处。手势是这个玩法的操作方式,不是锦上添花;
/// 两颗按钮按方向摆在两侧(「换一张」在左、「翻开它」在右),位置就在说往哪儿滑。
///
/// ## 抽到什么由服务端定
/// 线上**盒子里有什么服务端不下发**:盖着的牌牌面写着「?」,只给「一共能抽几次」
/// 和「已经抽到的是什么」。翻开那一下只是**请求**,`DRAW` **不带任何参数**
/// (真源 `serverPayload`:`random:draw → {}`)—— 抽哪一件由服务端按权重定,
/// 客户端挑的是位置不是内容,说了不算。
///
/// ## 与真源的已知差异(§7.2 accepted,「iOS 27 原生化」)
/// * 甩牌出画的时长 920ms → `CyMotion.slow`(350ms):真源那个值是照 CSS
///   `.9s` 配的,App 侧按系统的「一甩」节奏收快;减动效下整段跳过,直接换牌。
/// * 换色的满高椭圆擦除 → 背景色 `AnimatedContainer` 交叉淡化(§3.7 A2:
///   避免大面积位移/擦除,位移改淡入淡出)。卡面的道具色与三色轮转保留。
/// * 卡面图案按原型的「一扇小窗 + 三个几何块」重绘为 `CustomPaint`
///   (小程序是把同一段 SVG 编码成 data URI)—— 同图同色,按卡序轮转。
/// * 商家预览传明牌的 `cards` 那条路 App 侧没有对应页,不接。
class PlayKitRandomView extends StatefulWidget {
  const PlayKitRandomView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitRandomView> createState() => _PlayKitRandomViewState();
}

/// 真源 `THEMES`(`playkit-random/index.js`):ds-ok 卡池底色,**固定轮转**。
/// 颜色一放开,一副卡池里会出现十种不搭的组合。
const List<Color> _kDeckThemes = <Color>[
  Color(0xFF0B6ADC),
  Color(0xFFD99A16),
  Color(0xFFC5372F),
];

/// 真源 `art.js` 的四色(PALETTE)。
const List<Color> _kDeckArt = <Color>[
  Color(0xFF34A853),
  Color(0xFFF7B326),
  Color(0xFFDD363C),
  Color(0xFF0B6ADC),
];

const Color _kDeckInk = Color(0xFF111114);
const Color _kDeckPaper = Color(0xFFFBFBFB);

class _PlayKitRandomViewState extends State<PlayKitRandomView>
    with SingleTickerProviderStateMixin {
  /// 甩出去的那张:动画期间还留在屏上,飞完就摘掉(真源 `.dk__card--out`)。
  // 同 predict:显式初始化,别让 dispose 里那次访问成为第一次(见其注释)。
  late final AnimationController _out;
  final GlobalKey _deckKey = GlobalKey();

  late int _active;
  double _deckWidth = 0;
  double _dx = 0;
  bool _dragging = false;
  String? _leavingId;
  PlayKitDeckCard? _detail;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  Map<String, Object?> get _kit => widget.data.card.kit;

  List<Map<String, Object?>> get _drawn =>
      (_kit['drawn'] is List ? _kit['drawn']! as List : const <Object?>[])
          .whereType<Map>()
          .map(
            (Map<Object?, Object?> raw) => raw.map<String, Object?>(
              (Object? key, Object? value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          )
          .toList(growable: false);

  int get _drawCount => int.tryParse('${_kit['drawCount'] ?? ''}') ?? 0;

  List<PlayKitDeckCard> get _deck =>
      buildRandomDeck(drawn: _drawn, drawCount: _drawCount);

  /// 盖着的牌还能不能抽:服务端说抽满了(`complete`)就不再发请求。
  bool get _canDraw => widget.data.enabled && !widget.data.card.complete;

  @override
  void initState() {
    super.initState();
    _out = AnimationController(vsync: this, duration: CyMotion.slow);
    _active = _initialActive();
  }

  int _initialActive() {
    final List<PlayKitDeckCard> deck = _deck;
    return randomActiveIndex(_drawn.length, deck.length);
  }

  @override
  void didUpdateWidget(covariant PlayKitRandomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 服务端把新抽到的那张带回来之后,停在下一张还没翻的牌上 ——
    // 不用玩家自己滑过去(真源 observer 的线上分支)。
    final bool deckChanged =
        oldWidget.data.card.kit['drawn'].toString() !=
            _kit['drawn'].toString() ||
        oldWidget.data.card.kit['drawCount'].toString() != '$_drawCount';
    if (deckChanged) {
      setState(() {
        _detail = null;
        _active = _initialActive();
      });
    }
  }

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  void _measure() {
    final RenderObject? box = _deckKey.currentContext?.findRenderObject();
    if (box is RenderBox) _deckWidth = box.size.width;
  }

  void _next() {
    final List<PlayKitDeckCard> deck = _deck;
    if (deck.length < 2) return;
    final String leavingId = deck[_active].id;
    playKitHaptic(context, PlayKitHaptic.light);
    setState(() {
      _dx = 0;
      _active = (_active + 1) % deck.length;
      _leavingId = leavingId;
    });
    if (_reduced) {
      setState(() => _leavingId = null);
      return;
    }
    unawaited(
      _out.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _leavingId = null);
      }),
    );
  }

  void _open() {
    final List<PlayKitDeckCard> deck = _deck;
    if (deck.isEmpty || _active >= deck.length) return;
    final PlayKitDeckCard card = deck[_active];
    if (!card.opened) {
      // 还盖着的牌:翻开这一下只是**请求**,抽到什么由服务端按权重定。
      if (!_canDraw) return;
      playKitHaptic(context, PlayKitHaptic.medium);
      widget.data.onAction?.call(
        const PlayKitAction(label: '翻开它', action: 'DRAW'),
      );
      return;
    }
    // 「做成了」= 认下这张卡;翻开不等于通关,不出判定屏 ——
    // 盖一张绿屏上去,玩家就读不到卡上写的任务了(真源注释原文)。
    playKitHaptic(context, PlayKitHaptic.medium);
    setState(() => _detail = card);
  }

  void _onDragStart(DragStartDetails details) {
    // 真源 `.dk--reduced .dk__card { transition: none }` 关的是**转场**,
    // 不是手势:减动效用户照样该能拖着牌走,只是甩出去不留飞行动画。
    _measure();
    setState(() {
      _dragging = true;
      _dx = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    setState(() => _dx += details.delta.dx);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    final PlayKitDeckGesture gesture = randomGestureOf(_dx, _deckWidth);
    setState(() {
      _dragging = false;
      _dx = 0;
    });
    if (gesture == PlayKitDeckGesture.next) {
      _next();
    } else if (gesture == PlayKitDeckGesture.open) {
      _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<PlayKitDeckCard> deck = _deck;
    if (_active >= deck.length && deck.isNotEmpty) _active = deck.length - 1;
    final Color bg = _kDeckThemes[randomThemeIndexFor(_active)];
    final String deckName = '${_kit['deckName'] ?? ''}'.trim();
    return ColoredBox(
      color: bg,
      child: AnimatedContainer(
        // 真源 js 在 reducedMotion 下直接 setData 换色,不走撑开转场。
        duration: _reduced ? Duration.zero : CyMotion.fadeSwap,
        color: bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space4,
              vertical: CyTokens.space3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (deckName.isNotEmpty)
                  Text(
                    deckName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: CyTokens.typeBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: Center(child: _deckStack(deck))),
                      if (_detail != null)
                        Positioned.fill(child: _detailPanel(_detail!)),
                    ],
                  ),
                ),
                if (deck.isEmpty)
                  // 空态:一副牌一张都没有(服务端两样都没给)。
                  // 说清「怎么才会有」,不摆一个空牌堆。
                  const Padding(
                    padding: EdgeInsets.only(bottom: CyTokens.space3),
                    child: Text(
                      '这副牌还没装进内容，等商家把卡池配好再来。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: CyTokens.typeBody,
                        height: CyTokens.leadingNormal,
                      ),
                    ),
                  )
                else
                  Row(
                    children: <Widget>[
                      // 手势提示做进按钮本身:位置就在说往哪儿滑(真源原文)。
                      Expanded(
                        child: CyNativeButton(
                          key: const Key('playkit-random-next'),
                          label: '换一张',
                          role: CyNativeButtonRole.secondary,
                          icon: const CyNativeButtonIcon(
                            sfSymbol: 'chevron.left',
                            fallback: CupertinoIcons.chevron_left,
                          ),
                          onPressed: deck.length < 2 ? null : _next,
                        ),
                      ),
                      const SizedBox(width: CyTokens.space3),
                      Expanded(
                        child: CyNativeButton(
                          key: const Key('playkit-random-draw'),
                          label: '翻开它',
                          loading: widget.data.acting,
                          icon: const CyNativeButtonIcon(
                            sfSymbol: 'chevron.right',
                            fallback: CupertinoIcons.chevron_right,
                          ),
                          // 盖着的牌抽满了 / 宿主说不给点,按钮就得**看起来**点不了 ——
                          // 亮着让人点、点了静默 return,是骗人(禁用口径同 predict CTA)。
                          onPressed:
                              deck.isEmpty ||
                                  (!deck[_active].opened && !_canDraw)
                              ? null
                              : _open,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _deckStack(List<PlayKitDeckCard> deck) {
    if (deck.isEmpty) return const SizedBox.shrink();
    List<Widget> layered() {
      // Flutter 的 Stack 是「后画的在上」:按 z(真源里 10/20/30)升序摆。
      final List<(int, Widget)> zipped = <(int, Widget)>[];
      for (int i = 0; i < deck.length; i++) {
        final int pos = randomPosOf(i, _active, deck.length);
        final PlayKitDeckCard card = deck[i];
        final bool leaving = card.id == _leavingId;
        if (pos < 0 && !leaving) continue;
        final (int z, Widget face) = _deckCard(card, i, pos, leaving);
        zipped.add((leaving ? 40 : z, face));
      }
      zipped.sort((a, b) => a.$1.compareTo(b.$1));
      return <Widget>[for (final (int, Widget) entry in zipped) entry.$2];
    }

    return LayoutBuilder(
      key: _deckKey,
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = math.min(constraints.maxWidth, 260);
        final double height = width * 430 / 270;
        return SizedBox(
          width: width,
          height: height,
          child: GestureDetector(
            key: const Key('playkit-random-deck'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            // ★ 甩出的那张在 build 里读 _out.value —— 没有 AnimatedBuilder
            //   就没人逐帧重建,牌原地静止到消失(parts 文件 ★ 警告过的死动画)。
            child: AnimatedBuilder(
              animation: _out,
              builder: (BuildContext context, Widget? child) =>
                  Stack(children: layered()),
            ),
          ),
        );
      },
    );
  }

  (int, Widget) _deckCard(
    PlayKitDeckCard card,
    int index,
    int pos,
    bool leaving,
  ) {
    // 位置 0 = 手里那张(可拖动);1 / 2 是后面露出的两张(真源 .dk__card--1/2)。
    double dx = 0;
    double dy = 0;
    double angle = -2.2;
    double scale = 1;
    double opacity = 1;
    int z = 30;
    if (pos == 1) {
      dx = 0.05;
      dy = -0.02;
      angle = 2;
      scale = 0.985;
      z = 20;
    } else if (pos == 2) {
      dx = 0.09;
      dy = -0.04;
      angle = 5.5;
      scale = 0.97;
      z = 10;
    }
    if (leaving) {
      final double t = _reduced ? 1 : Curves.easeIn.transform(_out.value);
      dx = -1.12 * t;
      dy = 0.04 * t;
      angle = -2.2 - 3.8 * t;
      opacity = 1 - t;
      z = 40;
      scale = 1;
    } else if (pos == 0 && _dragging) {
      // 跟手但**带阻尼**:滑满一张卡宽,卡只走 30%,同时下沉、倾角转正
      // (真源 onMove;一比一跟手的话卡会被拖到屏外,而它其实还没被甩掉)。
      final double t = (_deckWidth <= 0 ? 0 : _dx / _deckWidth)
          .clamp(-1.0, 1.0)
          .toDouble();
      dx = t * 0.30;
      dy = t.abs() * 0.02;
      angle = -2.2 + t * 7;
    }
    final Widget cardFace = _DeckCardFace(card: card, artSeed: index);
    final Widget face = Positioned.fill(
      child: FractionalTranslation(
        // 百分比位移按**自身尺寸**算 —— 真源里那几个 translate(5%, -2%) 同义。
        translation: Offset(dx, dy),
        child: Transform.rotate(
          angle: angle * math.pi / 180,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity.clamp(0, 1),
              child: Semantics(
                label: card.opened ? '${card.title}，已翻开' : '还没翻开的卡，翻开看这一关',
                child: cardFace,
              ),
            ),
          ),
        ),
      ),
    );
    return (z, face);
  }

  Widget _detailPanel(PlayKitDeckCard card) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: _kDeckPaper,
        borderRadius: BorderRadius.circular(CyTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 真源详情眉标 `.dk__pill`:浅灰底深灰字的小胶囊(10.5px/700),
          // 不是灰字一行 —— 此前注释把它归错到 play-surface 的 `--sub`,已改口。
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE0DEDE),
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              ),
              child: const Text(
                '这一关',
                style: TextStyle(
                  color: Color(0xFF3C4043),
                  fontSize: CyTokens.typeCaption,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              card.title,
              style: const TextStyle(
                color: _kDeckInk,
                fontSize: CyTokens.typePageTitle,
                fontWeight: FontWeight.w600,
                height: CyTokens.leadingTight,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: Text(
                card.body,
                style: const TextStyle(
                  color: _kDeckInk,
                  fontSize: CyTokens.typeBody,
                  height: CyTokens.leadingNormal,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: CyNativeButton(
              key: const Key('playkit-random-detail-back'),
              label: '回到牌堆',
              role: CyNativeButtonRole.secondary,
              width: double.infinity,
              onPressed: () => setState(() => _detail = null),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一张牌面:标签 + 标题 + 图案。盖着的牌写「?」—— 真标题服务端还没给。
class _DeckCardFace extends StatelessWidget {
  const _DeckCardFace({required this.card, required this.artSeed});

  final PlayKitDeckCard card;
  final int artSeed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kDeckPaper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33000000)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 真源 `.dk__tag`:蓝底白字的小胶囊贴在卡面左上,不是灰字眉标。
          // (9pt 低于字级下限,收 micro;线上分支的 tag 文案真源就是这两句。)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0B6ADC),
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            ),
            child: Text(
              card.opened ? '这一关' : '还没翻开',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: CyTokens.typeMicro,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kDeckInk,
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w600,
                height: CyTokens.leadingTight,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: CustomPaint(
                painter: _DeckArtPainter(seed: artSeed),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡面图案 —— 一张卡唯一的「脸」:四张摞在一起时,玩家靠它分辨新旧
/// (真源 `art.js` 原文)。按原型那扇「小窗 + 三个几何块」重绘,颜色按卡序轮转。
class _DeckArtPainter extends CustomPainter {
  const _DeckArtPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final Color a1 = _kDeckArt[seed % 4];
    final Color a2 = _kDeckArt[(seed + 1) % 4];
    final Color a3 = _kDeckArt[(seed + 2) % 4];
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = _kDeckInk;
    final double w = size.width;
    final double h = size.height;

    // 三个几何块(原型:左弧、上三角、下圆/方)
    final Path arc = Path()
      ..moveTo(w * 0.10, h * 0.12)
      ..arcToPoint(
        Offset(w * 0.10, h * 0.62),
        radius: Radius.circular(w * 0.25),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(arc, Paint()..color = a1);
    canvas.drawPath(arc, stroke);

    final Path triangle = Path()
      ..moveTo(w * 0.62, h * 0.08)
      ..lineTo(w * 0.92, h * 0.16)
      ..lineTo(w * 0.68, h * 0.40)
      ..close();
    canvas.drawPath(triangle, Paint()..color = a2);
    canvas.drawPath(triangle, stroke);

    // 「小窗」:白底 + 顶栏 + 三个点(原型 `win()`)
    final Rect win = Rect.fromLTWH(w * 0.16, h * 0.28, w * 0.52, h * 0.56);
    canvas.drawRRect(
      RRect.fromRectAndRadius(win.translate(2, 3), const Radius.circular(4)),
      Paint()..color = _kDeckInk,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, const Radius.circular(4)),
      Paint()..color = _kDeckPaper,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, const Radius.circular(4)),
      stroke,
    );
    canvas.drawLine(
      Offset(win.left, win.top + h * 0.07),
      Offset(win.right, win.top + h * 0.07),
      stroke,
    );
    canvas.drawCircle(
      Offset(win.left + w * 0.04, win.top + h * 0.035),
      2.2,
      Paint()..color = const Color(0xFFDD363C),
    );
    canvas.drawCircle(
      Offset(win.left + w * 0.08, win.top + h * 0.035),
      2.2,
      Paint()..color = const Color(0xFFF7B326),
    );
    canvas.drawCircle(
      Offset(win.left + w * 0.12, win.top + h * 0.035),
      2.2,
      Paint()..color = const Color(0xFF34A853),
    );
    canvas.drawCircle(
      Offset(win.center.dx, win.center.dy + h * 0.02),
      w * 0.07,
      Paint()..color = a2,
    );
    canvas.drawCircle(
      Offset(win.center.dx, win.center.dy + h * 0.02),
      w * 0.07,
      stroke,
    );

    // 左下角的圆(原型 `circle cx=58 cy=162 r=28`,填 a3)
    canvas.drawCircle(
      Offset(w * 0.20, h * 0.86),
      w * 0.13,
      Paint()..color = a3,
    );
    canvas.drawCircle(Offset(w * 0.20, h * 0.86), w * 0.13, stroke);

    // 右下角方块(原型 rotate(-8deg) 那块)
    canvas.save();
    canvas.translate(w * 0.78, h * 0.80);
    canvas.rotate(-8 * math.pi / 180);
    final Rect square = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.20,
      height: w * 0.20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(3)),
      Paint()..color = a1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(3)),
      stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DeckArtPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
