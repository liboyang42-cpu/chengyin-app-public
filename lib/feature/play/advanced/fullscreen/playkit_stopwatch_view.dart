import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// `cy-playkit-stopwatch` · 精准停表(盲停)。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-stopwatch/`。
///
/// ## 盲停
/// 表一走起来,走动的数字就藏了 —— 目标和容差**不藏**,它们是规则,不是答案。
/// 不藏数字的话这题是「读秒」不是「估时」,谁都满分。所以容差在这个玩法里
/// 不是秘密(与猜数字相反:那边容差能反推出答案区间,所以要藏)。
///
/// ## 结果由服务端定
/// 客户端报的毫秒数是**设备时钟**算的,而设备时钟玩家改得动。后端
/// `SUBMIT_STOPWATCH` 用 `START_CHALLENGE` 记的**服务器时间戳**复核。
/// 所以开表那一下必须真发出去,不先发的话提交会被判成「还没开始」。
///
/// ## 开表前的 3-2-1
/// 真源里这段在共享台面 `cy-play-stage`(属性 `count-in`):计时从看到表那一刻起跳
/// 的话,人还在反应就在扣毫秒 —— 那不是「精准」,是偷时间。App 的共享台面还没落地,
/// 本组件自带一份同参数的计数(620ms/拍,3 起),宿主台面就绪后可以整体迁出去。
/// **减动效下不数,直接开跑** —— 数字跳动本身就是动效(真源 `cy-play-countin` 原文)。
///
/// ## 与真源的已知差异(§7.2 accepted + 一处行为修正)
/// * 屏是浅色玻璃(#F2F4F6 + 四团柔光),真源用 `backdrop-filter`;App 侧 M9 禁假玻璃,
///   柔光改用**四团径向渐变**画出来(真源注释自己写着:blur 不生效的机型退化后
///   几乎看不出差别),玻璃片用半透明白 + 描边。
/// * 字重 900 → w700,大字收到 104pt 并套 `FittedBox`(动态字体放大时不裁字,T4)。
/// * 命中之后:真源停在 `run` 相、再点会拿**没有重置过的 t0** 再提交一次
///   (第二次必然「晚 N 秒」)。App 侧命中后统一进 `over` 相,再点开下一局并
///   **重新发一条 START_CHALLENGE**。判定本来就在服务端,这里只修掉一次无效提交。
/// * `tries`(还能错几次):真源画在共享台面的页眉(`cy-play-stage` 的圆点),
///   用完弹整屏两个字的判定屏。App 侧台面与判定屏都还没落地,所以次数由本组件
///   自己记(一行说明 + 用尽后不再开下一局),服务端另有一份 `attempts` 兜底。
class PlayKitStopwatchView extends StatefulWidget {
  const PlayKitStopwatchView({
    super.key,
    required this.data,
    this.now,
    this.countIn = true,
  });

  final PlayKitFullscreenContext data;

  /// 注入时钟,测试用。
  final DateTime Function()? now;

  /// 真源 `cy-play-stage` 的 `count-in` 属性:精准停表要数,别的玩法不一定。
  final bool countIn;

  @override
  State<PlayKitStopwatchView> createState() => _PlayKitStopwatchViewState();
}

/// 原型 #kit2 皮肤私有色(小程序 `playkit-stopwatch/index.wxss`,逐值,`ds-ok`)。
/// 与倒计时同理:这一屏**恒为浅色**,跟随玩家域的恒暗主题会把玻璃屏翻黑。
const Color _kSwSurface = Color(0xFFF2F4F6);
const Color _kSwInk = Color(0xFF111111);
const Color _kSwMuted = Color(0xFF787878);
const Color _kSwGlassThin = Color(0x85FFFFFF);
const Color _kSwGlassStrong = Color(0xEBFFFFFF);
const Color _kSwBlobTop = Color(0xFFC9D6E0);
const Color _kSwBlobRight = Color(0xFFE7D9CC);
const Color _kSwBlobMid = Color(0xFFDCE3E6);
const Color _kSwBlobBottom = Color(0xFFCBD3D6);

/// 原型 126pt(252rpx)。收到 104 并套 `FittedBox`:375pt 宽屏上五位读数
/// (`12.34`)在原型尺寸下已经贴边,动态字体再放大就会裁字。
const double _kSwGiantSize = 104;
const double _kSwArrowSize = 40;

const String _kSwEyebrowFallback = '把手机拿到面前,随时可以开始';
const String _kSwCapRunning = '开跑 1 秒后数字消失 · 点屏幕任意处停';
const String _kSwCapHidden = '数字已隐藏 · 点屏幕任意处停';
const String _kSwDash = '—— · ——';

