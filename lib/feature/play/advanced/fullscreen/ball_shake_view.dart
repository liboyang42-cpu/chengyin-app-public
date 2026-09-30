import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_logic.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_fullscreen_sources.dart';

/// 弹球 · `cy-playkit-ballshake` 的 App 侧(结构 1:1 照搬小程序 index.wxml)。
///
/// 三条设计决定照原型(小程序 index.js 头部原文):
/// · **不画内框** —— 墙就是手机的四条边。多一个框,人会以为框外还有别的东西;
/// · **不给默认重力** —— 球只跟着倾斜走。手机平放它也一直在弹的话,玩家会以为
///   这屏在自己动,而不是自己在控制它;
/// · **球很轻** —— 重力只有普通的三分之一、阻尼几乎不给。沉的球会滚到底边
///   来回蹭,弹不起来就没得玩。
///
/// ★ 零点必须校准:人举着手机是三十几度不是平的。开跑后第一帧三轴读数记成
/// 「水平」,之后只按相对偏移给力 —— 不然一撒手球就一直往下滚。
///
/// ★ 撞击数报服务端复核:后端按 MAX_SHAKE_HITS_PER_SECOND(12)× 真实经过时间
/// 算上限,超了就是伪造。设备能谎报次数,谎报不了时间 —— 所以**开跑先发
/// START_CHALLENGE**,服务端拿那一刻的服务器时间当起点。
class PlayKitBallShakeView extends StatefulWidget {
  const PlayKitBallShakeView({
    super.key,
    required this.data,
    this.accelerationSource,
    this.random,
  });

  final PlayKitFullscreenContext data;

  /// 倾斜来源。widget 测试注入假流;null = 真机加速度计。
  final PlayKitAccelerationSource? accelerationSource;

  /// 反弹抖动采样(纯装饰:不加随机球会卡进一条来回直线)。
  final math.Random? random;

  @override
  State<PlayKitBallShakeView> createState() => _PlayKitBallShakeViewState();
}

/// idle | calibrating | counting | running | done。
enum _BallPhase { idle, calibrating, counting, running, done }

