import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import '../../core/media_art_uri.dart';
import '../../core/network/dio_client.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/providers.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/map/apple_scene_view.dart';
import '../../core/map/map_launcher.dart';
import '../../core/map/map_scene.dart';
import 'transfer_to_club_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/topic.dart';
import 'topic_detail_controller.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'topic_review_sheet.dart';
import 'topic_self_play_sheet.dart';
import 'topic_self_play_service.dart';

enum TopicAudioPlaybackState { loading, paused, playing, completed }

abstract interface class TopicAudioPlayer {
  Stream<TopicAudioPlaybackState> get stateStream;

  /// 放不出来。UI 的处置:收回按钮态 + 提示 + 让下一次点击重新 load。
  ///
  /// ⚠️ 覆盖面必须含**运行中**的播放错误(CDN 中途断流 / 解码失败),不只是
  ///   起播时 `load` / `play()` 抛的那一类 —— 那两类走 Future,运行中那一类只走
  ///   just_audio 自己的 `errorStream`(just_audio.dart:344-352 从 playbackEvent
  ///   造 PlayerException → :640 errorStream)。漏掉后者 = 音频断了但按钮永远亮着、
  ///   一句提示都没有,再点一下还被当成「暂停」,必须点两下才能重来。
  Stream<Object> get errorStream;

  Future<void> load(Uri uri, {MediaItem? mediaItem});

  Future<void> play();

  Future<void> pause();

  Future<void> seekToStart();

  Future<void> dispose();
}

typedef TopicAudioPlayerFactory = TopicAudioPlayer Function();

/// 把播放器状态流折成 UI 认的四态。
///
/// ★ 抽成顶层函数是为了能直接喂状态序列断言 ——
///   `just_audio.AudioPlayer` 在单测里起不来，挂在实例上就没东西能钉住这条链。
/// ⚠️ 本函数只接得住两个终态：播完（`completed`）和平台侧打断
///   （来电 / 音频会话被抢 ⇒ `playing` 掉回 false ⇒ `paused`）。
///   第三个终态「出错」在这条流上**看不见**：just_audio 出错时
///   `playing` 仍是 true，只有 `processingState` 掉回 idle，落到这里依旧是
///   `playing` —— 所以它必须由 [topicAudioErrorsFrom] 那一路补上。
Stream<TopicAudioPlaybackState> topicAudioStatesFrom(
  Stream<just_audio.PlayerState> states,
) => states.map((just_audio.PlayerState state) {
  if (state.processingState == just_audio.ProcessingState.loading ||
      state.processingState == just_audio.ProcessingState.buffering) {
    return TopicAudioPlaybackState.loading;
  }
  if (state.processingState == just_audio.ProcessingState.completed) {
    return TopicAudioPlaybackState.completed;
  }
  return state.playing
      ? TopicAudioPlaybackState.playing
      : TopicAudioPlaybackState.paused;
}).distinct();

/// 把两路播放错误合成一条：
/// - [launch] = **起播时**抛的（`setUrl` / `play()` 的 Future）
/// - [runtime] = **播放中**出的（CDN 中途断流 / 解码失败）。just_audio 只从
///   `errorStream` 报这一类，不订阅它 = 音频断了但按钮永远亮着、一句提示都没有。
///
/// ★ 抽成顶层函数是为了单独钉合流规则。**接哪条流**这层胶水另有守卫：
///   `just_audio.AudioPlayer` 起不了真播放器，但它是普通 class，
///   `implements + noSuchMethod` 就能注进构造函数的 `{player}`。
Stream<Object> topicAudioErrorsFrom(
  Stream<Object> launch,
  Stream<Object> runtime,
) {
  late final StreamController<Object> out;
  List<StreamSubscription<Object>> subs = <StreamSubscription<Object>>[];
  out = StreamController<Object>.broadcast(
    onListen: () => subs = <Stream<Object>>[launch, runtime]
        .map((Stream<Object> s) => s.listen(out.add, onError: out.addError))
        .toList(),
    onCancel: () async {
      for (final StreamSubscription<Object> s in subs) {
        await s.cancel();
      }
      subs = <StreamSubscription<Object>>[];
    },
  );
  return out.stream;
}

class JustAudioTopicAudioPlayer implements TopicAudioPlayer {
  JustAudioTopicAudioPlayer({just_audio.AudioPlayer? player})
    : _player = player ?? just_audio.AudioPlayer();

  final just_audio.AudioPlayer _player;
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  @override
  Stream<TopicAudioPlaybackState> get stateStream =>
      topicAudioStatesFrom(_player.playerStateStream);

  @override
  Stream<Object> get errorStream =>
      topicAudioErrorsFrom(_errors.stream, _player.errorStream);

  @override
  Future<void> load(Uri uri, {MediaItem? mediaItem}) async {
    // tag = MediaItem 是给 just_audio_background 的锁屏/控制中心元数据。
    await _player.setUrl(uri.toString(), tag: mediaItem);
  }

