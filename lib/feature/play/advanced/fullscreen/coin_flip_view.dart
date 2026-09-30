import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_logic.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_fullscreen_sources.dart';

/// 抛硬币 · `cy-playkit-coinflip` 的 App 侧(结构 1:1 照搬小程序 index.wxml)。
///
/// ★ 结果由服务端定,转动只是把它演出来。组件里**没有任何随机数决定正反** ——
/// 圈数(6–8 圈)是装饰,落到哪一面由宿主回传的 [PlayKitCard.selectedKey]
/// (`HEADS`/`TAILS`)决定。后端 FLIP_COIN 幂等:重复提交返回第一次的结果。
///
/// ★ **绕横轴翻**(抛硬币本来就上下翻,绕竖轴那是转陀螺)。转动时长与动画
/// 时长由同一个常数 [_spinMs] 驱动 —— 小程序那边散在 JS 与 WXSS 两处,对不上
/// 就会「转完之前先报结果」或「转完了愣在那儿」,这里结构上不可能漂。
///
/// ★ 这一屏**一个按钮都没有**:摇一摇就抛,点屏幕是没有加速度计时的退路。
class PlayKitCoinFlipView extends StatefulWidget {
  const PlayKitCoinFlipView({
    super.key,
    required this.data,
    this.accelerationSource,
    this.random,
  });

  final PlayKitFullscreenContext data;

  /// 摇一摇来源。widget 测试注入假流;null = 真机加速度计。
  final PlayKitAccelerationSource? accelerationSource;

  /// 圈数采样(纯装饰)。测试注入固定种子。
  final math.Random? random;

  @override
  State<PlayKitCoinFlipView> createState() => _PlayKitCoinFlipViewState();
}

