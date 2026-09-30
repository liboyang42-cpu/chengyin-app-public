import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../core/moderation/report_sheet.dart';
import '../../core/widgets/cy_confirm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/map/map_launcher.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_native_action_sheet.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/im_api.dart';
import '../../data/models/im.dart';
import 'chat_review_result_sheet.dart';
import 'im_controller.dart';
import 'im_time.dart';
import 'route_picker_sheet.dart';
import 'chat_card.dart';
import '../topic/topic_detail_controller.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 位置卡「导航过去」的地图唤起。★ 做成 provider 是为了能测:
/// 真跑 url_launcher 在测试环境里没有平台通道
/// (同 `topic_pricing_partner_page.dart` 的 MapLauncher 口径)。
typedef ImMapLauncher =
    Future<MapLaunchResult> Function({
      required double? lat,
      required double? lng,
      required String name,
      String? address,
      required bool isIOS,
    });

final imMapLauncherProvider = Provider<ImMapLauncher>((_) => launchNavigation);

/// 取一张图(相机 / 相册)。★ 做成 provider 是为了能测:
/// 真跑 `ImagePicker` 在测试环境里没有平台通道,**会挂住而不是抛错** ——
/// 一条直接 await 的路径在单测里根本走不完(理由同上面的 MapLauncher)。
typedef ImImagePicker = Future<XFile?> Function(CyImagePickSource source);

final imImagePickerProvider = Provider<ImImagePicker>((_) => _pickChatImage);

Future<XFile?> _pickChatImage(CyImagePickSource source) =>
    ImagePicker().pickImage(
      source: source == CyImagePickSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85, // 与俱乐部/发布域同口径:先压再传
    );

/// IM 聊天页:消息气泡列表(自己右 / 对方左)+ 底部输入框。
/// 拉取最新一页 → 标记已读;发送成功后重拉刷新。不做 WebSocket。
/// 对齐小程序 im/chat:气泡自己=白底黑字(action-primary)、对方=elevated 浅灰,
/// 尾角(8rpx)在气泡靠己侧顶角;时间用 tertiary 灰。
class ImChatPage extends ConsumerStatefulWidget {
  const ImChatPage({
    super.key,
    required this.conversationId,
    this.peerName = '',
    this.peerAvatar = '',
    this.peerMemberId = 0,
    this.liquidGlassSupported,
  });

  final int conversationId;
  final String peerName;
  final String peerAvatar;

  /// 对方的 memberId。★ 拉黑接口要的是它,不是 conversationId。
  ///   为 0 表示上游没带过来 —— 那时拉黑入口必须**隐藏**,
  ///   而不是摆在那里点下去必然失败。
  final int peerMemberId;

  /// 仅供能力分支测试;运行时用系统版本探测(与 `CyNativeButton` / `CyFooterBar` 同口径)。
  final bool? liquidGlassSupported;

  @override
  ConsumerState<ImChatPage> createState() => _ImChatPageState();
}

/// 会话页的五态(小程序 `loadState`)。「还没有消息」**只属于** ready ——
/// 网络失败、会话不存在、组局已结束,是三件不同的事,不能都说成「还没有消息」。
enum _ChatState { loading, ready, error, missing, closed }

