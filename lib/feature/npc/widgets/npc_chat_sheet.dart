import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../npc_controller.dart';
import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/ai_generated_note.dart';
import '../../../core/widgets/cy_net_image.dart';

/// 底部弹出的 NPC 追问对话 Sheet。
///
/// ⚠️ **当前无任何入口调用它,这是刻意的,不是漏接。**
/// 后端 `NpcFeatureFlags.chatOn()` 硬编码 `return false`(无形陪伴 V1 不提供自由
/// 追问,No-Go 理由是合规签字未过),`/api/ai/npc/chat` 恒拒。给用户一个点了必
/// 失败的入口比没有入口更坏,所以 `play_session_page` 的冒泡不传 `onTap`。
///
/// 接回的条件:后端放开 chat 轨 **且** App 接上 `/api/config/features`,
/// 由 flag 决定是否传 onTap —— 而不是在这里判。
class NpcChatSheet extends ConsumerStatefulWidget {
  const NpcChatSheet({
    super.key,
    required this.activityId,
    required this.scrollController,
  });

  final int activityId;
  final ScrollController scrollController;

  @override
  ConsumerState<NpcChatSheet> createState() => _NpcChatSheetState();
}

class _NpcChatSheetState extends ConsumerState<NpcChatSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(npcSessionProvider(widget.activityId).notifier).sendChat(text);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(npcSessionProvider(widget.activityId));
    final primary = session.npcs.isNotEmpty ? session.npcs.first : null;
    final CyPalette p = CyPalette.of(context);
    final bool empty = session.history.isEmpty && session.streamDelta == null;

    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(CyTokens.space4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.borderSubtle)),
            ),
            child: Row(
              children: [
                if (primary?.avatar != null)
                  CyNetImage(
                    primary!.avatar,
                    width: 32,
                    height: 32,
                    borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                  ),
                const SizedBox(width: CyTokens.space2_5),
                Text(
                  primary?.name ?? 'NPC',
                  style: CyType.callout.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  'AI 角色',
                  style: CyType.caption2.copyWith(color: p.textTertiary),
                ),
                const SizedBox(width: CyTokens.space2),
                CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 20,
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(CyTokens.space4),
              itemCount: empty
                  ? 1
                  : session.history.length +
                        (session.streamDelta != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (empty) return _empty(p);
                final isStreaming =
                    session.streamDelta != null &&
                    index == session.history.length;
                if (isStreaming) {
                  return _bubble(p, session.streamDelta!);
                }
                return _bubble(p, session.history[index].line);
              },
            ),
          ),
          // ★ 合规:自由追问是真调模型的一轨,产出必须带来源标注。
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CyTokens.space4),
            child: AiGeneratedNote(),
          ),
          // Input
          Container(
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _controller,
                      style: TextStyle(color: p.textPrimary),
                      placeholder: '跟 NPC 聊聊...',
                      placeholderStyle: TextStyle(color: p.textPlaceholder),
                      decoration: BoxDecoration(
                        color: p.bgSurfaceSubtle,
                        borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space4,
                        vertical: CyTokens.space2_5,
                      ),
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      autocorrect: true,
                      enableSuggestions: true,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  CupertinoButton(
                    key: const Key('npc-chat-send'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    color: p.actionPrimaryBg,
                    borderRadius: BorderRadius.circular(22),
                    onPressed: session.loading ? null : _send,
                    child: session.loading
                        ? const CupertinoActivityIndicator()
                        : Icon(
                            CupertinoIcons.paperplane_fill,
                            // 禁用底色是页面附近的中性填充,反色前景压上去没字;
                            // 前景跟着禁用条件切（口径同 ai_draft_sheet 提交钮）。
                            color: session.loading
                                ? p.textPlaceholder
                                : p.actionPrimaryFg,
                            size: 18,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(CyPalette p, String text) {
    // 真源 components/cy/npc-chat `.npc-chat__bubble` max-width:82% ——
    // 不限宽时短消息也撑成满宽横幅,读起来不像对话。280 与姊妹件
    // MerchantNpcChatSheet 同值,两个 NPC 面板的泡宽体系一致。
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          margin: const EdgeInsets.only(bottom: CyTokens.space3),
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space3_5,
            vertical: CyTokens.space2_5,
          ),
          decoration: BoxDecoration(
            color: p.bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          ),
          child: Text(
            text,
            // 真源 `.npc-chat__bubble` font-size: --cy-type-body(17),非常规小一档。
            style: CyType.body.copyWith(color: p.textPrimary, height: 1.4),
          ),
        ),
      ),
    );
  }

  /// 空态文案 1:1 小程序 `components/cy/npc-chat/index.wxml`。
  Widget _empty(CyPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space6),
      child: Text(
        '想知道下一步怎么走？问问我。',
        textAlign: TextAlign.center,
        style: CyType.subhead.copyWith(color: p.textTertiary),
      ),
    );
  }
}

/// 打开 NPC 追问 Sheet 的便捷方法。
Future<void> showNpcChatSheet(BuildContext context, int activityId) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.45,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            NpcChatSheet(
              activityId: activityId,
              scrollController: scrollController,
            ),
  );
}
