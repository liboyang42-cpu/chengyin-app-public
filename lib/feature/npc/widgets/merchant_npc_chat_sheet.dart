import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import '../../../core/media_art_uri.dart';
import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/ai_generated_note.dart';
import '../../../core/widgets/cy_net_image.dart';
import '../merchant_npc_chat_controller.dart';

/// 门店 NPC 对话面板。
///
/// ★★ 与 [NpcChatSheet](漫游/局内轨)是**两个面板**,不是重复:
///   那个围绕 SSE 流式 delta,门店轨是一次 POST 一个完整回复。
///
/// ★ 入口由**开关 + 已过审形象**共同决定,判定在调用方(店铺主页):
///   开关未开时后端返回 403,给一个点了必失败的入口比没有入口更坏。
class MerchantNpcChatSheet extends ConsumerStatefulWidget {
  const MerchantNpcChatSheet({
    super.key,
    required this.merchantId,
    required this.npcName,
    required this.scrollController,
    this.avatar,
    this.greeting,
  });

  final int merchantId;
  final String npcName;
  final String? avatar;

  /// 店铺主页已拿到的招呼语。作为固定首条气泡,不进对话状态。
  final String? greeting;

  final ScrollController scrollController;

  @override
  ConsumerState<MerchantNpcChatSheet> createState() =>
      _MerchantNpcChatSheetState();
}

class _MerchantNpcChatSheetState extends ConsumerState<MerchantNpcChatSheet> {
  final TextEditingController _input = TextEditingController();
  final AudioPlayer _player = AudioPlayer();

  /// 正在播哪条(按消息在列表里的下标)。null = 没在播。
  int? _playingIndex;

  @override
  void dispose() {
    _input.dispose();
    _player.dispose();
    super.dispose();
  }

