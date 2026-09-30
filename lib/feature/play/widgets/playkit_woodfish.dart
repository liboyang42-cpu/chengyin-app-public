import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../data/models/checkin_models.dart';

/// `cy-playkit-woodfish` · 赛博木鱼(Figma v5.1,node 48:283)。
///
/// 真源:`pages/play/components/playkit-woodfish/{index.wxml,index.wxss,index.js}`。
///
/// ★ **不判定通关**(真源注释原文),所以计数是纯陪伴:敲一下本地 +1,由宿主
///   `setData`(`pages/play/index.js:4745-4748`),不落库、不上报 ——
///   「前端不替它上报,也就没有『敲 1000 下刷分』这条路」。因此这个组件没有网络、
///   也没有空/错/载三态:它就是一块可敲的木鱼。计数**不在组件里**:真源由页面持有
///   (`woodfishCount`),组件只抛 `knock`;App 侧同款,宿主拿着 [count] 传进来。
///
/// 逐值对齐 wxss(1rpx = 0.5pt):台面 300×208rpx、木鱼身 84×72(椭圆)、
/// 开口 44×6、木槌 52×7 `rotate(-36°)`(敲击时 -8°、origin 左端中心)、红点 10、
/// 「功德 +1」600ms(=[CyMotion.celebrate],与真源 `KNOCK_MS` 同源 token)上浮淡出。
///
/// 已知差异(iOS 27 原生化,见 `docs/ios27-design-language.md` §7.2):
/// * 木鱼身真源是 `images/playkit-woodfish.svg`(92% 白椭圆 + 深描边)—— 这里用
///   同一组几何直接画,不引 `flutter_svg`(AGENTS.md:新第三方包 Ask first);
/// * w900 计数按手册 T3 收成 bold、字重差异属「iOS 27 原生化」
///   (门禁 `type_weight_ratchet_test` 卡 w800+ 上限)。
class PlayKitWoodfish extends StatefulWidget {
  const PlayKitWoodfish({
    super.key,
    required this.count,
    required this.onKnock,
    this.caption = defaultCaption,
  });

  /// 已敲次数(真源 `properties.count`,由宿主持有)。
  final int count;

  /// 敲一下(真源 `triggerEvent('knock', { count: count + 1 })` — 页面自己 +1)。
  final VoidCallback onKnock;

  /// 副文案(真源 `properties.caption` 的同一句默认值)。
  final String caption;

  static const String defaultCaption = '今晚的烦恼,敲一下少一个';

  /// 节点卡挂不挂木鱼的**唯一判据** —— 与真源
  /// `wx:if="{{sheet.node.ambient === 'woodfish'}}"`(index.wxml:962)同一条,
  /// 调用方不要另造条件。名字大小写敏感、不认识即不存在。
  static bool visibleFor(PlayNode node) =>
      node.ambient == kPlayKitWoodfishAmbient;

  /// 氛围件名字由服务端下发(见 [PlayNode.ambient]);服务端改名要同步改这里。
  static const String kPlayKitWoodfishAmbient = 'woodfish';

  @override
  State<PlayKitWoodfish> createState() => _PlayKitWoodfishState();
}

class _PlayKitWoodfishState extends State<PlayKitWoodfish> {
  /// 木槌回弹与飘字的总时长,与真源 `KNOCK_MS = 600` 同源(`--cy-motion-celebrate`)。
  static const Duration _knockMs = CyMotion.celebrate;

  bool _knocking = false;
  Timer? _knockTimer;

  @override
  void dispose() {
    // 真源 lifetimes.detached 同一手:页面走了别留着定时器。
    _knockTimer?.cancel();
    super.dispose();
  }

