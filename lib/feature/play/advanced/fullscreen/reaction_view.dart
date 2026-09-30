import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_logic.dart';
import 'playkit_fullscreen_parts.dart';

/// 变色就点 · `cy-playkit-reaction` 的 App 侧(结构 1:1 照搬小程序 index.wxml)。
///
/// ★ 这个玩法**没有 3-2-1**:它测的就是突然性,先数三下等于预告。
///
/// ★ 抢跑要单独判 —— 不判的话所有人都会在变色前狂点,这游戏就没了。
///
/// ★ 等待时长随机(1.4–4.2s),而且**由服务端决定这一轮算不算数**:组件只报
/// 「每轮点了多少毫秒」,服务端拿 START_CHALLENGE 那一刻的服务器墙钟复核。
/// 组件里那几个数只是显示。低于人类反应下限(120ms)的不收:那是提前按住
/// 不放蹭出来的,后端也会判抢跑。
///
/// ★ 整屏就是判定区,不给按钮:手指本来就悬在屏幕上方,再让人瞄准一个按钮
/// 会把反应时间测成瞄准时间。
class PlayKitReactionView extends StatefulWidget {
  const PlayKitReactionView({
    super.key,
    required this.data,
    this.now,
    this.random,
  });

  final PlayKitFullscreenContext data;

  /// 测试注入时钟 —— 毫秒成绩从这里算,不能靠系统钟。
  final DateTime Function()? now;

  /// 等待时长采样(0–1)。测试注入固定值。
  final double Function()? random;

  @override
  State<PlayKitReactionView> createState() => _PlayKitReactionViewState();
}

/// idle | wait | go | early | done(小程序 data.phase 原文)。
enum _ReactionPhase { idle, wait, go, early, done }

