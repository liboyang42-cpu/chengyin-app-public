import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// `cy-playkit-timewindow` · 「还没到开播时间」(Figma v5.1,node 45:293)。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-timewindow/`。
/// 结构 1:1:眉标 → 圆牌 + 标题 + 开放时段 → 大倒计时 +「后开播」(页脚 CTA 见下)。
///
/// ## 倒计时只读数,不判开放
/// 到点**不自己开门**:本地时钟玩家改得动,开门与否由服务端说了算。所以归零那一下
/// 只做一件事 —— 请宿主回服务端问一次([PlayKitFullscreenContext.onRefresh])。
/// 真源组件到点 `triggerEvent('open')`,头顶注释写的就是「由页面重新问服务端拿状态」;
/// ⚠️ 但页面的 `onPlayKitAction` 里 `open` 既没有 case、也不在 `ACTION_OF`,
/// 落进 default 后被 `if (!name) return` 吞掉 —— 小程序现状是**到点什么都不做**,
/// 玩家要自己关掉重开一次。App 侧把那句写了没接的意图接上了,是本机多做的一步。
/// 宿主没接这条时就地显示「已到开播时间」,不伪造"已开放"。
///
/// ## 与真源的已知差异(§7.2 accepted)
/// * 页脚那颗「订阅开播提醒」**没有移植**:它调的是微信订阅消息
///   (`wx.requestSubscribeMessage` + 服务端下发模板 id),iOS 侧没有等价物
///   (要 APNs,属新依赖 + 新权限)。这里如实标一行说明,不放一颗按不动的假按钮。
/// * 倒计时**每拍重新对表**,不做 `seconds--` 累加(真源用累加):切后台时定时器
///   会被限频,累加法回来会少算。读数口径不变,只是更准。
/// * 圆牌底色/描边取语义色(`bgSurfaceSubtle` / `borderSubtle`),
///   开放时段那行用 `statusInfo`:真源的 `--cy-color-playkit-night`(#5B8DEF)
///   没进 App 的 token 白名单(生成物已与当前 tokens.wxss 漂移,重生成会带进
///   无关改动),这是「iOS 27 原生化」的配色映射,登记为 accepted。
class PlayKitTimeWindowView extends StatefulWidget {
  const PlayKitTimeWindowView({
    super.key,
    required this.data,
    this.now,
    this.showGrabber = true,
  });

  final PlayKitFullscreenContext data;

  /// 注入时钟,测试用。生产路径就是 `DateTime.now`。
  final DateTime Function()? now;

  /// 宿主用原生 sheet 时关掉:系统自带那条 grabber。
  final bool showGrabber;

  @override
  State<PlayKitTimeWindowView> createState() => _PlayKitTimeWindowViewState();
}

class _PlayKitTimeWindowViewState extends State<PlayKitTimeWindowView> {
  Timer? _ticker;

  /// 开播时刻。`openFrom` 不是 "HH:mm" 时为 null —— 宁可不倒计时,
  /// 也不拿坏数据算出一个假读数。
  DateTime? _target;
  bool _reached = false;

  /// 到点只回问服务端一次(重取回来的状态若仍是未开放,由玩家点「重新检查」)。
  bool _rechecked = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant PlayKitTimeWindowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 卡片换了 = 服务端状态被重取过,重新对一次表(真源 `observers` 同口径)。
    // 判据只看 `openFrom`:状态每重取一次清单对象都是新的,按对象比会在
    // 「到点、已问过服务端、回话还没变」时把 at-zero 的读数打回一个新的倒计时。
    if ('${oldWidget.data.card.kit['openFrom'] ?? ''}' !=
        '${widget.data.card.kit['openFrom'] ?? ''}') {
      _arm();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _arm() {
    _ticker?.cancel();
    _ticker = null;
    _rechecked = false;
    _reached = false;
    final DateTime now = _now;
    final int seconds = playKitSecondsUntilOpen(
      '${widget.data.card.kit['openFrom'] ?? ''}',
      now,
    );
    if (seconds <= 0) {
      _target = null;
      return;
    }
    _target = now.add(Duration(seconds: seconds));
    _ticker = Timer.periodic(kCountdownTickInterval, (Timer _) => _tick());
  }

  void _tick() {
    final DateTime? target = _target;
    if (target == null) return;
    if (target.difference(_now).inSeconds > 0) {
      setState(() {});
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    setState(() => _reached = true);
    // 宿主正忙时不插队(它手上那次动作还没回来,重取会把状态换掉);
    // 等它空下来,「重新检查」那颗按钮会自己亮起来。
    if (!_rechecked && widget.data.enabled) {
      _rechecked = true;
      widget.data.onRefresh?.call();
    }
  }

  int get _remainSeconds {
    final DateTime? target = _target;
    if (target == null) return 0;
    final int remain = target.difference(_now).inSeconds;
    return remain > 0 ? remain : 0;
  }

  void _recheck() {
    if (!widget.data.enabled) return;
    widget.data.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final PlayKitCard card = widget.data.card;
    final String eyebrow = card.eyebrow.isEmpty ? '时段限定' : card.eyebrow;
    final String glyph = '${card.kit['glyph'] ?? '🌙'}';
    final String openFrom = '${card.kit['openFrom'] ?? '--:--'}';
    final String openTo = '${card.kit['openTo'] ?? '--:--'}';
    final String clock = playKitClockText(_remainSeconds);
    final bool canRecheck =
        widget.data.enabled && widget.data.onRefresh != null;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CyTokens.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space5,
        CyTokens.space2,
        CyTokens.space5,
        CyTokens.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.showGrabber)
            Center(
              child: Semantics(
                label: '下滑关闭',
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(top: CyTokens.space1),
                  decoration: BoxDecoration(
                    color: palette.borderStrong,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space3),
          Text(
            eyebrow,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: CyTokens.typeCaption,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.bgSurfaceSubtle,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Text(
                  glyph,
                  style: const TextStyle(fontSize: CyTokens.typeSectionTitle),
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      card.title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: CyTokens.typeSectionTitle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      '开放时段 $openFrom – $openTo',
                      style: TextStyle(
                        color: palette.statusInfo,
                        fontSize: CyTokens.typeBody,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: PlayKitBigFigure(
                  text: clock,
                  size: 44,
                  color: palette.textPrimary,
                  semanticsLabel: _reached ? '已到开播时间' : '距开播还剩 $clock',
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              Flexible(
                child: Text(
                  _reached ? '已到开播时间' : '后开播',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: CyTokens.typeBody,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space4),
          Text(
            'App 端不提供开播提醒（小程序的订阅消息在 iOS 上没有等价物）',
            style: TextStyle(
              color: palette.textTertiary,
              fontSize: CyTokens.typeLabel,
              height: CyTokens.leadingNormal,
            ),
          ),
          if (_reached) ...<Widget>[
            const SizedBox(height: CyTokens.space4),
            CupertinoButton.filled(
              minimumSize: const Size(kPlayKitMinTapTarget, CyTokens.btnH),
              onPressed: canRecheck ? _recheck : null,
              child: const Text('重新检查'),
            ),
          ],
        ],
      ),
    );
  }
}
