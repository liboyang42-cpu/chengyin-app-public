import '../../data/api/im_api.dart';
import '../../l10n/im_api_display.dart';
import '../../core/network/request_session_scope.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';
import '../../core/providers.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_predict_api.dart';
import '../../data/models/im.dart';
import '../auth/auth_controller.dart';
import 'conversation_swipe.dart';
import 'im_controller.dart';
import 'im_time.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 会话显示名。★ 系统/官方会话后端可能没有 nickname ——
/// 那时**不能**落成「城瘾用户」(那是在说对面是个人),按会话类型给通用称呼。
/// 与小程序 im/list 的兜底文案一致(`cp.nickname || (type==2 ? stringsOf(context).imSystemNotifications : stringsOf(context).imOfficialMessages)`)。
String conversationDisplayName(BuildContext context, Conversation conv) {
  final String name = conv.counterparty.nickname;
  if (name.isNotEmpty) return name;
  if (conv.type == kImTypeSystem) return stringsOf(context).imSystemNotifications;
  if (conv.type == kImTypeMerchant) return stringsOf(context).imOfficialMessages;
  return stringsOf(context).imMemberFallback;
}

/// Only replace locally generated placeholders. Server/user preview text is verbatim.
String conversationPreview(BuildContext context, Conversation conv) {
  if (conv.lastMsgText?.isNotEmpty == true) return conv.lastMsgText!;
  if (conv.lastMsgType == kMsgImage) return stringsOf(context).imPhotoPreview;
  if (conv.lastMsgType == kMsgCard) return stringsOf(context).imCardPreview;
  return '';
}

/// IM 会话列表:头像 + 昵称 + 最后消息 + 未读角标。点进聊天页。
/// 实时性弱:下拉刷新即可,不做 WebSocket。
///
/// 视觉按 §3.9 IM1/IM2/IM3:**无卡片底 + 系统分隔线**,行 = 头像 + 名称 +
/// 摘要 + 时间 + 未读,左右滑动露出操作,长按给同一套动作。
/// 与小程序 im/list 的差集在小程序没有的那几件上:系统通知/官方的行内身份、
/// 滑动操作、全部已读、会话内搜索 —— 见 PR 说明。
class ImConversationActionItem {
  const ImConversationActionItem({
    required this.id,
    required this.title,
    this.isDestructive = false,
    this.isCancel = false,
  });

  final String id;
  final String title;
  final bool isDestructive;
  final bool isCancel;
}

abstract interface class ImConversationActionPresenter {
  bool get supportsNativeActionSheet;

  Future<String?> showActionSheet({
    required BuildContext context,
    required List<ImConversationActionItem> items,
  });
}

class _LiquidGlassImConversationActionPresenter
    implements ImConversationActionPresenter {
  const _LiquidGlassImConversationActionPresenter();

  @override
  bool get supportsNativeActionSheet =>
      NativeLiquidGlassUtils.supportsLiquidGlass;

  @override
  Future<String?> showActionSheet({
    required BuildContext context,
    required List<ImConversationActionItem> items,
  }) {
    return LiquidGlassAlert.show(
      context: context,
      style: LiquidGlassAlertStyle.actionSheet,
      actions: items
          .map(
            (ImConversationActionItem item) => LiquidGlassAlertAction(
              id: item.id,
              title: item.title,
              isDestructive: item.isDestructive,
              isCancel: item.isCancel,
            ),
          )
          .toList(growable: false),
    );
  }
}

class ImListPage extends ConsumerStatefulWidget {
  const ImListPage({
    super.key,
    this.onOpenCoopPool,
    this.onOpenSquare,
    this.actionPresenter,
  });

  /// 公开导航缝：默认打开 App 真实路由，widget 测试可替换。
  final VoidCallback? onOpenCoopPool;
  final VoidCallback? onOpenSquare;
  final ImConversationActionPresenter? actionPresenter;

  @override
  ConsumerState<ImListPage> createState() => _ImListPageState();
}

enum _ConversationScope { all, channels, direct }

class _ImListPageState extends ConsumerState<ImListPage> {
  late final RequestSessionScope _requestScope;

  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  _ConversationScope _scope = _ConversationScope.all;

  /// 当前生效的筛选词。
  ///
  /// ★ 只筛**已经拉回来的会话**,不假装能搜聊天记录 ——
  ///   后端没有消息搜索端点(见 current-api-inventory),做成"搜全部"
  ///   就是给用户一个永远查不到东西的搜索框。
  String _keyword = '';