/// 开表:`{ game: 'stopwatch' }`。服务端只认这个驼峰名,少一个字母
/// 都等于「还没开始」—— 提交会被判成没有成绩。
const PlayKitAction _kStopwatchStart = PlayKitAction(
  label: '开始',
  action: 'START_CHALLENGE',
  payload: <String, Object?>{'game': 'stopwatch'},
);

enum PlayKitStopwatchPhase { intro, countIn, run, paused, over }

class _PlayKitStopwatchViewState extends State<PlayKitStopwatchView>
    with WidgetsBindingObserver {
  PlayKitStopwatchPhase _phase = PlayKitStopwatchPhase.intro;
  Timer? _ticker;
  Timer? _countInTimer;
  DateTime? _startedAt;
  int _elapsedMs = 0;
  int _pausedMs = 0;
  int _round = 1;
  int _countInFrom = 3;
  int _triesLeft = 0;
  bool _hidden = false;
  String _cap = _kSwCapRunning;
  String _verdictLine = '';

  DateTime get _now => (widget.now ?? DateTime.now)();

  int get _targetSeconds {
    final int seconds = widget.data.card.durationSeconds;
    return seconds > 0 ? seconds : 0;
  }

  /// 容差毫秒。整屏族的 `maxLength` 是**通用数值槽位**(与 screen 批的
  /// rounds / hits 同口径):这里放 `toleranceMs`。
  int get _toleranceMs => widget.data.card.maxLength ?? 0;

  double get _toleranceSeconds => _toleranceMs / 1000;

  /// 能错几次(`kit.tries`)。0 / 缺失 = 不限次 —— 真源同口径
  /// (`cy-play-stage` 的 `tries`,默认 0 时压根不画那排圆点)。
  int get _triesTotal {
    final Object? raw = widget.data.card.kit['tries'];
    final int tries = raw is num ? raw.toInt() : 0;
    return tries > 0 ? tries : 0;
  }

  /// 次数用尽:停完就收摊,再点屏幕不许开下一局(服务端那边
  /// `attempts >= tries` 已经把这一局判死了,再发只会撞「这一局已经交过了」)。
  bool get _exhausted => _triesTotal > 0 && _triesLeft == 0;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cap = _kSwCapRunning;
    _triesLeft = _triesTotal;
  }

  @override
  void didUpdateWidget(covariant PlayKitStopwatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final PlayKitCard card = widget.data.card;
    final PlayKitCard previous = oldWidget.data.card;
    // 真源 observer 的 'show, kicker, targetSeconds, toleranceMs, tries'
    if (card.kind != previous.kind ||
        card.durationSeconds != previous.durationSeconds ||
        card.maxLength != previous.maxLength ||
        card.kit['tries'] != previous.kit['tries']) {
      _stopTickers();
      setState(() {
        _phase = PlayKitStopwatchPhase.intro;
        _elapsedMs = 0;
        _hidden = false;
        _cap = _kSwCapRunning;
        _verdictLine = '';
        _round = 1;
        _triesLeft = _triesTotal;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTickers();
    super.dispose();
  }

  /// 切后台这一轮作废:回来时表还在走,那个成绩不是估出来的(真源 `pageLifetimes.hide`)。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_phase == PlayKitStopwatchPhase.run ||
          _phase == PlayKitStopwatchPhase.paused ||
          _phase == PlayKitStopwatchPhase.countIn) {
        _abort();
      }
    }
  }

  void _stopTickers() {
    _ticker?.cancel();
    _ticker = null;
    _countInTimer?.cancel();
    _countInTimer = null;
  }

  void _abort() {
    _stopTickers();
    if (!mounted) return;
    setState(() {
      _phase = PlayKitStopwatchPhase.intro;
      _elapsedMs = 0;
      _hidden = false;
      _cap = _kSwCapRunning;
      _verdictLine = '';
    });
  }

  /// 「开始」→(数 3-2-1)→ 真正开跑。
  void _requestStart() {
    if (!widget.data.enabled || widget.data.acting) return;
    if (_reduced || !widget.countIn) {
      _run();
      return;
    }
    setState(() {
      _phase = PlayKitStopwatchPhase.countIn;
      _countInFrom = 3;
    });
    _countInTimer?.cancel();
    _countInTimer = Timer.periodic(kCountInTickInterval, (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final int next = _countInFrom - 1;
      if (next > 0) {
        setState(() => _countInFrom = next);
        return;
      }
      timer.cancel();
      _countInTimer = null;
      _run();
    });
  }

  void _run() {
    setState(() {
      _phase = PlayKitStopwatchPhase.run;
      _startedAt = _now;
      _elapsedMs = 0;
      _pausedMs = 0;
      _hidden = false;
      _cap = _kSwCapRunning;
      _verdictLine = '';
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(kStopwatchTickInterval, (_) => _tick());
    // 开表要报给服务端:成绩按**服务器时间**复核(设备时钟玩家改得动),
    // 不先开表,SUBMIT_STOPWATCH 会被判成「还没开始」。
    widget.data.onAction?.call(_kStopwatchStart);
  }

  void _tick() {
    final DateTime? startedAt = _startedAt;
    if (startedAt == null) return;
    final int ms = _now.difference(startedAt).inMilliseconds;
    if (stopwatchAborted(ms, _targetSeconds.toDouble())) {
      // 忘了停也不能永远走下去:超目标 30 秒当这局没发生
      _abort();
      return;
    }
    if (ms >= kStopwatchHideAfter.inMilliseconds) {
      if (!_hidden) {
        setState(() {
          _hidden = true;
          _cap = _kSwCapHidden;
        });
      }
      return;
    }
    setState(() => _elapsedMs = ms);
  }

  void _togglePause() {
    if (_phase == PlayKitStopwatchPhase.run) {
      _ticker?.cancel();
      _ticker = null;
      _pausedMs = _elapsedMs;
      setState(() => _phase = PlayKitStopwatchPhase.paused);
      return;
    }
    if (_phase != PlayKitStopwatchPhase.paused) return;
    final DateTime? startedAt = _startedAt;
    if (startedAt == null) return;
    // 暂停不计入:把起点往后挪已经过的那一段
    _startedAt = startedAt.add(Duration(milliseconds: _elapsedMs - _pausedMs));
    setState(() => _phase = PlayKitStopwatchPhase.run);
    _ticker = Timer.periodic(kStopwatchTickInterval, (_) => _tick());
  }

  /// 整个舞台就是「停」的按钮。暂停中不接受停 —— 那等于把表停在自己挑的一刻。
  void _stop() {
    if (_phase == PlayKitStopwatchPhase.over) {
      if (_exhausted) return;
      setState(() => _round += 1);
      _run();
      return;
    }
    if (_phase != PlayKitStopwatchPhase.run) return;
    _ticker?.cancel();
    _ticker = null;
    final DateTime? startedAt = _startedAt;
    if (startedAt == null) return;
    final int elapsed = _now.difference(startedAt).inMilliseconds;
    final double target = _targetSeconds.toDouble();
    final double tolerance = _toleranceSeconds;
    final double diff = stopwatchDiffSeconds(elapsed, target);
    final bool hit = diff <= tolerance;
    final String detail = stopwatchStopDetail(
      elapsedMs: elapsed,
      targetSeconds: target,
      toleranceSeconds: tolerance,
    );
    // 「做成了」= 按下停那一刻,不管准不准 —— 那一下是玩家真正做的动作。
    // 减动效下不震(真源 motion.haptic 在 reducedMotion 时 return false)。
    if (!_reduced) {
      unawaited(HapticFeedback.mediumImpact());
    }
    // 次数记账在台面:真源 `stage.miss()` 返回「是否已用完」,错一次扣一颗点。
    // App 侧台面还没落地,这一笔由本组件自己记(服务端另有一份 `attempts`,
    // 用它封顶 —— 客户端少算一次也不会多发一条有效提交)。
    final bool exhausted;
    if (hit || _triesTotal == 0) {
      exhausted = false;
    } else {
      exhausted = _triesLeft <= 1;
    }
    setState(() {
      if (!hit && _triesTotal > 0) {
        _triesLeft = exhausted ? 0 : _triesLeft - 1;
      }
      _elapsedMs = elapsed;
      _hidden = false;
      _phase = PlayKitStopwatchPhase.over;
      // 档位与「早/晚」只是屏上的字,判定仍是服务端的事;次数用尽那一下
      // 真源换整屏两个字的判定屏(`cy-play-verdict`,timedOut=false → 「失败」),
      // App 侧判定屏也还没落地,先把这两个字摆在这一行的位置上。
      _verdictLine = exhausted
          ? '失败'
          : '${stopwatchTierLabel(diff, tolerance)} · $detail';
      _cap = hit || exhausted ? detail : '$detail · 点屏幕再来一局';
    });
    // 组件按玩家看到的单位报(毫秒),服务端按判定的单位收 —— 同一个单位,
    // 真源 `serverPayload` 的 `stopwatch:submit` 是 `{ stoppedMs: d.elapsedMs }`。
    widget.data.onAction?.call(
      PlayKitAction(
        label: '停表',
        action: 'SUBMIT_STOPWATCH',
        payload: <String, Object?>{'stoppedMs': elapsed},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitCard card = widget.data.card;
    final String eyebrow = card.eyebrow.isEmpty
        ? _kSwEyebrowFallback
        : card.eyebrow;
    return PlayKitStageSurface(
      background: _kSwSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space5,
        vertical: CyTokens.space6,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _AmbiencePainter()),
            ),
          ),
          if (_phase == PlayKitStopwatchPhase.intro)
            _intro(eyebrow)
          else if (_phase == PlayKitStopwatchPhase.countIn)
            _countIn()
          else
            _running(),
        ],
      ),
    );
  }

  Widget _intro(String eyebrow) {
    final String targetText = _targetSeconds.toDouble().toStringAsFixed(2);
    final String toleranceText = _toleranceSeconds.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          eyebrow,
          style: const TextStyle(
            color: _kSwMuted,
            fontSize: CyTokens.typeLabel,
          ),
        ),
        const Spacer(),
        _IntroRow(
          label: '目标',
          value: targetText,
          unit: '秒',
          valueKey: const ValueKey<String>('stopwatch-target'),
        ),
        const SizedBox(height: CyTokens.space5),
        _IntroRow(
          label: '误差',
          value: '±$toleranceText',
          unit: '秒',
          valueKey: const ValueKey<String>('stopwatch-tolerance'),
        ),
        const SizedBox(height: CyTokens.space6),
        const Text(
          '开跑 1 秒后数字会消失',
          style: TextStyle(color: _kSwMuted, fontSize: CyTokens.typeLabel),
        ),
        const SizedBox(height: CyTokens.space1),
        const Text(
          '点屏幕任意处停',
          style: TextStyle(color: _kSwMuted, fontSize: CyTokens.typeLabel),
        ),
        // 真源这一屏页眉有排圆点(`cy-play-stage` 的 `tries`):同一份信息,
        // App 侧换成一行说明 —— 与猜数字那一族的「可以错 N 次」同一口径(§7.2)。
        if (_triesTotal > 0) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            '可以错 $_triesTotal 次',
            style: const TextStyle(
              color: _kSwMuted,
              fontSize: CyTokens.typeLabel,
            ),
          ),
        ],
        const Spacer(),
        PlayKitSolidAction(
          label: '开始',
          width: double.infinity,
          background: _kSwInk,
          foreground: _kSwSurface,
          busy: !widget.data.enabled || widget.data.acting,
          onPressed: widget.data.enabled && !widget.data.acting
              ? _requestStart
              : null,
        ),
      ],
    );
  }

  /// 3-2-1:整屏压一层、只剩一个数字 —— 这一下的用处是「把注意力清空」,
  /// 所以屏上不能再有别的东西可看(真源 `cy-play-countin` 原文)。
  Widget _countIn() {
    return Semantics(
      liveRegion: true,
      label: '$_countInFrom 秒后开始',
      child: ExcludeSemantics(
        child: Center(
          child: PlayKitBigFigure(
            text: '$_countInFrom',
            size: _kSwGiantSize,
            color: _kSwInk,
          ),
        ),
      ),
    );
  }

  Widget _running() {
    final String targetText = _targetSeconds.toDouble().toStringAsFixed(2);
    final String toleranceText = _toleranceSeconds.toStringAsFixed(2);
    final bool paused = _phase == PlayKitStopwatchPhase.paused;
    return Column(
      children: <Widget>[
        if (paused) ...<Widget>[
          const Text(
            '已暂停',
            style: TextStyle(
              color: _kSwInk,
              fontSize: CyTokens.typeCardTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          const Text(
            '数字不会放出来',
            style: TextStyle(color: _kSwMuted, fontSize: CyTokens.typeCaption),
          ),
        ],
        Expanded(
          child: Semantics(
            button: true,
            label: '点屏幕任意处停',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _stop,
              child: Opacity(
                opacity: paused ? 0.4 : 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    PlayKitPill(
                      '第 $_round 局',
                      foreground: _kSwMuted,
                      background: _kSwGlassThin,
                    ),
                    if (_triesTotal > 0) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      // 真源是页眉那排圆点(用掉的涂灰);同一份信息换成一行字,
                      // 与准备屏那句、猜数字那族同一口径(§7.2)。
                      PlayKitPill(
                        _exhausted ? '次数用完了' : '还能错 $_triesLeft 次',
                        foreground: _kSwMuted,
                        background: _kSwGlassThin,
                      ),
                    ],
                    const SizedBox(height: CyTokens.space3),
                    AnimatedSwitcher(
                      duration: _reduced ? Duration.zero : CyMotion.fadeSwap,
                      child: _hidden
                          ? const PlayKitBigFigure(
                              key: ValueKey<String>('stopwatch-hidden'),
                              text: _kSwDash,
                              size: _kSwArrowSize,
                              color: _kSwInk,
                            )
                          : FittedBox(
                              key: const ValueKey<String>('stopwatch-reading'),
                              fit: BoxFit.scaleDown,
                              child: PlayKitBigFigure(
                                text: stopwatchSecondsText(_elapsedMs),
                                size: _kSwGiantSize,
                                color: _kSwInk,
                                semanticsLabel:
                                    '${stopwatchSecondsText(_elapsedMs)} 秒',
                              ),
                            ),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    PlayKitPill(
                      '目标 $targetText 秒 · 容差 ±$toleranceText',
                      foreground: _kSwInk,
                      background: _kSwGlassStrong,
                    ),
                    const SizedBox(height: CyTokens.space4),
                    if (_verdictLine.isNotEmpty)
                      Text(
                        _verdictLine,
                        style: const TextStyle(
                          color: _kSwInk,
                          fontSize: CyTokens.typeCardTitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      _cap,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _kSwMuted,
                        fontSize: CyTokens.typeLabel,
                        height: CyTokens.leadingNormal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _bar(),
      ],
    );
  }

  /// 底部那颗表跟着一起藏 —— 大数字藏了、这里还在走秒,等于没藏。
  Widget _bar() {
    final bool paused = _phase == PlayKitStopwatchPhase.paused;
    return Container(
      height: CyTokens.btnH,
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      decoration: BoxDecoration(
        color: _kSwGlassThin,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.time, size: 18, color: _kSwMuted),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Text(
              _hidden ? '––:––.––' : stopwatchClockText(_elapsedMs),
              style: TextStyle(
                color: _kSwInk,
                fontSize: CyTokens.typeBody,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(kPlayKitMinTapTarget),
            onPressed: _phase == PlayKitStopwatchPhase.over
                ? null
                : _togglePause,
            child: Icon(
              paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
              size: 20,
              color: _kSwInk,
              semanticLabel: paused ? '继续' : '暂停',
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroRow extends StatelessWidget {
  const _IntroRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.valueKey,
  });

  final String label;
  final String value;
  final String unit;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: _kSwMuted,
            fontSize: CyTokens.typeLabel,
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            PlayKitBigFigure(
              key: valueKey,
              text: value,
              size: 64,
              color: _kSwInk,
            ),
            const SizedBox(width: CyTokens.space2),
            const Text(
              '秒',
              style: TextStyle(color: _kSwMuted, fontSize: CyTokens.typeLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// 四团柔光 + 竖向底色。真源是 `filter: blur(46px)` 的色斑;
/// 这里用径向渐变直接画软边 —— 不引 `BackdropFilter`(M9 禁假玻璃),
/// 观感对齐,且在 blur 不生效的机型上**更**接近原型(真源注释同此判断)。
class _AmbiencePainter extends CustomPainter {
  const _AmbiencePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFFAFCFC), Color(0xFFEEF1F3)],
        ).createShader(rect),
    );
    _blob(canvas, rect, const Alignment(-0.52, -0.68), 0.38, 0.26, _kSwBlobTop);
    _blob(
      canvas,
      rect,
      const Alignment(0.64, -0.48),
      0.34,
      0.24,
      _kSwBlobRight,
    );
    _blob(canvas, rect, const Alignment(0.04, 0.24), 0.46, 0.32, _kSwBlobMid);
    _blob(
      canvas,
      rect,
      const Alignment(-0.64, 0.68),
      0.30,
      0.22,
      _kSwBlobBottom,
    );
  }

  void _blob(
    Canvas canvas,
    Rect rect,
    Alignment at,
    double radiusX,
    double radiusY,
    Color color,
  ) {
    final double cx = rect.width * (at.x + 1) / 2;
    final double cy = rect.height * (at.y + 1) / 2;
    final Rect area = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rect.width * radiusX * 2,
      height: rect.height * radiusY * 2,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[color, color.withAlpha(0)],
          stops: const <double>[0, 0.72],
        ).createShader(area),
    );
  }

  @override
  bool shouldRepaint(_AmbiencePainter oldDelegate) => false;
}
