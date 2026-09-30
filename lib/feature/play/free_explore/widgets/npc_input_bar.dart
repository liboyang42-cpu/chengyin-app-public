// 店铺分身对话的输入条(屏④底部)。逐条照搬小程序 `index.wxml:556-572`
// 与 `index.wxss:1735-1750`。
//
// ★ 样机注释,照抄别改:「按住说话:和打字**并列在同一条输入框里**,所以
//   『点了语音回不了打字』在结构上不成立」。⇒ 麦克风是输入框里的一个入口,
//   不是一个把输入框换掉的模式开关;录音时打字框照样能打。
//
// ⚠️ 本文件**只做 UI 与回调,不接录音实现**(那是批 4-6)。
//   麦克风靠 [NpcInputBar.onVoice] 决定渲不渲染:没人接实现就整个不画 ——
//   留一个点了没反应的按钮比没有按钮更坏。

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';

/// 打字框上限(样机 `maxlength="200"`)。
const int kNpcInputMaxLength = 200;

/// 麦克风**可见圆**的直径(样机 `.fx-npc__mic{width:56rpx}` = 28pt)。
///
/// ⚠️ 命中区不是这个数 —— 44pt 靠外面那层透明盒撑,不靠把圆画大
/// (样机那个 28pt 的命中区本身是不达标的,App 侧补上)。
const double _kMicDotSize = 28;

/// 输入条:打字 + 发送 + 按住说话。
///
/// 框里的文字**归自己管**(样机把 `shopNpc.input` 放在页面 data 里,但重答那条
/// 明确「不写回输入框」,所以页面并不需要读它)—— 页面少一次逐键重建。
class NpcInputBar extends StatefulWidget {
  const NpcInputBar({
    super.key,
    required this.npcName,
    required this.onSend,
    this.onFocus,
    this.onVoice,
    this.recording = false,
    this.thinking = false,
  });

  /// 占位文案里的名字:`问问{名}…`。
  final String npcName;

  /// 发送:回车或点发送键。发出去之后框自己清空。
  ///
  /// 文本已 `trim`,且保证非空(样机 `sendShopNpc` 先 trim 再判)。
  final void Function(String text) onSend;

  /// 输入框拿到焦点(样机 `bindfocus` → `shopNpc.started`):开场那句居中大字
  /// 该让位了。**页面自己够不着这条边** —— FocusNode 归本组件。
  final VoidCallback? onFocus;

  /// 按住说话。`true`=按下开始,`false`=松开或手势被打断结束。
  ///
  /// ⚠️ **可空,而且空的时候整个麦克风都不渲染**:批 4-5 只出 UI 与回调,
  /// 录音实现在批 4-6。没接上就别画,不要留一个点了没反应的按钮。
  final void Function(bool holding)? onVoice;

  /// 正在录音(由页面持有,因为录音器归页面管)。
  /// 置位后占位文案换成「正在听…松开发送」,输入框与麦克风一起高亮。
  final bool recording;

  /// 正在等分身回答。样机 `sendShopNpc` / `onVoiceStart` 见 `thinking` 就早退。
  ///
  /// ⚠️ 早退时**框里的字要原样留着** —— 发被挡下了却把框清了,等于玩家白打一遍。
  final bool thinking;

  @override
  State<NpcInputBar> createState() => _NpcInputBarState();
}