  /// 同一时刻只允许一行展开(iOS 行为);点别的行/开始滚动都不留第二个口子。
  Object? _openRow;

  bool _readingAll = false;

  void _openCoopPool() {
    if (widget.onOpenCoopPool != null) {
      widget.onOpenCoopPool!();
      return;
    }
    context.push('/coop-pool');
  }

  void _openSquare() {
    if (widget.onOpenSquare != null) {
      widget.onOpenSquare!();
      return;
    }
    context.push('/square');
  }

  List<Conversation> _filter(List<Conversation> all) {
    final String kw = _keyword.trim().toLowerCase();
    final List<Conversation> scoped = all
        .where((Conversation c) {
          return switch (_scope) {
            _ConversationScope.all => true,
            _ConversationScope.channels => c.isGroup,
            // 真源 im/list tabOf(spec 决策 2):私信这条轴是「能不能回」,
            // 客服 type=3 归私信 —— App 不能把它筛没。
            _ConversationScope.direct =>
              c.type == kImTypeSingle || c.type == kImTypeMerchant,
          };
        })
        .toList(growable: false);
    if (kw.isEmpty) return scoped;
    return scoped
        .where(
          (Conversation c) =>
              conversationDisplayName(context, c).toLowerCase().contains(kw) ||
              conversationPreview(context, c).toLowerCase().contains(kw),
        )
        .toList(growable: false);
  }

  /// 全部已读。
  ///
  /// ⚠️ 后端只有**单会话** `read(conversation_id)`,没有批量端点 —— 所以这里逐个发,
  ///   并且**按真实成功数回话**:一条都没成也弹「已全部标为已读」,就是给用户一个
  ///   假回执(小程序 im/list 在同一处踩过这个坑)。
  Future<void> _readAll(List<Conversation> list) => RequestSessionScope.run(
    _requestScope,
    () => _readAllScoped(list),
  );