class _PlayKitCoinFlipViewState extends State<PlayKitCoinFlipView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// 与小程序 SPIN_MS 同一个数:转完才落面。
  /// 这是**一次玩的整段编排**,不在 CyMotion 五档里 —— 字面量登记在
  /// `test/theme/motion_ratchet_test.dart` 的白名单,改一边必须改另一边。
  static const Duration _spin = Duration(milliseconds: 2200);

  /// 停着时的慢慢自转(小程序 cf-spin 9s linear)。
  static const Duration _idleTurn = Duration(milliseconds: 9000);

  /// 356rpx → 178pt,原型 .cncoin 逐值。
  static const double _coinSize = 178;

  late final AnimationController _flip;
  late final AnimationController _idle;
  late final AnimationController _burst;
  final PlayKitShakeDetector _shakeDetector = PlayKitShakeDetector();
  StreamSubscription<PlayKitAcceleration>? _acceleration;
  Tween<double> _spinTween = Tween<double>(begin: 0, end: 0);
  int _turns = 0;
  double _angleDeg = 0;
  bool _flipping = false;
  bool _applied = false;
  String _settledFace = '';
  String _pendingFace = '';
  String _big = '正面还是反面?';
  String _lab = '';
  String _hint = '摇一摇手机';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flip = AnimationController(
      vsync: this,
      duration: _spin,
    )..addListener(_onFlipTick);
    _flip.addStatusListener(_onFlipStatus);
    _idle = AnimationController(
      vsync: this,
      duration: _idleTurn,
    )..addListener(() {
        if (!_flipping) setState(() => _angleDeg = _idleAngleDeg);
      });
    _burst = AnimationController(
      vsync: this,
      duration: CyMotion.slow,
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) _burst.reset();
      });
    _listenAcceleration();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ★ 首次落面必须等这一刻:MediaQuery(减动效开关)在 initState 里读不到,
    //   读早了会直接踩框架的断言 —— 而且这条在真机上不报错,只在测试里红。
    if (!_applied) {
      _applied = true;
      _maybeFlip(normalizeCoinFace(widget.data.card.selectedKey));
    }
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _idle.stop();
    } else if (!_idle.isAnimating && _settledFace.isEmpty && !_flipping) {
      _idle.repeat();
    }
  }

  @override
  void didUpdateWidget(PlayKitCoinFlipView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String face = normalizeCoinFace(widget.data.card.selectedKey);
    if (face != normalizeCoinFace(oldWidget.data.card.selectedKey)) {
      _maybeFlip(face);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 传感器要跟着显隐开关:一直开着的话玩家退出这一关之后走两步还在抛。
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopAcceleration();
    } else if (state == AppLifecycleState.resumed &&
        _acceleration == null &&
        _settledFace.isEmpty) {
      _listenAcceleration();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAcceleration();
    _flip.dispose();
    _idle.dispose();
    _burst.dispose();
    super.dispose();
  }

  double get _idleAngleDeg => _idle.value * 360;

  void _listenAcceleration() {
    if (_acceleration != null) return;
    final PlayKitAccelerationSource source =
        widget.accelerationSource ?? const PlayKitDeviceAccelerationSource();
    _acceleration = source.watch().listen(
      (PlayKitAcceleration event) {
        final bool shaken = _shakeDetector.feed(
          x: event.x,
          y: event.y,
          z: event.z,
          atMs: event.at.inMilliseconds,
        );
        if (shaken) _onFlip();
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  void _stopAcceleration() {
    unawaited(_acceleration?.cancel());
    _acceleration = null;
  }

  /// 服务端给了面就演:圈数每次不同,不然第二次看就知道要转几圈了。
  void _maybeFlip(String face) {
    if (face.isEmpty) {
      _settledFace = '';
      _pendingFace = '';
      _angleDeg = 0;
      if (!MediaQuery.disableAnimationsOf(context) && !_idle.isAnimating) {
        _idle.repeat();
      }
      setState(() {
        _big = '正面还是反面?';
        _lab = _bothSidesLabel;
        _hint = '摇一摇手机';
      });
      return;
    }
    if (face == _settledFace || face == _pendingFace) return;
    _pendingFace = face;
    final math.Random random = widget.random ?? math.Random();
    _turns = nextCoinTurns(_turns, random.nextInt(3));
    final double target = coinSpinDegrees(_turns, face).toDouble();
    _idle.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _angleDeg = target);
      _settle(face);
      return;
    }
    _spinTween = Tween<double>(begin: _angleDeg, end: target);
    setState(() {
      _flipping = true;
      _big = '翻着…';
      _lab = '';
    });
    _flip.forward(from: 0);
  }

  void _onFlipTick() {
    if (!_flipping) return;
    setState(() => _angleDeg = _spinTween.transform(_flip.value));
  }

  void _onFlipStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _flipping) {
      _settle(_pendingFace);
    }
  }

  void _settle(String face) {
    final String action = _actionOf(face);
    setState(() {
      _flipping = false;
      _settledFace = face;
      _pendingFace = '';
      _big = face == kCoinHeads ? _headsLabel : _tailsLabel;
      _lab = action;
      _hint = '再摇一次';
    });
    // 「做成了」落在结果落面这一刻,不在点「抛」那一下 —— 点下去只是请求发出。
    playKitHaptic(context, PlayKitHaptic.medium);
    if (!MediaQuery.disableAnimationsOf(context)) {
      _burst.forward(from: 0);
    }
  }

  void _onFlip() {
    if (_settledFace.isNotEmpty || _flipping) return;
    if (!widget.data.enabled || widget.data.acting) return;
    playKitHaptic(context, PlayKitHaptic.light);
    widget.data.onAction?.call(
      PlayKitAction(
        label: '抛一次',
        action: 'FLIP_COIN',
        payload: const <String, Object?>{},
      ),
    );
  }

  List<PlayKitAction> get _sides => widget.data.card.choices;

  String get _headsLabel =>
      _sides.isNotEmpty && _sides.first.label.isNotEmpty ? _sides.first.label : '正面';

  String get _tailsLabel => _sides.length > 1 && _sides[1].label.isNotEmpty
      ? _sides[1].label
      : '反面';

  String _actionOf(String face) {
    final PlayKitAction? side = _sideOf(face);
    return side == null ? '' : '${side.payload['do'] ?? ''}';
  }

  PlayKitAction? _sideOf(String face) {
    if (_sides.isEmpty) return null;
    if (face == kCoinHeads) return _sides.first;
    return _sides.length > 1 ? _sides[1] : null;
  }

  String get _bothSidesLabel {
    final String heads = _actionOf(kCoinHeads);
    final String tails = _actionOf(kCoinTails);
    return '$_headsLabel · $heads\n$_tailsLabel · $tails';
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: '摇一摇手机，或点屏幕抛一次',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onFlip,
          child: Container(
            color: CyTokens.bgPage,
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    PlayKitKicker(
                      widget.data.card.eyebrow.isEmpty
                          ? '抛一次，认结果'
                          : widget.data.card.eyebrow,
                      color: CyTokens.textPrimary,
                    ),
                    const SizedBox(height: CyTokens.space5),
                    SizedBox(
                      height: 230,
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            _burstRing(),
                            _coin(reduceMotion),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: CyTokens.space5),
                    Text(
                      _big,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CyTokens.textPrimary,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    if (_lab.isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        _lab,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: CyTokens.textPrimary.withValues(alpha: 0.66),
                          fontSize: CyType.subhead.fontSize,
                          height: 1.8,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                    const SizedBox(height: CyTokens.space5),
                    PlayKitShakeHintRow(
                      text: _hint,
                      color: CyTokens.textPrimary.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 落面那一拍的确认环。★ 必须走 AnimatedBuilder:控制器**没有任何 listener**,
  /// 只在 build 里读 `_burst.value` 的话环会冻在第一帧(不透明度 0.5 常驻),
  /// 而它恰恰是「这一下成了」的唯一视觉反馈。
  Widget _burstRing() {
    return AnimatedBuilder(
      animation: _burst,
      builder: (BuildContext context, Widget? child) {
        // 0 = 还没触发,1 = 播完(状态监听会立刻 reset 回 0):两头都不画。
        if (_burst.value <= 0 || _burst.value >= 1) {
          return const SizedBox.shrink();
        }
        return Opacity(
          opacity: (1 - _burst.value) * 0.5,
          child: Transform.scale(scale: 1 + _burst.value * 0.22, child: child),
        );
      },
      child: Container(
        width: _coinSize,
        height: _coinSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: CyTokens.textPrimary, width: 2),
        ),
      ),
    );
  }

  Widget _coin(bool reduceMotion) {
    final double angleRad = _angleDeg * math.pi / 180;
    final int mod = ((_angleDeg % 360) + 360).toInt() % 360;
    final bool headsUp = mod <= 90 || mod >= 270;
    final Widget face = _CoinFaceWidget(
      heads: headsUp,
      headsLabel: _headsLabel,
      headsAction: _actionOf(kCoinHeads),
      tailsLabel: _tailsLabel,
      tailsAction: _actionOf(kCoinTails),
    );
    return Transform(
      alignment: Alignment.center,
      // 真源 `cf-spin` 全程带固定 rotateY(-9deg) 倾角 —— 正对着看是个平圆,
      // 晃不出「它有两面」。落定/翻转态真源只写 rotateX(js `coinStyle`),
      // 所以倾角只属于停着自转这一段。
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.00083) // perspective: 2400rpx ≈ 1200pt
        ..rotateY(_idle.isAnimating ? -9 * math.pi / 180 : 0)
        ..rotateX(angleRad),
      child: SizedBox(
        width: _coinSize,
        height: _coinSize,
        child: headsUp
            ? face
            : Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationX(math.pi),
                child: face,
              ),
      ),
    );
  }
}

