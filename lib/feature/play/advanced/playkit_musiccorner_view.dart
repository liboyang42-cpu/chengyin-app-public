import 'package:flutter/cupertino.dart';

import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_native_progress.dart';
import 'playkit_projection.dart';
import 'playkit_sheet_parts.dart';

/// `musicCorner`(治愈音乐角)的专属组件。
///
/// 真源 = 小程序 `pages/play/components/playkit-musiccorner/`:
/// - `index.js`:组件**不持有播放器** —— 音频要跨弹窗生命周期继续播(用户可能
///   收起面板继续走路),播放器归页面,组件只把「播/停」意图往上抛;
/// - `index.wxml`:播放键 + 波形(17 根照抄稿) + `trackName · M:SS` + hint + 进度条。
///
/// ⚠️ 真源里那枚「到点」胶囊挂在 `arrived` 上(`wx:if="{{arrived}}"`),而两端
/// **都没有产生方**(页面组装 kit 时不喂这个字段)。这里不摆一枚恒亮的「到点」——
/// 没数据源的徽标等于替服务端宣布了一件它没说过的事。
class PlayKitMusicCornerView extends StatelessWidget {
  const PlayKitMusicCornerView({
    super.key,
    required this.card,
    required this.enabled,
    this.acting = false,
    this.audioPlaying = false,
    this.audioPosition = Duration.zero,
    this.onToggleAudio,
  });

  final PlayKitCard card;
  final bool enabled;
  final bool acting;
  final bool audioPlaying;
  final Duration audioPosition;
  final VoidCallback? onToggleAudio;

  @override
  Widget build(BuildContext context) {
    final int duration = card.durationSeconds;
    final int position = audioPosition.inSeconds.clamp(0, duration);
    final double progress = duration <= 0 ? 0 : position / duration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PlayKitEyebrow(card.eyebrow),
        const SizedBox(height: CyTokens.space2),
        PlayKitTitle(card.title),
        const SizedBox(height: CyTokens.space3),
        Container(
          padding: const EdgeInsets.all(CyTokens.space3),
          decoration: BoxDecoration(
            color: CyTokens.bgPage,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(color: CyTokens.borderSubtle),
          ),
          child: Row(
            children: <Widget>[
              CyNativeIconButton(
                key: const Key('playkit-music-toggle'),
                label: audioPlaying ? '暂停店主的歌单' : '播放店主的歌单',
                icon: CyNativeButtonIcon(
                  sfSymbol: audioPlaying ? 'pause.fill' : 'play.fill',
                  fallback: audioPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                ),
                size: 64,
                iconSize: 24,
                onPressed: enabled && !acting && card.mediaUrl != null
                    ? onToggleAudio
                    : null,
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    PlayKitWaveform(progress: progress),
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      '${card.detail} · ${playKitFormatTime(position)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CyTokens.textSecondary,
                        fontSize: CyTokens.typeCaption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        Text(
          card.hint,
          style: const TextStyle(
            color: CyTokens.textSecondary,
            fontSize: CyTokens.typeBody,
            height: CyTokens.leadingNormal,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        CyNativeProgress(
          progress: progress.clamp(0.0, 1.0),
          semanticLabel: '店主的歌单播放进度',
          height: 6,
          progressColor: CyTokens.playKitMusic,
          trackColor: CyTokens.borderStrong,
        ),
      ],
    );
  }
}