  /// 连点不排队:重置这一次的飘字,不让 N 个动画叠在一起(真源 clearTimeout)。
  void _onKnock() {
    _knockTimer?.cancel();
    setState(() => _knocking = true);
    _knockTimer = Timer(_knockMs, () {
      _knockTimer = null;
      if (mounted) setState(() => _knocking = false);
    });
    // 真源 motion.haptic 默认 light,且 reducedMotion 时整个不发
    // (utils/motion.js:116 `haptic: reduced ? null : 'light'`)—— 触感也归动效。
    if (!MediaQuery.disableAnimationsOf(context)) {
      HapticFeedback.lightImpact();
    }
    widget.onKnock();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    return Container(
      // 真源 `.wf`:底色 play-surface-subtle #111111(恒暗道具语言,同
      // `_kWfInk` 的先例做法)、radius-lg、space-3 内边距、功德金 28% 描边(2rpx=1pt)。
      decoration: BoxDecoration(
        color: _kWfSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: _kWfMerit.withValues(alpha: 0.28)),
      ),
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _kWfStageW,
            height: _kWfStageH,
            child: Semantics(
              button: true,
              // 真源 aria-label 原话(全角逗号);台面之外那几个件全是 aria-hidden。
              label: '敲一下木鱼，当前功德 ${widget.count}',
              excludeSemantics: true,
              // 真源 bindtap 挂在 .wf__stage 上:整块台面都要接得住点击。
              child: GestureDetector(
                key: const ValueKey<String>('woodfish-stage'),
                behavior: HitTestBehavior.opaque,
                onTap: _onKnock,
                child: _Stage(knocking: _knocking, reduced: reduced),
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '×${widget.count}',
                  style: const TextStyle(
                    // 真源 `.pk-figure` + `.wf__count`:60rpx=30pt、italic、w900→bold、lh 1。
                    color: _kWfMerit,
                    fontSize: 30,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    height: 1,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                // 真源 `--cy-type-label`(24rpx=12pt)= iOS 梯级的 Caption1。
                Text(
                  widget.caption,
                  style: CyType.caption1.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: CyTokens.space1),
                // 真源 `--cy-type-micro`(20rpx=10pt),低于 HIG 下限 11pt,
                // 按手册取 Caption2。
                Text(
                  '剧情氛围件 · 不判定通关',
                  style: CyType.caption2.copyWith(color: palette.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 台面:木鱼身 + 开口 + 木槌 + 红点 + 飘字(真源 `.wf__stage`)。
/// 尺寸逐值照抄 wxss 的 rpx ×0.5,不改比例。
class _Stage extends StatelessWidget {
  const _Stage({required this.knocking, required this.reduced});

  final bool knocking;
  final bool reduced;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      // 木鱼身:真源 `images/playkit-woodfish.svg` —— 84×72 椭圆,92% 白 + 3px 深描边。
      Positioned(
        left: 4, // 8rpx
        top: 31, // 62rpx
        child: Container(
          width: _kWfBodyW,
          height: _kWfBodyH,
          decoration: BoxDecoration(
            color: CupertinoColors.white.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.all(
              Radius.elliptical(_kWfBodyW / 2, _kWfBodyH / 2),
            ),
            border: Border.all(color: _kWfInk, width: 3),
          ),
        ),
      ),
      // 木鱼开口:稿 48:286 的深色横杠(88×12rpx)。
      Positioned(
        left: 24,
        top: 81,
        child: _Bar(width: 44, height: 6, color: _kWfInk),
      ),
      // 木槌:稿 48:287,静置 -36° → 敲击 -8°。起点必须落在木鱼身内 ——
      // 深色槌压在浅色木鱼上才看得见(真源 2026-08-26 实拍结论)。
      Positioned(
        left: 70,
        top: 48,
        child: AnimatedRotation(
          turns: (knocking ? -8 : -36) / 360,
          duration: reduced ? Duration.zero : CyMotion.fast,
          curve: Curves.easeOut,
          alignment: Alignment.centerLeft,
          child: _Bar(width: 52, height: 7, color: _kWfInk),
        ),
      ),
      // 红点:敲击命中点。保持 danger 红 —— 它是「有新的」提示语义,不是身份色。
      Positioned(
        left: 120,
        top: 5,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: CyTokens.statusDanger,
            shape: BoxShape.circle,
          ),
        ),
      ),
      if (knocking)
        Positioned(
          left: 30,
          top: 7,
          child: _MeritFloat(reducedMotion: reduced),
        ),
    ],
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
    ),
    child: SizedBox(width: width, height: height),
  );
}

/// 「功德 +1」飘字:出现即上浮淡出,只放一次(真源 `@keyframes wf-merit`)。
/// 0% 透明/下 6pt → 40% 全亮/上 3pt → 100% 透明/上 16pt,三档都带 rotate(4°)。
/// 减动效时真源是 `.wf__stage--static .wf__merit { animation: none }` —— 静态显示,不动。
class _MeritFloat extends StatelessWidget {
  const _MeritFloat({required this.reducedMotion});

  final bool reducedMotion;

  static const TextStyle _style = TextStyle(
    color: _kWfMerit,
    // 真源 `--cy-type-body`(28rpx=14pt)+ w900→bold。
    fontSize: CyTokens.typeBody,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    const Widget text = Text('功德 +1', style: _style);
    if (reducedMotion) return text;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: _PlayKitWoodfishState._knockMs,
      curve: Curves.easeOut,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: (t < 0.4 ? t / 0.4 : (1 - t) / 0.6).clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: math.pi / 45, // 真源 keyframes 的 rotate(4deg)
          child: Transform.translate(
            offset: Offset(
              0,
              t < 0.4 ? 6 - 9 * (t / 0.4) : -3 - 13 * ((t - 0.4) / 0.6),
            ),
            child: child,
          ),
        ),
      ),
      child: text,
    );
  }
}

/// 台面尺寸(真源 `.wf__stage` 300×208rpx),逐值 ×0.5。
const double _kWfStageW = 150;
const double _kWfStageH = 104;
const double _kWfBodyW = 84;
const double _kWfBodyH = 72;

/// 逐值道具色(真源 `style/tokens.wxss`):这一屏恒为**玩家暗色**(道具语言),
/// 不跟主题翻转 —— 同先例 `playkit_stopwatch_view.dart` 的 `_kSwInk`。
const Color _kWfInk = Color(0xFF090909); // --cy-color-play-ink
const Color _kWfSurface = Color(0xFF111111); // --cy-color-play-surface-subtle
const Color _kWfMerit = Color(0xFFE8B44A); // --cy-color-playkit-merit 功德金
