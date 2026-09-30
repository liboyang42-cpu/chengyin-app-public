import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_logic.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_fullscreen_sources.dart';

/// 掷骰子 · `cy-playkit-diceroll` 的 App 侧(结构 1:1 照搬小程序 index.wxml)。
///
/// ★ **点数由服务端出**:这一屏里没有任何随机数 —— 摇出来的点数由后端算
/// (ROLL_DICE 幂等,重复提交返回第一次的点数),客户端只把动作抛出去。
///
/// ★ 两颗那一档**只报点数和**,不对应任务:一颗才是「掷到几就做第几件事」,
/// 两颗是用来分胜负的。拿两颗的和去索引六个面会越界,那是另一个玩法。
///
/// ★ 这一屏也没有按钮(摇一摇就扔),分段是唯一可点的东西。
///
/// 整屏色板 = 真源 `playkit-diceroll/index.wxss`(原型 `.dz` 恒浅台面)逐值:
/// 墨紫 `#2A2540` / 灰紫 `#6B6386` 及其各档透明 —— 不跟主题、不走 CyPalette,
/// 与 quiet_hold 的 `_scrim` / `_ink` 同一挡案口径(游戏美术,§7.2)。
class PlayKitDiceRollView extends StatefulWidget {
  const PlayKitDiceRollView({
    super.key,
    required this.data,
    this.accelerationSource,
  });

  final PlayKitFullscreenContext data;

  /// 摇一摇来源。widget 测试注入假流;null = 真机加速度计。
  final PlayKitAccelerationSource? accelerationSource;

  @override
  State<PlayKitDiceRollView> createState() => _PlayKitDiceRollViewState();
}