class _ImChatPageState extends ConsumerState<ImChatPage>
    with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<ChatMessage> _msgs = <ChatMessage>[];

  /// 没发出去的消息。★ 服务端**没有**本地消息表 —— 失败态只活在这个会话页里,
  /// 离开页面就没了,不会伪装成"发出去过"。
  final List<_Outgoing> _failed = <_Outgoing>[];
  bool _sending = false;

  _ChatState _state = _ChatState.loading;

  /// 「更早消息」分页。对齐小程序 `hasMore / cursor / loadingMore / loadMoreError`:
  /// 游标来自回执 `nextCursor`,失败**不推进游标** —— 否则重试会跳着丢一段历史。
  bool _hasMore = false;
  int _nextCursor = 0;
  bool _loadingMore = false;
  String? _loadMoreError;

  /// 进页之外的新消息:页面可见时 8 秒一轮(小程序 `onShow` 的 setInterval)。
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPoll();
    _load();
  }

  @override
  void dispose() {
    _stopPoll();
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 页面不可见就停表 —— 后台每 8 秒打一次后端是纯耗电。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPoll();
    } else {
      _stopPoll();
    }
  }

  void _startPoll() {
    _stopPoll();
    // 坏链接(拿不到会话 id)不许每 8 秒拿 conversation_id:0 打后端;
    // 已结束的组局是终态,也不会再变。
    if (widget.conversationId <= 0) return;
    if (_state == _ChatState.closed) return;
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _pollNew());
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  int _maxLocalId() {
    int max = 0;
    for (final ChatMessage m in _msgs) {
      if (m.id > max) max = m.id;
    }
    return max;
  }

  /// 轮询增量:`cursor_id:0, size:15`(小程序同参),只留 id 比本地最大 id 新的。
  /// ★ 失败**静默** —— 轮询是锦上添花,弹错会把用户正在看的页面搅乱;
  ///   失败态由下拉刷新 / 重试兜底。
  Future<void> _pollNew() async {
    if (_state == _ChatState.closed || widget.conversationId <= 0) return;
    // 页面被压在栈下(点开卡片详情、或处理结果面板盖着)时不打后端 ——
    // 小程序 `onHide` 会停表;App 没有 onHide,用「是不是当前路由」等效。
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final int maxId = _maxLocalId();
    try {
      final ChatPage page = await ref
          .read(imApiProvider)
          .messages(widget.conversationId, cursorId: 0, size: 15);
      if (!mounted) return;
      // 轮询读到了就是恢复了:一次瞬时失败不该把错误态钉在屏幕上,
      // 让输入栏一直禁用、只能靠用户手点「重试」才活过来。
      final List<ChatMessage> fresh = page.list
          .where((ChatMessage m) => m.id > maxId)
          .toList();
      if (fresh.isEmpty) {
        if (_state != _ChatState.ready) {
          setState(() => _state = _ChatState.ready);
        }
        return;
      }
      setState(() {
        _state = _ChatState.ready;
        _mergeMessages(fresh);
      });
      _scrollToBottom();
      _markRead();
    } catch (_) {
      // 静默:下层已给出的错误态/重试入口不受影响。
    }
  }

  /// 把新到的消息并进列表,按 id 去重(同 id 以新的一份为准)。
  /// [prepend]=true 用于「更早消息」——它们排在当前列表**前面**。
  void _mergeMessages(List<ChatMessage> incoming, {bool prepend = false}) {
    final List<ChatMessage> list = prepend
        ? <ChatMessage>[...incoming]
        : <ChatMessage>[..._msgs];
    final List<ChatMessage> additions = prepend ? _msgs : incoming;
    for (final ChatMessage m in additions) {
      final int index = list.indexWhere((ChatMessage x) => x.id == m.id);
      if (index >= 0) {
        if (!prepend) list[index] = m;
      } else {
        list.add(m);
      }
    }
    _msgs = list;
  }

  Future<void> _load() async {
    // ★ 坏链接(没有会话 id)= missing,不打后端、也不给可用输入栏 ——
    //   它不是「空对话」。小程序同判据(`if (!conversationId) return`)。
    if (widget.conversationId <= 0) {
      setState(() => _state = _ChatState.missing);
      return;
    }
    // 下拉刷新**不切骨架**:列表已经有内容,切走再切回来会跳版(D4),
    // 也让 RefreshIndicator 自己转的那一圈白转。首次进页才走 loading。
    setState(() {
      if (_msgs.isEmpty) _state = _ChatState.loading;
      _loadMoreError = null;
    });
    try {
      final page = await ref
          .read(imApiProvider)
          .messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _state = _ChatState.ready;
        _msgs = page.list;
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor ?? 0;
        _loadMoreError = null;
      });
      _markRead();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final bool closed =
          e is ImApiException && e.errorCode == 'HANGOUT_CLOSED';
      setState(() {
        _state = closed ? _ChatState.closed : _ChatState.error;
        if (closed) _stopPoll();
      });
    }
  }

  /// 加载更早消息(单飞:进行中或没有更多时直接返回)。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _state != _ChatState.ready) return;
    final double beforeMax = _scroll.hasClients
        ? _scroll.position.maxScrollExtent
        : 0;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final ChatPage page = await ref
          .read(imApiProvider)
          .messages(widget.conversationId, cursorId: _nextCursor);
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _mergeMessages(page.list, prepend: true);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor ?? _nextCursor;
      });
      _keepScrollAfterPrepend(beforeMax);
    } catch (e) {
      if (!mounted) return;
      // ★ 失败不动已有消息、不动游标 —— 重试必须还是同一个 cursor,
      //   否则跳着丢一段历史(小程序 `_setLoadMoreError` 同款)。
      setState(() {
        _loadingMore = false;
        _loadMoreError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 更早的消息插在列表上方,内容会整体下移 —— 不补偏移的话,
  /// 用户正读着的那句会被顶出屏幕(D4:加载不跳版)。
  void _keepScrollAfterPrepend(double beforeMax) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final double delta = _scroll.position.maxScrollExtent - beforeMax;
      if (delta <= 0) return;
      _scroll.jumpTo(_scroll.offset + delta);
    });
  }

  Future<void> _markRead() async {
    try {
      await ref.read(imApiProvider).read(widget.conversationId);
      ref.invalidate(imConversationsProvider);
    } catch (_) {
      // 已读失败不打扰用户。
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// 发一张路线卡片。
  ///
  /// ★ 只传 topicId,展示字段由接收方现拉 ——
  ///   把标题塞进 extra_json 的话,路线改名后聊天记录里还是旧名字。
  Future<void> _sendRoute() async {
    final int? topicId = await pickRouteToShare(context);
    if (topicId == null || !mounted || _sending) return;
    await _dispatch(_Outgoing.route(topicId));
  }

  /// 发一条位置:复用发布域选点页 `/publish/poi`(只读复用,不动它那页)。
  ///
  /// ⚠️ 选点页只回 `(name, latitude, longitude)` —— **没有地址**。
  ///   所以 address 只能是空串(卡片上地址那行不渲染),
  ///   而不是拿名字冒充地址、或自己编一个。
  Future<void> _sendLocation() async {
    final ({String name, double latitude, double longitude})? point =
        await context.push<({String name, double latitude, double longitude})>(
          '/publish/poi',
        );
    if (point == null || !mounted || _sending) return;
    await _dispatch(
      _Outgoing.location(
        name: point.name,
        address: '',
        lat: point.latitude,
        lng: point.longitude,
      ),
    );
  }

  /// 发一张图片:选来源 → 取图 → 上传 OSS → 作为 `msg_type=2` 发出。
  ///
  /// ★ 与小程序同一条链:`app.chooseImage` → `/api/common/uploadOSS`
  ///   → `_sendMessage({msg_type:2, content:url})`。
  ///   [anchor] 是「+」的矩形 —— S4:来源选择 sheet 从触发元素弹。
  Future<void> _sendImage(Rect? anchor) async {
    if (_sending) return;
    final CyImagePickSource? source = await cyChooseImageSource(
      context,
      sourceRect: anchor,
    );
    if (source == null || !mounted) return;
    final XFile? file;
    try {
      file = await ref.read(imImagePickerProvider)(source);
    } catch (_) {
      if (!mounted) return;
      CyNativeNotice.show(context, '没能打开相册或相机，请重试', isError: true);
      return;
    }
    if (file == null || !mounted) return;
    final String url;
    try {
      url = await ref.read(imApiProvider).uploadImage(file.path);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    await _dispatch(_Outgoing.image(url));
  }

  /// 「+」= 动作菜单(图片 / 位置 / 路线),对齐小程序 im/chat 的 plus 面板
  /// (`plusSheetItems: ['图片','位置','路线']`)。
  /// 用共用层原生 presenter(iOS 26 玻璃 sheet,测试/旧系统回退 Cupertino)。
  Future<void> _openPlusMenu(Rect? anchor) async {
    if (_sending) return;
    final _PlusAction? action = await showCyNativeActionSheet<_PlusAction>(
      context: context,
      title: '发送',
      actions: const <CyNativeAction<_PlusAction>>[
        CyNativeAction(value: _PlusAction.image, label: '图片'),
        CyNativeAction(value: _PlusAction.location, label: '位置'),
        CyNativeAction(value: _PlusAction.route, label: '路线'),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PlusAction.image:
        await _sendImage(anchor);
      case _PlusAction.location:
        await _sendLocation();
      case _PlusAction.route:
        await _sendRoute();
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    // 闸守在**每个真发出去的出口**上:非 ready(加载中/坏链接/失败/已结束)
    // 一律不发 —— 输入栏虽然已经是可见禁用态,行为层的闸不能只靠它。
    if (_state != _ChatState.ready) return;
    _input.clear();
    await _dispatch(_Outgoing.text(text));
  }

  /// 发送一条消息(文本 / 图片 / 卡片)。★ 全部走**同一条出口** ——
  /// 失败重发必须按原样重发;多份实现迟早分叉成"卡片重发退化成一句「[路线]」"。
  ///
  /// ★ 失败**不再只弹一个 toast**:toast 2.4 秒后消失,用户手上只剩一句
  ///   不知道发没发出去的话(输入框里那份还会被下次输入覆盖掉)。
  ///   失败的消息留在列表里带重试,才是能回答"发出去了没有"的状态。
  Future<void> _dispatch(_Outgoing out) async {
    if (_sending) return;
    if (_state != _ChatState.ready) return;
    setState(() {
      _sending = true;
      _failed.remove(out);
    });
    try {
      final ChatMessage msg = await ref
          .read(imApiProvider)
          .send(
            widget.conversationId,
            // content 是**内容本身**:文本是正文、图片是 URL;卡片是降级文案
            //   ——不认识卡片的客户端至少看到「[路线]」而不是一片空白。
            //   小程序发的是「[卡片]」,这里说得更具体些。
            content: out.content,
            msgType: out.msgType,
            extraJson: out.extraJson,
          );
      if (!mounted) return;
      setState(() {
        _msgs = <ChatMessage>[..._msgs, msg];
        _sending = false;
      });
      _scrollToBottom();
      // §3.9 IM7:发出去了给一次轻触感。★ 只做「发送」这一侧 ——
      // 「收到」需要一个真的到达事件,而本页是下拉/进页刷新的轮询,
      // 没有 WebSocket;把「刷新时多了几条」当成收到,会在用户自己
      // 手动刷新时无端震动一次。
      HapticFeedback.selectionClick();
      ref.invalidate(imConversationsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (!_failed.contains(out)) _failed.add(out);
      });
      // ★ 失败的消息也滚到底 —— 用户往上翻着看历史时发消息失败,
      //   不滚的话失败气泡停在屏幕外,"发出去了没有"照样没人回答。
      _scrollToBottom();
      CyNativeNotice.show(context, '发送失败，点消息上的「重试」再发一次', isError: true);
    }
  }

  /// 拉黑对方。★ 不可逆感很强的动作,先二次确认。
  /// 举报一条消息。
  ///
  /// ⚠️ 提示文案与广场举报同一条纪律:后端只入审核队列、**不立即删消息**,
  ///   所以不能说「已删除」。
  Future<void> _reportMessage(ChatMessage m) async {
    final String? reason = await showReportSheet(context, targetLabel: '这条消息');
    if (reason == null || !mounted) return;
    try {
      final String msg = await ref
          .read(imApiProvider)
          .reportMessage(m.id, reason);
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _blockPeer() async {
    final name = widget.peerName.isNotEmpty ? widget.peerName : '这个用户';
    final bool ok = await cyConfirm(
      context,
      title: '拉黑 $name?',
      content: '拉黑后你将不再收到对方的消息。',
      confirmText: '拉黑',
      danger: true,
    );
    if (ok != true || !mounted) return;
    try {
      final msg = await ref.read(imApiProvider).block(widget.peerMemberId);
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  /// 「更多」= 动作菜单。★ 小程序这一格是「举报 / 拉黑 / 清空聊天」,
  /// 但 App 这边前两项已经有了自己的入口(举报=长按消息、拉黑=导航栏),
  /// 同一个动作两套入口反而更乱(I5:同类动作同词同图标),
  /// 所以这里只留**别处没有的那一件**。
  Future<void> _openMoreMenu() async {
    final String? action = await showCyNativeActionSheet<String>(
      context: context,
      title: '更多',
      actions: const <CyNativeAction<String>>[
        CyNativeAction<String>(
          value: 'clear',
          label: '清空聊天',
          destructive: true,
        ),
      ],
    );
    if (action != 'clear' || !mounted) return;
    await _clearChat();
  }

  /// 清空聊天:`POST /api/im/delete`(清的是**我这一侧**的会话)。
  ///
  /// ⚠️ 动作名「清空聊天」照小程序 `moreSheetItems`(`index.js:11`);警示句
  ///   与消息列表的滑动删除**同一句**(`im_list_page.dart:492`,只把那边的
  ///   「删除」换成这边的动作名)—— 同一个接口同一件事,不能一处说「清空」
  ///   一处说「撤回」。后端**不**清除对方的记录。
  Future<void> _clearChat() async {
    final bool ok = await cyConfirm(
      context,
      title: '清空聊天',
      content: '删除后不会清除对方消息记录，确定清空这条会话吗？',
      confirmText: '清空',
      danger: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(imApiProvider).deleteConversation(widget.conversationId);
      if (!mounted) return;
      ref.invalidate(imConversationsProvider);
      // 回消息列表:清空的会话不该还留在栈里(返回又看到它,像没删掉)。
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/im');
      }
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentMemberIdProvider);
    final title = widget.peerName.isNotEmpty ? widget.peerName : '聊天';
    return CupertinoPageScaffold(
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        // 「拉黑」+「更多」两枚图标钮:各自 44pt 热区、不重叠(I1)。
        // 拉黑仍只在上游真带了 memberId 时出现 —— 摆一个点下去必然失败的
        // 按钮,比没有这个按钮更糟。
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.peerMemberId > 0)
              _navAction(
                label: '拉黑此人',
                icon: CupertinoIcons.nosign,
                onPressed: _blockPeer,
              ),
            _navAction(
              label: '更多',
              icon: CupertinoIcons.ellipsis_circle,
              onPressed: _openMoreMenu,
            ),
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _buildBody(myId)),
              _InputBar(
                controller: _input,
                sending: _sending,
                onSend: _send,
                onPlus: _openPlusMenu,
                liquidGlassSupported: widget.liquidGlassSupported,
                blockedText: _state == _ChatState.ready
                    ? null
                    : _sendBlockedText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 非 ready 时输入栏为什么点不动 —— 按**真实原因**给一句话,不写「不可用」。
  /// 小程序 `sendBlockedMap` 的同款口径。
  String get _sendBlockedText => switch (_state) {
    _ChatState.loading => '消息加载中…',
    _ChatState.missing => '链接已失效，回消息列表重新进入',
    _ChatState.closed => '组局已结束，不能继续聊天',
    _ChatState.error => '消息没加载出来，点上方「重试」再试',
    _ChatState.ready => '',
  };

  /// 导航栏纯图标动作:44pt 热区 + 自己的语义标签 + 独立的点按动作(A2)。
  Widget _navAction({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      enabled: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: CupertinoButton(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ),
    );
  }

  /// 组局已结束的出口:回消息列表。
  /// ⚠️ 后端回执里的 `returnPath` 是**小程序**路径
  ///   (`/subpackageB/pages/im/list/index`),App 里点它是 404 ——
  ///   所以这里一律走 App 自己的消息列表路由。
  void _backToMessageList() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/im');
    }
  }

  Widget _buildBody(int myId) {
    switch (_state) {
      case _ChatState.loading:
        return const CySkeleton(type: CySkeletonType.list, count: 4);
      case _ChatState.missing:
        // 坏链接:不是「空对话」,也不打后端。
        return StatusView(
          message: '这个会话打不开',
          sub: '链接可能已失效，回消息列表重新进入',
          icon: CupertinoIcons.exclamationmark_circle,
          scrollable: true,
        );
      case _ChatState.closed:
        // 组局已结束(后端回执 errorCode=HANGOUT_CLOSED)→ 终态,不是网络错误。
        return StatusView(
          message: '这个组局已结束',
          sub: '聊天已关闭。如有平台处置，可在消息列表的系统通知中查看处理结果。',
          icon: CupertinoIcons.lock,
          large: true,
          scrollable: true,
          onRetry: _backToMessageList,
          retryLabel: '返回消息列表',
        );
      case _ChatState.error:
        return StatusView(
          message: '消息没加载出来',
          sub: '网络或服务暂时不可用,已发出的消息不会丢',
          icon: CupertinoIcons.wifi_slash,
          onRetry: _load,
        );
      case _ChatState.ready:
        break;
    }
    if (_msgs.isEmpty && _failed.isEmpty) {
      return StatusView(
        message: '还没有消息',
        sub: '发送第一条消息,和对方确认路线、集合点或合作细节',
        icon: CupertinoIcons.hand_raised,
        scrollable: true,
      );
    }
    final List<_ChatItem> items = _chatItems();
    // 「加载更早消息」那一行只在真有可能/正在进行/刚失败时出现 ——
    // 没有更多时摆一个点了没反应的入口,和占位按钮是一回事。
    final bool showLoadMore =
        _hasMore || _loadingMore || _loadMoreError != null;
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3,
          vertical: CyTokens.space3,
        ),
        // 没发出去的消息排在最后 —— 它们的时间戳是"现在",
        // 混在历史里会让整条时间线看起来被污染了。
        itemCount: items.length + _failed.length + (showLoadMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (showLoadMore && i == 0) {
            return _LoadMoreRow(
              hasMore: _hasMore,
              loading: _loadingMore,
              error: _loadMoreError,
              onLoadMore: _loadMore,
            );
          }
          final int index = showLoadMore ? i - 1 : i;
          if (index >= items.length) {
            final _Outgoing out = _failed[index - items.length];
            return _FailedRow(
              outgoing: out,
              onRetry: _sending ? null : () => _dispatch(out),
            );
          }
          final _ChatItem item = items[index];
          if (item.messages.length > 1) {
            return _MultiImageRow(
              messages: item.messages,
              isMine: item.messages.first.senderId == myId,
              peerAvatar: widget.peerAvatar,
              peerName: widget.peerName,
              showTime: item.showTime,
            );
          }
          final ChatMessage m = item.messages.single;
          return _MessageRow(
            message: m,
            isMine: m.senderId == myId,
            peerAvatar: widget.peerAvatar,
            peerName: widget.peerName,
            showTime: item.showTime,
            onReport: () => _reportMessage(m),
          );
        },
      ),
    );
  }

  /// 把消息流切成**渲染项**:连续同发送方的图片合成一条多图项,其余一条一项。
  ///
  /// ★ 一次发三张图应该是**一条**多图消息,不是三个独立气泡竖着排 ——
  ///   后者既占满屏,也看不出"这是一组"。
  /// ⚠️ 分组只影响**渲染**,不动 `_msgs` —— 分页游标与消息 id 的口径不能变。
  List<_ChatItem> _chatItems() {
    final List<_ChatItem> items = <_ChatItem>[];
    ChatMessage? prev;
    for (int i = 0; i < _msgs.length; i++) {
      final ChatMessage m = _msgs[i];
      if (m.isImage) {
        final List<ChatMessage> run = <ChatMessage>[m];
        int j = i + 1;
        while (j < _msgs.length &&
            _msgs[j].isImage &&
            _msgs[j].senderId == m.senderId) {
          run.add(_msgs[j]);
          j += 1;
        }
        i = j - 1;
        items.add(_ChatItem(messages: run, showTime: _shouldShowTime(prev, m)));
        prev = run.last;
        continue;
      }
      items.add(
        _ChatItem(
          messages: <ChatMessage>[m],
          showTime: _shouldShowTime(prev, m),
        ),
      );
      prev = m;
    }
    return items;
  }

  /// 与上一条间隔超过 5 分钟则显示时间分隔。
  bool _shouldShowTime(ChatMessage? prev, ChatMessage cur) {
    if (prev == null) return true;
    final a = DateTime.tryParse((prev.createTime ?? '').replaceFirst(' ', 'T'));
    final b = DateTime.tryParse((cur.createTime ?? '').replaceFirst(' ', 'T'));
    if (a == null || b == null) return false;
    return b.difference(a).inMinutes.abs() >= 5;
  }
}

/// 「+」菜单的三个动作 —— 与小程序 plus 面板同一集合,不多不少。
enum _PlusAction { image, location, route }

/// 一条要发出去的消息:文本 / 图片 / 路线卡 / 位置卡共用。
/// 失败后**原样**重发 —— 重发不能退化成另一种类型。
class _Outgoing {
  const _Outgoing.text(String text)
    : content = text,
      msgType = kMsgText,
      extraJson = null,
      label = text;

  /// 图片消息:content 就是 OSS URL(小程序 `{msg_type:2, content:url}` 同形)。
  /// [label] 是给失败行看的 —— 不能把一串 URL 摆给用户。
  const _Outgoing.image(String url)
    : content = url,
      msgType = kMsgImage,
      extraJson = null,
      label = '[图片]';

  /// 路线卡:只传 topicId,展示字段接收方现拉(小程序 spec 决策 8)。
  _Outgoing.route(int topicId)
    : content = '[路线]',
      msgType = kMsgCard,
      extraJson = routeCardJson(topicId),
      label = '[路线]';

  /// 位置卡:extra_json 字段与小程序 `sendCard({cardType:'location',…})` 同形。
  _Outgoing.location({
    required String name,
    required String address,
    required double lat,
    required double lng,
  }) : content = '[位置]',
       msgType = kMsgCard,
       extraJson = locationCardJson(
         name: name,
         address: address,
         lat: lat,
         lng: lng,
       ),
       label = '[位置]';

  /// 服务端 content。★ 图片消息这里必须是 URL,**不是**「[图片]」——
  /// content 是内容本身,不能拿展示文案顶替。
  final String content;
  final int msgType;
  final String? extraJson;

  /// 失败行里显示的字。
  final String label;
}

/// 一个渲染项(§ _chatItems):文本/卡片 = 1 条,图片组 = 连续 N 条。
class _ChatItem {
  const _ChatItem({required this.messages, required this.showTime});

  final List<ChatMessage> messages;
  final bool showTime;
}

/// 一组连续图片(同一发送方)。铺成两列网格。
///
/// ⚠️ 单张图**不走这里** —— 它仍走 _Bubble 里的单图分支。不为了"统一"而让
/// 一条消息长得像一组;那也会让已有的聊天基准图无谓地变。
class _MultiImageRow extends StatelessWidget {
  const _MultiImageRow({
    required this.messages,
    required this.isMine,
    required this.peerAvatar,
    required this.peerName,
    required this.showTime,
  });

  final List<ChatMessage> messages;
  final bool isMine;
  final String peerAvatar;
  final String peerName;
  final bool showTime;

  /// 单元格边长。两列 + 间距 4 ⇒ 224pt,与单图气泡的 160pt 同一量级。
  static const double _cellSize = 110;

  @override
  Widget build(BuildContext context) {
    // 同组图片是同一发送方(分组判据就是 senderId),头像是回填发送者的
    // senderName/senderAvatar,缺失回退口径同 _MessageRow。
    final ChatMessage first = messages.first;
    final String senderName = first.senderName?.isNotEmpty ?? false
        ? first.senderName!
        : peerName;
    final String senderAvatar = first.senderAvatar?.isNotEmpty ?? false
        ? first.senderAvatar!
        : peerAvatar;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space1),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isMine) ...<Widget>[
            _ChatAvatar(url: senderAvatar, name: senderName),
            const SizedBox(width: CyTokens.space2),
          ],
          // ★ 与 _MessageRow 同构:列必须收进 Flexible,否则群聊里一条长昵称
          //   (发送者名不受会话名长度约束,#459 起)会把 Row 撑爆报 overflow。
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _RowHeader(
                  isMine: isMine,
                  name: senderName,
                  time: showTime
                      ? fmtMessageTime(messages.first.createTime)
                      : '',
                ),
                Semantics(
                  container: true,
                  // 一屏图 VoiceOver 读不出"有几张",这里补上。
                  label: '图片消息，共 ${messages.length} 张',
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: _cellSize * 2 + 4,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        alignment: isMine
                            ? WrapAlignment.end
                            : WrapAlignment.start,
                        children: <Widget>[
                          for (final ChatMessage m in messages)
                            _cell(m.content ?? ''),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8), // 16rpx,与单图一致
      child: Image.network(
        url,
        width: _cellSize,
        height: _cellSize,
        fit: BoxFit.cover,
        // 坏图兜底与单图同款,不画系统碎图标
        errorBuilder: (BuildContext context, _, _) => Container(
          width: _cellSize,
          height: _cellSize,
          color: CyPalette.of(context).bgElevated,
          alignment: Alignment.center,
          child: Icon(
            CupertinoIcons.photo,
            color: CyPalette.of(context).textDisabled,
          ),
        ),
      ),
    );
  }
}