  @override
  Future<void> play() {
    // just_audio.play() 会等到暂停或播放完才结束，UI 指令不应长时占用回调。
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        if (!_errors.isClosed) _errors.add(error);
      }),
    );
    return Future<void>.value();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekToStart() => _player.seek(Duration.zero);

  @override
  Future<void> dispose() async {
    await _errors.close();
    await _player.dispose();
  }
}

/// 路线详情:封面(5:3)/名称/简介/章节/节点。
/// 对齐小程序 `pages/topic/index`(`.det1` 5:3 封面、`.det-type` 标题、节点编号)。
class TopicDetailPage extends ConsumerWidget {
  const TopicDetailPage({
    super.key,
    required this.topicId,
    this.audioPlayerFactory,
    this.onShowNotice,
  });
  final int topicId;
  final TopicAudioPlayerFactory? audioPlayerFactory;

  /// 「立即解锁」被未登录/商家身份挡住时的提示出口。默认走真机原生通知;
  /// 注入它只为让 widget 测试能断言点击生效,而不拖进真实登录流/钥匙串通道。
  final void Function(BuildContext context, String message)? onShowNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(topicDetailProvider(topicId));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 小程序的标题在内容区；这里只让原生导航栏承载返回手势与返回键，
      // 不把大标题搬到居中栏上，以免改变小程序的首屏几何。
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('路线详情'),
              Expanded(
                child: detail.when(
                  loading: () => const CySkeleton(type: CySkeletonType.detail),
                  error: (Object err, StackTrace st) => isUnauthorizedError(err)
                      // ★ 游客(和 App Store 审核员)从列表/分享点进来必然走到这里:
                      //   路由对游客开放(`_loginRequiredPrefixes` 不含 /topic),而后端
                      //   `/api/topic/info-to-user` 对无 token 的请求返回 401(生产实测)。
                      //   说成「检查网络」是**误导** —— 后端好好的,是要登录;而且
                      //   「重试」按多少次都还是 401,是条死路。改成可恢复的登录引导。
                      ? StatusView(
                          message: '登录后查看路线详情',
                          sub: '这一步需要登录,登录完会自动回到这一页。',
                          icon: CupertinoIcons.lock,
                          retryLabel: '去登录',
                          onRetry: () async {
                            if (!await requireLogin(context, ref)) return;
                            ref.invalidate(topicDetailProvider(topicId));
                          },
                        )
                      : StatusView(
                          message: '没能打开这条路线',
                          sub: '检查网络后重试',
                          icon: CupertinoIcons.exclamationmark_triangle,
                          onRetry: () =>
                              ref.invalidate(topicDetailProvider(topicId)),
                        ),
                  data: (TopicDetail d) => _DetailBody(
                    detail: d,
                    audioPlayerFactory: audioPlayerFactory,
                    onShowNotice: onShowNotice,
                  ),
                ),
              ),
              // ★ V9:底部动作条。对齐小程序 `pages/topic/index/index.wxml:330-339` 的
              //   三分支售票门禁 —— 之前这页整个没有动作条,看完只能返回。
              detail.maybeWhen(
                data: (TopicDetail d) => _TopicFooter(detail: d),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({
    required this.detail,
    this.audioPlayerFactory,
    this.onShowNotice,
  });
  final TopicDetail detail;
  final TopicAudioPlayerFactory? audioPlayerFactory;
  final void Function(BuildContext context, String message)? onShowNotice;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  String _activeTab = 'detail';
  late final TopicAudioPlayer _audioPlayer;
  late final StreamSubscription<TopicAudioPlaybackState> _audioSubscription;
  late final StreamSubscription<Object> _audioErrorSubscription;
  TopicAudioPlaybackState _audioState = TopicAudioPlaybackState.paused;
  String? _loadedAudioUrl;
  bool _audioFailed = false;

  TopicDetail get detail => widget.detail;

  /// 提示:优先用注入的出口(测试),否则走真机原生通知。
  void _notice(BuildContext context, String message) {
    final hook = widget.onShowNotice;
    if (hook != null) {
      hook(context, message);
      return;
    }
    CyNativeNotice.show(context, message, isError: true);
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer =
        widget.audioPlayerFactory?.call() ?? JustAudioTopicAudioPlayer();
    // ★ 两条 listen 都要带 `onError`：流本身出错时没有 onError 就是**未捕获的
    //   zone error**（在 release 里直接抛到根），而不是走到 UI 的失败提示。
    _audioSubscription = _audioPlayer.stateStream.listen(
      _onAudioState,
      onError: _onAudioError,
    );
    _audioErrorSubscription = _audioPlayer.errorStream.listen(
      _onAudioError,
      onError: _onAudioError,
    );
  }

  void _onAudioState(TopicAudioPlaybackState state) {
    if (!mounted) return;
    if (state == TopicAudioPlaybackState.completed) {
      setState(() => _audioState = TopicAudioPlaybackState.paused);
      unawaited(_resetCompletedAudio());
      return;
    }
    setState(() => _audioState = state);
  }

  void _onAudioError(Object error) {
    if (!mounted) return;
    setState(() {
      _audioState = TopicAudioPlaybackState.paused;
      _audioFailed = true;
      _loadedAudioUrl = null;
    });
    CyNativeNotice.show(context, '主题音频暂时无法播放', isError: true);
  }

  Future<void> _resetCompletedAudio() async {
    try {
      await _audioPlayer.pause();
      await _audioPlayer.seekToStart();
    } catch (_) {
      if (!mounted) return;
      setState(() => _audioFailed = true);
      CyNativeNotice.show(context, '主题音频暂时无法播放', isError: true);
    }
  }

  Future<void> _toggleAudio() async {
    if (_audioState == TopicAudioPlaybackState.loading) return;
    if (_audioState == TopicAudioPlaybackState.playing) {
      try {
        await _audioPlayer.pause();
      } catch (error) {
        _onAudioError(error);
      }
      return;
    }

    final raw = detail.audioUrl;
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      if (!mounted) return;
      CyNativeNotice.show(context, '主题音频暂时无法播放', isError: true);
      return;
    }

    try {
      if (_loadedAudioUrl != raw) {
        setState(() {
          _audioState = TopicAudioPlaybackState.loading;
          _audioFailed = false;
        });
        await _audioPlayer.load(uri, mediaItem: _audioMediaItem(uri));
        _loadedAudioUrl = raw;
      }
      await _audioPlayer.play();
    } catch (_) {
      _loadedAudioUrl = null;
      if (!mounted) return;
      setState(() {
        _audioState = TopicAudioPlaybackState.paused;
        _audioFailed = true;
      });
      CyNativeNotice.show(context, '主题音频暂时无法播放', isError: true);
    }
  }