class _PlayKitDiceRollViewState extends State<PlayKitDiceRollView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// 与小程序 ROLL_MS 同一个数:摇完 900ms 才报和(整段编排,不在 CyMotion 五档里;
  /// 字面量登记在 motion_ratchet 白名单)。
  static const Duration _rollSpan = Duration(milliseconds: 900);

  /// 74pt 的骰子(148rpx),两颗各偏 62pt(原型 place())。
  static const double _dieSize = 74;
  static const double _twoDiceOffset = 62;

  late final AnimationController _roll;
  late final CurvedAnimation _eased;
  final PlayKitShakeDetector _shakeDetector = PlayKitShakeDetector();
  StreamSubscription<PlayKitAcceleration>? _acceleration;
  int _count = 1;
  List<int> _values = const <int>[];
  bool _rolling = false;
  bool _applied = false;
  int _sum = 0;
  String _sub = '摇一摇，把骰子扔出去';
  String _hint = '摇一摇手机';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _roll = AnimationController(
      vsync: this,
      duration: _rollSpan,
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) _settle();
      });
    _eased = CurvedAnimation(
      parent: _roll,
      curve: const Cubic(0.3, 0.1, 0.3, 1),
    );
    _count = widget.data.card.maxLength == 2 ? 2 : 1;
    _listenAcceleration();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ★ 首次摆点必须等这一刻:MediaQuery(减动效开关)在 initState 里读不到,
    //   读早了会直接踩框架的断言 —— 而且这条在真机上不报错,只在测试里红。
    if (_applied) return;
    _applied = true;
    _applyValues(parseDiceValues(_cardValues));
  }

  @override
  void didUpdateWidget(PlayKitDiceRollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.card.selectedKey != oldWidget.data.card.selectedKey) {
      _applyValues(parseDiceValues(_cardValues));
    }
  }

  /// 投影把服务端点数编在 selectedKey 里:'4' 或 '5,4'(见 projectPlayKit)。
  List<int> get _cardValues => parseDiceValues(
    widget.data.card.selectedKey
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toList(),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopAcceleration();
    } else if (state == AppLifecycleState.resumed && _acceleration == null) {
      _listenAcceleration();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAcceleration();
    _eased.dispose();
    _roll.dispose();
    super.dispose();
  }

  void _listenAcceleration() {
    if (_acceleration != null) return;
    final PlayKitAccelerationSource source =
        widget.accelerationSource ?? const PlayKitDeviceAccelerationSource();
    _acceleration = source.watch().listen(
      (PlayKitAcceleration event) {
        if (_shakeDetector.feed(
          x: event.x,
          y: event.y,
          z: event.z,
          atMs: event.at.inMilliseconds,
        )) {
          _onRoll();
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  void _stopAcceleration() {
    unawaited(_acceleration?.cancel());
    _acceleration = null;
  }

  void _applyValues(List<int> values) {
    if (values.isEmpty) {
      setState(() {
        _values = const <int>[];
        _rolling = false;
        _sum = 0;
        _sub = '摇一摇，把骰子扔出去';
        _hint = '摇一摇手机';
      });
      return;
    }
    final String sub = values.length == 1
        ? (diceTaskFor(values, _faces).isNotEmpty
              ? diceTaskFor(values, _faces)
              : '摇到 ${values.first}')
        : '${values.join(' + ')}，两颗只比大小';
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _count = values.length == 2 ? 2 : 1;
        _values = values;
        _rolling = false;
        _sum = diceSumOf(values);
        _sub = sub;
        _hint = '再摇一次';
      });
      _haptic();
      return;
    }
    setState(() {
      // 换颗数要把骰子重新摆一遍;滚动这一拍先把点数和清零 ——
      // 骰子还在转就报和,等于结果比动作先到。
      _count = values.length == 2 ? 2 : 1;
      _values = values;
      _rolling = true;
      _sum = 0;
      _sub = sub;
      _hint = '再摇一次';
    });
    _roll.forward(from: 0);
  }

  void _settle() {
    if (!_rolling) return;
    setState(() {
      _rolling = false;
      _sum = diceSumOf(_values);
    });
    _haptic();
  }

  void _haptic() => playKitHaptic(context, PlayKitHaptic.medium);

  List<String> get _faces => <String>[
    for (final PlayKitAction choice in widget.data.card.choices) choice.label,
  ];

  void _onRoll() {
    if (_rolling) return;
    if (!widget.data.enabled || widget.data.acting) return;
    playKitHaptic(context, PlayKitHaptic.light);
    widget.data.onAction?.call(
      PlayKitAction(
        label: '摇一摇',
        action: 'ROLL_DICE',
        payload: const <String, Object?>{},
      ),
    );
  }

  void _onCount(int count) {
    if (count == _count || _rolling) return;
    setState(() {
      _count = count;
      _values = const <int>[];
      _sum = 0;
      _sub = '摇一摇，把骰子扔出去';
      _hint = '摇一摇手机';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '摇一摇手机，或点屏幕扔一次',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onRoll,
          child: Container(
            // ★ 整屏:底下这层必须铺满。只按内容宽收缩的话,右边会露出宿主底色,
            //   「地面」就不是一整块了 —— 快照里一眼看得见(lib 里只有这一屏的
            //   子节点里没有会撑满宽度的东西:分段是 min 宽的行,大字是一条短文案)。
            constraints: const BoxConstraints.expand(),
            // 小程序 .dz 的 `radial-gradient(64% 42% at 50% 58%)`:暖灰的地上
            // 中间稍亮,像顶上有一盏灯。不是平色 —— 平色那盏灯就没了。
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 0.16),
                radius: 1,
                transform: _FeltGlowTransform(),
                colors: <Color>[
                  Color(0xFFF6EAEA),
                  Color(0xFFF3F0EE),
                  Color(0xFFF1F1EF),
                ],
                stops: <double>[0, 0.58, 1],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.space4,
                  CyTokens.pageX,
                  CyTokens.space4,
                  CyTokens.space6,
                ),
                child: Column(
                  children: <Widget>[
                    PlayKitKicker(
                      widget.data.card.eyebrow.isEmpty
                          ? '掷到几就做第几件事'
                          : widget.data.card.eyebrow,
                      color: const Color(0xFF2A2540),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    _segmented(),
                    const SizedBox(height: CyTokens.space2),
                    Expanded(child: _stage()),
                    _output(),
                    const SizedBox(height: CyTokens.space3),
                    PlayKitShakeHintRow(
                      text: _hint,
                      color: const Color(0xFF2A2540).withValues(alpha: 0.5),
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

  /// 一颗 / 两颗:胶囊分段(原型 .dz__seg)。iOS 侧把每一颗的命中区提到
  /// 44pt(L9) —— 原型是 36px,压在可点区域的下限上。
  Widget _segmented() {
    Widget segment(int count, String label) {
      final bool on = _count == count;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onCount(count),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? const Color(0xFFFFFFFF) : null,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              boxShadow: on
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x292A2540),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: on ? const Color(0xFF2A2540) : const Color(0xFF6B6386),
                fontSize: CyType.footnote.fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x142A2540),
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          segment(1, '一颗'),
          const SizedBox(width: CyTokens.space1),
          segment(2, '两颗'),
        ],
      ),
    );
  }

  Widget _stage() {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        for (int index = 0; index < _count; index++) _die(index),
        // 落影:骰子扔到哪就停在哪,影子跟着它(原型 .dz__sh,中心 +37pt)。
        for (int index = 0; index < _count; index++)
          Transform.translate(
            offset: Offset(_dieOffset(index), 37),
            child: Container(
              width: 66,
              height: 16,
              decoration: const BoxDecoration(
                // 真源 `.dz__sh` 逐值:rgba(42, 37, 64, .55) + blur(10rpx=5pt)。
                // Flutter 的 BoxDecoration 没有 backdrop blur,同色柔影描边等效。
                color: Color(0x8C2A2540),
                borderRadius: BorderRadius.all(Radius.circular(8)),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Color(0x8C2A2540), blurRadius: 5),
                ],
              ),
            ),
          ),
      ],
    );
  }

  double _dieOffset(int index) =>
      _count == 2 ? (index == 1 ? _twoDiceOffset : -_twoDiceOffset) : 0;

  Widget _die(int index) {
    final int value = index < _values.length ? _values[index] : 1;
    final double t = _dieProgress(index);
    final double dy = _riseSequence.transform(t);
    final double rotation = _spinSequence.transform(t);
    return Transform.translate(
      offset: Offset(_dieOffset(index), dy),
      child: Transform.rotate(
        angle: rotation * math.pi / 180,
        child: Container(
          width: _dieSize,
          height: _dieSize,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F6F3),
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x242A2540), blurRadius: 18, offset: Offset(0, 8)),
            ],
            border: Border.all(color: const Color(0x142A2540)),
          ),
          child: _pips(dicePipsOf(value)),
        ),
      ),
    );
  }

  double _dieProgress(int index) {
    if (!_rolling) return 1;
    final double delayed = _eased.value - index * 0.06;
    return (delayed / (1 - index * 0.06)).clamp(0.0, 1.0);
  }

  /// 原型 dz-roll 的四段编排:30% 抛起并转 220°,60% 落回转 420°,
  /// 78% 再弹一下,100% 停稳在 720°。
  static final Animatable<double> _riseSequence = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: -23), weight: 30),
      TweenSequenceItem<double>(tween: Tween<double>(begin: -23, end: 0), weight: 30),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: -8), weight: 18),
      TweenSequenceItem<double>(tween: Tween<double>(begin: -8, end: 0), weight: 22),
    ],
  );

  static final Animatable<double> _spinSequence = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: 220), weight: 30),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 220, end: 420), weight: 30),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 420, end: 520), weight: 18),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 520, end: 720), weight: 22),
    ],
  );

  Widget _pips(List<bool> pips) {
    return Column(
      children: <Widget>[
        for (int row = 0; row < 3; row++)
          Expanded(
            child: Row(
              children: <Widget>[
                for (int column = 0; column < 3; column++)
                  Expanded(
                    child: Center(
                      child: pips[row * 3 + column]
                          ? Container(
                              width: 11,
                              height: 11,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2A2540),
                                shape: BoxShape.circle,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _output() {
    return SizedBox(
      height: 78,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (_sum > 0)
            Text(
              '$_sum',
              style: const TextStyle(
                color: Color(0xFF2A2540),
                fontSize: 52,
                fontWeight: FontWeight.w700,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                height: 1,
                letterSpacing: 0,
              ),
            ),
          Text(
            _sub,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF2A2540).withValues(alpha: 0.66),
              fontSize: CyType.subhead.fontSize,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// wxss 那颗光晕是**椭圆**(64% 屏宽 × 42% 屏高),而 Flutter 的 RadialGradient
/// 只有圆 —— 绕圆心压一次,把圆压成同一颗椭圆,而不是把「顶上那盏灯」丢掉。
/// RadialGradient 的 radius 是「短边的几分之几」,取 1 就是短边(竖屏=屏宽),
/// 于是 0.64 横向、`0.42 × 高/宽` 纵向正好落回 wxss 的两个半轴。
class _FeltGlowTransform extends GradientTransform {
  const _FeltGlowTransform();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final Offset center = Offset(
      bounds.left + bounds.width * 0.5,
      bounds.top + bounds.height * 0.58,
    );
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(0.64, 0.42 * bounds.height / bounds.width, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }
}