  Future<void> _readAllScoped(List<Conversation> list) async {
    if (_readingAll) return;
    final List<int> ids = list
        .where((Conversation c) => c.unread > 0)
        .map((Conversation c) => c.conversationId)
        .toList(growable: false);
    if (ids.isEmpty) return;
    setState(() => _readingAll = true);
    int failed = 0;
    for (final int id in ids) {
      try {
        await ref.read(imApiProvider).read(id);
      } catch (_) {
        failed += 1;
      }
    }
    if (!mounted) return;
    setState(() => _readingAll = false);
    ref.invalidate(imConversationsProvider);
    if (failed == 0) {
      CyNativeNotice.show(context, stringsOf(context).imReadAllDone);
    } else if (failed == ids.length) {
      CyNativeNotice.show(context, stringsOf(context).imReadFailed, isError: true);
    } else {
      CyNativeNotice.show(context, stringsOf(context).imReadRemaining(failed), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final convs = ref.watch(imConversationsProvider);
    final List<Conversation> loaded = convs.value ?? <Conversation>[];
    final bool hasUnread = loaded.any((Conversation c) => c.unread > 0);
    return CupertinoPageScaffold(
      // 导航栏尾侧 = 「全部已读」(小程序 im/list 右上角那个 ✓ 的等价物)。
      // ⚠️ 中槽**保持空**:本页的标题是页内 CyPageTitle,导航栏再写一遍
      //   「消息」会出现两个同名文本,而 Dynamic Type 门禁正是按 stringsOf(context).imMessages 找锚点的。
      navigationBar: CupertinoNavigationBar(
        trailing: Semantics(
          container: true,
          button: true,
          label: stringsOf(context).imReadAll,
          enabled: hasUnread && !_readingAll,
          onTap: hasUnread ? () => _readAll(loaded) : null,
          child: ExcludeSemantics(
            child: CupertinoButton(
              key: const Key('im-read-all'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: hasUnread && !_readingAll
                  ? () => _readAll(loaded)
                  : null,
              child: Icon(
                CupertinoIcons.checkmark_alt,
                color: hasUnread
                    ? CyPalette.of(context).textPrimary
                    : CyPalette.of(context).textDisabled,
              ),
            ),
          ),
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
              CyPageTitle(stringsOf(context).imMessages),
              CyCell(
                key: const Key('im-coop-pool-entry'),
                title: stringsOf(context).imCoopPool,
                subtitle: stringsOf(context).imCoopPoolHint,
                onTap: _openCoopPool,
              ),
              // 竞猜待答:玩家押完了,答案得商家给,而且**有期限** ——
              // 小程序里这一行只对能结算竞猜的人出现(问身份,不问待办条数),
              // 就在消息列表里,和「合作池」同一层。
              if (ref.watch(authControllerProvider).user?.isMerchantView ==
                  true)
                const _PredictInboxEntry(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.pageX,
                  vertical: CyTokens.space2,
                ),
                child: CupertinoSlidingSegmentedControl<_ConversationScope>(
                  groupValue: _scope,
                  children: <_ConversationScope, Widget>{
                    _ConversationScope.all: Text(stringsOf(context).imAll),
                    _ConversationScope.channels: Text(stringsOf(context).imChannels),
                    _ConversationScope.direct: Text(stringsOf(context).imDirect),
                  },
                  onValueChanged: (_ConversationScope? value) {
                    if (value != null) setState(() => _scope = value);
                  },
                ),
              ),
              Expanded(
                child: convs.when(
                  loading: () =>
                      const CySkeleton(type: CySkeletonType.list, count: 6),
                  error: (Object err, StackTrace st) => StatusView(
                    message: stringsOf(context).imFetchFailed,
                    sub: stringsOf(context).imFetchHint,
                    icon: CupertinoIcons.wifi_slash,
                    scrollable: true,
                    onRetry: () => ref.invalidate(imConversationsProvider),
                  ),
                  data: _buildList,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// tab 空态按真源 `im/list` 分来路:频道说频道怎么来,私信才给「去广场找人」;
  /// 频道空态摆「去广场」是假下一步(广场不产频道会话)。
  Widget _scopeEmpty() {
    final bool channels = _scope == _ConversationScope.channels;
    return StatusView(
      message: channels ? stringsOf(context).imNoChannels : stringsOf(context).imNoDirect,
      sub: channels ? stringsOf(context).imNoChannelsHint : stringsOf(context).imNoDirectHint,
      icon: CupertinoIcons.chat_bubble,
      scrollable: true,
      onRetry: channels ? null : _openSquare,
      retryLabel: stringsOf(context).imFindPeople,
    );
  }

  Widget _buildList(List<Conversation> list) {
    if (list.isEmpty) {
      return _scopeEmpty();
    }
    final List<Conversation> shown = _filter(list);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // §3.9 IM1:顶部内联搜索。只在真有会话时出现 ——
        // 空态/错误态摆一个搜不了东西的框,是纯噪音。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            0,
            CyTokens.pageX,
            CyTokens.space2,
          ),
          child: CySearchField(
            key: const Key('im-search'),
            value: _keyword,
            placeholder: stringsOf(context).imSearch,
            onChanged: (String v) => setState(() {
              _keyword = v;
              _openRow = null;
            }),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              // 两态不混:关键词没命中报「没有匹配的会话」;tab 内没有会话
              // 出该 tab 的来路空态(_scopeEmpty),不许蹭搜索文案。
              ? (_keyword.trim().isEmpty
                    ? _scopeEmpty()
                    : StatusView(
                        message: stringsOf(context).imNoMatches,
                        sub: stringsOf(context).imNoMatchesHint,
                        icon: CupertinoIcons.search,
                        scrollable: true,
                      ))
              : RefreshIndicator.adaptive(
                  onRefresh: () async =>
                      ref.invalidate(imConversationsProvider),
                  child: ColoredBox(
                    // 行底由 CySwipeActionsRow 统一画 bgPage(滑开时露出的那条
                    // 底就是这一层,系统里它等于页面底);容器若还是 bgSurface,
                    // 展开态会在行缝里显出第二种颜色。
                    color: CyPalette.of(context).bgPage,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: _channelRows(shown),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  List<Widget> _channelRows(List<Conversation> conversations) {
    final Map<String, List<Conversation>> groups =
        <String, List<Conversation>>{};
    for (final Conversation conversation in conversations) {
      // 客服 type=3 与单聊同组:真源 tabOf 决策 2「分 tab 的轴是能不能回」。
      final String key =
          conversation.type == kImTypeSingle ||
              conversation.type == kImTypeMerchant
          ? stringsOf(context).imDirect
          : !conversation.isGroup
          ? stringsOf(context).imNotifications
          : conversation.counterparty.bizKey.startsWith('topic_')
          ? stringsOf(context).imThemeChannels
          : conversation.counterparty.bizKey.startsWith('club_')
          ? stringsOf(context).imClubChannels
          : conversation.counterparty.bizKey.startsWith('team_')
          ? stringsOf(context).imTeamChannels
          : stringsOf(context).imOtherChannels;
      (groups[key] ??= <Conversation>[]).add(conversation);
    }
    return groups.entries
        .expand((MapEntry<String, List<Conversation>> entry) {
          return <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                CyTokens.space1,
              ),
              // iOS 分组列表 section header:Footnote 13 Semibold + 次级灰(L2 标题式
              // 大小写,不全大写),与本页 .conv-time 的次级灰层级一致。
              // labelLarge 是 Material 档位、暗色下无对比度,不归这里。
              child: Semantics(
                header: true,
                child: Text(
                  entry.key,
                  style: CyType.footnote.copyWith(
                    fontWeight: FontWeight.w600,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
            ),
            ...entry.value.asMap().entries.map(
              (MapEntry<int, Conversation> item) => _ConversationTile(
                conv: item.value,
                isLast: item.key == entry.value.length - 1,
                openKey: _openRow,
                onOpen: (bool open) => setState(
                  () => _openRow = open ? item.value.conversationId : null,
                ),
                onChanged: () => ref.invalidate(imConversationsProvider),
                actionPresenter: widget.actionPresenter,
              ),
            ),
          ];
        })
        .toList(growable: false);
  }
}

/// 「竞猜待答」入口。玩家押完了,答案得商家给,而且**有期限** ——
/// 超过 48 小时不给,那一轮由平台作废、谁都拿不到奖。放在消息里,
/// 商家是在这儿被提醒的,不必自己想起来去翻点位。
///
/// ⚠️ 只对**能结算的人**出现,问的是身份、不是待办条数:在这里拉待办会把
///   「不是商家」这个正常回执静默吞掉,同一段静默也会吞掉真的网络失败 ——
///   商家就再也收不到提醒,且没有任何痕迹(小程序注释原话)。
class _PredictInboxEntry extends ConsumerWidget {
  const _PredictInboxEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool visible =
        ref.watch(merchantCanSettlePredictProvider).value ?? false;
    if (!visible) return const SizedBox.shrink();
    return CyCell(
      key: const Key('im-predict-entry'),
      title: stringsOf(context).imPredictInbox,
      subtitle: stringsOf(context).imPredictInboxHint,
      onTap: () => context.push('/merchant/predict'),
    );
  }
}

class _ConversationTile extends ConsumerStatefulWidget {
  const _ConversationTile({
    required this.conv,
    required this.onChanged,
    required this.isLast,
    required this.openKey,
    required this.onOpen,
    this.actionPresenter,
  });
  final Conversation conv;

  /// 标已读/免打扰/删除后让列表重取，以服务端状态为准。
  final VoidCallback onChanged;

  /// 最后一行不画分隔线(§3.9 IM1:系统分隔线)。
  final bool isLast;

  /// 当前展开的是哪一行 —— 同一时刻只开一行(iOS 行为)。
  final Object? openKey;
  final ValueChanged<bool> onOpen;
  final ImConversationActionPresenter? actionPresenter;

  @override
  ConsumerState<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends ConsumerState<_ConversationTile> {
  late final RequestSessionScope _requestScope;

  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  bool _busy = false;
  bool _menuOpen = false;

  List<ImConversationActionItem> get _items => <ImConversationActionItem>[
    ImConversationActionItem(id: 'read', title: stringsOf(context).imRead),
    ImConversationActionItem(
      id: 'mute',
      title: switch (widget.conv.muted) {
        true => stringsOf(context).imUnmute,
        false => stringsOf(context).imMute,
        null => stringsOf(context).imMuteUnknown,
      },
    ),
    ImConversationActionItem(
      id: 'delete',
      title: stringsOf(context).imDelete,
      isDestructive: true,
    ),
    ImConversationActionItem(id: 'cancel', title: stringsOf(context).cancel, isCancel: true),
  ];

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, message, isError: isError);
  }

  Future<String?> _showCupertinoActionSheet(
    List<ImConversationActionItem> items,
  ) {
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        actions: items
            .where((ImConversationActionItem item) => !item.isCancel)
            .map(
              (ImConversationActionItem item) => CupertinoActionSheetAction(
                isDestructiveAction: item.isDestructive,
                onPressed: () => Navigator.of(sheetContext).pop(item.id),
                child: Text(item.title),
              ),
            )
            .toList(growable: false),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(stringsOf(context).cancel),
        ),
      ),
    );
  }

  Future<String?> _showActionSheet() async {
    final ImConversationActionPresenter presenter =
        widget.actionPresenter ??
        const _LiquidGlassImConversationActionPresenter();
    final List<ImConversationActionItem> items = _items;
    if (presenter.supportsNativeActionSheet) {
      try {
        return await presenter.showActionSheet(context: context, items: items);
      } on MissingPluginException {
        // 原生通道未注册，降级到 Cupertino action sheet。
      } on PlatformException {
        // 系统 presentation 暂不可用，降级但不改变动作。
      }
    }
    if (!mounted) return null;
    return _showCupertinoActionSheet(items);
  }

  /// 长按菜单:标已读 / 免打扰(或恢复提醒) / 删除。
  ///
  /// ⚠️ 删除的是**我这一侧的会话**,不是把消息从对方那儿撤回 ——
  ///   文案不能写「撤回」或「已销毁」,那是对用户撒谎。
  Future<void> _menu() async {
    if (_busy || _menuOpen) return;
    setState(() => _menuOpen = true);
    String? action;
    try {
      action = await _showActionSheet();
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
    if (action == null || action == 'cancel' || !mounted) return;
    if (action != 'read' && action != 'mute' && action != 'delete') return;
    await _run(action);
  }

  /// 执行一个动作。★ 长按菜单与左右滑动**共用这一个出口** ——
  ///   两份实现迟早会分叉成两套语义(L6:滑动与长按顶部动作必须一致)。
  Future<void> _run(String action) => RequestSessionScope.run(
    _requestScope,
    () => _runScoped(action),
  );

  Future<void> _runScoped(String action) async {
    if (_busy) return;
    if (action == 'mute' && widget.conv.muted == null) {
      _toast(stringsOf(context).imMuteRefresh, isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      ImReceipt? message;
      if (action == 'read') {
        await ref.read(imApiProvider).read(widget.conv.conversationId);
      } else if (action == 'mute') {
        message = await ref
            .read(imApiProvider)
            .muteReceipt(widget.conv.conversationId, muted: !widget.conv.muted!);
      } else if (action == 'delete') {
        final bool ok = await cyConfirm(
          context,
          title: stringsOf(context).imDeleteConversation,
          content: stringsOf(context).imDeleteConfirm,
          confirmText: stringsOf(context).imDelete,
          danger: true,
        );
        if (!ok || !mounted) return;
        message = await ref
            .read(imApiProvider)
            .deleteConversationReceipt(widget.conv.conversationId);
      }
      if (!mounted) return;
      if (message != null) _toast(imReceiptText(message, stringsOf(context)));
      widget.onChanged();
    } catch (e) {
      _toast(imErrorText(e, stringsOf(context)), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final conv = widget.conv;
    final cp = conv.counterparty;
    final name = conversationDisplayName(context, conv);
    final bool unread = conv.unread > 0;
    void openChat() {
      // 带上对方 memberId —— 拉黑接口要的是 target_member_id,
      // 只有 conversationId 拉不了黑。
      final extra = <String, String>{
        'name': name,
        'avatar': cp.avatar,
        'memberId': cp.id.toString(),
      };
      context.push('/im/chat/${conv.conversationId}', extra: extra);
    }

    return CySwipeRow(
      selfKey: conv.conversationId,
      openKey: widget.openKey,
      enabled: !_busy,
      onOpen: widget.onOpen,
      // 左→右:标已读 + 免打扰。顺序与长按菜单同源(L6)。
      leading: <CySwipeAction>[
        if (unread)
          CySwipeAction(
            id: 'read',
            label: stringsOf(context).imRead,
            icon: CupertinoIcons.checkmark_alt,
            onPressed: () => _run('read'),
          ),
        CySwipeAction(
          id: 'mute',
          label: conv.muted == true ? stringsOf(context).imUnmute : stringsOf(context).imMute,
          icon: conv.muted == true
              ? CupertinoIcons.bell
              : CupertinoIcons.bell_slash,
          onPressed: () => _run('mute'),
        ),
      ],
      // 右→左:删除(破坏性)。★ 滑动只**露出**,真删还要过一次 cyConfirm ——
      //   划一下就没了,等于把每一次误触直接变成后果。
      trailing: <CySwipeAction>[
        CySwipeAction(
          id: 'delete',
          label: stringsOf(context).imDelete,
          icon: CupertinoIcons.delete,
          destructive: true,
          onPressed: () => _run('delete'),
        ),
      ],
      child: Semantics(
        button: true,
        label: stringsOf(context).imConversationSemantics(name),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _busy ? null : _menu,
          onTap: openChat,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space4,
                  vertical: CyTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    _ConversationAvatar(conv: conv, name: name),
                    const SizedBox(width: 11), // --cy-legacy-22(22rpx)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        // .conv-name:subtitle(32rpx) + weight 700
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (conv.type ==
                                        kImTypeMerchant) ...<Widget>[
                                      const SizedBox(width: CyTokens.space1),
                                      const _OfficialTag(),
                                    ],
                                    if (conv.muted == true) ...<Widget>[
                                      const SizedBox(width: CyTokens.space1),
                                      Icon(
                                        CupertinoIcons.bell_slash,
                                        size: 14,
                                        color: p.textTertiary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (conv.lastMsgAt != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: CyTokens.space2,
                                  ),
                                  child: Text(
                                    fmtConversationTime(conv.lastMsgAt, context: context),
                                    // .conv-time:label(24rpx) + --cy-text-secondary
                                    style: textTheme.labelMedium?.copyWith(
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: CyTokens.space1), // 8rpx
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  conversationPreview(context, conv),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  // .conv-preview:body(28rpx) + --cy-text-secondary
                                  // ★ 未读时摘要提到主色 ——「信息」就是这么分已读/未读的:
                                  //   靠整行的轻重,不是靠多贴一个点。
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: unread
                                        ? p.textPrimary
                                        : p.textSecondary,
                                  ),
                                ),
                              ),
                              if (unread) ...<Widget>[
                                const SizedBox(
                                  width: 7,
                                ), // --cy-legacy-14(14rpx)
                                CyBadge(count: conv.unread),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.isLast)
                Container(
                  key: const Key('im-separator'),
                  // 系统分隔线,缩进到文字起点(16 边距 + 头像 56 + 间距 11)。
                  // 不缩进 = 把两行"切开"的一刀;缩进才是「信息」的样子。
                  // ★ 颜色走系统语义色(§3.6 分工),不挪用品牌色:分隔线是
                  //   系统层,换个外观/开高对比时该由系统决定。
                  height: 1 / MediaQuery.devicePixelRatioOf(context),
                  margin: const EdgeInsets.only(left: 83),
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「官方」标签(会话类型 3,小程序 im/list 的 .official-tag)——
/// 官方客服会话与普通私信在一行里长得一样,用户会以为对面是个真人。
/// 配色跟真源同语义:蓝 = 信息/系统消息(DS §2.1),用状态 info 而不是品牌色
/// (C1:品牌色只给主 CTA/未读等状态);软底 + info 字是仓内 info 徽标同款
/// (`activity_detail_page` / `my_coupons_page`)。
class _OfficialTag extends StatelessWidget {
  const _OfficialTag();

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space1,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: p.statusInfo.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
      child: Text(
        stringsOf(context).imOfficial,
        style: TextStyle(
          fontSize: CyTokens.typeMicro,
          fontWeight: FontWeight.w700,
          color: p.statusInfo,
        ),
      ),
    );
  }
}

/// 会话头像。★ 系统通知**没有**对方头像 —— 拿一个空圆冒充「某个人」是错的表达,
/// 换成铃铛图标头(小程序 im/list 的 .sys-avatar 是同一处取舍)。
/// 其余走 CyAvatar:网络图 + errorBuilder 回落到首字母占位、112rpx、圆形描边。
class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.conv, required this.name});

  final Conversation conv;
  final String name;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    if (conv.type == kImTypeSystem) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.bgElevated,
          border: Border.all(color: p.borderSubtle),
        ),
        alignment: Alignment.center,
        child: Icon(CupertinoIcons.bell, size: 24, color: p.textSecondary),
      );
    }
    return CyAvatar(url: conv.counterparty.avatar, fallback: name, size: 56);
  }
}
