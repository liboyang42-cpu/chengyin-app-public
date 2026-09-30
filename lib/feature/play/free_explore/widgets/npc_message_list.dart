// 店铺分身对话的消息流(屏④中段)。逐条照搬小程序 `index.wxml:539-556`
// 与 `index.wxss:1721-1734`。
//
// ★ 样机注释,照抄别改:「**对方消息不套气泡**(裸正文 + 操作行),我方才是右侧胶囊
//   —— 与 ChatGPT / assistant-ui 的分工一致」。
//   对方也套上气泡,这一屏就成了「双方对称的聊天软件」,而不是「分身在跟你说话」。
//
// ★ 操作行**用文字不用图标**:图标集是生成物(`scripts/ds-build-icons.py`,源 coolicons)
//   **不许手改**,里面没有「复制」这个字形;硬拿别的图标顶会比文字更难认。

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../../../../data/models/shop_npc_models.dart';
import '../shop_npc_logic.dart';

/// 我方胶囊最宽占多少(样机 `.fx-msg--me .fx-msg__t{max-width:78%}`)。
const double _kMineMaxWidthFactor = 0.78;

/// 消息流。滚到底、等待名条、对方那条下面的两个文字操作都在这里。
///
/// 只做展示与回调 —— 复制到剪贴板、重答发请求都由页面接住。
class NpcMessageList extends StatefulWidget {
  const NpcMessageList({
    super.key,
    required this.messages,
    required this.npcName,
    this.thinking = false,
    this.onCopy,
    this.onRetry,
  });

  final List<ShopNpcMessage> messages;

  /// 等待名条上的名字:`{名} 正在输入…`。
  final String npcName;

  /// 正在等分身回答。
  final bool thinking;

  /// 「复制」:把这条回答原文带走(分身说的常是地址/年份/暗号,记不住)。
  final void Function(String text)? onCopy;

  /// 「重答」:参数是这条回答在 [messages] 里的**下标**,与样机 `data-idx` 同源 ——
  /// 页面拿它去 `retryQuestionFor` 往前找最近的我方提问。
  final void Function(int index)? onRetry;

  @override
  State<NpcMessageList> createState() => _NpcMessageListState();
}

class _NpcMessageListState extends State<NpcMessageList> {
  final ScrollController _controller = ScrollController();

  /// 等待名条的第二拍:false =「正在输入…」/ true =「正在回答」。
  bool _thinkPhase = false;
  Timer? _beat;

  @override
  void initState() {
    super.initState();
    if (widget.thinking) _startBeat();
    _scheduleScrollToEnd();
  }

