import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// `cy-playkit-countdown` · 倒计时 · 一钟油。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-countdown/`。
/// 结构 1:1 —— 它**不附加玩法**:没有对错、没有次数、没有限时开关,它就是倒计时本身,
/// 到点只是把商家写的那句话亮出来。所以这屏上没有判定,只有一个数。
///
/// ## 结果由服务端定
/// 后端 `SUBMIT_COUNTDOWN` **不接受客户端报的数字,一个都不收**:到没到点由服务端
/// 拿 `START_CHALLENGE` 记的服务器时间戳算。这里报的只是「我这边走完了」。
/// 组件里的 `Date.now()` 只驱动**读数与油面**,不参与判定 —— 设备时钟玩家改得动。
///
/// ## 两个不能省的细节
/// 1. **每拍重新对时,不做 `seconds--` 累加**:小程序切后台定时器会被限频甚至停掉,
///    累加法回来会少算 —— 那等于白送时间。
/// 2. **到点那一下要有触感**(真源 `motion.haptic({type:'medium'})`)。
///    但 `motion.haptic` 在 `reducedMotion` 时直接 `return false` —— 触感也是动效,
///    减动效用户一并关掉。App 侧照做(这条有测试钉着)。
///
/// ## 与真源的已知差异(§7.2 accepted,「iOS 27 原生化」)
/// * 真源用 `mix-blend-mode: difference` 让文字「露在白底上算黑、泡在油里翻白」;
///   Flutter 侧等价做法是同一份文字画两层、第二层用**油面轮廓**裁剪成反色。
///   分界线因此是油面那条波形本身,不是一条水平线 —— 观感一致。
/// * 字重 900 → w700(T3:中文大字号堆到 900 会糊成一块黑),字号按原型 88pt 保留。
/// * 退出按钮由**宿主**提供:整屏缝的 `PlayKitFullscreenContext` 里没有 close 回调,
///   台面 chrome(退出/限时条/判定屏)是宿主的活,不在玩法组件里抢一份。
class PlayKitCountdownView extends StatefulWidget {
  const PlayKitCountdownView({super.key, required this.data, this.now});

  final PlayKitFullscreenContext data;

  /// 注入时钟,测试用。生产路径就是 `DateTime.now`。
  final DateTime Function()? now;

  @override
  State<PlayKitCountdownView> createState() => _PlayKitCountdownViewState();
}

/// 原型私有色(小程序 `playkit-countdown/index.wxss` 的 `#fff` / `#0B0B0C`)。
///
/// 为什么不用 `CyPalette`:这一屏**恒为浅色**(白底一钟油),而玩家域是恒暗 ——
/// 跟随主题会把白底翻黑,油里那半截白字当场看不见。同类先例:
/// `merchant_ai_insight_page` 的页面私有色逐项保持小程序真源。
const Color _kCountdownSurface = Color(0xFFFFFFFF);
const Color _kCountdownInk = Color(0xFF0B0B0C);

/// 原型 176rpx = 88pt。不在 iOS 梯级上(梯级最大 34):整屏计时数字是道具,
/// 与 `CyTokens.stillnessTimerType = 80` 同类。
const double _kCountdownFigureSize = 88;

/// 到点那句提示的宽度上限:真源左右各留 26px,长句自动折行。
const double _kCountdownDoneWidth = 260;

const PlayKitAction _kCountdownStart = PlayKitAction(
  label: '开始倒计时',
  action: 'START_CHALLENGE',
  payload: <String, Object?>{'game': 'countdown'},
);

/// 到点:结果服务端算,客户端**不带参数**(真源 `serverPayload` 的
/// `countdown:finish` 返回 `{}`)。
const PlayKitAction _kCountdownFinish = PlayKitAction(
  label: '倒计时到点',
  action: 'SUBMIT_COUNTDOWN',
);