class _NpcInputBarState extends State<NpcInputBar> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // ⚠️ 用 FocusNode 而不是 `CupertinoTextField.onTap`:样机 `bindfocus` 管的是
    // **拿到焦点**这件事,点一下只是其中一条路(软键盘、Tab、程序化聚焦都算)。
    _focus.addListener(() {
      if (_focus.hasFocus) widget.onFocus?.call();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canSend => _ctrl.text.trim().isNotEmpty && !widget.thinking;

  void _send() {
    if (!_canSend) return;
    widget.onSend(_ctrl.text.trim());
    _ctrl.clear();
  }

  void _hold(bool holding) {
    // ★ 闸只挂在**按下**那条边。样机 `onVoiceStart`(index.js:1296)判 `thinking`
    //   早退,而 `onVoiceEnd`(:1317)判的是 `recording`、**不判 `thinking`** ——
    //   收尾那条边永远放行,重复收尾由录音器自己的 `if (!_recording) return` 挡。
    //
    //   两条边都挡的话:按住麦克风的同时另一根手指点发送(或软键盘 send)
    //   ⇒ `thinking` 变真,此时松手 `_hold(false)` 早退,`ShopNpcVoice.stop()`
    //   **永远不被调用** ⇒ 录音挂到 60 秒上限才自己停,再把那 60 秒传上去。
    //   这正是下面 `onTapCancel` 那句注释所防的事,只是这条路没堵上。
    if (holding && widget.thinking) return;
    widget.onVoice?.call(holding);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasVoice = widget.onVoice != null;
    return Padding(
      // 样机 `.fx-npc__bar{padding:space4 pageX calc(space4 + safe-area-inset-bottom)}`。
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        CyTokens.space4 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              key: const Key('npc-input-pill'),
              height: CyTokens.btnH,
              // 麦克风那 44pt 的命中盒自带 8pt 透明外扩,所以右内边距只留 space2,
              // 可见圆到边仍是样机的 space4;没有麦克风时右边补回 space4。
              padding: EdgeInsets.only(
                left: CyTokens.space4,
                right: hasVoice ? CyTokens.space2 : CyTokens.space4,
              ),
              decoration: BoxDecoration(
                color: widget.recording
                    ? CyTokens.bgSurfaceStrong
                    : CyTokens.bgElevated,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: CupertinoTextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      maxLength: kNpcInputMaxLength,
                      // 样机 `confirm-type="send"`。
                      textInputAction: TextInputAction.send,
                      onSubmitted: (String _) => _send(),
                      // 逐键只是为了让发送键跟着亮灭,值本身不外传。
                      onChanged: (String _) => setState(() {}),
                      placeholder: widget.recording
                          ? '正在听…松开发送'
                          : '问问${widget.npcName}…',
                      placeholderStyle: const TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: CyTokens.textTertiary,
                      ),
                      style: const TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: CyTokens.textPrimary,
                      ),
                      padding: EdgeInsets.zero,
                      decoration: null,
                    ),
                  ),
                  if (hasVoice)
                    _Mic(recording: widget.recording, onHold: _hold),
                ],
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          _SendButton(enabled: _canSend, onPressed: _send),
        ],
      ),
    );
  }
}

/// 按住说话。
///
/// 用 [GestureDetector] 而不是 `CupertinoButton`:后者只在抬手那一下回调,
/// 拿不到「按下」这条边 —— 而这个按钮的语义就是按下与抬起两件事
/// (样机 `bindtouchstart` / `bindtouchend` / `bindtouchcancel`)。
class _Mic extends StatelessWidget {
  const _Mic({required this.recording, required this.onHold});

  final bool recording;
  final void Function(bool holding) onHold;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '按住说话',
      button: true,
      child: GestureDetector(
        key: const Key('npc-input-mic'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails _) => onHold(true),
        onTapUp: (TapUpDetails _) => onHold(false),
        // ⚠️ 打断也要收尾,否则录音一直挂着,玩家松了手却还在录。
        onTapCancel: () => onHold(false),
        child: SizedBox(
          // 命中区 44pt;可见圆仍是样机的 28pt。
          width: CyTokens.btnH,
          height: CyTokens.btnH,
          child: Center(
            child: Container(
              key: const Key('npc-input-mic-dot'),
              width: _kMicDotSize,
              height: _kMicDotSize,
              decoration: recording
                  ? const BoxDecoration(
                      color: CyTokens.textPrimary,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Icon(
                // ⚠️ 样机拿 `phone` 字形顶麦克风,是因为它那套图标集(生成物,不许手改)
                // 里**没有**麦克风;`CupertinoIcons` 里有真的,不用顶。
                CupertinoIcons.mic_fill,
                size: 15,
                color: recording ? CyTokens.textInverse : CyTokens.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 发送。空输入时置灰(样机 `.fx-npc__send.is-off{opacity:.35}`)且点了不发。
class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      key: const Key('npc-input-send'),
      padding: EdgeInsets.zero,
      minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
      pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.4,
      onPressed: enabled ? onPressed : null,
      child: Opacity(
        key: const Key('npc-input-send-dim'),
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: CyTokens.btnH,
          height: CyTokens.btnH,
          decoration: const BoxDecoration(
            color: CyTokens.textPrimary,
            shape: BoxShape.circle,
          ),
          child: Semantics(
            label: '发送',
            button: true,
            child: Icon(
              CupertinoIcons.arrow_right,
              size: 15,
              color: enabled ? CyTokens.textInverse : CyTokens.textPlaceholder,
            ),
          ),
        ),
      ),
    );
  }
}