  /// 锁屏/控制中心元数据。字段全部取路线详情真源:名称/发起者/俱乐部/封面/时长。
  ///
  /// ⚠️ `duration` 不许为 null:just_audio_background 的进度拖动
  ///   (`_seekRelative`/`_seekContinuously`)对 `MediaItem.duration!` 强解包,
  ///   null 会在锁屏快进时炸。下发时长优先;没有就落到 1ms —— 锁屏 scrubber
  ///   本来画不出来,这个值只是不炸的兜底。
  MediaItem _audioMediaItem(Uri uri) => MediaItem(
    id: 'topic-audio-${detail.id}-$uri',
    title: detail.name,
    artist: detail.initiatorName,
    album: detail.clubName,
    artUri: mediaArtUri(detail.picUrl),
    duration: (detail.audioDuration == null || detail.audioDuration! <= 0)
        ? const Duration(milliseconds: 1)
        : Duration(seconds: detail.audioDuration!),
  );

  @override
  void dispose() {
    unawaited(_audioSubscription.cancel());
    unawaited(_audioErrorSubscription.cancel());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  Future<void> _openLocation(TopicNode node) async {
    final result = await launchNavigation(
      lat: node.latitude,
      lng: node.longitude,
      name: node.name.isEmpty ? '路线节点' : node.name,
      address: node.address,
      isIOS: Theme.of(context).platform == TargetPlatform.iOS,
    );
    if (!mounted) return;
    final message = mapLaunchMessage(result);
    if (message.isNotEmpty) {
      CyNativeNotice.show(context, message, isError: true);
    }
  }

  /// 付费墙「立即解锁」= 与底栏「随时开玩」同一个 selfPlayBuy 流
  /// (index.wxml:465 都 bindtap="selfPlayBuy")。
  Future<void> _unlockStory() async {
    final injected = widget.onShowNotice;
    if (injected == null) {
      // 真机:先过登录闸(测试里注入 onShowNotice 绕开它,不拖进真实登录/钥匙串)。
      if (!await requireLogin(context, ref) || !mounted) return;
    }
    if (!mounted) return;
    final role = ref.read(authControllerProvider).user?.effectiveRole;
    if (role == 'merchant') {
      _notice(context, '商家用户不可购买');
      return;
    }
    if (injected != null) {
      // 测试路径:非商家非游客 → 证明确实走到了解锁流,不拉起真实自玩购买 sheet。
      injected(context, 'unlock');
      return;
    }
    await showTopicSelfPlaySheet(context, topicId: detail.id);
  }

  /// 已购票去「我的订单」找回:index.js:1039 → /subpackageMember/order/order。
  void _goMyOrders() => context.push('/orders');

  Future<void> _showReviewSheet() async {
    if (!await requireLogin(context, ref) || !mounted) return;
    await showTopicReviewSheet(context, topicId: detail.id);
  }

  Future<void> _graduateBeta(WidgetRef ref) async {
    final bool ok = await cyConfirm(
      context,
      title: '转为正式主题',
      content: '转正后不再显示 Beta 试玩标识。主题内容、已售出的票和进行中的行程都不受影响。',
      confirmText: '确认转正',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(topicApiProvider).graduateBetaTopic(detail.id);
      if (!mounted) return;
      CyNativeNotice.show(context, '已转为正式主题');
      // 转正是服务端事实:回来重读详情,别在本地手改 betaFlag —— 那会和后端漂。
      ref.invalidate(topicDetailProvider(detail.id));
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        _Cover(url: detail.picUrl),
        const SizedBox(height: CyTokens.space3),
        Text(
          detail.name.isEmpty ? '未命名路线' : detail.name,
          style: textTheme.titleMedium?.copyWith(
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w700,
            color: CyTokens.textPrimary,
          ),
        ),
        if (detail.subtitle?.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            detail.subtitle!,
            style: textTheme.labelMedium?.copyWith(
              fontSize: CyTokens.typeLabel,
              height: CyTokens.leadingNormal,
              color: CyTokens.textSecondary,
            ),
          ),
        ],
        // ★ Beta 试玩期(`pages/topic/index/index.wxml:73-82`):标识对所有人可见;
        //   「转为正式主题」只有作者(isOwner)看得到,后端也只认创建者。
        //   转正不可逆 —— 按钮必须走二次确认,而且要说清票和行程不受影响,
        //   否则作者不敢点。
        if (detail.betaFlag == 1) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          Container(
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: CyTokens.bgSurface,
              border: Border.all(color: CyTokens.borderSubtle),
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const CyTag(label: 'Beta 试玩'),
                    const SizedBox(width: CyTokens.space2),
                    Expanded(
                      child: Text(
                        'Beta 期主题，欢迎在评论区反馈体验',
                        style: textTheme.labelSmall?.copyWith(
                          fontSize: CyTokens.typeCaption,
                          color: CyTokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (detail.isOwner) ...<Widget>[
                  const SizedBox(height: CyTokens.space3),
                  CyNativeButton(
                    key: const Key('topic-graduate-beta'),
                    label: '转为正式主题',
                    onPressed: () => _graduateBeta(ref),
                    role: CyNativeButtonRole.secondary,
                    height: 44,
                  ),
                ],
              ],
            ),
          ),
        ],
        if (detail.categoryNames.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          Wrap(
            spacing: CyTokens.space1,
            runSpacing: CyTokens.space1,
            children: detail.categoryNames
                .map((name) => CyTag(label: name))
                .toList(),
          ),
        ],
        if (detail.initiatorName?.isNotEmpty == true ||
            detail.clubName?.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          Wrap(
            spacing: CyTokens.space4,
            runSpacing: CyTokens.space2,
            children: <Widget>[
              if (detail.initiatorName?.isNotEmpty == true)
                _Attribution(
                  icon: CupertinoIcons.person,
                  label: '发起人',
                  value: detail.initiatorName!,
                ),
              if (detail.clubName?.isNotEmpty == true)
                _Attribution(
                  icon: CupertinoIcons.person_3,
                  label: '承接俱乐部',
                  value: detail.clubName!,
                ),
            ],
          ),
        ],
        // ★ 移交给俱乐部承接。判据是 `isOwner`(后端 ApiTopicController:996
        //   `isOwner = memberId == 我 ? 1 : 0`)—— 非创建者会被后端拒
        //   「无权移交该主题」,入口就不给。
        if (detail.isOwner) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          SizedBox(
            width: double.infinity,
            child: CyNativeButton(
              key: const Key('topic-transfer-to-club'),
              label: '移交给俱乐部承接',
              icon: const CyNativeButtonIcon(
                sfSymbol: 'arrow.left.arrow.right',
                fallback: CupertinoIcons.arrow_left_right,
              ),
              onPressed: () async {
                final int? newId = await showTransferToClubSheet(
                  context,
                  topicId: detail.id,
                );
                if (newId == null || !context.mounted) return;
                // 移交完下一步一定是去配新草稿的票种 —— 直接带过去。
                await cyConfirm(
                  context,
                  title: '已移交',
                  content: '新的城市定向草稿已生成,接下来配票种并邀请该俱乐部承接。',
                  confirmText: '去配置',
                  showCancel: false,
                );
                if (context.mounted) context.push('/topic/$newId');
              },
              role: CyNativeButtonRole.secondary,
              height: 44,
            ),
          ),
        ],
        // 参与商家。★ 小程序 topic/merchantinfo 顶部的统计栏有这一项,
        //   而它对一条正在招商的路线是关键信息 —— 商家看的就是「已经有几家了」。
        // ⚠️ 拿不到时**整栏不显示**,不兜 0:
        //   「还没有商家承接」和「这个数没算出来」是两回事,
        //   写死 0 会劝退本来想报名的商家。
        if (detail.merchantCount != null) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
        ],
        _TopicMetrics(detail: detail),
        const SizedBox(height: CyTokens.space4),
        CyTabs(
          key: const Key('topic-detail-tabs'),
          variant: CyTabsVariant.segmented,
          tabs: const <CyTab>[
            CyTab(key: 'detail', label: '详情'),
            CyTab(key: 'nodes', label: '路线节点'),
            CyTab(key: 'route', label: '路线'),
          ],
          active: _activeTab,
          onChanged: (value) => setState(() => _activeTab = value),
        ),
        const SizedBox(height: CyTokens.space2),
        switch (_activeTab) {
          'nodes' => _TopicNodesView(detail: detail, onLocation: _openLocation),
          'route' => _TopicRouteList(detail: detail, onLocation: _openLocation),
          _ => _TopicOverview(
            detail: detail,
            audioState: _audioState,
            audioFailed: _audioFailed,
            onPlayAudio: _toggleAudio,
            onReview: _showReviewSheet,
          ),
        },
        // 故事付费墙:index.wxml:462 `storyLocked && lockedChapterCount>0`。
        // 挂在故事/路线内容末尾,解锁前只露出已解锁章节 + 这张卡。
        if (detail.showStoryPaywall) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          _StoryPaywall(
            price: detail.selfPlayPrice,
            onUnlock: _unlockStory,
            onMyOrders: _goMyOrders,
          ),
        ],
      ],
    );
  }
}

