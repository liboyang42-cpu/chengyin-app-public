import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_logic.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_fullscreen_sources.dart';

/// 安静挑战 · `cy-playkit-quiethold` 的 App 侧(结构 1:1 照搬小程序 index.wxml)。
///
/// ★ 过线就判输,不是清零重来。「一声都不许出」这条规则要立得住,就不能给第二次。
/// ★ 判**峰值**不判均值:一声咳嗽在均值里会被摊平,而人的直觉对得上峰值。
/// ★ 阈值必须现场校准,不能写死:咖啡馆的底噪比书店高一大截,书店的阈值拿到
///   咖啡馆就是「一开局就输」。取 80 分位当底噪 —— 不取最大值,否则校准那两秒里
///   的一次咳嗽会把线抬到没人能触发。
///
/// ★ 录音**不上传、不落盘,用完即弃**(见 [PlayKitRecorderSoundLevelSource]):
///   这一屏只需要每帧的振幅,不需要内容。
///
/// ★ 拿不到麦克风就明说,不假装在听 —— 让人以为在真听是更糟的事。
class PlayKitQuietHoldView extends StatefulWidget {
  const PlayKitQuietHoldView({
    super.key,
    required this.data,
    this.soundSource,
    this.now,
  });

  final PlayKitFullscreenContext data;

  /// 响度来源。widget 测试注入假流;null = 真机麦克风。
  final PlayKitSoundLevelSource? soundSource;

  /// 计时时钟。**成绩由服务端按服务器时间复核**,这里的时钟只用来推进度显示。
  final DateTime Function()? now;

  @override
  State<PlayKitQuietHoldView> createState() => _PlayKitQuietHoldViewState();
}

enum _QuietPhase { idle, calibrating, running, done }