class _PlayKitReactionViewState extends State<PlayKitReactionView>
    with WidgetsBindingObserver {
  // 玩法信号色:等待态是红、变色态是绿、抢跑单独一态 —— 照 Human Benchmark
  // 的读法,那是这类玩法里唯一被大量人验证过的配色约定,不自己发明。
  static const Color _waitColor = Color(0xFFC5372F);
  static const Color _goColor = Color(0xFF22C55E);
  static const Color _earlyColor = Color(0xFF1B1B22);
  static const Color _doneColor = Color(0xFF0F172A);

  /// 生产用的等待时长采样(1.4–4.2s)。测试注入 [PlayKitReactionView.random]。
  final math.Random _randomSource = math.Random();

  _ReactionPhase _phase = _ReactionPhase.idle;
  final List<int> _times = <int>[];
  bool _armed = false;
  DateTime? _goAt;
  Timer? _timer;
  String _big = '—';
  String _sub = '点一下开始';

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  int get _rounds {
    final int rounds = widget.data.card.maxLength ?? 0;
    return rounds > 0 ? rounds : 3;
  }

  int get _goalMs => widget.data.card.durationSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(PlayKitReactionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.card.kind != widget.data.card.kind) _reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台就把这一轮作废:回来时屏幕可能已经绿了很久,那个「成绩」是假的。
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _abortRound();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  void _reset() {
    _stop();
    _armed = false;
    _times.clear();
    setState(() {
      _phase = _ReactionPhase.idle;
      _big = '—';
      _sub = '点一下开始';
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _abortRound() {
    if (_phase != _ReactionPhase.wait && _phase != _ReactionPhase.go) return;
    _stop();
    setState(() {
      _phase = _ReactionPhase.idle;
      _big = '—';
      _sub = '刚才切走了，这一轮不算。点一下重来';
    });
  }

  /// 进入等待:红屏,随机若干毫秒后转绿。
  void _arm() {
    setState(() {
      _phase = _ReactionPhase.wait;
      _big = '等';
      _sub = '变绿再点 —— 早点了算抢跑';
    });
    // 开表要报给服务端:成绩按服务器时间复核,不先开表提交会被判成「还没开始」。
    // 第一轮报一次就够,服务端记的是这一局的起点。
    if (!_armed) {
      _armed = true;
      widget.data.onAction?.call(
        const PlayKitAction(
          label: '开始挑战',
          action: 'START_CHALLENGE',
          payload: <String, Object?>{'game': 'reaction'},
        ),
      );
    }
    _stop();
    // ★ 生产必须**真随机**:固定间隔的话第二轮就能背下来,测的就不是反应了。
    final double unit = widget.random?.call() ?? _randomSource.nextDouble();
    _timer = Timer(
      Duration(milliseconds: pickReactionWaitMs(unit)),
      () {
        if (!mounted) return;
        _goAt = _now;
        setState(() {
          _phase = _ReactionPhase.go;
          _big = '点!';
          _sub = '';
        });
      },
    );
  }

  void _onTap() {
    if (!widget.data.enabled) return;
    switch (_phase) {
      case _ReactionPhase.idle:
      case _ReactionPhase.early:
        _arm();
      case _ReactionPhase.wait:
        // 抢跑:这一轮作废,但不判整局输 —— 抢跑是操作失误,不是答错。
        _stop();
        playKitHaptic(context, PlayKitHaptic.light);
        setState(() {
          _phase = _ReactionPhase.early;
          _big = '抢跑';
          _sub = '绿了才能点。点一下重来';
        });
      case _ReactionPhase.go:
        _measure();
      case _ReactionPhase.done:
        break;
    }
  }

  void _measure() {
    final DateTime? goAt = _goAt;
    if (goAt == null) return;
    final int ms = _now.difference(goAt).inMilliseconds;
    // 低于人类反应下限的不收:那是提前按住不放蹭出来的,后端也会判抢跑。
    if (ms < kReactionMinHumanMs) {
      setState(() {
        _phase = _ReactionPhase.early;
        _big = '抢跑';
        _sub = '这个快得不像人手。点一下重来';
      });
      return;
    }
    _times.add(ms);
    // 「做成了」落在每一轮成绩落定这一刻。
    playKitHaptic(context, PlayKitHaptic.medium);
    if (_times.length < _rounds) {
      setState(() {
        _phase = _ReactionPhase.idle;
        _big = '$ms';
        _sub = '毫秒 · 点一下进入下一轮';
      });
      return;
    }
    final int best = reactionBestOf(_times);
    setState(() {
      _phase = _ReactionPhase.done;
      _big = '$best';
      _sub = '三轮里最快的一次';
    });
    // 成绩报服务端,由它拿真实墙钟复核 —— 本地这几个数只是显示。
    widget.data.onAction?.call(
      PlayKitAction(
        label: '提交成绩',
        action: 'SUBMIT_REACTION',
        payload: <String, Object?>{'times': List<int>.of(_times)},
      ),
    );
  }

  Color get _background => switch (_phase) {
    _ReactionPhase.idle || _ReactionPhase.wait => _waitColor,
    _ReactionPhase.go => _goColor,
    _ReactionPhase.early => _earlyColor,
    _ReactionPhase.done => _doneColor,
  };

  @override
  Widget build(BuildContext context) {
    final String semanticsLabel = switch (_phase) {
      _ReactionPhase.wait => '等待变色，变色后立刻点',
      _ReactionPhase.go => '现在点',
      _ReactionPhase.early => '抢跑了，点一下重来',
      _ReactionPhase.done => _goalMs > 0
          ? '三轮里最快的一次 $_big 毫秒，达标线 $_goalMs 毫秒'
          : '三轮里最快的一次 $_big 毫秒',
      _ReactionPhase.idle => '点一下开始',
    };
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: AnimatedContainer(
            // 红转绿是本玩法唯一反馈,转场必须在位;减动效下**瞬切**
            // (真源 app.wxss 的 prefers-reduced-motion 把这条 transition 压没)。
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : CyMotion.fast,
            curve: Curves.linear,
            color: _background,
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    PlayKitKicker(
                      widget.data.card.eyebrow.isEmpty
                          ? '变绿就点'
                          : widget.data.card.eyebrow,
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.68),
                    ),
                    const SizedBox(height: CyTokens.space5),
                    Text(
                      _big,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 84,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                      ),
                    ),
                    if (_sub.isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space4),
                      SizedBox(
                        width: 300,
                        child: Text(
                          _sub,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            // 真源 `.rx__sub` opacity .82(kicker 的 .68 已在位)。
                            color: const Color(0xFFFFFFFF).withValues(alpha: 0.82),
                            fontSize: CyType.subhead.fontSize,
                            height: 1.7,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