class _PlayKitCountdownViewState extends State<PlayKitCountdownView>
    with TickerProviderStateMixin {
  Timer? _ticker;
  DateTime? _startedAt;
  int _elapsedMs = 0;
  bool _running = false;
  bool _finished = false;

  /// 油面波形两条:速度不同。同速的话整块像一个刚体在晃,不像液体。
  late final AnimationController _waveA;
  late final AnimationController _waveB;
  late final Listenable _waves;

  DateTime get _now => (widget.now ?? DateTime.now)();

  int get _totalSeconds {
    final int seconds = widget.data.card.durationSeconds;
    return seconds > 0 ? seconds : 0;
  }

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _waveA = AnimationController(vsync: this, duration: kCountdownWaveA);
    _waveB = AnimationController(
      vsync: this,
      duration: kCountdownWaveB,
      value: 0.5,
    );
    _waves = Listenable.merge(<Listenable>[_waveA, _waveB]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWaveRun());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWaveRun();
  }

  @override
  void didUpdateWidget(covariant PlayKitCountdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final PlayKitCard card = widget.data.card;
    final PlayKitCard previous = oldWidget.data.card;
    // 真源 observer 的 'show, seconds':换了一段(或换了时长)就整个重来
    if (card.kind != previous.kind ||
        card.durationSeconds != previous.durationSeconds) {
      _reset();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _waveA.dispose();
    _waveB.dispose();
    super.dispose();
  }

  /// 减动效:波形不转(`.oc--reduced .oc__wv { animation: none; }`)。
  void _syncWaveRun() {
    if (!mounted) return;
    if (_reduced) {
      _waveA.stop();
      _waveB.stop();
      return;
    }
    if (!_waveA.isAnimating) _waveA.repeat();
    if (!_waveB.isAnimating) _waveB.repeat(reverse: true);
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    _elapsedMs = 0;
    _running = false;
    _finished = false;
  }

  void _start() {
    if (_running) return;
    setState(() {
      _startedAt = _now;
      _elapsedMs = 0;
      _running = true;
      _finished = false;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(kCountdownTickInterval, (_) => _tick());
    widget.data.onAction?.call(_kCountdownStart);
  }

  void _tick() {
    final DateTime? startedAt = _startedAt;
    if (startedAt == null) return;
    // 每拍对时,不累加
    final int elapsed = _now.difference(startedAt).inMilliseconds;
    final int left = countdownRemainSeconds(elapsed, _totalSeconds);
    if (left > 0) {
      setState(() => _elapsedMs = elapsed);
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _elapsedMs = elapsed;
      _running = false;
      _finished = true;
    });
    // 「做成了」= 到点那一下。倒计时的全部意义就在这一刻。
    // 减动效下不震(真源 motion.haptic 在 reducedMotion 时 return false)。
    if (!_reduced) {
      unawaited(HapticFeedback.mediumImpact());
    }
    widget.data.onAction?.call(_kCountdownFinish);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = _reduced;
    final PlayKitCard card = widget.data.card;
    final int total = _totalSeconds;
    final int shown = _running || _finished
        ? countdownRemainSeconds(_elapsedMs, total)
        : total;
    final double oilTarget = countdownOilFraction(_elapsedMs, total);
    final String kicker = card.eyebrow.isEmpty ? '倒计时' : card.eyebrow;
    final String doneText = card.hint;
    final bool canPress = widget.data.enabled && !widget.data.acting;
    final String label = _running ? '走着呢' : (_finished ? '再来一次' : '开始');

    return PlayKitStageSurface(
      background: _kCountdownSurface,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double height = constraints.maxHeight;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: oilTarget, end: oilTarget),
            duration: reduced ? Duration.zero : kCountdownOilStep,
            curve: Curves.linear,
            builder: (BuildContext context, double oil, Widget? _) {
              return AnimatedBuilder(
                animation: _waves,
                builder: (BuildContext context, Widget? _) {
                  final double oilTop = height * oil;
                  final Path oilPath = countdownOilSurfacePath(
                    width: constraints.maxWidth,
                    top: oilTop,
                    height: height,
                    phaseA: _waveA.value,
                    phaseB: _waveB.value,
                  );
                  final Widget copy = _CountdownCopy(
                    kicker: kicker,
                    clock: formatPlayClock(shown),
                    doneText: _finished ? doneText : '',
                    color: _kCountdownInk,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      const ColoredBox(color: _kCountdownSurface),
                      // 油
                      CustomPaint(painter: _OilPainter(path: oilPath)),
                      // 文字两层:墨色一层(白底上读到黑),
                      // 油面轮廓里再画一层白(泡在油里自动翻白)。
                      ClipRect(
                        clipper: _StraightClipper(top: oilTop),
                        child: copy,
                      ),
                      // 油面里那层是**纯装饰副本**:同一份文字画第二遍而已。
                      // 不排掉语义的话读屏会把读数、眉标、注解各念两遍。
                      ClipPath(
                        clipper: _PathClipper(path: oilPath),
                        child: ExcludeSemantics(
                          child: _CountdownCopy(
                            kicker: kicker,
                            clock: formatPlayClock(shown),
                            doneText: _finished ? doneText : '',
                            color: _kCountdownSurface,
                          ),
                        ),
                      ),
                      Positioned(
                        left: CyTokens.space4,
                        right: CyTokens.space4,
                        bottom: CyTokens.space6,
                        child: PlayKitSolidAction(
                          label: label,
                          background: _kCountdownSurface,
                          foreground: _kCountdownInk,
                          border: _kCountdownInk,
                          busy: _running || !canPress,
                          onPressed: _running ? null : _start,
                          semanticsLabel: _running ? '倒计时进行中' : '开始倒计时',
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// 眉标 + 大数字 + 到点那句注解。画两层用同一个 `color` 参数换色。
class _CountdownCopy extends StatelessWidget {
  const _CountdownCopy({
    required this.kicker,
    required this.clock,
    required this.doneText,
    required this.color,
  });

  final String kicker;
  final String clock;
  final String doneText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space8),
          child: Align(
            alignment: Alignment.topCenter,
            child: PlayKitEyebrow(kicker, color: color),
          ),
        ),
        Center(
          child: PlayKitBigFigure(
            text: clock,
            size: _kCountdownFigureSize,
            color: color,
            semanticsLabel: '剩余 $clock',
          ),
        ),
        if (doneText.isNotEmpty)
          Align(
            alignment: const Alignment(0, 0.55),
            child: SizedBox(
              width: _kCountdownDoneWidth,
              child: Text(
                doneText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: CyTokens.typeBody,
                  height: CyTokens.leadingLoose,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OilPainter extends CustomPainter {
  const _OilPainter({required this.path});

  final Path path;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _kCountdownInk
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_OilPainter oldDelegate) => oldDelegate.path != path;
}

/// 油面轮廓:上边界是**两条错速波叠出来的那条线**,往下填满。
///
/// 提成公开纯函数是为了文字层能用**同一条路径**裁剪 —— 两层各画各的,
/// 分界处会露一条缝(一条细线里文字一半黑一半白,放大看像印刷错位)。
Path countdownOilSurfacePath({
  required double width,
  required double top,
  required double height,
  required double phaseA,
  required double phaseB,
}) {
  final double bottom = math.max(top, height);
  final Path path = Path();
  if (width <= 0) return path..addRect(Rect.fromLTRB(0, top, 0, bottom));
  const int samples = 48;
  for (int i = 0; i <= samples; i++) {
    final double x = width * i / samples;
    final double y = math.min(
      top,
      math.min(
        _waveY(x, width, top, amplitude: 9, cycles: 4, phase: phaseA),
        _waveY(x, width, top + 5, amplitude: 6, cycles: 7, phase: phaseB),
      ),
    );
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path
    ..lineTo(width, bottom)
    ..lineTo(0, bottom)
    ..close();
  return path;
}

double _waveY(
  double x,
  double width,
  double baseline, {
  required double amplitude,
  required double cycles,
  required double phase,
}) {
  return baseline +
      amplitude * math.sin((x / width * cycles + phase) * 2 * math.pi);
}

/// 裁到 `y < top`(白底那一段)。
class _StraightClipper extends CustomClipper<Rect> {
  const _StraightClipper({required this.top});

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, math.max(0, top));

  @override
  bool shouldReclip(_StraightClipper oldClipper) => oldClipper.top != top;
}

/// 按任意路径裁剪(油面那一段)。
class _PathClipper extends CustomClipper<Path> {
  const _PathClipper({required this.path});

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClipper oldClipper) => oldClipper.path != path;
}