  /// 播放 / 停止一条回复的语音。
  ///
  /// ★ 播放失败静默收尾:语音是附加能力,它放不出来不该弹错误框打断对话。
  Future<void> _toggleAudio(int index, String url) async {
    if (_playingIndex == index) {
      await _player.stop();
      if (mounted) setState(() => _playingIndex = null);
      return;
    }
    setState(() => _playingIndex = index);
    try {
      // tag = MediaItem 是给 just_audio_background 的锁屏/控制中心元数据,
      // 标题/头像都取 NPC 真实字段。
      await _player.setUrl(
        url,
        tag: MediaItem(
          id: 'npc-chat-${widget.merchantId}-$index',
          title: widget.npcName,
          artUri: mediaArtUri(widget.avatar),
          // 1ms 防炸兜底:just_audio_background 锁屏拖动对 duration! 强解包。
          duration: const Duration(milliseconds: 1),
        ),
      );
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (ProcessingState s) => s == ProcessingState.completed,
      );
    } catch (_) {
      // 静默:见方法注释。
    } finally {
      if (mounted) setState(() => _playingIndex = null);
    }
  }

  /// 招呼语占不占第一格。
  int get _leadCount => (widget.greeting ?? '').trim().isEmpty ? 0 : 1;

  void _send() {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    ref.read(merchantNpcChatProvider(widget.merchantId).notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final MerchantNpcChatState s = ref.watch(
      merchantNpcChatProvider(widget.merchantId),
    );

    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      child: Column(
        children: <Widget>[
          _header(p, t),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(CyTokens.space4),
              itemCount: _leadCount + s.messages.length + (s.sending ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index < _leadCount) {
                  return _bubble(
                    ChatMessage(text: widget.greeting!, fromNpc: true),
                    p,
                    t,
                    -1,
                  );
                }
                final int i = index - _leadCount;
                if (i == s.messages.length) return _typing(p);
                return _bubble(s.messages[i], p, t, i);
              },
            ),
          ),
          // ★ 合规:门店对话是真调模型的一轨,产出必须带来源标注。
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CyTokens.space4),
            child: AiGeneratedNote(),
          ),
          _inputBar(p, s),
        ],
      ),
    );
  }

  Widget _header(CyPalette p, TextTheme t) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          if ((widget.avatar ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              child: CyNetImage(
                widget.avatar,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(width: CyTokens.space2_5),
          Expanded(
            child: Text(
              widget.npcName,
              style: t.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: Icon(CupertinoIcons.xmark, size: 20, color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m, CyPalette p, TextTheme t, int index) {
    final bool npc = m.fromNpc;
    final bool hasAudio = (m.audioUrl ?? '').isNotEmpty;
    final bool playing = _playingIndex == index;
    return Align(
      alignment: npc ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment: npc
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(bottom: CyTokens.space2),
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3_5,
              vertical: CyTokens.space2_5,
            ),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              // 失败气泡用更弱的底色 + 次级文字色:它不是店主说的话。
              color: m.failed
                  ? p.bgSurfaceSubtle
                  : npc
                  ? p.bgSurface
                  : p.brandSoft,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            child: Text(
              m.text,
              style: t.bodyMedium?.copyWith(
                color: m.failed ? p.textSecondary : p.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          if (hasAudio)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CupertinoButton(
                    key: Key('merchant-npc-audio-$index'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(88, 44),
                    onPressed: () => _toggleAudio(index, m.audioUrl!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          playing
                              ? CupertinoIcons.stop_fill
                              : CupertinoIcons.speaker_2_fill,
                          size: 16,
                        ),
                        const SizedBox(width: CyTokens.space1),
                        Text(playing ? '停止' : '听店主说', style: t.bodySmall),
                      ],
                    ),
                  ),
                  // ★★ 合规:合成语音必须有可感知的标识。
                  //   《人工智能生成合成内容标识办法》2025-09-01 起施行。
                  Text(
                    'AI 合成声音',
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          if (m.failed)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space3),
              child: CupertinoButton(
                key: const Key('merchant-npc-retry'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                onPressed: () => ref
                    .read(merchantNpcChatProvider(widget.merchantId).notifier)
                    .retry(),
                child: Text('重试', style: t.bodySmall),
              ),
            ),
        ],
      ),
    );
  }

  Widget _typing(CyPalette p) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: CyTokens.space2),
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3_5,
          vertical: CyTokens.space3,
        ),
        decoration: BoxDecoration(
          color: p.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: const CupertinoActivityIndicator(radius: 8),
      ),
    );
  }

  Widget _inputBar(CyPalette p, MerchantNpcChatState s) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: CupertinoTextField(
                key: const Key('merchant-npc-input'),
                controller: _input,
                placeholder: '问问这家店,比如「有什么推荐」',
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space4,
                  vertical: CyTokens.space2_5,
                ),
                decoration: BoxDecoration(
                  color: p.bgSurfaceSubtle,
                  borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                ),
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            CupertinoButton(
              key: const Key('merchant-npc-send'),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              // 与 [NpcChatSheet] 发送钮同一对 token:brand 在暗端是近白,
              // 白图标压上去直接消失;CTA 底/前景必须成对取。
              color: p.actionPrimaryBg,
              borderRadius: BorderRadius.circular(22),
              onPressed: s.sending ? null : _send,
              child: s.sending
                  ? const CupertinoActivityIndicator()
                  : Icon(
                      CupertinoIcons.paperplane_fill,
                      // 前景跟着禁用条件切,否则禁用态近白字压中性底看不见。
                      color: s.sending ? p.textPlaceholder : p.actionPrimaryFg,
                      size: 18,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 打开门店对话面板。
Future<void> showMerchantNpcChatSheet(
  BuildContext context, {
  required int merchantId,
  required String npcName,
  String? avatar,
  String? greeting,
}) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.2,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            MerchantNpcChatSheet(
              merchantId: merchantId,
              npcName: npcName,
              avatar: avatar,
              greeting: greeting,
              scrollController: scrollController,
            ),
  );
}
