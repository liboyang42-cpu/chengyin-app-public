// 店铺分身对话(屏④)。逐条照搬小程序 `.fx-npc`
// (pages/play/index.wxml:520-575 / index.wxss:1688-1750 / index.js:1192-1440)。
//
// 结构自上而下:人形舞台 → 开场问候(压在消息流之上,开口后淡出)→ 消息流 → 输入条。
//
// ★ 样机那一层是 `page-container` 页内层,所以它要自己接管物理返回;
//   App 侧是一条独立的 `CupertinoPageRoute`,系统返回 = pop 本路由 = 收起这一层,
//   语义天然相同,不需要 `PopScope` 再拦一次(拦了反而会把 iOS 侧滑吃掉)。

import 'dart:async';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_native_notice.dart';
import '../../../data/api/account_api.dart';
import '../../../data/api/ai_npc_api.dart';
import '../../../data/models/checkin_models.dart';
import '../../../data/models/shop_npc_models.dart';
import '../play_session_controller.dart';
import 'shop_npc_logic.dart';
import 'shop_npc_voice.dart';
import 'widgets/npc_figure.dart';
import 'widgets/npc_input_bar.dart';
import 'widgets/npc_message_list.dart';

/// 整屏入场:`.fx-npc{ opacity:0; transition:opacity .26s ease }`。
const Duration kShopNpcFade = Duration(milliseconds: 260);

/// 开页 30ms 后才 `is-open`(样机 index.js:1204)。
const Duration kShopNpcOpenDelay = Duration(milliseconds: 30);

/// 舞台顶(`.fx-npc__stage{top:190rpx}`)。
const double kShopNpcStageTop = 95;

/// 问候语与消息流**共用同一个盒子**(`top:760rpx; bottom:300rpx`)——
/// 样机就是这么叠的:开口前大字占住它,开口后大字淡出、消息流露出来。
const double kShopNpcLogTop = 380;
const double kShopNpcLogBottom = 150;

/// 开场问候:`padding:0 72rpx; font-size:46rpx`(这一屏唯一的大字)。
const double kShopNpcHelloPadX = 36;
const double kShopNpcHelloSize = 23;

/// 店铺分身对话页。按 [nodeId] 从 provider 现读节点,不接快照(与屏②/屏③ 同款)。
class ShopNpcPage extends ConsumerStatefulWidget {
  const ShopNpcPage({
    super.key,
    required this.sessionKey,
    required this.nodeId,
    this.voice,
  });

  final PlaySessionKey sessionKey;
  final int nodeId;

  /// 只为测试注入:默认自己 new 一个。真机上没有第二个调用方传它。
  @visibleForTesting
  final ShopNpcVoice? voice;

  @override
  ConsumerState<ShopNpcPage> createState() => _ShopNpcPageState();
}

class _ShopNpcPageState extends ConsumerState<ShopNpcPage> {
  /// ⚠️ 每次改动都**换一个新 List**,不许原地 add ——
  /// [NpcMessageList] 靠 `oldWidget.messages.last.id` 判要不要滚到底,
  /// 原地改的话 old 和 new 是同一个对象,那条判断恒真,**新消息永远不滚到底**。
  List<ShopNpcMessage> _msgs = const <ShopNpcMessage>[];

  bool _thinking = false;

  /// 点过输入框(样机 `bindfocus` → `shopNpc.started`)。
  bool _focused = false;

  /// 整屏渐显。
  bool _open = false;
  Timer? _openTimer;

  /// 问候语只合成一次:它吃 `DateTime.now()`,每帧现算的话跨过整点会当场换一句。
  String? _greeting;

  late final ShopNpcVoice _voice = widget.voice ?? ShopNpcVoice();

  /// 大字让位的判据。
  ///
  /// ★ 样机一共三处置 `started`:`onShopNpcFocus`(index.js:1288)、
  ///   `_beginRecord`(:1314)、`sendShopNpc`(:1357)——
  ///   **按下麦克风那一刻就置**,所以按住说话的那几秒大字已经让开了。
  ///   `_voice.recording` 这一项就是对齐 `_beginRecord` 那处;少了它,
  ///   「已经聊过几句、再按住说话」的那几秒大字会重新压住消息流(`z-index:2`),
  ///   之前的对话看不见。
  bool get _started =>
      _focused || _msgs.isNotEmpty || _thinking || _voice.recording;