/// 一枚硬币的正面 / 背面。正反都是同一层 SVG 的读法:
/// 抬起的外圈、数据环、四个方位菱形;正面多一个中间浮雕 + 两条弧字,
/// 背面是中央一块二维码(种子写死 —— 每次翻面图案都一样才是同一枚币)。
class _CoinFaceWidget extends StatelessWidget {
  const _CoinFaceWidget({
    required this.heads,
    required this.headsLabel,
    required this.headsAction,
    required this.tailsLabel,
    required this.tailsAction,
  });

  final bool heads;
  final String headsLabel;
  final String headsAction;
  final String tailsLabel;
  final String tailsAction;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CoinFacePainter(heads: heads),
      child: heads
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Transform.translate(
                  offset: const Offset(0, -52),
                  child: Text(
                    headsLabel,
                    style: _engraved,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, 52),
                  child: Text(
                    headsAction,
                    textAlign: TextAlign.center,
                    style: _engraved,
                  ),
                ),
              ],
            )
          : null,
    );
  }

  TextStyle get _engraved => TextStyle(
    color: const Color(0xBF9299A3),
    fontSize: CyType.caption1.fontSize,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
}

class _CoinFacePainter extends CustomPainter {
  const _CoinFacePainter({required this.heads});

  final bool heads;