class _PlayKitBallShakeViewState extends State<PlayKitBallShakeView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// 物理步长,与小程序 `STEP_MS` 同值(定步长 = 采样节拍,不是过渡;
  /// 字面量登记在 motion_ratchet 白名单)。
  static const Duration _stepSpan = Duration(milliseconds: 16);

  /// 球半径 26rpx。按 **750rpx = 屏宽** 折算,不是写死 13pt ——
  /// 判定就是「球撞到边几次」,球的大小直接改变难度,窄屏偏大宽屏偏小都不行。
  static const double _ballRpx = 26;

  /// 撞边闪光 420ms(原型 `bl-edge` 动画同值)。
  static const Duration _edgeFlash = Duration(milliseconds: 420);

  /// 校准 1200ms(原型台面 `calibrate-ms`)。
  static const Duration _calibrateSpan = Duration(milliseconds: 1200);

  /// 3-2-1 每一拍 620ms(原型 `cy-play-countin` 的 TICK_MS)。
  static const Duration _countinTick = Duration(milliseconds: 620);
  static const int _countFrom = 3;

  /// 限时条读数刷新节拍,不是过渡。
  static const Duration _limitTickSpan = Duration(milliseconds: 1000);

  static const Color _field = Color(0xFF0A0A0B);

  /// 台面遮罩:原型 `--cy-color-play-scrim` 的兜底值 rgba(8,8,10,.78)。
  /// 校准与 3-2-1 都压在这一层上 —— 是遮罩不是独立一屏,底下还看得见场地。
  static const Color _scrim = Color(0xC708080A);

  late final AnimationController _flash;
  late final AnimationController _calibrate;
  StreamSubscription<PlayKitAcceleration>? _acceleration;
  Timer? _physics;
  Timer? _deadline;
  Timer? _limitTick;
  Timer? _countinTimer;

  _BallPhase _phase = _BallPhase.idle;
  Size _fieldSize = Size.zero;
  double _radius = 13;
  double _x = 0;
  double _y = 0;
  double _vx = 0;
  double _vy = 0;
  double _gx = 0;
  double _gy = 0;
  double? _zeroX;
  double? _zeroY;
  int _hits = 0;
  int _countin = _countFrom;
  int _limitLeft = 0;
  final List<Offset> _trail = <Offset>[];
  String _flashEdge = '';
  String _result = '';
  bool _submitted = false;

  int get _goal {
    final int goal = widget.data.card.maxLength ?? 0;
    return goal > 0 ? goal : 30;
  }

  /// 限时时长。原型 `limit-seconds="{{timed ? seconds : 0}}"` 的等价折叠:
  /// 真正进判定的永远是「有效限时」,0 = 不限时(也就没有 3-2-1)。
  int get _limitSeconds =>
      widget.data.card.durationSeconds > 0 ? widget.data.card.durationSeconds : 0;

  String get _kicker => widget.data.card.eyebrow.isEmpty
      ? '撞够 $_goal 次'
      : widget.data.card.eyebrow;

  String get _sub =>
      _limitSeconds > 0 ? '$_limitSeconds 秒内撞满' : '不限时，撞满为止';

  math.Random get _random => widget.random ?? math.Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flash = AnimationController(
      vsync: this,
      duration: _edgeFlash,
    );
    _calibrate = AnimationController(
      vsync: this,
      duration: _calibrateSpan,
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) _afterCalibrate();
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台就停:回来时球还在原地,但这段时间没人在玩,继续跑等于白送时间。
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_phase == _BallPhase.running || _phase == _BallPhase.calibrating ||
          _phase == _BallPhase.counting) {
        _abort();
      } else {
        _stopAll();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAll();
    _flash.dispose();
    _calibrate.dispose();
    super.dispose();
  }

  void _abort() {
    _stopAll();
    setState(() {
      _phase = _BallPhase.idle;
      _result = '刚才切走了，这一局不算';
      _hits = 0;
      _trail.clear();
      _flashEdge = '';
    });
  }

  void _stopAll() {
    _stopPhysics();
    _stopDeadline();
    _stopCountin();
    _stopAcceleration();
    _calibrate.stop();
  }

  void _stopPhysics() {
    _physics?.cancel();
    _physics = null;
  }

  void _stopCountin() {
    _countinTimer?.cancel();
    _countinTimer = null;
  }

  void _stopDeadline() {
    _deadline?.cancel();
    _deadline = null;
    _limitTick?.cancel();
    _limitTick = null;
  }

  void _stopAcceleration() {
    unawaited(_acceleration?.cancel());
    _acceleration = null;
  }

  void _listenAcceleration() {
    if (_acceleration != null) return;
    final PlayKitAccelerationSource source =
        widget.accelerationSource ?? const PlayKitDeviceAccelerationSource();
    _acceleration = source.watch().listen(
      (PlayKitAcceleration event) {
        if (_phase != _BallPhase.running) return;
        final double? zeroX = _zeroX;
        final double? zeroY = _zeroY;
        if (zeroX == null || zeroY == null) {
          // 零点 = 开跑后第一帧。之后只按相对偏移给力(见类注释)。
          _zeroX = event.x;
          _zeroY = event.y;
          return;
        }
        final BallShakeTilt tilt = ballShakeTiltOf(
          x: event.x,
          y: event.y,
          zeroX: zeroX,
          zeroY: zeroY,
        );
        _gx = tilt.gx;
        _gy = tilt.gy;
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  void _begin() {
    if (_phase == _BallPhase.calibrating ||
        _phase == _BallPhase.counting ||
        _phase == _BallPhase.running) {
      return;
    }
    if (!widget.data.enabled || widget.data.acting) return;
    playKitHaptic(context, PlayKitHaptic.light);
    setState(() {
      _phase = _BallPhase.calibrating;
      _hits = 0;
      _trail.clear();
      _flashEdge = '';
      _result = '';
    });
    _calibrate.forward(from: 0);
  }

  void _afterCalibrate() {
    if (!mounted) return;
    // 3-2-1 给限时的那些:计时从看到题那一刻起跳的话,人还在读题就在扣秒。
    // 减动效:不数了,直接开始 —— 数字跳动本身就是动效。
    if (_limitSeconds > 0 && !MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _phase = _BallPhase.counting;
        _countin = _countFrom;
      });
      _stopCountin();
      _countinTimer = Timer.periodic(
        _countinTick,
        (Timer timer) {
          final int next = _countin - 1;
          if (next > 0) {
            setState(() => _countin = next);
            return;
          }
          timer.cancel();
          _countinTimer = null;
          _run();
        },
      );
      return;
    }
    _run();
  }

  void _run() {
    if (!mounted) return;
    _stopAcceleration();
    _zeroX = null;
    _zeroY = null;
    _x = _fieldSize.width / 2;
    _y = _fieldSize.height * 0.35;
    _vx = 0;
    _vy = 0;
    _gx = 0;
    _gy = 0;
    _submitted = false;
    setState(() {
      _phase = _BallPhase.running;
      _hits = 0;
      _limitLeft = _limitSeconds;
      _trail.clear();
      _flashEdge = '';
      _result = '';
    });
    // 开表要给服务端:成绩按服务器时间复核,不先开表提交会被判成「还没开始」。
    // 设备时钟玩家改得动,所以这一条不能省。
    widget.data.onAction?.call(
      const PlayKitAction(
        label: '开始挑战',
        action: 'START_CHALLENGE',
        payload: <String, Object?>{'game': 'ballShake'},
      ),
    );
    _listenAcceleration();
    _stopPhysics();
    _physics = Timer.periodic(
      _stepSpan,
      (Timer _) => _step(),
    );
    if (_limitSeconds > 0) {
      _stopDeadline();
      // 截止时刻钉死,不靠逐拍刷新:切后台被限频时逐拍会永远不超时。
      _deadline = Timer(
        Duration(milliseconds: _limitSeconds * 1000 + 60),
        () => _finish(false),
      );
      _limitTick = Timer.periodic(_limitTickSpan, (
        Timer _,
      ) {
        if (_phase != _BallPhase.running) return;
        setState(() => _limitLeft = math.max(0, _limitLeft - 1));
      });
    }
  }

  void _step() {
    if (_phase != _BallPhase.running) return;
    final Size size = _fieldSize;
    if (size.isEmpty) return;
    _vx += _gx;
    _vy += _gy;
    _vx *= kBallDamp;
    _vy *= kBallDamp;
    _x += _vx;
    _y += _vy;

    final double r = _radius;
    String hit = '';
    if (_x < r) {
      _x = r;
      _vx = _bounce(_vx);
      hit = 'left';
    }
    if (_x > size.width - r) {
      _x = size.width - r;
      _vx = _bounce(_vx);
      hit = 'right';
    }
    if (_y < r) {
      _y = r;
      _vy = _bounce(_vy);
      hit = 'top';
    }
    if (_y > size.height - r) {
      _y = size.height - r;
      _vy = _bounce(_vy);
      hit = 'bottom';
    }

    _trail.insert(0, Offset(_x, _y));
    if (_trail.length > 4) _trail.removeRange(4, _trail.length);

    if (hit.isNotEmpty) {
      _hits += 1;
      _flashEdge = hit;
      playKitHaptic(context, PlayKitHaptic.light);
      if (!MediaQuery.disableAnimationsOf(context)) {
        _flash.forward(from: 0);
      }
    }
    setState(() {});
    if (hit.isNotEmpty && _hits >= _goal) _finish(true);
  }

  double _bounce(double velocity) =>
      ballShakeBounce(velocity, _random.nextDouble());

  void _finish(bool won) {
    if (_phase != _BallPhase.running) return;
    _stopAll();
    setState(() {
      _phase = _BallPhase.done;
      _result = won ? '撞满了' : '时间到，撞了 $_hits 次';
    });
    // ★ 限时耗尽**不提交**:小程序那边这一路只由台面判负(onVerdict 转出去的
    //   `ballshake:verdict` 在 ACTION_OF 里根本没有条目,发了也是死分支);而且
    //   报一个没撞满的成绩上去,`submitted` 会把这一格标成做过了,玩家再也回不来
    //   重试 —— 而这一关是可重来的。撞满才有成绩。
    if (!won || _submitted) return;
    _submitted = true;
    widget.data.onAction?.call(
      PlayKitAction(
        label: '提交成绩',
        action: 'SUBMIT_BALL_SHAKE',
        payload: <String, Object?>{'hits': _hits},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final bool busy = !widget.data.enabled ||
        widget.data.acting ||
        _phase == _BallPhase.calibrating ||
        _phase == _BallPhase.counting ||
        _phase == _BallPhase.running;
    return Semantics(
      label: '倾斜手机让球撞够四条边，撞满 $_goal 次',
      child: ExcludeSemantics(
        child: Container(
          color: _field,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size size = constraints.biggest;
              if (size.width > 0 && size != _fieldSize) {
                _fieldSize = size;
                _radius = _ballRpx * size.width / 750;
                _x = _x == 0 ? size.width / 2 : _x;
                _y = _y == 0 ? size.height * 0.35 : _y;
              }
              return Stack(
                children: <Widget>[
                  _edge(
                    'top',
                    reduceMotion: reduceMotion,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    top: 0,
                    height: 96,
                  ),
                  _edge(
                    'bottom',
                    reduceMotion: reduceMotion,
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    bottom: 0,
                    height: 96,
                  ),
                  _edge(
                    'left',
                    reduceMotion: reduceMotion,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    left: 0,
                    width: 96,
                  ),
                  _edge(
                    'right',
                    reduceMotion: reduceMotion,
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    right: 0,
                    width: 96,
                  ),
                  for (int i = _trail.length - 1; i >= 0; i--)
                    _trailDot(_trail[i], 0.14 - i * 0.035),
                  // 球一直在场上(照 wxml):开局前它停在开局位(场地中心偏上),
                  // 告诉玩家「球在这儿,倾斜就会动」 —— 藏起来的话这一屏空得像坏了。
                  _ball(),
                  Positioned(
                    top: padding.top + CyTokens.space6,
                    left: CyTokens.pageX,
                    right: CyTokens.pageX,
                    child: Column(
                      children: <Widget>[
                        if (_limitSeconds > 0 && _phase == _BallPhase.running)
                          _limitBar(),
                        PlayKitKicker(
                          _kicker,
                          color: const Color(0xFFFFFFFF).withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: CyTokens.space2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              '$_hits',
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 66,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                                letterSpacing: 0,
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: CyTokens.space2),
                            Text(
                              '/ $_goal 次',
                              style: TextStyle(
                                // 真源 `.bl__unit` opacity .42(大数字是满白,单位压一档)。
                                color: const Color(0xFFFFFFFF).withValues(alpha: 0.42),
                                fontSize: CyType.footnote.fontSize,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          _result.isEmpty ? _sub : _result,
                          style: TextStyle(
                            color: const Color(0xFFFFFFFF).withValues(alpha: 0.5),
                            fontSize: CyType.subhead.fontSize,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_phase == _BallPhase.calibrating)
                    Positioned.fill(
                      child: ColoredBox(
                        color: _scrim,
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _calibrate,
                            builder: (BuildContext context, Widget? child) =>
                                PlayKitCalibratePanel(
                              label: '拿成你打算玩的姿势',
                              progress: _calibrate.value,
                              ink: const Color(0xFFFFFFFF),
                              // 真源 `.cal__bar` = `--cy-color-play-accent-soft`
                              // rgba(255,255,255,.14)(quiethold 同一条,此前两处不一致)。
                              soft: const Color(0x24FFFFFF),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_phase == _BallPhase.counting)
                    Positioned.fill(
                      child: ColoredBox(
                        color: _scrim,
                        child: Center(
                          child: Text(
                            '$_countin',
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: CyTokens.typeDisplay,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: CyTokens.space5,
                    right: CyTokens.space5,
                    bottom: padding.bottom + CyTokens.space6,
                    child: PlayKitStageButton(
                      label: _phase == _BallPhase.running ? '撞!' : '开始',
                      busy: busy,
                      onPressed: busy ? null : _begin,
                      background: const Color(0xFFFFFFFF),
                      foreground: _field,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _ball() {
    final double diameter = _radius * 2 + 1;
    return Positioned(
      left: _x - _radius - 0.5,
      top: _y - _radius - 0.5,
      width: diameter,
      height: diameter,
      child: const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFFFFFFF), shape: BoxShape.circle),
      ),
    );
  }

  Widget _trailDot(Offset at, double opacity) {
    final double diameter = _radius * 2 + 1;
    return Positioned(
      left: at.dx - _radius - 0.5,
      top: at.dy - _radius - 0.5,
      width: diameter,
      height: diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF).withValues(alpha: opacity.clamp(0.0, 1.0)),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// 撞边不是画一条白线。线是「那儿有个东西」,而撞击要说的是「那儿亮了一下」——
  /// 所以是一片从边缘往里散开、越往里越淡的光,没有硬边。
  Widget _edge(
    String name, {
    required bool reduceMotion,
    required Alignment begin,
    required Alignment end,
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: _flash,
        builder: (BuildContext context, Widget? child) {
          final bool on = _flashEdge == name;
          final double opacity = !on
              ? 0
              : reduceMotion
              ? 0.5
              : (1 - Curves.easeIn.transform(_flash.value)).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: begin,
                  end: end,
                  colors: const <Color>[
                    Color(0x9EFFFFFF),
                    Color(0x38FFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: const <double>[0, 0.34, 1],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _limitBar() {
    final double fraction = _limitSeconds > 0
        ? (_limitLeft / _limitSeconds).clamp(0.0, 1.0)
        : 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Row(
        children: <Widget>[
          Text(
            '限时',
            style: TextStyle(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.5),
              fontSize: CyType.caption2.fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              child: SizedBox(
                height: 3,
                child: Stack(
                  children: <Widget>[
                    const Positioned.fill(child: ColoredBox(color: Color(0x1FFFFFFF))),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        child: const ColoredBox(
                          color: Color(0xFFFFFFFF),
                          child: SizedBox(height: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          Text(
            '${_limitLeft}s',
            style: TextStyle(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.5),
              fontSize: CyType.caption2.fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