/// 故事付费墙卡。真源 `pages/topic/index/index.wxml:462-468` +
/// index.wxss 的 `.topic-story-paywall`。解锁走 selfPlayBuy(与底栏同一入口),
/// 「已购票」链去我的订单找回 —— 后端只回填 isSignUp,不自动核销已购的自玩票。
class _StoryPaywall extends StatelessWidget {
  const _StoryPaywall({
    required this.price,
    required this.onUnlock,
    required this.onMyOrders,
  });

  final double? price;
  final VoidCallback onUnlock;
  final VoidCallback onMyOrders;

  @override
  Widget build(BuildContext context) {
    final p = price;
    final priceText = (p == null || p <= 0) ? '免费' : '¥${p.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: CyTokens.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: CyTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '解锁完整体验',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: CyTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            '解锁后可看全部故事线、答题揭秘与到店权益',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
          ),
          const SizedBox(height: CyTokens.space3),
          Text(
            priceText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: CyTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            key: const Key('topic-story-unlock'),
            label: '立即解锁',
            onPressed: onUnlock,
            height: 44,
          ),
          const SizedBox(height: CyTokens.space2),
          Center(
            child: CupertinoButton(
              key: const Key('topic-story-my-orders'),
              minimumSize: const Size(44, 44),
              onPressed: onMyOrders,
              child: Text(
                '已购票？去「我的订单」找回',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: CyTokens.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: palette.textSecondary),
        const SizedBox(width: CyTokens.space1),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}

class _TopicMetrics extends StatelessWidget {
  const _TopicMetrics({required this.detail});
  final TopicDetail detail;

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, String, String)>[
      ('评价', detail.averageRating?.toStringAsFixed(1) ?? '0', '★'),
      ('预计探索', '${detail.totalHoursText}+', '小时'),
      (
        '开放时间',
        detail.openPeriodText.isEmpty ? '待定' : detail.openPeriodText,
        '总时长',
      ),
      ('总里程', detail.totalMileage?.toString() ?? '—', '公里'),
      ('参与商家', detail.merchantCount?.toString() ?? '—', '家'),
    ];
    return Wrap(
      key: const Key('topic-merchant-count'),
      spacing: CyTokens.space2,
      runSpacing: CyTokens.space2,
      children: metrics
          .map(
            (item) => SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(item.$1, style: Theme.of(context).textTheme.labelSmall),
                  Text(item.$2, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    item.$3,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TopicOverview extends StatelessWidget {
  const _TopicOverview({
    required this.detail,
    required this.audioState,
    required this.audioFailed,
    required this.onPlayAudio,
    required this.onReview,
  });
  final TopicDetail detail;
  final TopicAudioPlaybackState audioState;
  final bool audioFailed;
  final VoidCallback onPlayAudio;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final templates = detail.chapters
        .expand((chapter) => chapter.nodes)
        .map((node) => node.template)
        .whereType<TopicTemplate>()
        .toList();
    final merchants = detail.merchants;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(detail.name, style: Theme.of(context).textTheme.titleLarge),
        if (detail.subtitle?.isNotEmpty == true) Text(detail.subtitle!),
        if (detail.audioUrl?.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          Semantics(
            key: const Key('topic-audio'),
            container: true,
            button: true,
            enabled: audioState != TopicAudioPlaybackState.loading,
            label: audioState == TopicAudioPlaybackState.loading
                ? '主题音频加载中'
                : audioState == TopicAudioPlaybackState.playing
                ? '暂停主题音频'
                : '播放主题音频',
            liveRegion: audioFailed,
            onTap: audioState == TopicAudioPlaybackState.loading
                ? null
                : onPlayAudio,
            child: ExcludeSemantics(
              child: CyCell(
                title: '主题音频讲解',
                subtitle: audioState == TopicAudioPlaybackState.loading
                    ? '正在加载…'
                    : audioState == TopicAudioPlaybackState.playing
                    ? '${detail.audioDuration ?? 0} 秒 · 正在播放'
                    : audioFailed
                    ? '加载失败 · 点击重试'
                    : '${detail.audioDuration ?? 0} 秒 · 点此播放',
                leading: audioState == TopicAudioPlaybackState.loading
                    ? const CupertinoActivityIndicator()
                    : Icon(
                        audioState == TopicAudioPlaybackState.playing
                            ? CupertinoIcons.pause_circle
                            : CupertinoIcons.play_circle,
                      ),
                onTap: audioState == TopicAudioPlaybackState.loading
                    ? null
                    : onPlayAudio,
              ),
            ),
          ),
        ],
        if (templates.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          const CySectionTitle('节点介绍'),
          const SizedBox(height: CyTokens.space2),
          ...templates.map(
            (template) => CyCell(
              title: template.title,
              subtitle: [
                template.players,
                template.duration == null ? null : '${template.duration}分钟',
              ].whereType<String>().join(' · '),
              onTap: template.id <= 0
                  ? null
                  : () => context.push('/template/${template.id}'),
            ),
          ),
        ],
        const SizedBox(height: CyTokens.space5),
        const CySectionTitle('主题介绍'),
        const SizedBox(height: CyTokens.space2),
        Text(
          detail.introduction?.isNotEmpty == true
              ? detail.introduction!
              : '暂无介绍',
        ),
        const SizedBox(height: CyTokens.space5),
        const CySectionTitle('场次'),
        if (detail.perkCapacityText.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(detail.perkCapacityText),
        ],
        const SizedBox(height: CyTokens.space2),
        if (detail.tickets.isEmpty)
          const Text('暂无可参加的场次')
        else if (detail.productType == 2)
          ...detail.tickets.map(
            (ticket) => CyCell(
              title: ticket.name,
              subtitle: <String>[
                if (ticket.sessionTimeText.isNotEmpty) ticket.sessionTimeText,
                if (ticket.meetingPoint?.isNotEmpty == true)
                  '集合点 · ${ticket.meetingPoint}',
                if (ticket.refundRule?.isNotEmpty == true)
                  '退改 · ${ticket.refundRule}',
                ticket.remaining == null ? '余席待确认' : '余 ${ticket.remaining} 席',
              ].join('\n'),
              trailing: ticket.price == null
                  ? null
                  : Text('¥${ticket.price!.toStringAsFixed(2)}'),
            ),
          )
        else
          ...detail.tickets.map((ticket) => _TicketRosterTile(ticket: ticket)),
        if (detail.productType == 2 && detail.tickets.isNotEmpty)
          const Text('每人限购 1 张 · 场次内自由顺序，不带队'),
        if (merchants.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          const CySectionTitle('阵容/商家'),
          const SizedBox(height: CyTokens.space2),
          ...merchants.map(
            (merchant) => CyCell(
              title: merchant.name.isEmpty ? '商家' : merchant.name,
              subtitle: merchant.businessTime,
              onTap: merchant.memberId <= 0
                  ? null
                  : () => context.push(
                      '/merchant/public-home/member/${merchant.memberId}',
                    ),
            ),
          ),
        ],
        const SizedBox(height: CyTokens.space5),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                detail.averageRating?.toStringAsFixed(1) ?? '0',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            CyNativeButton(
              label: '投票',
              onPressed: onReview,
              role: CyNativeButtonRole.secondary,
              height: 44,
            ),
          ],
        ),
        if (detail.comments.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('还没有人评价过这条路线'),
              const SizedBox(height: CyTokens.space1),
              const Text('玩过之后回来写一条，可以获得平台积分。'),
              const SizedBox(height: CyTokens.space2),
              CyNativeButton(
                label: '成为第一个评价的人',
                onPressed: onReview,
                role: CyNativeButtonRole.secondary,
                height: 44,
              ),
            ],
          )
        else
          ...detail.comments.map((comment) => _CommentRow(comment: comment)),
        const SizedBox(height: CyTokens.space3),
        CyCell(
          title: '设计路线、报名、分享、评论都可以获得平台积分',
          subtitle: '和好友一起报名更划算，路线票可抵扣减免',
          onTap: () => context.push('/growth'),
        ),
      ],
    );
  }
}