  @override
  void initState() {
    super.initState();
    _openTimer = Timer(kShopNpcOpenDelay, () {
      if (mounted) setState(() => _open = true);
    });
  }

  /// 这一页正在拆。
  ///
  /// ⚠️ **`mounted` 顶替不了它**:元素只是「失活」(deactivated)时 `mounted` 仍是
  /// true,而这时 `ref.read` 已经会撞「Looking up a deactivated widget's ancestor
  /// is unsafe」。而失活恰恰早于子树 unmount,也早于本 State 的 `dispose` ——
  /// 「握着麦克风退页」走的就是那个窗口(见 [_uploadVoice])。
  bool _gone = false;

  @override
  void deactivate() {
    _gone = true;
    super.deactivate();
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    // ★ 不停的话麦克风一直被占着,表现是「退出这页之后微信语音也用不了了」。
    //   挂在 dispose 而不是返回钮上:退出的路不止一条(返回钮、iOS 侧滑、系统返回)。
    unawaited(_voice.dispose());
    super.dispose();
  }

  // ── 消息流 ─────────────────────────────────────────────────────────

  ShopNpcMessage _mk(String text, {required bool mine}) =>
      ShopNpcMessage(id: _msgs.length + 1, mine: mine, text: text);

  /// 挂一条分身的回答。[replaceIdx] 传了就**改写**那一条(重答),不传则追加。
  ///
  /// ⚠️ 改写时 **id 原样带过去**(`copyWithText`)—— 换 id 会让列表判成新节点,
  /// 整条重新入场闪一下(样机 index.js:1394)。
  void _pushReply(String text, {int? replaceIdx}) {
    final ShopNpcMessage? target =
        (replaceIdx != null && replaceIdx >= 0 && replaceIdx < _msgs.length)
        ? _msgs[replaceIdx]
        : null;
    _msgs = target != null && !target.mine
        ? (List<ShopNpcMessage>.of(_msgs)
            ..[replaceIdx!] = target.copyWithText(text))
        : <ShopNpcMessage>[..._msgs, _mk(text, mine: false)];
  }

  // ── 问答 ───────────────────────────────────────────────────────────

  void _send(String text) {
    if (_thinking) return;
    setState(() {
      _msgs = <ShopNpcMessage>[..._msgs, _mk(text, mine: true)];
      _focused = true;
      _thinking = true;
    });
    unawaited(_ask(text));
  }

  /// 重答:把这条回答**之前**最近的那句我方提问原样再问一次,新答案改写原来那条。
  void _retry(int index) {
    if (_thinking) return;
    final String? ask = retryQuestionFor(_msgs, index);
    if (ask == null) return; // 前面没有我方提问 ⇒ 连请求都不发
    setState(() => _thinking = true);
    unawaited(_ask(ask, replaceIdx: index));
  }

  /// 打字与重答**共用**这一段 —— 兜底文案的口径只能有一份(样机 `_askShopNpc`)。
  Future<void> _ask(String text, {int? replaceIdx}) async {
    String reply = '';
    String? serverMsg;
    bool offline = false;
    // ★ provider 查找放在 try 外面,口径与 [_uploadVoice] 同一份:它撞的是
    //   「元素已失活」那类框架断言,不是这一次请求失败。塞进 try 会被下面的兜底
    //   `catch (_)` 吞掉 —— 一个真 bug 就此变成「点了没反应」。
    //   今天 `_ask` 只从活着的页面同步进入,不致命;**留两份口径才致命**:
    //   下一个人照这里抄一段异步进入的,就把第 2 类错误静默吞了。
    final AiNpcApi api = ref.read(aiNpcApiProvider);
    try {
      final ShopNpcReply r = await api.shopChat(
        // 后端按 (user, requestId) 幂等:抖动重发不会二次调模型、二次计费。
        requestId: AccountApi.newRequestId(),
        nodeId: widget.nodeId,
        message: text,
      );
      reply = r.text;
    } on ShopNpcException catch (e) {
      // 闸关(403)/内容安全拦截:后端说了话,原样端出去。
      serverMsg = e.message;
    } on DioException catch (_) {
      // ★ 样机这里 `.then()` 没有 `.catch()`,网络失败静默无反应 ——
      //   那是样机的缺陷不是设计意图,不照抄(控制者裁决 2026-09-10)。
      offline = true;
    } catch (e) {
      // ★ 兜底。少了这一支,第三种异常会变成未捕获的异步错误(这一段由 `unawaited`
      //   发起),`_thinking` 永远停在 true:发送键恒置灰、麦克风恒不响应、
      //   底下挂一条「正在回答」不会消失 —— 玩家唯一的出路是退出这一页。
      //   落在「问题没送到」这一档而不是兜底句:这里确实一个字都没拿到。
      // ⚠️ **要记一句**:不记的话第三种异常与「网络不好」在现场完全无法区分,
      //   而它们的下一步动作正好相反(一个要查代码,一个只要等信号)。
      debugPrint('[shop-npc] _ask 兜底异常: $e');
      offline = true;
    }
    if (!mounted) return;

    // ★ 口径②:重答失败**不能覆盖原文**(2026-09-08 实拍)。
    //   「玩家点重答是想要个更好的答案,结果把已经拿到的好答案换成一句『网络异常』,
    //    等于为了再问一次把答案弄丢了」⇒ 保住原文,错误走轻提示。
    if (reply.isEmpty && replaceIdx != null) {
      setState(() => _thinking = false);
      CyNativeNotice.show(context, serverMsg ?? kShopNpcRetryFailed);
      return;
    }
    setState(() {
      _thinking = false;
      // ⚠️ 掉线那一档**不能**落到 `replyTextOr` 的兜底句上:那句是「替分身回答」,
      //   而这里是「问题从来没送到」(与语音那条 `kVoiceNotHeard` 分工同源)。
      _pushReply(
        offline ? kShopNpcNetFailed : replyTextOr(reply, serverMsg),
        replaceIdx: replaceIdx,
      );
    });
  }

