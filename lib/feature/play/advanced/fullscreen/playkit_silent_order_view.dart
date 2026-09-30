import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../../../../core/widgets/cy_native_button.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// `cy-playkit-silentorder` · 沉默点单 · 店员见证制。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-silentorder/`
/// (Figma v5.1 node 46:295)。
///
/// ## 判定不在这一屏
/// 真源 `index.js` 头注原文:「计时是『已表演多久』的正计时,**纯陪伴用**:
/// 它不参与判定,判定发生在店员扫见证码那一刻」。所以这一屏没有「通过」按钮,
/// 也没有任何成绩上报 —— 玩家能做的两件事只有「把见证码给店员看」和「认输说话」。
///
/// ## 这一件在小程序里是「半屏 sheet」
/// 它的壳是 `cy-sheet`(带 handle 的半屏),不是 `cy-play-stage` ——
/// 所以**没有**登记进 [kFullscreenPlayKinds],宿主按 sheet 呈现。
/// 宿主用原生 sheet 时把 [showGrabber] 关掉(系统自带那条)。
///
/// ## 与真源的已知差异(§7.2 accepted)
/// * `cy-sheet` 的关闭手势 → App 侧交给系统 sheet 的下滑,组件不再自带「关闭」。
/// * 认输走后端的路真源也没接(`utils/playkit-view.js#ACTION_OF` 里没有
///   `silentorder:giveup`),App 同样只抛给宿主;宿主对这类**真源本来就不发**
///   的 kind 走静默路径(`playkit_host.dart`),与真源同口径 ——
///   停表 + medium 触感,零提示。
class PlayKitSilentOrderView extends StatefulWidget {
  const PlayKitSilentOrderView({
    super.key,
    required this.data,
    this.showGrabber = true,
  });

  final PlayKitFullscreenContext data;

  /// 宿主用原生 sheet 呈现时关掉。
  final bool showGrabber;

  @override
  State<PlayKitSilentOrderView> createState() => _PlayKitSilentOrderViewState();
}

class _PlayKitSilentOrderViewState extends State<PlayKitSilentOrderView> {
  Timer? _ticker;
  int _elapsed = 0;
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    // 服务端给了就从它续(真源:「组件断电重开时从 elapsedSeconds 续」)
    final int seed = _int(_kit['elapsedSeconds']);
    _elapsed = seed > 0 ? seed : 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Map<String, Object?> get _kit => widget.data.card.kit;

  void _giveUp() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _gaveUp = true);
    // 真源 `index.js` 的 onGiveUp:放弃是不可逆的(这一轮表演就结束了),给 medium
    // —— 与「作答」同级。减动效下不震的规矩在 [playKitHaptic] 里,同一条。
    playKitHaptic(context, PlayKitHaptic.medium);
    widget.data.onAction?.call(
      const PlayKitAction(label: '认输说话', action: 'giveup'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final PlayKitCard card = widget.data.card;
    final String eyebrow = card.eyebrow.isEmpty
        ? '沉默点单 · 店员见证制'
        : card.eyebrow;
    final String qrUrl = _text(_kit['qrUrl']);
    final bool canAct = widget.data.enabled && !widget.data.acting;

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
          PlayKitEyebrow(eyebrow, color: palette.textSecondary),
          const SizedBox(height: CyTokens.space2),
          if (card.title.isNotEmpty)
            Text(
              card.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (card.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              card.detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeBody,
                height: CyTokens.leadingNormal,
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space4),
          _QrBox(qrUrl: qrUrl, palette: palette),
          const SizedBox(height: CyTokens.space2),
          Text(
            '见证码 · 店员猜中后扫这里',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textTertiary,
              fontSize: CyTokens.typeCaption,
            ),
          ),
          const SizedBox(height: CyTokens.space4),
          Row(
            children: <Widget>[
              Icon(
                CupertinoIcons.time_solid,
                size: 16,
                color: palette.textSecondary,
              ),
              const SizedBox(width: CyTokens.space1),
              // 正计时,不是倒计时:这一屏没有时限,秒数只说明「表演了多久」
              Text(
                '已表演 ${formatPlayClock(_elapsed)}',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: CyTokens.typeBody,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const Spacer(),
              CyNativeButton(
                key: const Key('playkit-silent-order-giveup'),
                label: '认输说话',
                role: CyNativeButtonRole.secondary,
                onPressed: canAct && !_gaveUp ? _giveUp : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 见证码。服务端没给地址时是真源那句「见证码生成中」——
/// 不补一张假二维码,也不把空盒子画成「加载失败」。
class _QrBox extends StatelessWidget {
  const _QrBox({required this.qrUrl, required this.palette});

  final String qrUrl;
  final CyPalette palette;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 188,
      height: 188,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgPage,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: qrUrl.isEmpty
          ? Center(
              child: Text(
                '见证码生成中',
                style: TextStyle(
                  color: palette.textPlaceholder,
                  fontSize: CyTokens.typeBody,
                ),
              ),
            )
          : CyNetImage(
              qrUrl,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              fallback: Center(
                child: Text(
                  '见证码生成中',
                  style: TextStyle(
                    color: palette.textPlaceholder,
                    fontSize: CyTokens.typeBody,
                  ),
                ),
              ),
            ),
    ),
  );
}

String _text(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}