  @override
  void didUpdateWidget(NpcMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thinking != oldWidget.thinking) {
      if (widget.thinking) {
        _startBeat();
      } else {
        _stopBeat();
      }
    }
    // ⚠️ 判据是「最后一条是不是换了」,不是「条数变了」:重答是**原地改写**
    // (id 不变、条数不变),那种时候不该硬把列表拽到底 —— 玩家可能正在往回翻。
    final ShopNpcMessage? last = widget.messages.isEmpty
        ? null
        : widget.messages.last;
    final ShopNpcMessage? was = oldWidget.messages.isEmpty
        ? null
        : oldWidget.messages.last;
    //
    // ⚠️⚠️ **`thinking` 不能也算一条滚动理由**(2026-09-10 复审实证)。页面 `_retry`
    //   的真实序列是 `thinking: false → true`(点下那一刻,消息一条没变)→ `false`
    //   + 原地改写:`||` 的右半边在**第一步**就把列表拽到底了 ——
    //   玩家往回翻到第 3 条点「重答」,手指还没抬,正在看的那条已经被拽走。
    //   等待名条只是长在末尾的一行,它自己不构成「有新东西要给你看」;
    //   真的有(打字发送、语音识别回来)那一下 `last.id` 本来就换了,照样滚。
    if (last?.id != was?.id) {
      _scheduleScrollToEnd();
    }
  }

  void _startBeat() {
    _beat?.cancel();
    _thinkPhase = false;
    // 一句话不动地挂着,超过一秒就像卡住了;换一拍是在说「还在,只是慢」。
    _beat = Timer(kThinkPhaseDelay, () {
      if (mounted) setState(() => _thinkPhase = true);
    });
  }

  void _stopBeat() {
    _beat?.cancel();
    _beat = null;
    _thinkPhase = false;
  }

  /// 样机 `scroll-into-view` 钉最后一条。
  void _scheduleScrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_controller.hasClients) return;
      final double end = _controller.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpTo(end);
      } else {
        _controller.animateTo(
          end,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _beat?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.messages.length + (widget.thinking ? 1 : 0);
    return ListView.builder(
      key: const Key('npc-msg-list'),
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      itemCount: count,
      itemBuilder: (BuildContext context, int i) {
        if (i >= widget.messages.length) {
          return _ThinkingLine(npcName: widget.npcName, phase: _thinkPhase);
        }
        final ShopNpcMessage m = widget.messages[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: CyTokens.space4),
          child: m.mine
              ? _MineBubble(message: m)
              : _TheirLine(
                  message: m,
                  onCopy: widget.onCopy,
                  onRetry: widget.onRetry == null
                      ? null
                      : () => widget.onRetry!(i),
                ),
        );
      },
    );
  }
}

/// 对方:**裸正文 + 操作行**,没有气泡。
class _TheirLine extends StatelessWidget {
  const _TheirLine({
    required this.message,
    required this.onCopy,
    required this.onRetry,
  });

  final ShopNpcMessage message;
  final void Function(String text)? onCopy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('npc-msg-ai-${message.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          message.text,
          style: const TextStyle(
            fontSize: CyTokens.typeBody,
            height: 1.72,
            color: CyTokens.textPrimary,
          ),
        ),
        Row(
          key: const Key('npc-msg-ops'),
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            _OpText(
              label: '复制',
              semantics: '复制这条回答',
              onTap: onCopy == null ? null : () => onCopy!(message.text),
            ),
            const SizedBox(width: CyTokens.space3),
            _OpText(label: '重答', semantics: '让他再答一次', onTap: onRetry),
          ],
        ),
      ],
    );
  }
}

/// 一个文字操作。命中区按 44pt 撑开,**靠外扩的透明内边距去够,不是把字号撑大**
/// (样机 `.fx-msg__op{min-height:88rpx; padding:22rpx 20rpx 22rpx 0}`)。
class _OpText extends StatelessWidget {
  const _OpText({
    required this.label,
    required this.semantics,
    required this.onTap,
  });

  final String label;
  final String semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.fromLTRB(0, 11, 10, 11),
      minimumSize: const Size(44, 44),
      pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.4,
      onPressed: onTap,
      child: Semantics(
        label: semantics,
        button: true,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: CyTokens.typeCaption,
            color: CyTokens.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// 我方:右侧胶囊。
class _MineBubble extends StatelessWidget {
  const _MineBubble({required this.message});

  final ShopNpcMessage message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: c.maxWidth * _kMineMaxWidthFactor,
          ),
          child: Container(
            key: Key('npc-msg-me-${message.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: CyTokens.bgElevated,
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            ),
            child: Text(
              message.text,
              style: const TextStyle(
                fontSize: CyTokens.typeBody,
                height: 1.6,
                color: CyTokens.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 等待名条。
class _ThinkingLine extends StatelessWidget {
  const _ThinkingLine({required this.npcName, required this.phase});

  final String npcName;
  final bool phase;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space4),
      child: Text(
        '$npcName ${phase ? '正在回答' : '正在输入…'}',
        key: const Key('npc-msg-thinking'),
        style: const TextStyle(
          fontSize: CyTokens.typeCaption,
          color: CyTokens.textTertiary,
        ),
      ),
    );
  }
}