/// 票种花名册(买了票的人)。
///
/// ⚠️ 小程序 2026-09-04 把「报名玩家」并进了「阵容/商家」(`pages/topic/index/index.js`
///   的判定表注释),App 侧这块**结构**是否还留着由对齐线裁定 —— 本批只做外观:
///   Material `ExpansionTile`/`ListTile`(Material 墨水涟漪 + 自带分隔线)换成系统行
///   (L3/§3.3),展开行为、字段、跳转一律不变。
class _TicketRosterTile extends StatefulWidget {
  const _TicketRosterTile({required this.ticket});

  final TopicTicket ticket;

  @override
  State<_TicketRosterTile> createState() => _TicketRosterTileState();
}

class _TicketRosterTileState extends State<_TicketRosterTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final TopicTicket ticket = widget.ticket;
    return Column(
      children: <Widget>[
        CupertinoListTile(
          padding: EdgeInsets.zero,
          onTap: () => setState(() => _expanded = !_expanded),
          title: Text(ticket.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('${ticket.registrants.length}/${ticket.totalInventory}'),
              const SizedBox(width: CyTokens.space2),
              AnimatedRotation(
                // 展开/收起只改箭头朝向;Reduce Motion 下不做旋转(A2)。
                duration: reduceMotion ? Duration.zero : CyMotion.fast,
                turns: _expanded ? 0.25 : 0,
                child: const Icon(CupertinoIcons.chevron_forward, size: 16),
              ),
            ],
          ),
        ),
        if (_expanded)
          for (final TopicRegistrant person in ticket.registrants)
            CupertinoListTile(
              padding: EdgeInsets.zero,
              leadingSize: 36,
              leading: CyAvatar(url: person.avatar, size: 36),
              title: Text(person.nickname),
              onTap: person.memberId <= 0
                  ? null
                  : () => context.push('/user/${person.memberId}'),
            ),
      ],
    );
  }
}