class _PlayKitQuietHoldViewState extends State<PlayKitQuietHoldView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 校准 2s(原型台面 `calibrate-ms="2000"`):太短量不准底噪,太长人开始不耐烦。
  static const Duration _calibrateSpan = Duration(milliseconds: 2000);

  /// 一帧最多只记 0.1 秒:切后台时定时器会被限频,回来那一帧的间隔可能有好几秒 ——
  /// 不夹的话等于熄屏几秒就白得几秒安静,而那几秒根本没在听。
  static const double _maxStepSeconds = 0.1;

  /// 台面遮罩:原型 `--cy-color-play-scrim` 的兜底值 rgba(8,8,10,.78)。
  static const Color _scrim = Color(0xC708080A);

  /// 玩法信号色(原型 `.qt__n` 绿/黄/红三档,ds-ok 道具色不参与主题翻转)。
  static const Color _ink = Color(0xFFE8F0EA);
  static const Color _okColor = Color(0xFF3ECF8E);
  static const Color _midColor = Color(0xFFD9A327);
  static const Color _hotColor = Color(0xFFE0464C);

  late final AnimationController _calibrate;
  PlayKitSoundLevelSource? _source;
  StreamSubscription<double>? _levels;
  Timer? _tickTimer;

  _QuietPhase _phase = _QuietPhase.idle;
  List<double> _samples = <double>[];
  final List<double> _frame = <double>[];
  double _mid = 0.12;
  double _hot = 0.21;
  double _held = 0;
  double _left = 15;
  DateTime? _last;
  String _band = 'ok';
  String _result = '';
  bool _submitted = false;

  /// 挑战时长(秒)。原型 `seconds` 默认 15。
  int get _total {
    final int seconds = widget.data.card.durationSeconds;
    return seconds > 0 ? seconds : 15;
  }

  String get _kicker => widget.data.card.eyebrow.isEmpty
      ? '别出声'
      : widget.data.card.eyebrow;

  /// 商家在编辑页填的说明行(`sub`);空就不渲染 —— 没填的地方不要替他解释。
  String get _sub => widget.data.card.detail;

  DateTime get _nowTime => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _left = _total.toDouble();
    _calibrate = AnimationController(
      vsync: this,
      duration: _calibrateSpan,
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) _afterCalibrate();
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台就停:回来那一帧的间隔可能有好几秒,不停等于「熄屏几秒」白赚几秒安静,
    // 而那几秒根本没在听。
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_phase == _QuietPhase.running || _phase == _QuietPhase.calibrating) {
        _abort();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTick();
    unawaited(_levels?.cancel());
    unawaited(_source?.stop());
    _calibrate.dispose();
    super.dispose();
  }

  void _stopTick() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// 用完即弃:断订阅、停录音,两件事**当场发起**,谁也不用等谁。
  ///
  /// 这两步都不 await:断订阅返回的是 root zone 的已完结 future,在它后面
  /// 挂 `await` 会把「停录音」推迟到真实事件循环的下一拍 —— 测试里等不到,
  /// 真机上也只是白白多绕一圈。停录音的善后由来源自己负责。
  void _stopMic() {
    final StreamSubscription<double>? levels = _levels;
    final PlayKitSoundLevelSource? source = _source;
    _levels = null;
    _source = null;
    if (levels != null) unawaited(levels.cancel());
    if (source != null) unawaited(source.stop());
  }

  void _abort() {
    _stopTick();
    _stopMic();
    _calibrate.stop();
    setState(() {
      _phase = _QuietPhase.idle;
      _band = 'ok';
      _held = 0;
      _left = _total.toDouble();
      _result = '刚才切走了，这一局不算';
    });
  }

  Future<void> _start() async {
    if (_phase == _QuietPhase.calibrating || _phase == _QuietPhase.running) {
      return;
    }
    if (!widget.data.enabled || widget.data.acting) return;
    final PlayKitSoundLevelSource source =
        widget.soundSource ?? PlayKitRecorderSoundLevelSource();
    _source = source;
    try {
      await source.start();
    } on Object catch (error) {
      // 拿不到麦克风就明说,不假装在听 —— 让人以为在真听是更糟的事。
      if (!mounted) return;
      final String detail = error is PlayKitMicUnavailable
          ? error.message
          : '麦克风没打开';
      setState(() {
        _phase = _QuietPhase.idle;
        _result = '$detail，这一关没法开始。到系统设置里允许麦克风再回来';
      });
      return;
    }
    if (!mounted) {
      await source.stop();
      return;
    }
    _levels = source.watch().listen(
      (double level) {
        if (_phase == _QuietPhase.calibrating) {
          // 校准期间每一拍采一个峰值(80 分位从这里出)。
          _samples.add(level);
          return;
        }
        if (_phase == _QuietPhase.running) _frame.add(level);
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
    setState(() {
      _phase = _QuietPhase.calibrating;
      _samples = <double>[];
      _frame.clear();
      _result = '';
      _band = 'ok';
      _held = 0;
      _left = _total.toDouble();
    });
    _calibrate.forward(from: 0);
  }

  void _afterCalibrate() {
    if (!mounted) return;
    final QuietThresholds thresholds = quietThresholdsOf(
      quietBaselineOf(_samples),
    );
    _mid = thresholds.mid;
    _hot = thresholds.hot;
    _run();
  }

  void _run() {
    if (!mounted) return;
    _held = 0;
    _left = _total.toDouble();
    _last = _nowTime;
    _frame.clear();
    _submitted = false;
    setState(() {
      _phase = _QuietPhase.running;
      _band = 'ok';
      _result = '';
    });
    // 开表要给服务端:成绩按服务器时间复核,不先开表提交会被判成「还没开始」。
    // 设备时钟玩家改得动,所以这一条不能省。
    widget.data.onAction?.call(
      const PlayKitAction(
        label: '开始挑战',
        action: 'START_CHALLENGE',
        payload: <String, Object?>{'game': 'quietHold'},
      ),
    );
    _stopTick();
    _tickTimer = Timer.periodic(
      kQuietPoll,
      (Timer _) => _tick(),
    );
  }

  void _tick() {
    if (_phase != _QuietPhase.running) return;
    final DateTime now = _nowTime;
    final DateTime? last = _last;
    _last = now;
    // ★ 一帧最多 0.1 秒(见 _maxStepSeconds)。
    final double dt = last == null
        ? 0
        : math.min(
            _maxStepSeconds,
            now.difference(last).inMilliseconds / 1000,
          );
    final double peak = quietPeakOf(_frame);
    _frame.clear();

    final String band = quietBandOf(peak, _mid, _hot);
    if (band == 'hot') {
      _finish(false);
      return;
    }
    _held += dt;
    setState(() {
      _band = band;
      _left = math.max(0, _total - _held);
    });
    if (_held >= _total) _finish(true);
  }

  void _finish(bool won) {
    if (_phase != _QuietPhase.running) return;
    _stopTick();
    _stopMic();
    playKitHaptic(context, PlayKitHaptic.medium);
    setState(() {
      _phase = _QuietPhase.done;
      _band = won ? 'ok' : 'hot';
      _left = won ? 0 : _left;
      _result = won ? '整整 $_total 秒，一声没出' : '出了一声，这一局就到这儿';
    });
    if (_submitted) return;
    _submitted = true;
    // 组件按玩家读得懂的单位报(秒),服务端按判定的单位收(毫秒)——
    // 换算在宿主层做,见 playkit_fullscreen_payload.dart。
    widget.data.onAction?.call(
      PlayKitAction(
        label: '提交成绩',
        action: 'SUBMIT_QUIET_HOLD',
        payload: <String, Object?>{'heldSeconds': _held.round()},
      ),
    );
  }

  Color get _bandColor => switch (_band) {
    'mid' => _midColor,
    'hot' => _hotColor,
    _ => _okColor,
  };

  List<Color> get _background => switch (_band) {
    // 快到线时整屏透出一点暖色,给人一个收声的机会 —— 只有绿和红的话,
    // 人是在毫无预兆的情况下失败的。
    'mid' => const <Color>[Color(0xFF1A1408), Color(0xFF0A0805)],
    'hot' => const <Color>[Color(0xFF2A0F10), Color(0xFF120607)],
    _ => const <Color>[Color(0xFF0D1512), Color(0xFF050A08)],
  };

  String get _semantics {
    final int seconds = _left.ceil();
    final String band = switch (_band) {
      'mid' => '有点吵',
      'hot' => '过线了',
      _ => '安静',
    };
    if (_phase == _QuietPhase.running) return '还剩 $seconds 秒，$band';
    if (_phase == _QuietPhase.done) return _result;
    return _sub.isEmpty ? '别出声，$_total 秒' : '别出声，$_sub';
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bool busy = !widget.data.enabled ||
        widget.data.acting ||
        _phase == _QuietPhase.calibrating ||
        _phase == _QuietPhase.running;
    final String big = _left.toStringAsFixed(1);
    return Semantics(
      liveRegion: true,
      label: _semantics,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          // Reduce Motion:颜色瞬时切过去,不缩不推(A2)。
          duration: reduceMotion ? Duration.zero : CyMotion.standard,
          curve: Curves.linear,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _background,
            ),
          ),
          child: Stack(
            children: <Widget>[
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.space7,
                    CyTokens.space6,
                    CyTokens.space7,
                    CyTokens.space6,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      PlayKitKicker(
                        _kicker,
                        color: _ink.withValues(alpha: 0.68),
                      ),
                      const SizedBox(height: CyTokens.space5),
                      AnimatedDefaultTextStyle(
                        duration: reduceMotion ? Duration.zero : CyMotion.fast,
                        curve: Curves.linear,
                        // 族名/字距沿用它所在那一层的默认样式,只改颜色与字号:
                        // AnimatedDefaultTextStyle 是**整份替换**不是合并,自己拼一份
                        // 裸 TextStyle 会把族名丢掉 —— 真机上落回系统字体(恰好一样),
                        // 测试里则整个掉进内置测试字体的方框,基线就废了。
                        style: DefaultTextStyle.of(context).style.copyWith(
                          color: _bandColor,
                          fontSize: 82,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          letterSpacing: 0,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                        child: Text(big),
                      ),
                      if (_result.isNotEmpty || _sub.isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space4),
                        SizedBox(
                          width: 300,
                          child: Text(
                            _result.isNotEmpty ? _result : _sub,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _ink.withValues(alpha: 0.75),
                              fontSize: CyType.subhead.fontSize,
                              height: 1.75,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: CyTokens.space5),
                      PlayKitStageButton(
                        label: _phase == _QuietPhase.running ? '安静中' : '开始',
                        busy: busy,
                        onPressed: busy ? null : () => unawaited(_start()),
                        background: _ink,
                        foreground: const Color(0xFF0D1512),
                      ),
                    ],
                  ),
                ),
              ),
              if (_phase == _QuietPhase.calibrating)
                Positioned.fill(
                  child: ColoredBox(
                    color: _scrim,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _calibrate,
                        builder: (BuildContext context, Widget? child) =>
                            PlayKitCalibratePanel(
                          label: '先听一下这儿有多吵',
                          progress: _calibrate.value,
                          ink: _ink,
                          // --cy-color-play-accent-soft:rgba(255,255,255,.14)
                          soft: const Color(0x24FFFFFF),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
