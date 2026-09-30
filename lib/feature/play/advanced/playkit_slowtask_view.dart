import 'package:flutter/cupertino.dart';

import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_scratch.dart';
import 'playkit_projection.dart';
import 'playkit_sheet_parts.dart';

/// `slowTask`(跨日慢任务)的专属组件。
///
/// 真源 = 小程序 `pages/play/components/playkit-slowtask/`:
/// 三态由服务端的 `started / claimed / daysLeft` 决定,**组件自己不推算日期**
/// (客户端算「隔天」就等于改手机日期即可提前解锁,判定在服务端)。
/// 未开始 = 一句话 + 一个按钮(低摩擦);等待中 = 只说还要等几天,不秒级倒计时
/// (低压循环,秒级倒计时会制造压力);已就绪 / 已领取各有各的正文。
///
/// 真源「已领取」那屏把正文盖在 `cy-scratch` 刮层下(真源 `playkit-slowtask/
/// index.wxml:25`)—— 仓内已有共享件 [CyScratch],照真源刮开揭示,
/// 不把 `unlockText` 直接摊开。
class PlayKitSlowTaskView extends StatelessWidget {
  const PlayKitSlowTaskView({
    super.key,
    required this.card,
    required this.enabled,
    this.acting = false,
    this.onAction,
  });

  final PlayKitCard card;
  final bool enabled;
  final bool acting;
  final ValueChanged<PlayKitAction>? onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      PlayKitEyebrow(card.eyebrow),
      const SizedBox(height: CyTokens.space2),
      PlayKitTitle(card.title),
      const SizedBox(height: CyTokens.space4),
      if (card.claimed)
        Container(
          padding: const EdgeInsets.all(CyTokens.space3),
          decoration: BoxDecoration(
            color: CyTokens.bgPage,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(color: CyTokens.playKitSlow),
          ),
          // 真源 `playkit-slowtask/index.wxml:25`:领取后内容盖在刮层下
          // (`cy-scratch label="今日进度" threshold="0.4"`)——
          // 「把『看见』变成主动动作」。阈值 0.4 是那一屏自己的值,比默认的 0.55 低。
          child: CyScratch(
            label: '今日进度',
            threshold: 0.4,
            child: Text(
              card.unlockText,
              style: const TextStyle(
                color: CyTokens.textPrimary,
                fontSize: CyTokens.typeBody,
                height: CyTokens.leadingLoose,
              ),
            ),
          ),
        )
      else if (card.started && card.daysLeft > 0)
        Column(
          children: <Widget>[
            // 真源 `.sl__moon`:64pt(128rpx)圆徽,`border: 2rpx solid
            // --cy-color-playkit-slow`,里面是 `<cy-icon name="clock" size="44" />`
            // = 22pt 的**线稿**时钟。填实版(clock_fill)在 64pt 圈里读成一枚
            // 实心蓝盘,把「描边圈 + 图标」的两层结构压成了一层。
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: CyTokens.playKitSlow),
              ),
              child: const Icon(
                CupertinoIcons.clock,
                color: CyTokens.playKitSlow,
                size: 22,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              '还有 ${card.daysLeft} 天',
              style: const TextStyle(
                color: CyTokens.textPrimary,
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (card.detail.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                card.detail,
                textAlign: TextAlign.center,
                // 真源 `.sl__waithint`:label 档 + tertiary。
                style: const TextStyle(
                  color: CyTokens.textTertiary,
                  fontSize: CyTokens.typeLabel,
                ),
              ),
            ],
          ],
        )
      else
        Text(
          card.detail,
          style: const TextStyle(
            color: CyTokens.textSecondary,
            fontSize: CyTokens.typeBody,
            height: CyTokens.leadingLoose,
          ),
        ),
      if (card.primaryAction case final PlayKitAction action) ...<Widget>[
        const SizedBox(height: CyTokens.space4),
        CyNativeButton(
          label: action.label,
          width: double.infinity,
          loading: acting,
          onPressed: enabled && !acting ? () => onAction?.call(action) : null,
        ),
      ],
    ],
  );
}