/// 一条评价:昵称 + 时间 + 星数 + 正文。
/// 小程序同款信息(`pages/topic/index/index.wxml` `.det6 .li`:tit/time/stars/desc)。
class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final TopicComment comment;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  comment.memberNickname,
                  style: textTheme.titleSmall?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                '${comment.rating} ★',
                style: textTheme.labelSmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            comment.createTime,
            style: textTheme.labelSmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            comment.contents,
            style: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _TopicNodesView extends StatelessWidget {
  const _TopicNodesView({required this.detail, required this.onLocation});
  final TopicDetail detail;
  final ValueChanged<TopicNode> onLocation;

  @override
  Widget build(BuildContext context) {
    final nodes = detail.chapters.expand((chapter) => chapter.nodes).toList();
    final points = <MapPoint>[
      for (int index = 0; index < nodes.length; index++)
        if (nodes[index].latitude != null && nodes[index].longitude != null)
          MapPoint(
            id: '${nodes[index].id}',
            latitude: nodes[index].latitude!,
            longitude: nodes[index].longitude!,
            title: nodes[index].name,
            subtitle: nodes[index].address,
            nodeId: nodes[index].id,
            topicId: detail.id,
            sortOrder: index,
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (points.isNotEmpty)
          SizedBox(
            key: const Key('topic-route-map'),
            height: 240,
            child: AppleSceneView(scene: MapScene.build(points: points)),
          )
        else
          const StatusView(
            key: Key('topic-route-map'),
            message: '路线地图待生成',
            sub: '节点还没有完整坐标',
          ),
        const SizedBox(height: CyTokens.space4),
        if (detail.chapters.isEmpty)
          const StatusView(message: '这条路线还没有节点', sub: '发布者完成路线配置后，这里会显示路线与节点')
        else
          ...detail.chapters.map(
            (chapter) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  chapter.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${detail.totalTimeText} · ${detail.locationCount} 个节点 · ${detail.templateCount} 个玩法',
                ),
                if (chapter.description?.isNotEmpty == true)
                  Text(chapter.description!),
                ...List<Widget>.generate(chapter.nodes.length, (index) {
                  final node = chapter.nodes[index];
                  return CyCell(
                    title:
                        '${index + 1}. ${node.description?.isNotEmpty == true ? node.description : node.name}',
                    subtitle: node.template?.title,
                    onTap: () => onLocation(node),
                  );
                }),
                const SizedBox(height: CyTokens.space4),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopicRouteList extends StatelessWidget {
  const _TopicRouteList({required this.detail, required this.onLocation});
  final TopicDetail detail;
  final ValueChanged<TopicNode> onLocation;

  @override
  Widget build(BuildContext context) => detail.chapters.isEmpty
      ? const StatusView(message: '这条路线还没有任务', sub: '发布者完成路线配置后，这里会显示每一站')
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: detail.chapters
              .map(
                (chapter) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      chapter.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${detail.totalTimeText} · ${detail.locationCount} 个节点 · ${detail.templateCount} 个玩法',
                    ),
                    const SizedBox(height: CyTokens.space2),
                    ...List<Widget>.generate(chapter.nodes.length, (index) {
                      final node = chapter.nodes[index];
                      return CyCell(
                        title:
                            '${index + 1}. ${node.name.isEmpty ? '未命名节点' : node.name}',
                        subtitle: <String>[
                          if (node.businessTime?.isNotEmpty == true)
                            node.businessTime!,
                          if (node.address?.isNotEmpty == true) node.address!,
                        ].join('\n'),
                        leading: node.images.isEmpty
                            ? const Icon(Icons.place_outlined)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  CyTokens.radiusSm,
                                ),
                                child: CyNetImage(
                                  node.images.first,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                        onTap: () => onLocation(node),
                      );
                    }),
                    const SizedBox(height: CyTokens.space4),
                  ],
                ),
              )
              .toList(),
        );
}