  // 小程序 .cnface 的三层读法:conic 明暗交替(车出来的齿)+ 一处主光斑
  // + 边缘往里压暗。只有一个高光看着像塑料 —— 塑料才只有一个高光。
  static const List<Color> _metal = <Color>[
    Color(0xFFB4BAC3),
    Color(0xFFEEF1F4),
    Color(0xFF949BA6),
    Color(0xFFDADEE4),
    Color(0xFF8B929D),
    Color(0xFFE6E9EE),
    Color(0xFF8F96A1),
    Color(0xFFDFE3E8),
    Color(0xFFB4BAC3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    final Rect rect = Offset.zero & size;
    // 200 视框 → 实际尺寸的比例,faces.js 的值逐条按它折。
    final double u = size.shortestSide / 200;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          startAngle: 208 * math.pi / 180,
          endAngle: 208 * math.pi / 180 + 2 * math.pi,
          colors: _metal,
          stops: <double>[0, 0.094, 0.211, 0.344, 0.461, 0.583, 0.717, 0.85, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.5),
          radius: 0.56,
          colors: <Color>[
            const Color(0xFFFFFFFF).withValues(alpha: 0.8),
            const Color(0xFFFFFFFF).withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0x2B12161C),
            const Color(0x0012161C),
            const Color(0x6B12161C),
          ],
          stops: const <double>[0, 0.72, 1],
        ).createShader(rect),
    );

    // 滚花:转到侧面能看见一圈密齿,所以侧壁得真做出来。
    final Paint knurl = Paint()..style = PaintingStyle.stroke;
    for (int i = 0; i < 60; i++) {
      final double angle = i * math.pi * 2 / 60;
      knurl
        ..strokeWidth = 0.9 * u
        ..color = (i.isEven
            ? const Color(0x59FFFFFF)
            : const Color(0x59000000));
      canvas.drawLine(
        center +
            Offset(math.cos(angle), math.sin(angle)) * radius * 0.94,
        center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.99,
        knurl,
      );
    }

    // 内圈刻线(emb():同一形状画三遍 —— 暗的往右下、亮的往左上、中间本体)。
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * u;
    for (final double r in <double>[93, 88, 74, 63]) {
      _embossedCircle(canvas, center, r * u, line);
    }
    // 数据环:长短不一的短块绕一圈,读起来像一串二进制,不是一圈均匀虚线。
    _dashedRing(canvas, center, 80.5 * u, 5.2 * u, const <int>[7, 3, 3, 2, 10, 4, 3, 6, 4, 2]);
    _dashedRing(canvas, center, 69 * u, 3.4 * u, const <int>[3, 2, 8, 3, 2, 5, 4, 2, 3]);

    if (heads) {
      _logoRelief(canvas, size, u);
    } else {
      _qrFace(canvas, size, u);
    }
  }

  void _embossedCircle(Canvas canvas, Offset center, double radius, Paint base) {
    for (final (Offset shift, Color color) in <(Offset, Color)>[
      (const Offset(0.7, 0.7), const Color(0x9E262B32)),
      (const Offset(-0.7, -0.7), const Color(0x85FFFFFF)),
      (Offset.zero, const Color(0xE69299A3)),
    ]) {
      canvas.drawCircle(
        center + shift,
        radius,
        base..color = color,
      );
    }
  }

  /// 长短相间的短块串成一环。
  void _dashedRing(
    Canvas canvas,
    Offset center,
    double radius,
    double width,
    List<int> pattern,
  ) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = const Color(0xE69299A3);
    double angle = 0;
    int index = 0;
    while (angle < math.pi * 2) {
      final double step =
          pattern[index % pattern.length] * 0.0175; // ≈1° 一片
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        step * 0.62,
        false,
        paint,
      );
      angle += step;
      index++;
    }
  }

  /// 中央浮雕:同一形状画三遍(暗 / 亮 / 本体),只画一层是平的。
  void _logoRelief(Canvas canvas, Size size, double u) {
    const List<(Offset, Color)> passes = <(Offset, Color)>[
      (Offset(1.1, 1.1), Color(0x99262B32)),
      (Offset(-1.1, -1.1), Color(0x8CFFFFFF)),
      (Offset.zero, Color(0xF2A6ADB7)),
    ];
    for (final (Offset shift, Color color) in passes) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: '城',
          style: TextStyle(
            color: color,
            fontSize: 76 * u,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        size.center(Offset.zero) -
            Offset(painter.width / 2, painter.height / 2) +
            shift,
      );
    }
  }

  /// 背面:中央一块二维码。种子写死,每次生成同一张。
  void _qrFace(Canvas canvas, Size size, double u) {
    const int n = 13;
    const double cell = 4.6;
    final double x0 = 100 - n * cell / 2;
    final List<List<bool>> matrix = List<List<bool>>.generate(
      n,
      (_) => List<bool>.filled(n, false),
    );
    void mark(int r0, int c0) {
      for (int i = 0; i < 7; i++) {
        for (int j = 0; j < 7; j++) {
          matrix[r0 + i][c0 + j] =
              i == 0 ||
              i == 6 ||
              j == 0 ||
              j == 6 ||
              (i >= 2 && i <= 4 && j >= 2 && j <= 4);
        }
      }
    }

    mark(0, 0);
    mark(0, n - 7);
    mark(n - 7, 0);
    int seed = 20260909;
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if ((r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7)) {
          continue;
        }
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        matrix[r][c] = ((seed >> 16) & 0xFF) % 100 < 46;
      }
    }
    final Paint cellPaint = Paint()..color = const Color(0xCC5A616B);
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (!matrix[r][c]) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (x0 + c * cell) * u,
            (x0 + r * cell) * u,
            cell * u,
            cell * u,
          ),
          cellPaint,
        );
      }
    }
    final Paint frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * u
      ..color = const Color(0xE69299A3);
    canvas.drawRect(
      Rect.fromLTWH(
        (x0 - 5) * u,
        (x0 - 5) * u,
        (n * cell + 10) * u,
        (n * cell + 10) * u,
      ),
      frame,
    );
  }

  @override
  bool shouldRepaint(_CoinFacePainter oldDelegate) => oldDelegate.heads != heads;
}