  // ── 语音 ───────────────────────────────────────────────────────────

  Future<void> _onVoice(bool holding) async {
    if (holding) {
      await _voice.start(onClip: _uploadVoice, onNotice: _notice);
    } else {
      await _voice.stop();
    }
    if (mounted) setState(() {}); // recording 变了,输入框要换占位文案
  }

  Future<void> _uploadVoice(String path) async {
    // ★ 握着麦克风退页会从**两条**路走到这里,而且都在本 State 还没 `dispose` 之前:
    //   ① `dispose()` → `_voice.dispose()` → `stop()` → `onClip(path)`;
    //   ② 子树 unmount 时 `RawGestureDetectorState.dispose()` 补一次 `onTapCancel`
    //      ⇒ `_hold(false)` → `_onVoice(false)` → `stop()` → 这里。
    //   两条都不该再发一次要花钱的写请求 —— 页面都没了,答案没人看得到。
    if (_gone) return;
    // ★ 上传期间保持 thinking:它是「上传还在飞、玩家又按下去」那道闸
    //   ([ShopNpcVoice] 开下一段时会删掉上一段临时文件)。
    setState(() => _thinking = true);
    // ★ provider 查找**放在 try 外面**:它撞的是「元素已失活」那类框架断言,
    //   不是这一次请求失败。塞进 try 会被下面的兜底 `catch (_)` 吞掉 ——
    //   一个真 bug 就此变成「点了没反应」,再也没人看得见。
    final AiNpcApi api = ref.read(aiNpcApiProvider);
    ShopNpcReply? r;
    String? serverMsg;
    bool offline = false;
    try {
      r = await api.voiceChat(
        requestId: AccountApi.newRequestId(),
        nodeId: widget.nodeId,
        filePath: path,
      );
    } on ShopNpcException catch (e) {
      serverMsg = e.message;
    } on DioException catch (_) {
      offline = true;
    } catch (e) {
      // ★ 兜底,理由同 `_ask`(**含那句 `debugPrint`**)。实证触发点:`AiNpcApi.voiceChat` 里的
      //   `await MultipartFile.fromFile(path, ...)` 在临时文件不在时抛的是
      //   **`PathNotFoundException`,不是 `DioException`**,而且它在 `dio.post`
      //   **之前**求值 —— dio 的包装够不着。临时目录被系统回收、或上一段 clip 已被
      //   `_dropStale()` 删掉,都会命中。
      debugPrint('[shop-npc] _uploadVoice 兜底异常: $e');
      offline = true;
    }
    if (!mounted) return;
    setState(() {
      _thinking = false;
      if (r == null) {
        // 失败**不补我方消息**(样机 `onDone` 的 `!r.ok` 分支就是直接端回答):
        // 没识别出内容,凭空挂一条「（语音）」等于替玩家编了一句他没说过的话。
        _pushReply(offline ? kShopNpcNetFailed : voiceErrorText(serverMsg));
        return;
      }
      // 先补 ASR 原话 ——「玩家要能看见自己被听成了什么」。
      _msgs = <ShopNpcMessage>[..._msgs, _mk(asrMineText(r.asr), mine: true)];
      _pushReply(replyTextOr(r.text, null));
    });
  }