/// 5:3 封面,无图时兜底图标 + 文案。
/// 对齐小程序 `.det1`(aspect-ratio 5/3)。
class _Cover extends StatelessWidget {
  const _Cover({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final fallback = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.route_outlined, size: 40, color: palette.textDisabled),
        const SizedBox(height: CyTokens.space1),
        Text(
          '封面暂不可用',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: CyTokens.typeCaption,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
    return AspectRatio(
      aspectRatio: 5 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: (url == null || url!.isEmpty)
            ? fallback
            : ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
              ),
      ),
    );
  }
}

/// 主题底部动作条:照小程序 `pages/topic/index/index.wxml:330-339` 的三分支门禁。
///
/// ★ 判据取自后端 `TopicInfoVO`(48/49/57 行),不是猜的:
///   - `lifecycle` **空 = 普通主题,照常售票**;非空表示走招募流程,
///     1 招募中 / 2 定价中 —— 这两态**未到售票态,不可购买**(小程序注释里的 F2-3 售票门禁)。
///   - `selfPlay == 1` 才开放「自玩通行证」。⚠️ 判据是这个**开关**,
///     不是 `selfPlayPrice` 有没有值 —— 小程序用的就是 `info.selfPlay==1`。
class _TopicFooter extends ConsumerWidget {
  const _TopicFooter({required this.detail});

