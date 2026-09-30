import 'package:flutter/cupertino.dart';

import '../../../core/theme/cy_tokens.dart';
import 'playkit_blindtaste_view.dart';
import 'playkit_musiccorner_view.dart';
import 'playkit_projection.dart';
import 'playkit_sheet_parts.dart';
import 'playkit_slowtask_view.dart';

/// App 端节点玩法呈现层。
///
/// 数据只来自 [PlayKitCard] 的服务端投影；这里不推算通关、不补造二维码、
/// 步数或奖励。交互使用 Cupertino / Liquid Glass 能力分支，几何与 Mini
/// 的玩法组件保持同一信息顺序。
///
/// v5.1 那三件有专属组件的(blindTaste / musicCorner / slowTask)已经拆到各自
/// 文件里 —— 它们各自有独立的三态与交互,挤在这一个文件里三份实现互相看不见。
/// 这个类现在只负责**分发**:按 kind 把卡片交给对应组件,未覆盖的走 [_generic]。
class AdvancedPlayKitView extends StatelessWidget {
  const AdvancedPlayKitView({
    super.key,
    required this.card,
    required this.enabled,
    this.acting = false,
    this.audioPlaying = false,
    this.audioPosition = Duration.zero,
    this.onAction,
    this.onToggleAudio,
  });

  final PlayKitCard card;
  final bool enabled;
  final bool acting;
  final bool audioPlaying;
  final Duration audioPosition;
  final ValueChanged<PlayKitAction>? onAction;
  final VoidCallback? onToggleAudio;

  @override
  Widget build(BuildContext context) => switch (card.kind) {
    PlayKitKind.blindTaste => PlayKitBlindTasteView(
      card: card,
      enabled: enabled,
      acting: acting,
      onAction: onAction,
    ),
    PlayKitKind.musicCorner => PlayKitMusicCornerView(
      card: card,
      enabled: enabled,
      acting: acting,
      audioPlaying: audioPlaying,
      audioPosition: audioPosition,
      onToggleAudio: onToggleAudio,
    ),
    PlayKitKind.slowTask => PlayKitSlowTaskView(
      card: card,
      enabled: enabled,
      acting: acting,
      onAction: onAction,
    ),
    _ => _generic(context),
  };

  Widget _generic(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      PlayKitTitle(card.title),
      if (card.detail.isNotEmpty) ...<Widget>[
        const SizedBox(height: CyTokens.space2),
        Text(
          card.detail,
          style: const TextStyle(
            color: CyTokens.textSecondary,
            fontSize: CyTokens.typeBody,
          ),
        ),
      ],
    ],
  );
}