  // ── 操作行 ─────────────────────────────────────────────────────────

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    // 样机 `wx.setClipboardData` 自带系统提示;App 没有,不补一句就是点了没反应。
    _notice('已复制');
  }

  void _notice(String message) {
    // ⚠️ **`mounted` 一个人挡不住**:`CyNativeNotice.show` 第一句就是
    //   `Overlay.of(context, rootOverlay: true)` —— 和 `ref.read` 同样是**祖先查找**,
    //   同样撞「Looking up a deactivated widget's ancestor is unsafe」。
    //   真实触发路径(不是构造的):按住麦克风退页 ⇒ 子树 unmount 时
    //   `RawGestureDetectorState.dispose()` 补一次 `onTapCancel`
    //   ⇒ `_hold(false)` → `_onVoice(false)` → `ShopNpcVoice.stop()`
    //   ⇒ 拿不到文件 / 权限被拒 ⇒ `onNotice(...)` → 这里。
    //   ⚠️ 首次按下弹权限框那一次尤其常见。
    if (_gone || !mounted) return;
    CyNativeNotice.show(context, message);
  }

  // ── 组装 ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final PlayNodesResult? data = ref
        .watch(playSessionProvider(widget.sessionKey))
        .value;
    final PlayNode? node = data?.nodeById(widget.nodeId);
    final PlayNpcBrief? npc = node?.npc;
    if (node == null || npc == null) {
      return const Material(
        color: CyTokens.bgPage,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '这家的分身暂时读不到，返回卡片再试',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CyTokens.textSecondary,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
        ),
      );
    }
    _greeting ??= greetingFor(
      authored: npc.greeting,
      npcName: npc.name,
      shopName: node.name,
      now: DateTime.now(),
    );

    // ★ 键盘避让归本页:`NpcInputBar` 只吃安全区(`padding.bottom`),两个都吃会
    //   重复计算。消息流的底同步抬起,否则输入条上去了、正在说的话还压在键盘下面。
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool still = MediaQuery.disableAnimationsOf(context);

    return Material(
      color: CyTokens.bgPage,
      child: AnimatedOpacity(
        opacity: _open ? 1 : 0,
        duration: still ? Duration.zero : kShopNpcFade,
        child: Stack(
          children: <Widget>[
            Positioned(
              top: kShopNpcStageTop,
              left: 0,
              right: 0,
              child: NpcFigure(npcName: npc.name),
            ),
            Positioned(
              top: kShopNpcLogTop,
              left: 0,
              right: 0,
              bottom: kShopNpcLogBottom + keyboard,
              child: NpcMessageList(
                messages: _msgs,
                npcName: npc.name,
                thinking: _thinking,
                onCopy: _copy,
                onRetry: _retry,
              ),
            ),
            // 开场大字压在消息流之上(`z-index:2`),开口后淡出上移。
            Positioned(
              top: kShopNpcLogTop,
              left: 0,
              right: 0,
              bottom: kShopNpcLogBottom + keyboard,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  key: const Key('npc-hello-fade'),
                  opacity: _started ? 0 : 1,
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  child: AnimatedSlide(
                    offset: _started ? const Offset(0, -0.02) : Offset.zero,
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kShopNpcHelloPadX,
                        ),
                        child: Text(
                          _greeting!,
                          key: const Key('npc-hello'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            // ds-ok 这一屏唯一的大字,比正文再大几档
                            fontSize: kShopNpcHelloSize,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                            color: CyTokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboard,
              child: NpcInputBar(
                npcName: npc.name,
                onSend: _send,
                onFocus: () {
                  if (!_focused) setState(() => _focused = true);
                },
                onVoice: (bool holding) => unawaited(_onVoice(holding)),
                recording: _voice.recording,
                thinking: _thinking,
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top,
              left: CyTokens.pageX,
              child: CyNativeIconButton(
                key: const Key('npc-back'),
                label: '收起，回到卡片',
                icon: const CyNativeButtonIcon(
                  sfSymbol: 'chevron.backward',
                  fallback: CupertinoIcons.back,
                ),
                onPressed: () => Navigator.of(context).pop(),
                size: CyTokens.btnH,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