  final TopicDetail detail;

  Future<void> _openActivities(BuildContext context, WidgetRef ref) async {
    if (detail.merchantClosed) {
      CyNativeNotice.show(context, '商家暂停营业，暂不可报名', isError: true);
      return;
    }
    if (!await requireLogin(context, ref) || !context.mounted) return;
    final role = ref.read(authControllerProvider).user?.effectiveRole;
    if (role == 'merchant') {
      CyNativeNotice.show(context, '商家用户不可报名主题', isError: true);
      return;
    }
    try {
      final rows = await ref
          .read(topicSelfPlayServiceProvider)
          .activities(detail.id);
      if (!context.mounted) return;
      if (rows.isEmpty) {
        CyNativeNotice.show(context, '暂无可参加的场次');
        return;
      }
      if (rows.length == 1) {
        context.push('/activity/${rows.first.id}');
        return;
      }
      final shown = rows.take(6).toList();
      final selected = await showCupertinoModalPopup<TopicActivityEntry>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('选择场次'),
          actions: shown
              .map(
                (row) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(row),
                  child: Text(row.name.isEmpty ? '场次 ${row.id}' : row.name),
                ),
              )
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );
      if (selected != null && context.mounted) {
        context.push('/activity/${selected.id}');
      }
    } catch (error) {
      if (!context.mounted) return;
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? lc = detail.lifecycle;
    final Widget bar = _bar(context, ref, lc);
    // 拍板 2026-09-16 #10:发布者已打烊时**先把原因说出来**,
    // 别等人点了下单才被后端拒。
    if (!detail.merchantClosed) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            0,
          ),
          child: Text(
            '商家暂停营业，暂不可报名',
            style: TextStyle(color: CyPalette.of(context).statusWarning),
          ),
        ),
        bar,
      ],
    );
  }

  Widget _bar(BuildContext context, WidgetRef ref, int? lc) {
    // ⓪ 已购态优先:index.wxml 用 `is_join==1` 单列出「去票夹·查看我的票」,
    //   盖过下面的 lifecycle/selfPlay/报名三分支。真源 goJoinedPlay →
    //   票夹路线票 tab(stype=0),不进 play(index.js:1284)。
    //   is_join 取后端回填的 isSignUp,不只信 URL 参数(P0 2026-09-05)。
    if (detail.isSignUp) {
      return CyFooterBar(
        primary: CyNativeButton(
          label: '去票夹 · 查看我的票',
          onPressed: () => context.push('/tickets?stype=0'),
          height: 44,
        ),
      );
    }

    // ① 走招募流程且未到售票态:只给一个禁用态说明,不给购买入口。
    if (lc == 1 || lc == 2) {
      return CyFooterBar(
        primary: CyNativeButton(
          label: lc == 1 ? '招募中 · 未开售' : '定价中 · 未开售',
          onPressed: lc == 2 && detail.isOwner
              ? () => context.push('/topic/${detail.id}/pricing')
              : null,
          role: CyNativeButtonRole.secondary,
          height: 44,
        ),
      );
    }

    // ② 开放自玩通行证:次「查看场次」+ 主「¥X 随时开玩」。
    if (detail.selfPlay == 1) {
      final double? p = detail.selfPlayPrice;
      final String label = (p != null && p > 0)
          ? '¥${p.toStringAsFixed(2)} 随时开玩'
          : '随时开玩';
      return CyFooterBar(
        secondary: CyNativeButton(
          label: '查看场次',
          onPressed: () => _openActivities(context, ref),
          role: CyNativeButtonRole.secondary,
          height: 44,
        ),
        primary: CyNativeButton(
          label: label,
          onPressed: () async {
            if (detail.merchantClosed) {
              CyNativeNotice.show(context, '商家暂停营业，暂不可报名', isError: true);
              return;
            }
            if (!await requireLogin(context, ref)) return;
            if (!context.mounted) return;
            final role = ref.read(authControllerProvider).user?.effectiveRole;
            if (role == 'merchant') {
              CyNativeNotice.show(context, '商家用户不可购买', isError: true);
              return;
            }
            await showTopicSelfPlaySheet(context, topicId: detail.id);
          },
          height: 44,
        ),
      );
    }

    // ③ 其余:去参加(进场次列表)。
    return CyFooterBar(
      primary: CyNativeButton(
        label: '去参加',
        onPressed: () => _openActivities(context, ref),
        height: 44,
      ),
    );
  }
}