/// 列表最上面那一行:加载更早消息 / 正在加载 / 加载失败重试。
/// 对齐小程序 im/chat 的 `load-more` 三态(cy-inline-error / loadingMore / hasMore)。
class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool loading;

  /// 失败原因。★ 失败**不隐藏**这一行 —— 重试入口就长在这里,
  /// 藏了用户只能退出重进。
  final String? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String? failure = error;
    if (failure != null) {
      return Semantics(
        container: true,
        liveRegion: true,
        label: '更早消息没有加载。$failure',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space3),
            child: Column(
              children: <Widget>[
                Text(
                  '更早消息没有加载',
                  textAlign: TextAlign.center,
                  style: textTheme.labelMedium?.copyWith(
                    color: CyPalette.of(context).textPrimary,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  failure,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                CupertinoButton(
                  key: const Key('im-load-more-retry'),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                  ),
                  onPressed: onLoadMore,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (loading || !hasMore) {
      return Padding(
        padding: const EdgeInsets.only(bottom: CyTokens.space2),
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: '正在加载更早消息',
            child: const ExcludeSemantics(child: CupertinoActivityIndicator()),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      button: true,
      label: '加载更早消息',
      onTap: onLoadMore,
      child: ExcludeSemantics(
        child: CupertinoButton(
          key: const Key('im-load-more'),
          minimumSize: const Size.fromHeight(44),
          padding: EdgeInsets.zero,
          onPressed: onLoadMore,
          child: Text(
            '加载更早消息',
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: CyPalette.of(context).statusInfo,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条没发出去的消息:留在列表里,点一下原样重发。
class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.outgoing, required this.onRetry});

  final _Outgoing outgoing;

  /// 发送中为 null(正在重发,不让人连点)。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Semantics(
      container: true,
      button: true,
      label: '发送失败，点按重试',
      enabled: onRetry != null,
      onTap: onRetry,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.exclamationmark_circle,
                      size: 18,
                      color: CyTokens.statusDanger,
                    ),
                    const SizedBox(width: CyTokens.space2),
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 240),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space3,
                          vertical: CyTokens.space2_5,
                        ),
                        decoration: BoxDecoration(
                          // 比正常气泡更暗 —— 它还没成为一条消息。
                          color: p.bgElevated,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(4),
                            bottomLeft: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                          ),
                          border: Border.all(color: CyTokens.statusDanger),
                        ),
                        child: Text(
                          outgoing.label,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: p.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  '未发送，点按重试',
                  style: TextStyle(
                    fontSize: CyTokens.typeCaption,
                    color: CyTokens.statusDanger,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.isMine,
    required this.peerAvatar,
    required this.peerName,
    required this.showTime,
    required this.onReport,
  });

  final ChatMessage message;
  final bool isMine;
  final String peerAvatar;
  final String peerName;
  final bool showTime;

  /// 长按举报这条消息(只对别人的消息生效,见 build 里的判断)。
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    // 卡片消息(msgType=3):extra_json 解析一次,布局与气泡都按它分流。
    final ChatCardData? card = message.msgType == kMsgCard
        ? parseChatCard(message.extraJson, fallbackTitle: message.content)
        : null;
    // 系统卡(generic):整宽居左、**不带头像** ——
    // 小程序里它不在 `.row` 里渲染(wxml 通用卡分支),没有发送方概念。
    final bool isSystemCard = card?.type == 'generic';
    final String time = showTime ? fmtMessageTime(message.createTime) : '';
    // 群聊要分清谁在说话:后端 `ImServiceImpl#listMessages` 按 senderId 回填
    // senderName/senderAvatar(单聊回填的就是对端,值不变)。缺失(系统消息
    // senderId=0、成员查不到、真源无群聊页故无回退先例)回退会话级
    // peerName/peerAvatar —— 即修复前的行为,单聊零回归。
    final String senderName = message.senderName?.isNotEmpty ?? false
        ? message.senderName!
        : peerName;
    final String senderAvatar = message.senderAvatar?.isNotEmpty ?? false
        ? message.senderAvatar!
        : peerAvatar;
    // 「名字 · 时间」只属于普通气泡:卡片的时间走居中分隔,系统卡没有发送方。
    final Widget? header = message.msgType == kMsgCard || isSystemCard
        ? null
        : _RowHeader(isMine: isMine, name: senderName, time: time);
    return Column(
      children: <Widget>[
        // 时间分隔两种放法,两处都渲会对同一时刻重复显示(小程序同一判据):
        //   · 卡片消息 → 居中分隔(wxml 限定 msgType==3);
        //   · 普通气泡 → 贴气泡的「名字 · 时间」一行。
        if (showTime && message.msgType == kMsgCard)
          Padding(
            // 真源 .time-div margin: 24rpx 0 space-1-5(上 12 / 下 6,不对称)。
            padding: const EdgeInsets.only(
              top: CyTokens.space3,
              bottom: CyTokens.space1_5,
            ),
            child: Text(
              fmtMessageTime(message.createTime),
              // .time-div:label 字阶(24rpx→12pt,不是 sender-name 的 caption 11)
              // + --cy-text-secondary。落 CyType.caption1 同档(T5 字距 0)。
              style: CyType.caption1.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: CyTokens.space1),
          child: Row(
            mainAxisAlignment: isMine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 系统卡没有发送方,不给头像(小程序里它整宽居左,不在 `.row` 里)。
              if (!isMine && !isSystemCard) ...<Widget>[
                _ChatAvatar(url: senderAvatar, name: senderName),
                const SizedBox(width: CyTokens.space2),
              ],
              Flexible(
                // ★ 长按举报。只对**别人**的消息开放 —— 举报自己没有意义。
                //   Apple 1.2 要求能举报**具体内容**;此前 App 只有「拉黑这个人」,
                //   那解决的是「别再骚扰我」,不解决「这条内容该被处理」——
                //   被拉黑的人对别人还是照发。
                // 系统卡先判:它 senderId=0,可能和"我"(未登录/系统会话)撞上,
                // 落进 isMine 分支就会渲成一张看不懂的占位气泡。
                child: isSystemCard
                    ? _SystemCardBubble(
                        card: card!,
                        isTrustedSystem: message.senderId == 0,
                      )
                    : isMine
                    ? _Bubble(
                        message: message,
                        isMine: isMine,
                        card: card,
                        header: header,
                      )
                    : GestureDetector(
                        onLongPress: onReport,
                        child: _Bubble(
                          message: message,
                          isMine: isMine,
                          card: card,
                          header: header,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 气泡上方那一行。对方 = 「名字 · 时间」(名字恒在 —— 小程序 `displayName`
/// 每条都挂,时间只在间隔 ≥5 分钟时追加);自己 = 只有时间、右对齐。
/// 空串 = 整行不渲。
class _RowHeader extends StatelessWidget {
  const _RowHeader({
    required this.isMine,
    required this.name,
    required this.time,
  });

  final bool isMine;
  final String name;
  final String time;

  @override
  Widget build(BuildContext context) {
    final String text = isMine || name.isEmpty
        ? time
        : (time.isEmpty ? name : '$name · $time');
    if (text.isEmpty) return const SizedBox.shrink();
    // .sender-name 用 secondary、.msg-time 用 tertiary(小程序 wxss),字阶
    // --cy-font-caption = 22rpx = 11pt。`textTheme.labelSmall` 同为 11pt 但带
    // Material 的 w500 + 0.5 字距(T5 中文字距一律 0、真源不加粗),故取
    // CyType.caption2 阶梯档 + C4 语义色。本域玩家恒暗,palette 与旧常量同值。
    final CyPalette palette = CyPalette.of(context);
    final Color color = isMine ? palette.textTertiary : palette.textSecondary;
    return Padding(
      padding: EdgeInsets.only(
        left: isMine ? 0 : CyTokens.space1,
        right: isMine ? CyTokens.space1 : 0,
        // 真源 .sender-name margin-bottom = --cy-legacy-6(6rpx→3pt)。
        // 梯上没有 3pt 这一档,space1_5(6pt)是它的两倍 —— 不折算错值。
        bottom: 3,
      ),
      child: Text(text, style: CyType.caption2.copyWith(color: color)),
    );
  }
}

/// 系统卡(`cardType:generic`,仅系统可发)。对齐小程序 im/chat 的通用卡:
/// 图标 + 标题 + 副标题 + meta,底部按优先级三选一 ——
/// 处理结果 / 自定义按钮 / 「查看详情」。
///
/// ⚠️ 「查看处理结果」只在 `senderId == 0` 时出现(小程序同判据):
///   extra_json 是发送方可控字段,不看发送方就长出一个"审核回执"按钮,
///   等于让人自己伪造一张平台处置卡。
class _SystemCardBubble extends ConsumerWidget {
  const _SystemCardBubble({required this.card, required this.isTrustedSystem});

  final ChatCardData card;

  /// 发送方是系统(senderId == 0)才认卡片里的处理结果。
  final bool isTrustedSystem;

  Future<void> _openResult(BuildContext context) async {
    final ChatCardResult? result = card.result;
    if (result == null || result.isEmpty) return;
    await showChatReviewResult(context, result);
  }

  void _onCardTap(BuildContext context, WidgetRef ref) {
    // ① 有处理结果 → 先看结果,不跳走(小程序 onCardTap 的同一条顺序)。
    final ChatCardResult? result = card.result;
    if (isTrustedSystem && result != null && !result.isEmpty) {
      unawaited(_openResult(context));
      return;
    }
    // ② 官方通知点击回流:best-effort —— 失败不提示也不拦截跳转,
    //    用户点的是「看这条通知」,不是「上报一次点击」。
    final int? bc = card.bcId;
    if (bc != null) {
      unawaited(
        ref
            .read(officialApiProvider)
            .reportBroadcastClick(bc)
            .catchError((Object _) {}),
      );
    }
    // ③ 卡片自带的跳转目标。⚠️ 只认站内路径 —— extra_json 是**发送方可控**
    //    字段,塞一个 `https://…` 进来会让 push 抛「没有这条路由」。
    //    (小程序 `onCardTap` 直接 navigateTo,同一个洞;这里是 App 侧收紧。)
    final String? action = card.action;
    if (action != null && action.startsWith('/')) context.push(action);
  }

  /// 自定义按钮:站内路径(action 以 `/` 开头)才跳转,否则按「已处理」提示
  /// (小程序 `onCardBtn` 的同一条分支)。
  void _onCardBtn(BuildContext context, ChatCardButton button) {
    final String? action = button.action;
    if (action != null && action.startsWith('/')) {
      context.push(action);
      return;
    }
    CyNativeNotice.show(context, '已处理');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ChatCardResult? result = card.result;
    final bool showResult =
        isTrustedSystem && result != null && !result.isEmpty;
    return Container(
      // 填满至上限(小程序 `.card` 整宽 max-480rpx;flex 里不能收缩到内容)。
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 240), // 480rpx
      decoration: BoxDecoration(
        color: p.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd), // 24rpx
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            container: true,
            button: true,
            label: card.title,
            onTap: () => _onCardTap(context, ref),
            child: ExcludeSemantics(
              child: CupertinoButton(
                key: const Key('system-card-body'),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => _onCardTap(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // .card-icon:圆角方底 + 信息蓝图标
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: p.bgSurfaceSubtle,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusSm,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          CupertinoIcons.info,
                          size: 16,
                          color: p.statusInfo,
                        ),
                      ),
                      const SizedBox(width: CyTokens.space2_5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              card.title,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                              ),
                            ),
                            if (card.sub.isNotEmpty) ...<Widget>[
                              const SizedBox(height: CyTokens.space1_5),
                              Text(
                                card.sub,
                                style: textTheme.labelMedium?.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (card.meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.space3,
                0,
                CyTokens.space3,
                CyTokens.space2_5,
              ),
              child: Text(
                card.meta,
                style: textTheme.labelMedium?.copyWith(color: p.textSecondary),
              ),
            ),
          if (showResult)
            _buttonRow(context, <Widget>[
              _cardButton(
                context,
                label: '查看处理结果',
                isReject: false,
                onTap: () => unawaited(_openResult(context)),
              ),
            ])
          else if (card.buttons.isNotEmpty)
            _buttonRow(context, <Widget>[
              for (final ChatCardButton b in card.buttons)
                _cardButton(
                  context,
                  label: b.text,
                  isReject: b.isReject,
                  onTap: () => _onCardBtn(context, b),
                ),
            ])
          else if (card.action != null)
            _buttonRow(context, <Widget>[
              _cardButton(
                context,
                label: '查看详情',
                isReject: false,
                onTap: () => _onCardTap(context, ref),
              ),
            ]),
        ],
      ),
    );
  }

  /// 按钮区:整行等分,顶部一条分隔线;多个按钮之间竖分隔(小程序 .card-btns)。
  Widget _buttonRow(BuildContext context, List<Widget> buttons) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.borderSubtle)),
      ),
      // ⚠️ 不能用 CrossAxisAlignment.stretch:卡片在 Column 里高度无界,
      //   stretch 会把 h=Infinity 传给按钮直接炸布局。等分按钮各自等高
      //   (都是单行文案 + 同款内边距),竖分隔线自然等长。
      child: Row(
        children: <Widget>[
          for (int i = 0; i < buttons.length; i++)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: i == buttons.length - 1
                      ? null
                      : Border(right: BorderSide(color: p.borderSubtle)),
                ),
                child: buttons[i],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardButton(
    BuildContext context, {
    required String label,
    required bool isReject,
    required VoidCallback onTap,
  }) {
    final CyPalette p = CyPalette.of(context);
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
          minimumSize: const Size(44, 44),
          onPressed: onTap,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              fontWeight: FontWeight.w700,
              // .card-btn 信息蓝;reject 走危险色
              color: isReject ? p.statusDanger : p.statusInfo,
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.card,
    this.header,
  });

  final ChatMessage message;
  final bool isMine;

  /// 气泡正上方那一行「名字 · 时间」。由 `_MessageRow` 算好传进来 ——
  /// 空(null)= 不渲(卡片与系统卡),不是「渲一个空的」。
  final Widget? header;

  /// 已解析的卡片载荷(只有 msgType=3 才有)。★ 由 `_MessageRow` 解析一次传进来 ——
  /// 一处解析、一处分流,免得布局判一次、渲染再判一次。
  final ChatCardData? card;

  @override
  Widget build(BuildContext context) {
    final Widget body = _body(context);
    final Widget? h = header;
    if (h == null) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[h, body],
    );
  }

  Widget _body(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    // .bubble.me = 28rpx 8rpx 28rpx 28rpx;.bubble.other = 8rpx 28rpx 28rpx 28rpx
    // 尾角(8rpx)在气泡靠己侧顶角,主角 28rpx(wxss 注明无对应 radius token)。
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMine ? 14 : 4),
      topRight: Radius.circular(isMine ? 4 : 14),
      bottomLeft: const Radius.circular(14),
      bottomRight: const Radius.circular(14),
    );

    if (message.isImage) {
      // .b-img:width 320rpx、radius 16rpx(8pt)
      return ClipRRect(
        borderRadius: BorderRadius.circular(8), // 16rpx
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160), // 320rpx
          child: Image.network(
            message.content ?? '',
            width: 160,
            errorBuilder: (BuildContext context, _, _) => Container(
              width: 120,
              height: 120,
              color: CyPalette.of(context).bgElevated,
              alignment: Alignment.center,
              child: Icon(
                CupertinoIcons.photo,
                color: CyPalette.of(context).textDisabled,
              ),
            ),
          ),
        ),
      );
    }

    // 卡片消息(msgType=3):App 此前**能发不能收** ——
    // 会掉进下面的「不认识的类型」兜底,自己发的自己都看不懂。
    // 系统卡(generic)在 `_MessageRow` 就分流走了(整宽、不带头像),不到这里。
    final ChatCardData? c = card;
    if (c != null) {
      if (c.type == 'location') {
        return _LocationCardBubble(
          name: c.name,
          address: c.address,
          lat: c.lat,
          lng: c.lng,
          isMine: isMine,
          radius: radius,
        );
      }
      return _RouteCardBubble(
        topicId: c.topicId,
        type: c.type,
        bcId: c.bcId,
        action: c.action,
        isMine: isMine,
        radius: radius,
      );
    }

    // ★ 这个分支同时接住两种"不是文本"的情况,都不能渲成空壳:
    //   · 文本但 content 为空(后端字段可空)→ 一个没有字的圆角块,
    //     看着像渲染坏了,而不像"这条没内容"。
    //   · msgType 是本版本不认识的(后端将来加语音/系统卡)→ 掉进这里,
    //     要么摊出原始载荷,要么同样是空壳。
    final String? raw = message.content;
    final bool unknownType = !message.isText && !message.isImage;
    final String body = unknownType
        ? '[这条消息当前版本显示不了]'
        : (raw == null || raw.trim().isEmpty ? '[消息为空]' : raw);
    final bool placeholder = unknownType || body != raw;

    return Container(
      constraints: const BoxConstraints(maxWidth: 240), // 480rpx
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3, // 24rpx
        vertical: CyTokens.space2_5, // 20rpx
      ),
      decoration: BoxDecoration(
        // 自己=白底黑字(action-primary),对方=elevated 浅灰 + text-primary
        color: isMine ? palette.actionPrimaryBg : palette.bgElevated,
        borderRadius: radius,
      ),
      child: Text(
        body,
        style: textTheme.bodyMedium?.copyWith(
          color: placeholder
              // 占位文案压成次级色 —— 它不是对方说的话,不该和正文一样重。
              ? (isMine ? palette.actionPrimaryFg : palette.textSecondary)
              : (isMine ? palette.actionPrimaryFg : palette.textPrimary),
          fontStyle: placeholder ? FontStyle.italic : null,
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    // .row-avatar:64rpx(32pt),占位底 = --cy-bg-page
    const double size = 32;
    final CyPalette palette = CyPalette.of(context);
    final fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: CyTokens.bgPage,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first : '瘾',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: palette.actionPrimaryBg),
      ),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// 底部输入框 + 发送按钮。
/// 对齐 im/chat:输入框大圆角矩形(radius-lg)+ bg-page 底 + 描边 none,
/// 发送键收进框内右侧、圆形,随有无文字在灰底灰箭头/反色实底间切换。
class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPlus,
    required this.blockedText,
    this.liquidGlassSupported,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  /// 非 null ⇒ 整条输入栏是**可见禁用态**,这行字说明为什么点不动
  /// (小程序 `disabled-tip` + `input-bar--off` 同款)。
  final String? blockedText;

  /// 「+」:弹出「图片 / 位置 / 路线」动作菜单。
  /// [anchor] 是「+」自己的矩形 —— S4:sheet 从触发元素弹出,不是屏幕中央。
  final void Function(Rect? anchor) onPlus;

  /// 仅供能力分支测试;运行时用系统版本探测(同 `CyFooterBar`)。
  final bool? liquidGlassSupported;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final String? blocked = widget.blockedText;
    final bool enabled = blocked == null;
    final CyPalette palette = CyPalette.of(context);
    // §3.9 IM5 / M8:输入条是浮动功能层 —— iOS 26+ 真玻璃,iOS 13–25 回退
    // 实色条。两条路径的**几何完全一致**(同 `CyFooterBar`:只换材质,
    // 不换布局,页面不因系统版本重排)。
    final bool useNativeGlass =
        widget.liquidGlassSupported ??
        NativeLiquidGlassUtils.supportsLiquidGlass;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.pageX,
        vertical: CyTokens.space2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ★ 行为层的闸早就有了(发送守卫),这里补的是**可供性**那一半:
          //   不让一条点不动的输入栏看起来像能发消息,也不整条隐藏
          //   —— 隐藏会藏掉「这是会话页」,回来时还会跳版。
          if (blocked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space1_5),
              child: Text(
                blocked,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
          Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Row(
              children: <Widget>[
                Builder(
                  // 锚点要的是「+」自己的矩形 —— Builder 的 context 正好落在它身上。
                  builder: (BuildContext plusContext) => Semantics(
                    container: true,
                    button: true,
                    // 与小程序同一个 aria-label(`添加图片、位置或路线`)。
                    label: '添加图片、位置或路线',
                    enabled: enabled && !widget.sending,
                    onTap: !enabled || widget.sending
                        ? null
                        : () => widget.onPlus(cySourceRectOf(plusContext)),
                    child: ExcludeSemantics(
                      child: CupertinoButton(
                        key: const Key('im-plus'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: !enabled || widget.sending
                            ? null
                            : () => widget.onPlus(cySourceRectOf(plusContext)),
                        child: const Icon(CupertinoIcons.add, size: 24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: CupertinoTextField(
                    controller: widget.controller,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    keyboardType: TextInputType.text,
                    autocorrect: true,
                    enableSuggestions: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                    onSubmitted: (_) => widget.onSend(),
                    placeholder: enabled ? '发消息...' : '会话不可用',
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3_5,
                      vertical: CyTokens.space3,
                    ),
                    suffix: _SendButton(
                      enabled: enabled,
                      hasText: _hasText,
                      sending: widget.sending,
                      onSend: widget.onSend,
                    ),
                    decoration: BoxDecoration(
                      color: CyTokens.bgPage,
                      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // ★ 材质包在 SafeArea **里面**:玻璃/实色条一直铺到屏幕底边(「信息」的输入条
    //   就是这样),内容再被 home indicator 顶上来。反过来的话,条子会在底边上方
    //   断掉,露出一条与页面底同色的缝。
    final Widget bar = useNativeGlass
        ? LiquidGlassContainer(
            key: const Key('im-input-bar-glass'),
            config: const LiquidGlassConfig(shape: LiquidGlassEffectShape.rect),
            child: content,
          )
        : DecoratedBox(
            key: const Key('im-input-bar-solid'),
            decoration: BoxDecoration(
              color: palette.bgSurface,
              border: Border(
                // 分隔线走系统语义色(§3.6 分工),不是品牌 token。
                top: BorderSide(
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
              ),
            ),
            child: content,
          );
    return SafeArea(top: false, child: bar);
  }
}

/// 发送键:72rpx 视觉圆,空闲=surface-subtle 底 + tertiary 灰箭头,
/// 有文字=action-primary 白底黑箭头,发送中显示小转圈。
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.hasText,
    required this.sending,
    required this.onSend,
  });

  /// 整条输入栏可用(会话 ready);false 时发送键必须点不动。
  final bool enabled;
  final bool hasText;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bool active = enabled && hasText && !sending;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
      child: Semantics(
        container: true,
        label: '发送消息',
        value: sending ? '正在发送' : null,
        button: true,
        enabled: active,
        onTap: active ? onSend : null,
        child: ExcludeSemantics(
          child: CupertinoButton(
            onPressed: active ? onSend : null,
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            child: Container(
              width: 36, // 72rpx
              height: 36,
              decoration: BoxDecoration(
                color: active
                    ? CyTokens.actionPrimaryBg
                    : CyTokens.bgSurfaceSubtle,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(),
                    )
                  : Icon(
                      // cy-icon name=arrow-right rotate(-90deg) → 朝上
                      CupertinoIcons.arrow_up,
                      size: 16, // 32rpx
                      color: active
                          ? CyTokens.actionPrimaryFg
                          : CyTokens.textTertiary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 位置卡气泡。对齐小程序 im/chat 的 `rcard`:
/// pin 图标 + 地点名 + 地址(可空)+ 「导航过去」页脚。
/// 点击 = 唤起系统地图(小程序 `wx.openLocation` 的 App 等价物,见
/// `core/map/map_launcher.dart` —— 那里有「打不开地图就复制地址」的兜底链)。
class _LocationCardBubble extends ConsumerWidget {
  const _LocationCardBubble({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.isMine,
    required this.radius,
  });

  final String name;
  final String address;
  final double? lat;
  final double? lng;
  final bool isMine;
  final BorderRadius radius;

  Future<void> _navigate(BuildContext context, WidgetRef ref) async {
    final MapLaunchResult result = await ref.read(imMapLauncherProvider)(
      lat: lat,
      lng: lng,
      name: name.isEmpty ? '共享位置' : name,
      address: address.isEmpty ? null : address,
      isIOS: defaultTargetPlatform == TargetPlatform.iOS,
    );
    if (!context.mounted) return;
    final String message = mapLaunchMessage(result);
    if (message.isEmpty) return; // 打开了地图就别打扰
    CyNativeNotice.show(
      context,
      message,
      isError: result == MapLaunchResult.noCoordinates,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CyPalette palette = CyPalette.of(context);
    final Color fg = isMine ? palette.actionPrimaryFg : palette.textPrimary;
    final Color sub = isMine ? palette.actionPrimaryFg : palette.textSecondary;
    final String title = name.isEmpty ? '共享位置' : name;
    return Semantics(
      container: true,
      button: true,
      // 与小程序同一个 aria-label(导航到{{name || '共享位置'}})。
      label: '导航到$title',
      onTap: () => _navigate(context, ref),
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: () => _navigate(context, ref),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: radius,
          child: Container(
            // 填满至上限(240pt = 480rpx)而非收缩到内容宽 —— 小程序 wxss
            // 对 `.rcard` 实测过同款 bug:进 flex 后卡收缩到远小于 480rpx。
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: isMine ? palette.actionPrimaryBg : palette.bgElevated,
              borderRadius: radius,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(CupertinoIcons.placemark, size: 16, color: sub),
                    const SizedBox(width: CyTokens.space2),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
                // 地址可空(小程序 `wx:if="{{item.card.address}}"` 同款):
                // 没有就整行不渲,不摆一个空行。
                if (address.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: sub,
                    ),
                  ),
                ],
                const SizedBox(height: CyTokens.space2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '导航过去',
                      style: TextStyle(
                        fontSize: CyTokens.typeCaption,
                        color: sub,
                      ),
                    ),
                    const SizedBox(width: CyTokens.space1),
                    Icon(CupertinoIcons.chevron_forward, size: 10, color: sub),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 路线卡片气泡。
class _RouteCardBubble extends ConsumerWidget {
  const _RouteCardBubble({
    required this.topicId,
    required this.type,
    required this.bcId,
    required this.action,
    required this.isMine,
    required this.radius,
  });

  final int topicId;
  final String type;

  /// 官方通知的广播 id。非空时点击要上报回流。
  final int? bcId;

  /// 卡片自带的跳转目标。有它就跳它,没有才跳路线详情。
  final String? action;
  final bool isMine;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 标题现拉。拿不到时用「路线 #id」兜 ——
    //   **不显示空白也不显示「加载中」**:一条对方明明发了的消息
    //   在我这儿消失,比显示一个编号严重得多。
    final CyPalette palette = CyPalette.of(context);
    final String title = ref
        .watch(topicDetailProvider(topicId))
        .maybeWhen(
          data: (t) => t.name,
          orElse: () => chatCardFallbackTitle(type: type, topicId: topicId),
        );
    return CupertinoButton(
      key: Key('chat-card-$topicId'),
      onPressed: () {
        // ★ 点击回流是 **best-effort**:失败不影响跳转,也不提示 ——
        //   用户点的是「去看这条路线」,不是「上报一次点击」。
        //   (小程序那边同样是 success(){} fail(){} 空回调。)
        final int? bc = bcId;
        if (bc != null) {
          unawaited(
            ref
                .read(officialApiProvider)
                .reportBroadcastClick(bc)
                .catchError((Object _) {}),
          );
        }
        context.push(action ?? '/topic/$topicId');
      },
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      borderRadius: radius,
      child: Container(
        // 填满至上限,同位置卡(.rcard 实测缺口,见上)。
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: isMine ? palette.actionPrimaryBg : palette.bgElevated,
          borderRadius: radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 报名卡的「报名成功」标记条(wxml `.rcard-flag`,绿 = 成功语义)。
            // ★ 只有 signup 有;路线卡渲这条就是伪造了一个不存在的状态。
            if (type == 'signup')
              Semantics(
                container: true,
                label: '报名成功',
                child: ExcludeSemantics(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3,
                      vertical: CyTokens.space1_5,
                    ),
                    color: palette.statusSuccess.withValues(alpha: 0.14),
                    child: Text(
                      '报名成功',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        fontWeight: FontWeight.w700,
                        color: palette.statusSuccess,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(CyTokens.space3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    CupertinoIcons.map,
                    size: 16,
                    color: isMine
                        ? palette.actionPrimaryFg
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          // 报名卡与路线卡是两种东西,卡面上的类型字也跟着分 ——
                          // 降级文案同理(小程序:该活动已下架 / 该路线已下架)。
                          type == 'signup' ? '活动' : '路线',
                          style: TextStyle(
                            fontSize: CyTokens.typeMicro,
                            color: isMine
                                ? palette.actionPrimaryFg
                                : palette.textDisabled,
                          ),
                        ),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: CyTokens.typeBody,
                            fontWeight: FontWeight.w600,
                            color: isMine
                                ? palette.actionPrimaryFg
                                : palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
