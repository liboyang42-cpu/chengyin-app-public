// AI 生成内容的来源标注。
//
// ★★ 这**不是文案偏好,是合规标注**。小程序 club/detail/index.wxml:457
//   那行注释写得很直白:「合规:AI 生成内容来源标注」。
//   《生成式人工智能服务管理暂行办法》要求对生成内容做标识;
//   而对用户来说它还有第二个作用 —— 提醒「这段是机器写的,发出去之前你得看一遍」,
//   因为发出去之后署名的是**用户**,不是 AI。
//
// ⚠️ 三个 AI 产出面(俱乐部 AI 策划 / 主题 AI 起草 / 节点 AI 助手)
//   此前**一处都没标**。收口成一个组件,新增的面天然带上;
//   配套门禁 ai_output_must_be_labeled 拦「有 AI 产出却没标注」。

import 'package:flutter/material.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';

/// 与小程序逐字一致 —— 同一个产品的同一句合规话,不该有两种说法。
const String kAiGeneratedNote = 'AI 生成内容,请核对后再发布';

class AiGeneratedNote extends StatelessWidget {
  const AiGeneratedNote({super.key});

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 12, color: p.textTertiary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              kAiGeneratedNote,
              key: const Key('ai-generated-note'),
              style: TextStyle(
                  fontSize: CyTokens.typeCaption, color: p.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
