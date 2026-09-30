import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/map/apple_scene_view.dart';
import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/coord.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_native_action_sheet.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_progress.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/account_api.dart';
import '../../data/api/play_api.dart';
import '../../data/api/play_route_api.dart';
import '../../data/api/play_run_session_api.dart';
import '../../data/models/checkin_models.dart' hide PlayRouteState;
import '../../data/models/club_lead.dart';
import '../../data/models/consent_record.dart';
import '../../data/models/npc.dart';
import '../../data/models/play_check.dart';
import '../../data/models/play_route_state.dart';
import '../../data/models/play_run_session.dart';
import '../../data/models/preference_play.dart';
import '../../data/models/roam_social.dart';
import '../map/map_controller.dart';
import '../map/map_scene_mapper.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../npc/npc_controller.dart';
import '../npc/widgets/npc_bubble.dart';
import '../prefab/prefab_story_engine.dart' show isPrefabLifeTopic;
import 'app_sensor_challenge_placeholder.dart';
import 'advanced/advanced_play_controller.dart';
import 'advanced/advanced_play_sheet.dart';
import 'advanced/fullscreen/playkit_timer_logic.dart' show formatPlayClock;
import 'classic_play_surfaces.dart';
import 'player_game_module_views.dart';
import 'classic_game_task_sheet.dart';
import 'filter_shot_camera.dart';
import 'filter_shot_camera_page.dart';
import 'free_explore/card_detail_page.dart';
import 'free_explore/free_explore_pass_view.dart';
import 'pack_opening_intro.dart';
import 'play_gap_logic.dart';
import 'play_empty_state.dart';
import 'preference_play_page.dart';
import 'play_run_session_store.dart';
import 'play_session_controller.dart';
import 'play_route_controller.dart';
import 'widgets/journey_check_stage.dart';
import 'widgets/play_leaderboard_sheet.dart';
import 'widgets/play_node_card_extras.dart';
import 'widgets/play_operating_system_sheet.dart';
import 'stillness_challenge_controller.dart';
import 'stillness_challenge_page.dart';
import 'stillness_platform.dart';
import 'team_lead_page.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';

Set<int> parseSeenEggIds(String? raw) {
  if (raw == null || raw.isEmpty) return <int>{};
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return <int>{};
    return decoded
        .whereType<num>()
        .map((num id) => id.toInt())
        .where((int id) => id > 0)
        .toSet();
  } catch (_) {
    return <int>{};
  }
}

const int _freeExploreMode = 2;

enum _SubmissionResult { success, businessFailure, transportFailure }

void _emitActivityNpc(
  WidgetRef ref,
  int activityId,
  NpcEventType event, {
  int? nodeId,
}) {
  if (activityId <= 0) return;
  ref
      .read(npcSessionProvider(activityId).notifier)
      .onEvent(event, nodeId: nodeId);
}

/// 扫码打卡游玩页(真实闭环 v1):
/// 进入 → 按 activityId 拉 /api/play/nodes 渲染节点+进度 →「扫码打卡」扫节点二维码
/// → /api/play/checkin(activityId+code)→ 弹发奖结果 → 刷新进度。
///
/// 路由接法(go_router):
///   GoRoute(
///     path: '/play/:activityId',
///     builder: (ctx, state) => PlaySessionPage(
///       activityId: int.parse(state.pathParameters['activityId']!),
///     ),
///   );
///   跳转:context.push('/play/${activityId}');
PlaySessionKey _playKey(int activityId, int? topicId) {
  final int? validActivityId = activityId > 0 ? activityId : null;
  return (
    activityId: validActivityId,
    topicId: validActivityId == null && (topicId ?? 0) > 0 ? topicId : null,
  );
}

/// 真源 `goBackDetail`(`pages/play/index.js:2816`):游玩页由场次详情/票夹压入,
/// 优先原路返回;没有栈(分享链/门口码直落)则回票夹。
void _exitPlaySession(BuildContext context) {
  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }
  GoRouter.maybeOf(context)?.go('/tickets');
}

/// 真源 `goGetPass`(`pages/play/index.js:2801`):没有(或已过期)自玩通行证时,
/// 出路是去主题详情买通行证 —— 自玩没有「报名」这个动作,指向票夹是错的指引。
void _goGetPlayPass(BuildContext context, int? topicId) {
  final int id = topicId ?? 0;
  if (id > 0) {
    context.push('/topic/$id');
    return;
  }
  _exitPlaySession(context);
}

/// 真源 `index.js:2960` 的换轨 key:有 activityId 用 activityId,否则用 topicId。
/// App 侧没有小程序那种带 `mock=1` 的开发者预览票,不拼 mock 参数。
String? _prefabRedirectRoute(PlaySessionKey key) {
  final String param = key.activityId != null
      ? 'activityId=${key.activityId}'
      : 'topicId=${key.topicId}';
  return '/play/prefab?$param';
}

/// 真源 `reloadPlay()`:「重新加载」得真把 `GET /api/play/nodes` 再发一次。
/// 这里不用 `ref.invalidate` —— 会话 controller 复用了 `_loadedOnce`,invalidate
/// 只会把状态打回 loading 而不再发请求(同 `preference_play_page.dart` 的用法)。
void _reloadPlaySession(WidgetRef ref, PlaySessionKey key) {
  unawaited(ref.read(playSessionProvider(key).notifier).load());
}

abstract interface class PlayMerchantConsentNativeDriver {
  Future<String?> show({
    required BuildContext context,
    required String merchantName,
  });
}

class _LiquidGlassMerchantConsentNativeDriver
    implements PlayMerchantConsentNativeDriver {
  const _LiquidGlassMerchantConsentNativeDriver();

  @override
  Future<String?> show({
    required BuildContext context,
    required String merchantName,
  }) {
    return LiquidGlassAlert.show(
      context: context,
      style: LiquidGlassAlertStyle.actionSheet,
      title: '当前门店授权',
      message: '仅 $merchantName 可按现场事实查看必要信息',
      actions: const <LiquidGlassAlertAction>[
        LiquidGlassAlertAction(id: 'show', title: '出示核销码'),
        LiquidGlassAlertAction(
          id: 'revoke',
          title: '撤回授权',
          isDestructive: true,
        ),
        LiquidGlassAlertAction(id: 'cancel', title: '取消', isCancel: true),
      ],
    );
  }
}

class PlaySessionPage extends ConsumerWidget {
  const PlaySessionPage({
    super.key,
    required this.activityId,
    this.topicId,
    this.registrationId,
    this.liquidGlassSupported,
    this.consentNativeDriver,
  });

  final int activityId;
  final int? topicId;
  final int? registrationId;

  /// 仅供测试固定 iOS 26 capability；运行时由系统版本决定。
  final bool? liquidGlassSupported;
  final PlayMerchantConsentNativeDriver? consentNativeDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = _playKey(activityId, topicId);
    // 真源 `loadData` 第一拍(`pages/play/index.js:2828`):缺场次参数不是「加载失败」,
    // 连请求都不该发;那一支也不给「重新加载」—— 重试必然命中同一行 return,是假按钮。
    final PlayEmptyGuide? missingSession =
        key.activityId == null && key.topicId == null
        ? kPlayMissingSessionGuide
        : null;
    final async = missingSession == null
        ? ref.watch(playSessionProvider(key))
        : const AsyncValue<PlayNodesResult>.loading();
    final bool merchantView =
        ref.watch(authControllerProvider).user?.isMerchantView == true;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.bgDeep,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppColors.bgDeep,
        border: null,
        leading: Semantics(
          label: '返回',
          button: true,
          child: CupertinoButton(
            key: const Key('play-back'),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: () => _exitPlaySession(context),
            child: const ExcludeSemantics(
              child: Icon(CupertinoIcons.back, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: missingSession != null
            ? PlayEmptyGuideView(
                guide: missingSession,
                onBackDetail: () => _exitPlaySession(context),
              )
            : async.when(
                loading: () => const LoadingView(),
                error: (Object e, _) => PlayEmptyGuideView(
                  guide: classifyPlayNodesFailure(e),
                  onReload: () => _reloadPlaySession(ref, key),
                  onBackDetail: () => _exitPlaySession(context),
                  onGetPass: () => _goGetPlayPass(context, key.topicId),
                  onRelogin: () async {
                    // 真源 `doRelogin`:就地登录成功后重拉首屏,人留在这一页。
                    if (!await requireLogin(context, ref)) return;
                    _reloadPlaySession(ref, key);
                  },
                ),
                data: (PlayNodesResult result) {
                  // 《预制人生》有自己的故事引擎。真源 `pages/play/index.js:2959`:
                  // 首载回包命中主题名就立刻换轨 redirectTo,绝不短暂露出通用城市定向首屏。
                  // redirectTo 语义 = 替换当前页,这里用 pushReplacement 同型;
                  // 「首载」由 controller 记账,打卡后的自动回拉不换轨。
                  String? prefabRoute;
                  if (isPrefabLifeTopic(result.topicName) &&
                      ref
                          .read(playSessionProvider(key).notifier)
                          .consumeFirstLoadData()) {
                    prefabRoute = _prefabRedirectRoute(key);
                  }
                  if (prefabRoute != null) {
                    final String route = prefabRoute;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      GoRouter.of(context).pushReplacement(route);
                    });
                    return const SizedBox.shrink();
                  }
                  if (merchantView && result.nodes.isEmpty) {
                    return _MerchantPlayEmpty(
                      onBack: () {
                        final NavigatorState navigator = Navigator.of(context);
                        if (navigator.canPop()) {
                          navigator.pop();
                          return;
                        }
                        GoRouter.maybeOf(context)?.go('/feed');
                      },
                    );
                  }
                  // 真源对成功回包还要落两种空态:未报名 / 没有打卡点(`index.js:2846-2852`),
                  // 两种都不渲染地图,只给那一条出路。商家不是报名方,「去报名」对它是假出路
                  // (商家自己的空态见 [_MerchantPlayEmpty])。
                  if (!merchantView) {
                    final PlayEmptyGuide? guide = classifyPlayNodesResult(
                      result,
                    );
                    if (guide != null) {
                      return PlayEmptyGuideView(
                        guide: guide,
                        onBackDetail: () => _exitPlaySession(context),
                      );
                    }
                  }
                  final bool immersiveClassic =
                      result.mode == 1 && result.chapters.isNotEmpty;
                  return Column(
                    // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
                    // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!immersiveClassic) const CyPageTitle('游玩打卡'),
                      Expanded(
                        child: _PlayBody(
                          activityId: activityId,
                          topicId: topicId,
                          registrationId: registrationId,
                          liquidGlassSupported: liquidGlassSupported,
                          consentNativeDriver: consentNativeDriver,
                          result: result,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _MerchantPlayEmpty extends StatelessWidget {
  const _MerchantPlayEmpty({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.only(top: 112),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '这家的信息没拿到',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          const Text(
            '回上一页重新进一次',
            style: TextStyle(color: CyTokens.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: CyTokens.space5),
          CyNativeButton(label: '返回', onPressed: onBack),
        ],
      ),
    ),
  );
}

class _PlayBody extends ConsumerStatefulWidget {
  const _PlayBody({
    required this.activityId,
    required this.topicId,
    required this.registrationId,
    required this.liquidGlassSupported,
    required this.consentNativeDriver,
    required this.result,
  });

  final int activityId;
  final int? topicId;
  final int? registrationId;
  final bool? liquidGlassSupported;
  final PlayMerchantConsentNativeDriver? consentNativeDriver;
  final PlayNodesResult result;

  @override
  ConsumerState<_PlayBody> createState() => _PlayBodyState();
}

class _PlayBodyState extends ConsumerState<_PlayBody> {
  bool _packIntroDone = false;
  bool _finishPresented = false;
  bool _endingPresented = false;
  late bool _sawIncomplete;
  bool _busy = false;
  bool _navigationPurposeAccepted = false;
  final Map<int, HintUnlockResult> _unlockedHints = <int, HintUnlockResult>{};
  final Map<int, PuzzleHintResult> _puzzleHints = <int, PuzzleHintResult>{};
  final Map<int, String> _puzzleRevealActionIds = <int, String>{};
  PlayRouteState? _routeAuthority;
  int? _advancedReadyNodeId;
  StreamSubscription<PlayNavigationPosition>? _eggLocationSubscription;
  Timer? _eggBubbleTimer;
  final Set<int> _seenEggIds = <int>{};
  DateTime? _lastEggAt;
  String? _eggBubbleText;
  int _eggTrackingGeneration = 0;

  /// 「谁在这儿打过卡」:按节点 id 存头像堆与人数(小程序 pages/play 同一条链)。
  /// 拉不到就保持空 —— 这是一行的补充信息,不弹错、不重试。
  final Map<int, RoamShopVisitors> _visitors = <int, RoamShopVisitors>{};

  // ── R14 旅程检定(入口在 encounter.allowedActions,不在 playKit)──
  // 真源 pages/play/index.js `journeyCheck` 一份状态:题面 + 回执 + 请求态。
  bool _journeyCheckShow = false;
  int _journeyCheckNodeId = 0;
  JourneyCheckProblem? _journeyCheckProblem;
  JourneyCheckReceipt? _journeyCheckReceipt;
  bool _checkActing = false;
  int _checkProbeEpoch = 0;

  /// 检定动作失败的可恢复文案(真源 `_afterCheck` 的 FAIL 表;后端原文 msg 优先)。
  static const Map<String, String> _journeyCheckFailText = <String, String>{
    'roll': '掷骰没成功，再试一次',
    'reroll': '重掷没成功，再试一次',
    'settle': '结算没成功，再试一次',
  };

  /// 节点大卡打开时问一次 encounter:服务端只在「已到店 && 未锁定 && 该节点旅程块
  /// check.enabled」时才把 'check' 放进 allowedActions —— 未到店时这里拿到的是空,
  /// 不弹任何东西。⚠️ 探测失败一律静默:检定不是通关闸,探测不成功不该打断
  /// 任何已有路径(打卡/任务/导航都不受影响)。
  Future<void> _probeJourneyCheck(PlayNode node) async {
    if (node.done) return;
    final int topicId = result.topicId;
    if (topicId <= 0) return; // encounter 只吃 topicId(活动会话与自玩都有)
    if (_journeyCheckShow && _journeyCheckNodeId == node.nodeId) return;
    final int epoch = ++_checkProbeEpoch;
    try {
      final Map<String, dynamic> data = await ref
          .read(playApiProvider)
          .encounter(topicId: topicId, nodeId: node.nodeId);
      if (!mounted || epoch != _checkProbeEpoch) return;
      final JourneyCheckProblem? problem = JourneyCheckProblem.fromEncounter(
        data,
      );
      if (problem == null) return;
      setState(() {
        _journeyCheckShow = true;
        _journeyCheckNodeId = node.nodeId;
        _journeyCheckProblem = problem;
        _journeyCheckReceipt = null;
      });
    } catch (_) {
      // 静默:探测不是闸。
    }
  }

  /// 掷 / 重掷 / 结算三条动作收成一个入口(真源 onJourneyCheckAction 同款分派)。
  /// 触感在检定屏里(掷/结算各一次);这里只管请求与把回执搬进视图。
  Future<void> _onJourneyCheckAction(String action) async {
    final JourneyCheckProblem? problem = _journeyCheckProblem;
    if (!_journeyCheckShow || problem == null || _checkActing) return;
    setState(() => _checkActing = true);
    final int topicId = result.topicId;
    final int nodeId = _journeyCheckNodeId;
    final String checkId = problem.checkId;
    final PlayApi api = ref.read(playApiProvider);
    Future<JourneyCheckReceipt> run() => switch (action) {
      'roll' => api.rollCheck(
        topicId: topicId,
        nodeId: nodeId,
        checkId: checkId,
      ),
      'reroll' => api.rerollCheck(
        topicId: topicId,
        nodeId: nodeId,
        checkId: checkId,
      ),
      _ => api.settleCheck(topicId: topicId, nodeId: nodeId, checkId: checkId),
    };
    try {
      final JourneyCheckReceipt receipt = await run();
      if (!mounted) return;
      setState(() {
        _checkActing = false;
        _journeyCheckReceipt = receipt;
      });
    } on PlayException catch (e) {
      if (!mounted) return;
      _checkActing = false;
      // 上局已结算过:掷骰会被拒,而 settle 是幂等的 —— 回读那份回执补上最终文案,
      // 别把玩家卡在掷不了。
      if (action == 'roll' && e.message.contains('已结算')) {
        await _recoverSettledCheck(topicId, nodeId, checkId);
        return;
      }
      _showError(
        e.message.isEmpty
            ? (_journeyCheckFailText[action] ?? '操作没成功，再试一次')
            : e.message,
      );
    } catch (_) {
      if (!mounted) return;
      _checkActing = false;
      _showError('网络异常，请重试');
    }
  }

  Future<void> _recoverSettledCheck(
    int topicId,
    int nodeId,
    String checkId,
  ) async {
    try {
      final JourneyCheckReceipt receipt = await ref
          .read(playApiProvider)
          .settleCheck(topicId: topicId, nodeId: nodeId, checkId: checkId);
      if (!mounted) return;
      setState(() => _journeyCheckReceipt = receipt);
    } on PlayException catch (e) {
      if (mounted) {
        _showError(e.message.isEmpty ? '这次检定已经结算过了' : e.message);
      }
    } catch (_) {
      if (mounted) _showError('这次检定已经结算过了');
    }
  }

  /// 检定屏退出。结算前后都能关 —— 失败也推进是产品口径,这里不设任何通关闸。
  void _closeJourneyCheck() {
    setState(() => _journeyCheckShow = false);
  }

  PlayNodesResult get result => widget.result;
  int get _routeVersion => _routeAuthority?.version ?? result.routeVersion;

  @override
  void initState() {
    super.initState();
    _sawIncomplete = !widget.result.allDone;
    Future.microtask(() {
      if (widget.activityId > 0) {
        ref.read(npcSessionProvider(widget.activityId).notifier).loadProfiles();
        ref
            .read(npcSessionProvider(widget.activityId).notifier)
            .onEvent(NpcEventType.enter);
      }
      _startEggTracking();
    });
    unawaited(_loadVisitors());
  }

  /// 单独一趟请求而不是塞进 nodes:一次最多 20 个来源(与小程序同款上限),
  /// 失败静默 —— 少一行脸不影响任何一件正事。
  Future<void> _loadVisitors() async {
    final List<int> ids = result.nodes
        .map((PlayNode node) => node.nodeId)
        .where((int id) => id > 0)
        .take(20)
        .toList();
    if (ids.isEmpty) return;
    try {
      final List<RoamShopVisitors> rows = await ref
          .read(roamApiProvider)
          .shopVisitors(sourceType: 2, sourceIds: ids);
      if (!mounted) return;
      setState(() {
        for (final RoamShopVisitors row in rows) {
          _visitors[row.sourceId] = row;
        }
      });
    } catch (_) {
      // 静默:头像是补充信息,不是这张卡的正事。
    }
  }

  @override
  void dispose() {
    _eggTrackingGeneration += 1;
    unawaited(_eggLocationSubscription?.cancel());
    _eggBubbleTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PlayBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.result.allDone) _sawIncomplete = true;
    if (!oldWidget.result.allDone && widget.result.allDone) {
      _finishPresented = false;
      _endingPresented = false;
    }
    if (oldWidget.result.topicId != widget.result.topicId ||
        oldWidget.result.eggs.length != widget.result.eggs.length) {
      unawaited(_startEggTracking());
    }
  }

  void _openJournal(PlayNodesResult visibleResult) {
    if (visibleResult.chapters.isEmpty) return;
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ClassicPlayJournalPage(
          chapter: visibleResult.chapters.first,
          nodes: visibleResult.nodes,
        ),
      ),
    );
  }

  void _presentFinish(PlayNodesResult visibleResult) {
    if (_finishPresented || !_sawIncomplete || !visibleResult.allDone) return;
    _finishPresented = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showClassicPlayFinishSheet(
        context,
        result: visibleResult,
        onJournal: () {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openJournal(visibleResult);
          });
        },
        onLeaderboard: () {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showPlayLeaderboardSheet(
              context: context,
              activityId: widget.activityId > 0 ? widget.activityId : null,
              topicId: widget.activityId > 0 ? null : visibleResult.topicId,
            );
          });
        },
        onShare: () {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) GoRouter.maybeOf(context)?.push('/square');
          });
        },
        onSave: () => _shareFootprint(visibleResult),
      );
    });
  }

  /// 结局信的会话参数按真源 `_sessionParams()`(`index.js:488`)取:
  /// 活动会话走 `/play/<activityId>/ending`,自玩会话没有 activityId,只能带 topicId。
  void _openEndingLetter() {
    final PlaySessionKey key = _playKey(widget.activityId, widget.topicId);
    if (key.activityId == null && key.topicId == null) return;
    GoRouter.maybeOf(context)?.push(
      key.topicId == null
          ? '/play/${key.activityId}/ending'
          : '/play/0/ending?topicId=${key.topicId}',
    );
  }

  /// 真源 `openFinish()`(`pages/play/index.js:5065`)第一件事是 `loadEnding()`,
  /// 而 `loadEnding` 第一行 `mode !== 2` 就 return(`:5050`)—— 结局信只属于探店日。
  /// App 侧 mode2 不走经典通关卡(`_buildSessionBody` 在 mode2 分支就返回),
  /// 所以这一封信挂在探店日的通关时刻上:打完整场才发,而且重进不重放
  /// (`_sawIncomplete` 同 `index.js:3228` 那条「重进早已完成的主题不重放仪式」)。
  void _presentEndingLetter(PlayNodesResult visibleResult) {
    if (visibleResult.mode != _freeExploreMode) return;
    if (_endingPresented || !_sawIncomplete || !visibleResult.allDone) return;
    _endingPresented = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openEndingLetter();
    });
  }

  Future<void> _shareFootprint(PlayNodesResult visibleResult) async {
    final String title = visibleResult.chapters.isEmpty
        ? '这一趟'
        : visibleResult.chapters.first.title ?? '这一趟';
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text:
            '保存我的城瘾足迹：$title · '
            '${visibleResult.doneCount} 个坐标 · ${visibleResult.doneCount * 12} 探索值',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  String get _eggStorageKey {
    final int scope = result.topicId > 0 ? result.topicId : widget.activityId;
    return 'play_egg_seen_$scope';
  }

  Future<void> _startEggTracking() async {
    final int generation = ++_eggTrackingGeneration;
    await _eggLocationSubscription?.cancel();
    _eggLocationSubscription = null;
    if (result.eggs.isEmpty) return;
    try {
      const FlutterSecureStorage storage = FlutterSecureStorage();
      final String? raw = await storage.read(key: _eggStorageKey);
      _seenEggIds
        ..clear()
        ..addAll(parseSeenEggIds(raw));
      final PlayNavigationLocationSource source = ref.read(
        playNavigationLocationSourceProvider,
      );
      final PlayNavigationPosition current = await source.current();
      if (!mounted || generation != _eggTrackingGeneration) return;
      _acceptEggPosition(current);
      _eggLocationSubscription = source.watch().listen(
        _acceptEggPosition,
        onError: (_) {},
      );
    } catch (_) {
      // 彩蛋是沿途增强能力；定位或本地存储不可用时不阻断主游玩流程。
    }
  }

  void _acceptEggPosition(PlayNavigationPosition position) {
    if (!mounted) return;
    final DateTime now = DateTime.now();
    if (_lastEggAt != null && now.difference(_lastEggAt!).inSeconds < 180) {
      return;
    }
    for (final PlayEgg egg in result.eggs) {
      if (_seenEggIds.contains(egg.id)) continue;
      final double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        egg.latitude,
        egg.longitude,
      );
      if (distance <= egg.radiusMeters) {
        _showEgg(egg, now);
        return;
      }
    }
  }

  void _showEgg(PlayEgg egg, DateTime now) {
    _lastEggAt = now;
    _seenEggIds.add(egg.id);
    unawaited(
      const FlutterSecureStorage()
          .write(
            key: _eggStorageKey,
            value: jsonEncode(_seenEggIds.toList(growable: false)),
          )
          .catchError((_) {}),
    );
    unawaited(
      ref
          .read(playApiProvider)
          .collectEgg(
            topicId: result.topicId > 0 ? result.topicId : null,
            eggId: egg.id,
            content: egg.text,
          )
          .catchError((_) {}),
    );
    HapticFeedback.lightImpact();
    setState(() => _eggBubbleText = egg.text);
    _eggBubbleTimer?.cancel();
    _eggBubbleTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _eggBubbleText = null);
    });
  }

  Future<void> _openEggCard() async {
    final String? text = _eggBubbleText;
    if (text == null) return;
    _eggBubbleTimer?.cancel();
    setState(() => _eggBubbleText = null);
    await showCyNativeActionSheet<bool>(
      context: context,
      title: '途中彩蛋 · 小瘾说',
      message: text,
      cancelLabel: '关闭',
      actions: const <CyNativeAction<bool>>[
        CyNativeAction<bool>(
          value: true,
          label: '知道了',
          systemImage: 'sparkles',
        ),
      ],
    );
  }

  Future<void> _runFilterShot(PlayNode node) async {
    if (_busy) return;
    final FilterShotConfig? config = FilterShotConfig.tryParse(
      node.sensorConfig ?? const <String, dynamic>{},
    );
    if (config == null) {
      _showError('滤镜玩法配置无效，请联系活动方');
      return;
    }
    setState(() => _busy = true);
    CheckinReward? reward;
    try {
      await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => FilterShotCameraPage(
            title: node.name,
            config: config,
            onSubmit: (File composite) async {
              reward = await ref
                  .read(
                    playSessionProvider(
                      _playKey(widget.activityId, widget.topicId),
                    ).notifier,
                  )
                  .filterPhoto(node.nodeId, composite.path);
            },
          ),
        ),
      );
      final CheckinReward? completedReward = reward;
      if (completedReward != null && mounted) {
        await showSensorRewardDialog(context, completedReward);
        ref
            .read(npcSessionProvider(widget.activityId).notifier)
            .onEvent(NpcEventType.checkinSuccess, nodeId: node.nodeId);
        if (completedReward.completed) {
          ref
              .read(npcSessionProvider(widget.activityId).notifier)
              .onEvent(NpcEventType.activityFinish);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// vm=7 静止挑战:全屏页采样 → 上报 heldSec → 复用传感器发奖弹窗。
  Future<void> _runStillnessChallenge(PlayNode node) async {
    if (_busy || node.sensorType != 'still') return;
    final StillnessConfig? config = StillnessConfig.tryParse(node.sensorConfig);
    if (config == null) {
      _showError('静止挑战配置无效，请联系活动方');
      return;
    }
    setState(() => _busy = true);
    try {
      final CheckinReward? reward = await Navigator.of(context)
          .push<CheckinReward>(
            CupertinoPageRoute<CheckinReward>(
              fullscreenDialog: true,
              builder: (_) => StillnessChallengePage(
                title: node.name,
                config: config,
                source: ref.read(stillnessSampleSourceProvider),
                wakeLock: ref.read(screenWakeLockProvider),
                onSubmit: (int heldSec) => ref
                    .read(
                      playSessionProvider(
                        _playKey(widget.activityId, widget.topicId),
                      ).notifier,
                    )
                    .sensorResult(node.nodeId, 'still', <String, dynamic>{
                      'heldSec': heldSec,
                    }),
              ),
            ),
          );
      if (reward != null && mounted) {
        await showSensorRewardDialog(context, reward);
        ref
            .read(npcSessionProvider(widget.activityId).notifier)
            .onEvent(NpcEventType.checkinSuccess, nodeId: node.nodeId);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runPreference(PlayNode node) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final PreferenceSubmission? submission = await Navigator.of(context)
          .push<PreferenceSubmission>(
            CupertinoPageRoute<PreferenceSubmission>(
              fullscreenDialog: true,
              builder: (_) => PreferencePlayPage(
                sessionKey: _playKey(widget.activityId, widget.topicId),
                nodeId: node.nodeId,
              ),
            ),
          );
      if (submission?.progress != null && mounted) {
        _emitActivityNpc(
          ref,
          widget.activityId,
          NpcEventType.checkinSuccess,
          nodeId: node.nodeId,
        );
        if (submission!.progress!.completed) {
          _emitActivityNpc(ref, widget.activityId, NpcEventType.activityFinish);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runHintAwareAnswer(PlayNode node) async {
    if (node.puzzleScoring && result.mode == 1) {
      await _runPuzzleAnswer(node);
      return;
    }
    final HintUnlockResult? unlocked = _unlockedHints[node.nodeId];
    final bool isLocked = node.hintLocked && unlocked == null;
    final bool? wantsHint = await showCupertinoModalPopup<bool>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: const Text('本站提示'),
        message: Text(
          isLocked ? '解锁提示需 ${node.hintCost} 积分，确认后由服务端扣分。' : '提示已可查看，也可以直接作答。',
        ),
        actions: <Widget>[
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(sheetContext, true),
            child: Text(isLocked ? '解锁提示 · ${node.hintCost} 积分' : '查看提示'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, false),
            child: const Text('直接答题'),
          ),
        ],
      ),
    );
    if (wantsHint == null || !mounted) return;
    if (!wantsHint) {
      await _runAnswer(node);
      return;
    }

    List<String> hints =
        unlocked?.hints ??
        <String>[
          if (node.hint1?.isNotEmpty == true) node.hint1!,
          if (node.hint2?.isNotEmpty == true) node.hint2!,
        ];
    int charged = 0;
    if (isLocked) {
      setState(() => _busy = true);
      try {
        final HintUnlockResult result = await ref
            .read(
              playSessionProvider(
                _playKey(widget.activityId, widget.topicId),
              ).notifier,
            )
            .unlockHint(node.nodeId);
        hints = result.hints;
        charged = result.cost;
        _unlockedHints[node.nodeId] = result;
      } on PlayException catch (error) {
        if (mounted) _showError(error.message);
        return;
      } catch (_) {
        if (mounted) _showError('解锁失败，请重试');
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    int visibleHintCount = hints.isEmpty ? 0 : 1;
    await showCyNativeSheet<void>(
      // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
      context,
      detents: CyNativeSheetDetents.medium,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) =>
            CupertinoPopupSurface(
              // 原生承载时不画自带底,透出系统 sheet 材质(S3)。
              isSurfacePainted: !isCyNativeSheet(context),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space4,
                    CyTokens.pageX,
                    CyTokens.space4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        charged > 0 ? '提示已解锁 · 扣除 $charged 积分' : '本站提示',
                        textAlign: TextAlign.center,
                        style: CupertinoTheme.of(
                          context,
                        ).textTheme.navTitleTextStyle,
                      ),
                      const SizedBox(height: CyTokens.space4),
                      Text(
                        hints.isEmpty
                            ? '该节点没有可用提示'
                            : hints.take(visibleHintCount).join('\n\n'),
                        style: CupertinoTheme.of(context).textTheme.textStyle,
                      ),
                      const SizedBox(height: CyTokens.space4),
                      if (visibleHintCount < hints.length) ...<Widget>[
                        CupertinoButton.tinted(
                          minimumSize: const Size(44, 44),
                          onPressed: () => setSheetState(() {
                            visibleHintCount += 1;
                          }),
                          child: const Text('再看一条'),
                        ),
                        const SizedBox(height: CyTokens.space2),
                      ],
                      CupertinoButton.filled(
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('去答题'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
    if (mounted) await _runAnswer(node);
  }

  Future<void> _runPuzzleAnswer(PlayNode node) async {
    final PuzzleHintResult? cached = _puzzleHints[node.nodeId];
    final List<String> hints = cached?.hints ?? node.usedHints;
    final int hintCount = cached?.hintCount ?? node.hintCount;
    final int scoreCap = cached?.scoreCap ?? node.puzzleScoreCap;
    final ClassicAnswerTaskResult? action = await showClassicPuzzleAnswerTask(
      context: context,
      node: node,
      usedHints: hints,
      hintCount: hintCount,
      scoreCap: scoreCap,
      image: _questionImage(node),
    );
    if (action == null || !mounted) return;

    if (action.action == ClassicAnswerTaskAction.submit) {
      await _submitAnswerValue(node, action.answer);
      return;
    }

    if (action.action == ClassicAnswerTaskAction.hint) {
      setState(() => _busy = true);
      try {
        final PuzzleHintResult next = await ref
            .read(
              playSessionProvider(
                _playKey(widget.activityId, widget.topicId),
              ).notifier,
            )
            .requestPuzzleHint(node.nodeId, hints.length + 1);
        _puzzleHints[node.nodeId] = next;
        if (!mounted) return;
        await _showPuzzleHints(next.hints, next.scoreCap);
      } on PlayException catch (error) {
        if (mounted) _showError(error.message);
        return;
      } catch (_) {
        if (mounted) _showError('提示没有加载出来，请重试');
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final bool confirmed = await cyConfirm(
      context,
      title: '查看答案？',
      content: '查看后本题解谜分为 0，并由服务端标记完成。',
      confirmText: '查看答案',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final String actionId = _puzzleRevealActionIds.putIfAbsent(
      node.nodeId,
      () =>
          'ios-puzzle-${node.nodeId}-${DateTime.now().microsecondsSinceEpoch}',
    );
    setState(() => _busy = true);
    try {
      final PlaySessionController controller = ref.read(
        playSessionProvider(
          _playKey(widget.activityId, widget.topicId),
        ).notifier,
      );
      PuzzleRevealResult reveal;
      try {
        reveal = await controller.revealPuzzle(
          node.nodeId,
          routeActionId: actionId,
          expectedRouteVersion: _routeVersion,
        );
      } on PlayException {
        _puzzleRevealActionIds.remove(node.nodeId);
        rethrow;
      } catch (_) {
        final PlayNodesResult readback = await controller.readback(
          apply: false,
        );
        if (readback.nodeById(node.nodeId)?.done != true) rethrow;
        try {
          reveal = await controller.revealPuzzle(
            node.nodeId,
            routeActionId: actionId,
            expectedRouteVersion: readback.routeVersion,
          );
        } on PlayException {
          _puzzleRevealActionIds.remove(node.nodeId);
          if (mounted) _showInfo('节点已在其他设备完成，进度已同步');
          controller.applyReadback(readback);
          return;
        }
      }
      _puzzleRevealActionIds.remove(node.nodeId);
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => CupertinoAlertDialog(
          title: const Text('答案'),
          content: Text(reveal.answerReveal),
          actions: <Widget>[
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      _emitActivityNpc(
        ref,
        widget.activityId,
        NpcEventType.checkinSuccess,
        nodeId: node.nodeId,
      );
      if (reveal.reward.completed) {
        _emitActivityNpc(ref, widget.activityId, NpcEventType.activityFinish);
      }
      controller.invalidatePlayRewards();
      try {
        await controller.readback();
      } catch (_) {
        if (mounted) _showInfo('答案已确认，进度稍后刷新');
      }
    } on PlayException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('查看答案请求没有送达，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPuzzleHints(List<String> hints, int scoreCap) =>
      showCyNativeSheet<void>(
        // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
        context,
        detents: CyNativeSheetDetents.medium,
        builder: (BuildContext sheetContext) => CupertinoPopupSurface(
          // 原生承载时不画自带底,透出系统 sheet 材质(S3)。
          isSurfacePainted: !isCyNativeSheet(sheetContext),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space4,
                CyTokens.pageX,
                CyTokens.space4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '本站提示',
                    textAlign: TextAlign.center,
                    style: CupertinoTheme.of(
                      sheetContext,
                    ).textTheme.navTitleTextStyle,
                  ),
                  const SizedBox(height: CyTokens.space3),
                  Text(hints.join('\n\n')),
                  const SizedBox(height: CyTokens.space3),
                  Text(
                    '当前最高 $scoreCap 解谜分 · 不影响探索值',
                    style: CupertinoTheme.of(
                      sheetContext,
                    ).textTheme.tabLabelTextStyle,
                  ),
                  const SizedBox(height: CyTokens.space4),
                  CupertinoButton.filled(
                    minimumSize: const Size(44, 44),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('继续解谜'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// 点击一个节点:按验证方式分流。
  /// done 不可点(由 tile 拦截);不可玩时给提示;否则按 needScan/needAnswer/needGps 分流。
  Future<void> _onNodeTap(PlayNode node) async {
    if (_busy) return;
    if (result.routeMode == 'BRANCH_GRAPH') {
      final PlayRouteState? route = _routeAuthority;
      if (route == null ||
          !route.active ||
          !route.nodeIsPlayable(node.nodeId)) {
        _showError(route?.lockReason(node.nodeId) ?? '路线状态暂未同步，请稍后重试');
        return;
      }
    }
    if (!result.playable) {
      _showError(
        result.timeNote?.isNotEmpty == true ? result.timeNote! : '当前不在可玩时间',
      );
      return;
    }
    if (node.hasAdvanced && _advancedReadyNodeId != node.nodeId) {
      final bool ready = await _runAdvancedPlay(node);
      if (!ready || !mounted) return;
      _advancedReadyNodeId = node.nodeId;
    }
    final PlayNodeInteraction interaction = playNodeInteractionFor(
      mode: result.mode,
      node: node,
    );
    // R14 旅程检定入口(契约:allowedActions)。与真源「开大卡时探测」同位:
    // 到店前服务端不会给 'check',这里什么都不弹,也不打断下面的动作分派。
    unawaited(_probeJourneyCheck(node));
    switch (interaction) {
      case PlayNodeInteraction.freeArrivalScan:
        await _runScan();
      case PlayNodeInteraction.freeProofPhoto:
        await _runPhoto(node);
      case PlayNodeInteraction.freeMerchantCode:
        await _openMerchantVerifyCode(node);
      case PlayNodeInteraction.answer:
        if (node.hasHint) {
          await _runHintAwareAnswer(node);
        } else {
          await _runAnswer(node);
        }
      case PlayNodeInteraction.photo:
        if (node.isFilterShot) {
          await _runFilterShot(node);
        } else if (node.hasUnsupportedPhotoSubtype) {
          _showError('滤镜玩法配置无效，请联系活动方');
        } else {
          await _runPhoto(node);
        }
      case PlayNodeInteraction.scan:
        await _runScan(node);
      case PlayNodeInteraction.arrive:
        await _runArrive(node);
      case PlayNodeInteraction.preference:
        await _runPreference(node);
      case PlayNodeInteraction.appSensorChallenge:
        await _runStillnessChallenge(node);
      case PlayNodeInteraction.unsupported:
        final int method = node.validationMethod!;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: UnsupportedPlayValidationMethod(
              nodeId: node.nodeId,
              validationMethod: method,
            ),
            library: 'chengyin_app.play',
            context: ErrorDescription('在选择节点打卡链路时'),
          ),
        );
        _showError('节点验证配置异常（方式 $method），请联系活动方');
    }
  }

  Future<bool> _runAdvancedPlay(PlayNode node) async {
    bool readyForBase = false;
    final AdvancedPlayController controller = AdvancedPlayController(
      gateway: ref.read(advancedPlayGatewayProvider),
      // 拍照问答两步链的第一步:与拍照打卡/商家资质同一条共享上传口
      // (`/api/common/uploadOSS`,JWT 由 dioClient 统一注入)。
      uploadPhoto: ref.read(playApiProvider).uploadImage,
      activityId: widget.activityId,
      topicId: result.topicId,
      nodeId: node.nodeId,
    );
    try {
      await showAdvancedPlaySheet(
        context: context,
        controller: controller,
        title: node.name,
        onReadyForBase: () {
          readyForBase = true;
          Navigator.of(context).pop();
        },
      );
      return readyForBase;
    } finally {
      controller.dispose();
    }
  }

  bool _isExactMerchantConsent(
    ConsentRecord? record,
    int merchantId,
    String eventType,
  ) =>
      record != null &&
      record.docType == AccountApi.merchantOnsiteDocType &&
      record.scene == AccountApi.merchantOnsiteScene &&
      record.scopeType == AccountApi.merchantScopeType &&
      record.scopeId == merchantId &&
      record.eventType == eventType;

  Future<void> _openMerchantVerifyCode(PlayNode node) async {
    final int registrationId = widget.registrationId ?? 0;
    if (registrationId <= 0) {
      _showError('从票夹进入后才能出示核销码');
      return;
    }
    final int merchantId = node.merchantId ?? 0;
    if (merchantId <= 0) {
      _showError('当前门店身份未确认，不能出示核销码');
      return;
    }

    ConsentRecord? latest;
    setState(() => _busy = true);
    try {
      latest = await ref
          .read(accountApiProvider)
          .latestMerchantOnsiteConsent(merchantId);
    } catch (_) {
      // 初次读失败仍可让用户明确选择；后续写入必须再由 latest 回读确认。
      latest = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    if (_isExactMerchantConsent(latest, merchantId, 'AGREE')) {
      final String? action = await _showMerchantConsentActions(node);
      if (!mounted || action == null) return;
      if (action == 'revoke') {
        await _revokeMerchantConsent(merchantId);
        return;
      }
      if (action == 'show') {
        context.push('/ticket/$registrationId/pass');
      }
      return;
    }

    final bool agreed = await cyConfirm(
      context,
      title: '仅授权当前门店',
      content:
          '为现场叫号与核销，同意向「${node.name.isEmpty ? '当前门店' : node.name}」提供你的姓名、头像、到店/核销状态和报名手机号。不会授权其他门店，可随时撤回。',
      confirmText: '同意并继续',
    );
    if (!agreed || !mounted) return;

    setState(() => _busy = true);
    try {
      final ConsentRecord record = await ref
          .read(accountApiProvider)
          .agreeMerchantOnsiteDataSharing(
            merchantId: merchantId,
            requestId: AccountApi.newRequestId(),
          );
      if (!mounted) return;
      if (!_isExactMerchantConsent(record, merchantId, 'AGREE')) {
        _showError('门店授权状态未确认，核销码未打开');
        return;
      }
      context.push('/ticket/$registrationId/pass');
    } catch (error) {
      if (mounted) {
        _showError(
          error.toString().replaceFirst('Exception: ', '').isEmpty
              ? '门店授权状态未确认，核销码未打开'
              : error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showMerchantConsentActions(PlayNode node) async {
    final bool useLiquidGlass =
        widget.liquidGlassSupported ??
        NativeLiquidGlassUtils.supportsLiquidGlass;
    if (useLiquidGlass) {
      try {
        return await (widget.consentNativeDriver ??
                const _LiquidGlassMerchantConsentNativeDriver())
            .show(
              context: context,
              merchantName: node.name.isEmpty ? '当前门店' : node.name,
            );
      } on MissingPluginException {
        // 原生通道未注册时使用下方完整 Cupertino action sheet。
      } on PlatformException {
        // iOS 26 capability 被运行时拒绝时，落到系统 Cupertino action sheet。
      }
    }
    if (!mounted) return null;
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: const Text('当前门店授权'),
        message: Text(
          '仅 ${node.name.isEmpty ? '当前门店' : node.name} 可按现场事实查看必要信息',
        ),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'show'),
            child: const Text('出示核销码'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, 'revoke'),
            child: const Text('撤回授权'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _revokeMerchantConsent(int merchantId) async {
    setState(() => _busy = true);
    try {
      final ConsentRecord record = await ref
          .read(accountApiProvider)
          .revokeMerchantOnsiteDataSharing(
            merchantId: merchantId,
            requestId: AccountApi.newRequestId(),
          );
      if (!mounted) return;
      if (!_isExactMerchantConsent(record, merchantId, 'REVOKE')) {
        _showError('门店授权状态未确认，核销码未打开');
        return;
      }
      _showInfo('已撤回当前门店授权，门店名单将不再显示你');
    } catch (error) {
      if (mounted) {
        _showError(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleNavigation(PlayNode node) async {
    final PlaySessionKey key = _playKey(widget.activityId, widget.topicId);
    final PlayNavigationController controller = ref.read(
      playNavigationProvider(key).notifier,
    );
    if (ref.read(playNavigationProvider(key)).targetNodeId == node.nodeId) {
      await controller.stop();
      return;
    }
    if (!_navigationPurposeAccepted) {
      final bool accepted = await cyConfirm(
        context,
        title: '开启前往导航',
        content: '仅在本游玩页前台使用定位计算剩余距离，并在行程 50% 和 90% 展示途中提示；结束前往或离开页面即停止。',
        cancelText: '暂不开启',
        confirmText: '同意并开始',
      );
      if (!accepted || !mounted) return;
      _navigationPurposeAccepted = true;
    }
    try {
      await controller.start(node);
    } on PlayException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('定位暂不可用，请稍后重试');
    }
  }

  /// 拍照打卡流程(vm2):让用户选"拍照/相册" → image_picker 取图 →
  /// controller.photo(先传 OSS 再上报)→ 成功复用发奖弹窗。
  /// 用户取消选图(返回 null)则什么都不做;失败按 PlayException 显示后端原文
  /// (如图片安全检查不过),其它异常统一"上传失败,请重试"。全程占用 _busy 防连点。
  Future<void> _runPhoto(PlayNode node) async {
    if (_busy) return;
    XFile? file;
    while (mounted) {
      final ImageSource? source = await _pickImageSource();
      if (source == null || !mounted) return;
      file = await ImagePicker().pickImage(source: source);
      if (file == null || !mounted) return;
      final bool? submit = await showClassicProofTask(
        context: context,
        title: node.gameTitle?.isNotEmpty == true ? node.gameTitle! : node.name,
        instruction: node.photoRequireDesc?.isNotEmpty == true
            ? node.photoRequireDesc!
            : '拍一张现场照片作为完成凭证',
        mode: ClassicProofMode.photo,
        ready: true,
        preview: ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: Image.file(File(file.path), fit: BoxFit.cover),
        ),
      );
      if (submit == null) return;
      if (submit) break;
    }
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final CheckinReward reward = await ref
          .read(
            playSessionProvider(
              _playKey(widget.activityId, widget.topicId),
            ).notifier,
          )
          .photo(node.nodeId, file.path);
      if (!mounted) return;
      await showRewardDialog(context, reward);
      // 照片回执里带回了 AI 参考分就挂到这张节点卡上(真源 `_applyAiScore`,
      // 只在 submitPhoto 回执处调一次)。服务端没给分 → `reward.aiScore` 是 null
      // → 卡上什么都不出现,不造占位分。
      ref
          .read(
            playNodeCardExtrasProvider(
              _playKey(widget.activityId, widget.topicId),
            ),
          )
          .applyPhotoReceipt(node.nodeId, reward.aiScore);
      // NPC: photo success
      _emitActivityNpc(
        ref,
        widget.activityId,
        NpcEventType.checkinSuccess,
        nodeId: node.nodeId,
      );
      if (reward.completed) {
        _emitActivityNpc(ref, widget.activityId, NpcEventType.activityFinish);
      }
    } on PlayException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      _showError('上传失败,请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 系统底部来源选择:拍照 / 相册 / 取消。取消(含点遮罩关闭)返回 null。
  Future<ImageSource?> _pickImageSource() async {
    final CyImagePickSource? source = await cyChooseImageSource(context);
    return switch (source) {
      CyImagePickSource.camera => ImageSource.camera,
      CyImagePickSource.gallery => ImageSource.gallery,
      null => null,
    };
  }

  /// GPS 到达流程:校验定位服务/权限 → 取 WGS84 定位 → 转 gcj02 → controller.arrive。
  /// 全程占用 _busy 防连点;后端 50m 围栏判定,失败按 PlayException 显示原文。
  Future<void> _runArrive(PlayNode node) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 1) 系统定位服务总开关。
      final bool serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (mounted) _showError('请开启系统定位后重试');
        return;
      }
      // 2) App 定位权限:未授予则发起请求。
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) _showError('需要定位权限才能到达打卡');
        return;
      }
      // 3) 取当前定位(WGS84)。
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      // 4) WGS84 → gcj02(后端围栏用 gcj02)。
      final gcj = wgs84ToGcj02(pos.longitude, pos.latitude);
      // 5) 上报到达。
      final CheckinReward reward = await ref
          .read(
            playSessionProvider(
              _playKey(widget.activityId, widget.topicId),
            ).notifier,
          )
          .arrive(node.nodeId, gcj.lng, gcj.lat);
      if (!mounted) return;
      await showRewardDialog(context, reward);
      // NPC: arrive success
      _emitActivityNpc(
        ref,
        widget.activityId,
        NpcEventType.checkinSuccess,
        nodeId: node.nodeId,
      );
      if (reward.completed) {
        _emitActivityNpc(ref, widget.activityId, NpcEventType.activityFinish);
      }
    } on PlayException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      _showError('定位失败,请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 扫码流程:打开扫码页,扫到 code 调 controller.checkin。
  Future<void> _runScan([PlayNode? node]) async {
    if (node != null) {
      final bool? start = await showClassicProofTask(
        context: context,
        title: node.gameTitle?.isNotEmpty == true ? node.gameTitle! : node.name,
        instruction: '扫描现场那枚二维码，让这一关的答案落到你手里。',
        mode: ClassicProofMode.scan,
      );
      if (start != true || !mounted) return;
    }
    final String? code = await Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => const _ScannerPage(),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final ok = await _submit(
      () => ref
          .read(
            playSessionProvider(
              _playKey(widget.activityId, widget.topicId),
            ).notifier,
          )
          .checkin(code),
    );
    if (ok) {
      _emitActivityNpc(ref, widget.activityId, NpcEventType.checkinSuccess);
    }
  }

  /// 答题流程:弹答题对话框(vm3 选项 / vm1 文字),提交后调 controller.answer。
  Future<_SubmissionResult?> _runAnswer(PlayNode node) async {
    final String? answerText = await _showAnswerPrompt(context, node);
    if (answerText == null || answerText.isEmpty || !mounted) return null;
    return _submitAnswerValue(node, answerText);
  }

  Future<_SubmissionResult?> _submitAnswerValue(
    PlayNode node,
    String answerText,
  ) async {
    final _SubmissionResult result = await _submitDetailed(
      () => ref
          .read(
            playSessionProvider(
              _playKey(widget.activityId, widget.topicId),
            ).notifier,
          )
          .answer(node.nodeId, answerText),
    );
    if (result == _SubmissionResult.success) {
      _emitActivityNpc(
        ref,
        widget.activityId,
        NpcEventType.answerRight,
        nodeId: node.nodeId,
      );
    } else if (result == _SubmissionResult.businessFailure) {
      _emitActivityNpc(
        ref,
        widget.activityId,
        NpcEventType.answerWrong,
        nodeId: node.nodeId,
      );
    }
    return result;
  }

  /// 统一提交:置 busy、调接口、成功弹奖、失败按 PlayException 显示后端原文。
  /// 返回 true 表示成功(含已打卡),false 表示失败。
  Future<bool> _submit(Future<CheckinReward> Function() action) async {
    return await _submitDetailed(action) == _SubmissionResult.success;
  }

  Future<_SubmissionResult> _submitDetailed(
    Future<CheckinReward> Function() action,
  ) async {
    setState(() => _busy = true);
    try {
      final CheckinReward reward = await action();
      if (!mounted) return _SubmissionResult.transportFailure;
      await showRewardDialog(context, reward);
      // NPC: activity finish
      if (reward.completed) {
        _emitActivityNpc(ref, widget.activityId, NpcEventType.activityFinish);
      }
      return _SubmissionResult.success;
    } on PlayException catch (e) {
      if (!mounted) return _SubmissionResult.businessFailure;
      _showError(e.message);
      return _SubmissionResult.businessFailure;
    } catch (_) {
      if (!mounted) return _SubmissionResult.transportFailure;
      _showError('操作失败,请重试');
      return _SubmissionResult.transportFailure;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    CyNativeNotice.show(context, msg, isError: true);
  }

  void _showInfo(String msg) {
    CyNativeNotice.show(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _buildSessionBody();
    // R14 旅程检定挂在页面顶层(真源 index.wxml 里 `cy-playkit-journey-check`
    // 与 playKit 同级),结算前后都能退出,不拦任何底下的玩法流。
    final JourneyCheckProblem? problem = _journeyCheckProblem;
    if (!_journeyCheckShow || problem == null) return body;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: body),
        Positioned.fill(
          child: JourneyCheckStage(
            problem: problem,
            receipt: _journeyCheckReceipt,
            acting: _checkActing,
            onAction: (String action) =>
                unawaited(_onJourneyCheckAction(action)),
            onClose: _closeJourneyCheck,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionBody() {
    PlayNodesResult visibleResult = result;
    if (result.routeMode == 'BRANCH_GRAPH') {
      final PlayRouteKey routeKey = (
        activityId: widget.activityId > 0 ? widget.activityId : null,
        topicId: widget.activityId > 0 ? null : widget.topicId,
      );
      final AsyncValue<PlayRouteState> route = ref.watch(
        playRouteStateProvider(routeKey),
      );
      final PlayRouteState? authority = route.value;
      if (authority == null) {
        _routeAuthority = null;
        return route.when(
          loading: () => const StatusView(
            icon: CupertinoIcons.arrow_2_circlepath,
            message: '正在同步路线…',
          ),
          error: (Object error, StackTrace _) => StatusView(
            icon: CupertinoIcons.exclamationmark_triangle,
            message: error is PlayRouteApiException
                ? error.message
                : '路线状态暂未同步，请稍后重试',
            onRetry: () => ref.invalidate(playRouteStateProvider(routeKey)),
          ),
          data: (_) => const SizedBox.shrink(),
        );
      }
      _routeAuthority = authority;
      visibleResult = result.applyRouteState(authority);
    } else {
      _routeAuthority = null;
    }
    // mode2(自由探索)进场先播 Rive 开卡包 intro,与小程序的卡包首屏对齐;
    // 播完/跳过/减弱动态效果都落到 _packIntroDone,列表才出现。
    if (visibleResult.mode == _freeExploreMode && !_packIntroDone) {
      return PackOpeningIntro(
        onDone: () => setState(() => _packIntroDone = true),
      );
    }
    if (visibleResult.mode == _freeExploreMode) {
      _presentEndingLetter(visibleResult);
      // 节点卡尾段(AI 参考分 / 木鱼计数)是这次游玩的 page data(真源
      // `pages/play/index.js` 的 `woodfishCount` / `sheet.node.aiScore`),
      // 要活过整趟游玩 —— 卡片关掉再进不该清零。`ref.read` 不续命,
      // autoDispose 会在卡片关掉那一帧丢掉它,所以在这里持有一份。
      ref.watch(
        playNodeCardExtrasProvider(_playKey(widget.activityId, widget.topicId)),
      );
      return FreeExplorePassView(
        data: visibleResult,
        completionActions: visibleResult.allDone
            ? _CompletionActions(
                showOperatingSystem: true,
                onLeaderboard: () {
                  showPlayLeaderboardSheet(
                    context: context,
                    activityId: widget.activityId > 0
                        ? widget.activityId
                        : null,
                    topicId: widget.activityId > 0
                        ? null
                        : visibleResult.topicId,
                  );
                },
                onOperatingSystem: () {
                  showPlayOperatingSystemSheet(
                    context: context,
                    topicId: visibleResult.topicId,
                  );
                },
              )
            : null,
        onTapNode: (PlayNode node) => Navigator.of(context).push<void>(
          CupertinoPageRoute<void>(
            // 只传 nodeId:详情页自己从 provider 现读,
            // 扫码/拍照成功后三步就地亮起,不用退出详情页。
            builder: (_) => CardDetailPage(
              sessionKey: _playKey(widget.activityId, widget.topicId),
              nodeId: node.nodeId,
              onPrimary: _onNodeTap,
            ),
          ),
        ),
      );
    }
    final nodes = <PlayNode>[...visibleResult.nodes]
      ..sort((PlayNode a, PlayNode b) => a.sortId.compareTo(b.sortId));
    final PlaySessionKey key = _playKey(widget.activityId, widget.topicId);
    final PlayNavigationState navigation = ref.watch(
      playNavigationProvider(key),
    );

    if (visibleResult.chapters.isNotEmpty) {
      _presentFinish(visibleResult);
      return _ClassicImmersivePlay(
        result: visibleResult,
        nodes: nodes,
        navigation: navigation,
        busy: _busy,
        activityId: widget.activityId,
        topicId: widget.topicId,
        registrationId: widget.registrationId,
        liquidGlassSupported: widget.liquidGlassSupported,
        onNodeTap: _onNodeTap,
        onNavigate: _toggleNavigation,
        onOpenJournal: () => _openJournal(visibleResult),
      );
    }

    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            _ProgressHeader(result: visibleResult),
            if (visibleResult.allDone)
              _CompletionActions(
                showOperatingSystem: visibleResult.mode == _freeExploreMode,
                onLeaderboard: () {
                  showPlayLeaderboardSheet(
                    context: context,
                    activityId: widget.activityId > 0
                        ? widget.activityId
                        : null,
                    topicId: widget.activityId > 0 ? null : widget.topicId,
                  );
                },
                onOperatingSystem: () {
                  showPlayOperatingSystemSheet(
                    context: context,
                    topicId: visibleResult.topicId,
                  );
                },
              ),
            if (navigation.active)
              _NavigationStatus(
                state: navigation,
                onClose: () =>
                    ref.read(playNavigationProvider(key).notifier).stop(),
              ),
            if (defaultTargetPlatform == TargetPlatform.iOS &&
                ref.watch(mapPrivacyAgreementProvider).value == true &&
                mapPlayNodes(nodes).isNotEmpty)
              SizedBox(
                height: 220,
                child: AppleSceneView(
                  scene: MapScene.build(points: mapPlayNodes(nodes)),
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.space4,
                  CyTokens.space2,
                  CyTokens.space4,
                  CyTokens.space5,
                ),
                itemCount: nodes.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: CyTokens.space2_5),
                itemBuilder: (BuildContext ctx, int i) => _NodeTile(
                  index: i + 1,
                  node: nodes[i],
                  playable: visibleResult.playable && nodes[i].routePlayable,
                  busy: _busy,
                  navigating: navigation.targetNodeId == nodes[i].nodeId,
                  visitors: _visitors[nodes[i].nodeId],
                  onNavigate:
                      nodes[i].latitude != null && nodes[i].longitude != null
                      ? () => _toggleNavigation(nodes[i])
                      : null,
                  onTap: () => _onNodeTap(nodes[i]),
                ),
              ),
            ),
            _ScanBar(
              activityId: widget.activityId,
              topicId: widget.topicId,
              registrationId: widget.registrationId,
              liquidGlassSupported: widget.liquidGlassSupported,
              mode: visibleResult.mode,
              playable: visibleResult.playable,
              allDone: visibleResult.allDone,
              timeNote: visibleResult.timeNote,
            ),
          ],
        ),
        if (navigation.line != null)
          Positioned(
            left: CyTokens.pageX,
            right: CyTokens.pageX,
            bottom: 100,
            child: _CompanionLine(line: navigation.line!),
          ),
        if (_eggBubbleText != null && navigation.line == null)
          Positioned(
            right: CyTokens.pageX,
            bottom: 100,
            child: CyNativeButton(
              key: const Key('play-egg-bubble'),
              label: _eggBubbleText!.runes.length > 16
                  ? '${String.fromCharCodes(_eggBubbleText!.runes.take(16))}…'
                  : _eggBubbleText!,
              role: CyNativeButtonRole.secondary,
              icon: const CyNativeButtonIcon(
                sfSymbol: 'sparkles',
                fallback: CupertinoIcons.sparkles,
              ),
              onPressed: _openEggCard,
            ),
          ),
        // NPC 陪伴层: 事件冒泡
        if (widget.activityId > 0 && navigation.line == null)
          Consumer(
            builder: (context, ref, _) {
              final session = ref.watch(npcSessionProvider(widget.activityId));
              if (session.bubbleQueue.isEmpty) return const SizedBox.shrink();
              final line = session.bubbleQueue.first;
              return Positioned(
                bottom: 100, // above bottom nav
                left: 0,
                right: 0,
                // ★ V1 不给「自由追问」入口:后端 NpcFeatureFlags.chatOn() 恒 false
                //   (合规签字未过),点进去必 403。留 onTap 就是一个假入口。
                //   将来接 /api/config/features 后按 flag 决定是否传 onTap。
                child: NpcBubble(line: line),
              );
            },
          ),
      ],
    );
  }
}

class _ClassicImmersivePlay extends ConsumerWidget {
  const _ClassicImmersivePlay({
    required this.result,
    required this.nodes,
    required this.navigation,
    required this.busy,
    required this.activityId,
    required this.topicId,
    required this.registrationId,
    required this.liquidGlassSupported,
    required this.onNodeTap,
    required this.onNavigate,
    required this.onOpenJournal,
  });

  final PlayNodesResult result;
  final List<PlayNode> nodes;
  final PlayNavigationState navigation;
  final bool busy;
  final int activityId;
  final int? topicId;
  final int? registrationId;
  final bool? liquidGlassSupported;
  final ValueChanged<PlayNode> onNodeTap;
  final Future<void> Function(PlayNode) onNavigate;
  final VoidCallback onOpenJournal;

  String get _chapterLabel {
    final String supplied = result.chapters.first.meta?.trim() ?? '';
    if (supplied == '第 1 章') return '第一章';
    return supplied.isEmpty ? '第一章' : supplied;
  }

  String get _mileage {
    // Mini 也只信 chapter.totalMileage；当前 App 模型未承载该字段，
    // 不拿节点直线距离冒充实际路线里程。
    return '—';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool showNativeMap =
        defaultTargetPlatform == TargetPlatform.iOS &&
        ref.watch(mapPrivacyAgreementProvider).value == true &&
        mapPlayNodes(nodes).isNotEmpty;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: KeyedSubtree(
            key: const Key('play-immersive-map'),
            child: showNativeMap
                ? AppleSceneView(
                    scene: MapScene.build(points: mapPlayNodes(nodes)),
                  )
                : const CustomPaint(painter: _ClassicMapFallbackPainter()),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.15,
                  colors: <Color>[Colors.transparent, const Color(0xCC080808)],
                  stops: const <double>[0.42, 1],
                ),
              ),
            ),
          ),
        ),
        ...nodes.indexed.map((entry) {
          final int index = entry.$1;
          final PlayNode node = entry.$2;
          final List<Alignment> positions = <Alignment>[
            const Alignment(-0.62, -0.58),
            const Alignment(0.48, -0.42),
            const Alignment(-0.18, -0.10),
            const Alignment(0.64, 0.12),
          ];
          return Align(
            alignment: positions[index % positions.length],
            child: _ClassicMapNode(
              node: node,
              index: index + 1,
              enabled: result.playable && node.routePlayable && !busy,
              navigating: navigation.targetNodeId == node.nodeId,
              onTap: () => onNodeTap(node),
              onNavigate: node.latitude != null && node.longitude != null
                  ? () => onNavigate(node)
                  : null,
            ),
          );
        }),
        if (navigation.active)
          Positioned(
            top: 12,
            left: CyTokens.pageX,
            right: CyTokens.pageX,
            child: _NavigationStatus(
              state: navigation,
              onClose: () => ref
                  .read(
                    playNavigationProvider(
                      _playKey(activityId, topicId),
                    ).notifier,
                  )
                  .stop(),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 136,
          child: _ClassicChapterCard(
            chapterLabel: _chapterLabel,
            chapterCount: result.chapters.length,
            gameCount: nodes.where((PlayNode node) => node.hasGame).length,
            mileage: _mileage,
            roleChip: PlayerGameRoleChip(activityId: activityId),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _ScanBar(
            activityId: activityId,
            topicId: topicId,
            registrationId: registrationId,
            liquidGlassSupported: liquidGlassSupported,
            mode: result.mode,
            playable: result.playable,
            allDone: result.allDone,
            timeNote: result.timeNote,
            immersive: true,
            onOpenJournal: onOpenJournal,
          ),
        ),
        // 本局玩家投影(拉一次)→ 首入身份卡;点胶囊开「本局线索」。
        PlayerGameRoleCardHost(activityId: activityId),
      ],
    );
  }
}

class _ClassicMapNode extends StatelessWidget {
  const _ClassicMapNode({
    required this.node,
    required this.index,
    required this.enabled,
    required this.navigating,
    required this.onTap,
    required this.onNavigate,
  });

  final PlayNode node;
  final int index;
  final bool enabled;
  final bool navigating;
  final VoidCallback onTap;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 150),
    decoration: BoxDecoration(
      color: const Color(0xE6111318),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      border: Border.all(
        color: node.done ? AppColors.success : const Color(0x6699A1AF),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: CupertinoButton(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            minimumSize: const Size(44, 44),
            onPressed: enabled ? onTap : null,
            child: Text(
              node.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled
                    ? CupertinoColors.white
                    : const Color(0xFF6A7282),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (onNavigate != null)
          CupertinoButton(
            key: Key('play-navigate-${node.nodeId}'),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: enabled ? onNavigate : null,
            child: Icon(
              navigating
                  ? CupertinoIcons.location_fill
                  : CupertinoIcons.location,
              size: 18,
              color: CupertinoColors.white,
            ),
          ),
      ],
    ),
  );
}

class _ClassicChapterCard extends StatelessWidget {
  const _ClassicChapterCard({
    required this.chapterLabel,
    required this.chapterCount,
    required this.gameCount,
    required this.mileage,
    this.roleChip,
  });

  final String chapterLabel;
  final int chapterCount;
  final int gameCount;
  final String mileage;

  /// 本局身份胶囊(小程序 `pcard__role`):点开「本局线索」。
  final Widget? roleChip;

  @override
  Widget build(BuildContext context) => Container(
    height: 142,
    decoration: BoxDecoration(
      color: const Color(0xFF111318),
      borderRadius: BorderRadius.circular(16),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x80000000),
          blurRadius: 40,
          offset: Offset(0, 18),
        ),
      ],
    ),
    child: Column(
      children: <Widget>[
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    chapterLabel,
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ?roleChip,
                const Icon(
                  CupertinoIcons.chevron_up,
                  size: 18,
                  color: Color(0xFF99A1AF),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Row(
              children: <Widget>[
                _ClassicStat(value: '$chapterCount', label: '章节数'),
                _ClassicStat(value: '$gameCount', label: '游戏数', centered: true),
                _ClassicStat(value: mileage, label: '路程 (公里)', end: true),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ClassicStat extends StatelessWidget {
  const _ClassicStat({
    required this.value,
    required this.label,
    this.centered = false,
    this.end = false,
  });

  final String value;
  final String label;
  final bool centered;
  final bool end;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 42,
            height: 1,
            fontWeight: FontWeight.w700,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF6A7282), fontSize: 12),
        ),
      ],
    ),
  );
}

class _ClassicMapFallbackPainter extends CustomPainter {
  const _ClassicMapFallbackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF15191D),
    );
    final Paint block = Paint()..color = const Color(0xFF1E2529);
    final Paint road = Paint()
      ..color = const Color(0xFF30383C)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;
    for (double y = -40; y < size.height; y += 110) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(24 + (y % 3) * 8, y, size.width - 68, 72),
          const Radius.circular(12),
        ),
        block,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(-20, size.height * 0.22)
        ..cubicTo(
          size.width * 0.3,
          size.height * 0.12,
          size.width * 0.42,
          size.height * 0.72,
          size.width + 30,
          size.height * 0.48,
        ),
      road,
    );
    canvas.drawLine(
      Offset(size.width * 0.72, -20),
      Offset(size.width * 0.33, size.height + 20),
      road,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CompletionActions extends StatelessWidget {
  const _CompletionActions({
    required this.showOperatingSystem,
    required this.onLeaderboard,
    required this.onOperatingSystem,
  });

  final bool showOperatingSystem;
  final VoidCallback onLeaderboard;
  final VoidCallback onOperatingSystem;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CyTokens.pageX,
      0,
      CyTokens.pageX,
      CyTokens.space2,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: CyNativeButton(
            key: const Key('play-complete-leaderboard'),
            label: '同行者榜',
            role: CyNativeButtonRole.secondary,
            onPressed: onLeaderboard,
          ),
        ),
        if (showOperatingSystem) ...<Widget>[
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: CyNativeButton(
              key: const Key('play-complete-os'),
              label: '我的新生活操作系统',
              role: CyNativeButtonRole.secondary,
              onPressed: onOperatingSystem,
            ),
          ),
        ],
      ],
    ),
  );
}

/// 共享的发奖弹窗(扫码/答题成功都用它);返回 Future 便于 await。
Future<void> showSensorRewardDialog(
  BuildContext context,
  CheckinReward reward,
) {
  return showCupertinoDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) => CupertinoAlertDialog(
      title: Text(reward.firstTime ? '挑战完成' : '挑战已记录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            reward.firstTime ? '+${reward.xpAwarded} 探索值' : '本节点已经完成过',
            style: const TextStyle(
              color: CyTokens.statusSuccess,
              fontSize: CyTokens.typeButton,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (reward.newBadges.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              '获得徽章：${reward.newBadges.map((PlayBadge badge) => badge.name).join('、')}',
              style: const TextStyle(color: CyTokens.textSecondary),
            ),
          ],
        ],
      ),
      actions: <CupertinoDialogAction>[
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('收下'),
        ),
      ],
    ),
  );
}

Future<void> showRewardDialog(BuildContext context, CheckinReward reward) {
  return showCyNativeSheet<void>(
    // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
    // 真源按徽章数给两档高度(0.48/0.28 顶部留白);detent 只有档位没有连续值,
    // 少徽章走 medium,徽章多走 both(从半屏起、可上拖到全屏)。
    context,
    detents: reward.newBadges.length > 3
        ? CyNativeSheetDetents.both
        : CyNativeSheetDetents.medium,
    builder: (BuildContext sheetContext) => CupertinoPopupSurface(
      // 原生承载时不画自带底,透出系统 sheet 材质(S3)。
      isSurfacePainted: !isCyNativeSheet(sheetContext),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                reward.firstTime ? '打卡成功' : '已打卡',
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(
                  sheetContext,
                ).textTheme.navLargeTitleTextStyle,
              ),
              const SizedBox(height: CyTokens.space3),
              Text(
                reward.firstTime ? '+${reward.pointsAwarded} 积分' : '该节点已打卡',
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(sheetContext).textTheme.textStyle
                    .copyWith(
                      color: reward.firstTime
                          ? CupertinoColors.systemIndigo.resolveFrom(
                              sheetContext,
                            )
                          : CupertinoColors.secondaryLabel.resolveFrom(
                              sheetContext,
                            ),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              // M2 夜间提示:后端随回执下发 nightWarning 才出现,不阻断
              // (真源 index.wxml:752「结果时刻出一句」—— 这个面就是结果时刻)。
              if (reward.nightWarning) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                Text(
                  '夜深了,注意安全',
                  textAlign: TextAlign.center,
                  style: CupertinoTheme.of(sheetContext).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          sheetContext,
                        ),
                      ),
                ),
              ],
              if (reward.completed) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                Text(
                  '🎉 恭喜通关!',
                  textAlign: TextAlign.center,
                  style: CupertinoTheme.of(sheetContext).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.systemGreen.resolveFrom(
                          sheetContext,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              if (reward.newBadges.isNotEmpty) ...<Widget>[
                const SizedBox(height: CyTokens.space4),
                Text(
                  '获得徽章',
                  style: CupertinoTheme.of(sheetContext).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          sheetContext,
                        ),
                      ),
                ),
                const SizedBox(height: CyTokens.space2),
                ...reward.newBadges.map(
                  (PlayBadge badge) => Padding(
                    padding: const EdgeInsets.only(bottom: CyTokens.space2),
                    child: Row(
                      children: <Widget>[
                        if (badge.iconUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusSm,
                            ),
                            child: Image.network(
                              badge.iconUrl,
                              width: 28,
                              height: 28,
                              errorBuilder: (_, _, _) => const Icon(
                                CupertinoIcons.rosette,
                                size: 28,
                                color: CupertinoColors.systemIndigo,
                              ),
                            ),
                          )
                        else
                          const Icon(
                            CupertinoIcons.rosette,
                            size: 28,
                            color: CupertinoColors.systemIndigo,
                          ),
                        const SizedBox(width: CyTokens.space2_5),
                        Expanded(
                          child: Text(
                            badge.name,
                            style: CupertinoTheme.of(
                              sheetContext,
                            ).textTheme.textStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: CyTokens.space3),
              CupertinoButton.filled(
                minimumSize: const Size(44, 44),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.result});

  final PlayNodesResult result;

  @override
  Widget build(BuildContext context) {
    final double pct = result.total > 0 ? result.doneCount / result.total : 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        CyTokens.space4,
        CyTokens.space4,
        CyTokens.space2,
      ),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '进度 ${result.doneCount}/${result.total}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: CyTokens.typeButton,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (result.allDone)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2_5,
                    vertical: CyTokens.space1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                  ),
                  child: const Text(
                    '🎉 已通关',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: CyTokens.typeLabel,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusSm),
            child: CyNativeProgress(
              progress: pct,
              height: 8,
              semanticLabel: '游玩进度',
              progressColor: result.allDone
                  ? AppColors.success
                  : AppColors.nodeGlow,
              trackColor: AppColors.bgElevated,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.index,
    required this.node,
    required this.playable,
    required this.busy,
    required this.navigating,
    required this.onNavigate,
    required this.onTap,
    this.visitors,
  });

  final int index;
  final PlayNode node;
  final bool playable;
  final bool busy;
  final bool navigating;
  final VoidCallback? onNavigate;
  final VoidCallback onTap;

  /// 「谁在这儿打过卡」的接口行(sourceType=2),没有就不画这一行。
  final RoamShopVisitors? visitors;

  /// 验证方式的角标(图标+文案),供用户预判打卡方式。
  ({IconData icon, String label})? get _methodHint {
    if (node.arrived || node.selfReported || node.merchantId != null) {
      if (!node.arrived) {
        return (icon: Icons.qr_code_scanner, label: '扫描门店码');
      }
      if (!node.selfReported) {
        return (icon: Icons.camera_alt_outlined, label: '拍摄到店凭证');
      }
      return (icon: Icons.qr_code_2, label: '出示核销码');
    }
    if (isUnsupportedPlayValidationMethod(node.validationMethod)) {
      return (icon: CupertinoIcons.exclamationmark_triangle, label: '配置异常');
    }
    if (node.needScan) return (icon: Icons.qr_code_scanner, label: '扫码');
    if (node.needAnswer) {
      return (icon: Icons.quiz_outlined, label: '答题');
    }
    if (node.needGps) return (icon: Icons.location_on_outlined, label: 'GPS');
    if (node.isFilterShot) {
      return (icon: Icons.center_focus_strong, label: '滤镜相机');
    }
    if (node.validationMethod == 2) {
      return (icon: Icons.camera_alt_outlined, label: '拍照');
    }
    if (node.validationMethod == 6) {
      return (icon: Icons.tune, label: '偏好题组');
    }
    if (node.isAppSensorChallenge) {
      return (
        icon: node.sensorType == 'still'
            ? Icons.sensors_outlined
            : Icons.sensors_off_outlined,
        label: 'App专属',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // done 不可点;不可玩或正在提交时禁用点击(灰显)。
    final bool isAppSensorChallenge = node.isAppSensorChallenge;
    final bool stillnessReady =
        isAppSensorChallenge &&
        node.sensorType == 'still' &&
        StillnessConfig.tryParse(node.sensorConfig) != null;
    final bool tappable =
        !node.done &&
        playable &&
        !busy &&
        (!isAppSensorChallenge || stillnessReady);
    final hint = _methodHint;

    final Widget tile = Container(
      padding: const EdgeInsets.all(CyTokens.space3_5),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(
          color: node.done ? AppColors.success : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: node.done ? AppColors.success : AppColors.bgElevated,
            ),
            child: node.done
                // 绿底之上用 onCoverFg(白),onPrimary 是白底按钮的黑字。
                ? const Icon(Icons.check, size: 18, color: CyTokens.onCoverFg)
                : Text(
                    '$index',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.name,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: node.done ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textSecondary,
                  ),
                ),
                if (node.address.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: CyTokens.space1),
                      Expanded(
                        child: Text(
                          node.address,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: CyTokens.typeLabel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (isAppSensorChallenge && !node.done)
                  AppSensorChallengePlaceholder(stillnessReady: stillnessReady),
                if (visitors != null && visitors!.total > 0) ...<Widget>[
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    children: <Widget>[
                      for (final String face in visitors!.avatars.take(3))
                        Padding(
                          padding: const EdgeInsets.only(
                            right: CyTokens.space1,
                          ),
                          child: CyAvatar(url: face, size: 20),
                        ),
                      Text(
                        '${visitors!.total} 个人在这儿打过卡',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: CyTokens.typeMicro,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // 右侧:已完成显示对勾文案;否则保留验证入口，并为有坐标节点提供小程序同款「前往」。
          const SizedBox(width: CyTokens.space2),
          if (node.done)
            const Text(
              '已完成',
              style: TextStyle(
                color: AppColors.success,
                fontSize: CyTokens.typeLabel,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...<Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (hint != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(hint.icon, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: CyTokens.space1),
                      Text(
                        hint.label,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: CyTokens.typeLabel,
                        ),
                      ),
                      if (!isAppSensorChallenge || stillnessReady)
                        const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                    ],
                  ),
                if (onNavigate != null)
                  CupertinoButton(
                    key: Key('play-navigate-${node.nodeId}'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                    ),
                    onPressed: !playable || busy ? null : onNavigate,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          navigating
                              ? CupertinoIcons.xmark
                              : CupertinoIcons.location,
                          size: 16,
                        ),
                        const SizedBox(width: CyTokens.space1),
                        Text(navigating ? '结束' : '导航去这里'),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    if (!tappable) {
      return Opacity(
        opacity: node.done || isAppSensorChallenge ? 1 : 0.6,
        child: tile,
      );
    }
    return Semantics(
      button: true,
      label: '${node.name}，${hint?.label ?? '打开节点'}',
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: tile,
      ),
    );
  }
}

class _NavigationStatus extends StatelessWidget {
  const _NavigationStatus({required this.state, required this.onClose});

  final PlayNavigationState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('play-navigation-status'),
      margin: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        0,
        CyTokens.space4,
        CyTokens.space2,
      ),
      padding: const EdgeInsets.only(left: CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: CyTokens.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.near_me, size: 18, color: CyTokens.textPrimary),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Text(
              '前往 ${state.targetName} · ${state.remainM} m',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CyTokens.textPrimary,
                fontSize: CyTokens.typeBody,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Semantics(
            label: '结束前往',
            button: true,
            child: CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: onClose,
              child: const Icon(CupertinoIcons.xmark, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanionLine extends StatelessWidget {
  const _CompanionLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '途中提示：$line',
      child: Container(
        key: const Key('play-companion-line'),
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3,
          vertical: CyTokens.space2_5,
        ),
        decoration: BoxDecoration(
          color: CyTokens.textPrimary,
          borderRadius: BorderRadius.circular(CyTokens.radiusXl),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('◈', style: TextStyle(color: CyTokens.onCoverFg)),
            const SizedBox(width: CyTokens.space2),
            Flexible(
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CyTokens.onCoverFg,
                  fontSize: CyTokens.typeBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 答题入口保留小程序的题面、选项顺序和返回值:
/// 选项题与文字题都走 Cupertino Sheet 的经典任务页(选项在内联列表里选,
/// 文字题短输入);取消或点遮罩均返回 null。
Future<String?> _showAnswerPrompt(BuildContext context, PlayNode node) {
  return showClassicAnswerTask(
    context: context,
    node: node,
    image: _questionImage(node),
  );
}

Widget? _questionImage(PlayNode node) => (node.questionImg?.isNotEmpty ?? false)
    ? Image.network(
        node.questionImg!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: CyTokens.bgSurfaceSubtle,
          child: Center(
            child: Icon(CupertinoIcons.photo, color: CyTokens.textSecondary),
          ),
        ),
      )
    : null;

class _ScanBar extends ConsumerStatefulWidget {
  const _ScanBar({
    required this.activityId,
    required this.topicId,
    required this.registrationId,
    required this.liquidGlassSupported,
    required this.mode,
    required this.playable,
    required this.allDone,
    required this.timeNote,
    this.immersive = false,
    this.onOpenJournal,
  });

  final int activityId;
  final int? topicId;
  final int? registrationId;
  final bool? liquidGlassSupported;
  final int mode;
  final bool playable;

  /// 服务端权威态说这一趟已经走完 —— 进行中的会话在这一刻作废。
  final bool allDone;
  final String? timeNote;
  final bool immersive;
  final VoidCallback? onOpenJournal;

  @override
  ConsumerState<_ScanBar> createState() => _ScanBarState();
}

class _ScanBarState extends ConsumerState<_ScanBar> {
  bool _busy = false;
  bool _running = false;

  /// 进行中的这一局:暂停/离页落盘(本机 + 服务端 `/api/play/run-session/*`),
  /// 重进接回来 —— 与小程序 `utils/play-run-session.js` 同一份语义。
  /// 用时只算**走过的**那段:[_elapsedBase] 是上次暂停时的秒数,[_clock] 只跑当前这一段。
  final PlayRunSessionStore _runStore = const PlayRunSessionStore(
    FlutterSecureStorage(),
  );
  late final PlayRunSessionGateway _runApi;
  final Stopwatch _clock = Stopwatch();
  int _elapsedBase = 0;
  bool _runStarted = false;

  /// 桌上这一局是「恢复出来的」而不是玩家自己开的 —— 服务端说结束时要撤的是它。
  bool _restored = false;

  /// 每次作废/新起一局 +1:在途的服务端恢复读迟到了,不能把刚结束的局拉回暂停态。
  int _restoreEpoch = 0;

  /// save/clear 串行发出:先暂停再结束时,迟到的 save 不能把已结束的会话写回
  /// (小程序 `_queueRunSync` 同款)。
  Future<void> _runSync = Future<void>.value();

  int get _elapsedSeconds => _elapsedBase + _clock.elapsed.inSeconds;

  int? get _scopeActivityId => widget.activityId > 0 ? widget.activityId : null;

  int? get _scopeTopicId => widget.activityId > 0 ? null : widget.topicId;

  @override
  void initState() {
    super.initState();
    _runApi = ref.read(playRunSessionApiProvider);
    if (widget.allDone || !widget.playable) {
      // 服务端权威态说这一趟已经结束 / 不可玩了:残留的会话在这一刻作废,不恢复。
      _endRun();
    } else if (widget.immersive) {
      unawaited(_restoreRun());
    }
  }

  @override
  void didUpdateWidget(covariant _ScanBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allDone && !oldWidget.allDone) _endRun();
  }

  @override
  void dispose() {
    // 离页 = 暂停:小程序在 onHide/onUnload 落的是同一份。
    if (_runStarted) {
      _clock.stop();
      unawaited(_persistRun());
    }
    super.dispose();
  }

  /// 重进接回上次暂停的行程。本机那份先接;再读服务端那份 ——
  /// 本机没有(换了手机)或服务端更新时改用服务端的,另一台设备已经结束这一局
  /// 就把本机那份作废。没有快照就什么都不做(不编一局出来)。
  Future<void> _restoreRun() async {
    final PlayPausedRun? local = await _runStore.read(
      activityId: _scopeActivityId,
      topicId: _scopeTopicId,
    );
    if (local != null && mounted) {
      _applyRestoredRun(local, fromOtherDevice: false);
    }

    final int epoch = ++_restoreEpoch;
    final PlayRunSessionRead remote;
    try {
      remote = await _runApi.read(
        activityId: _scopeActivityId,
        topicId: _scopeTopicId,
      );
    } catch (_) {
      return; // 读不到就沿用本机那份(小程序 ok:false 同款),不打断游玩
    }
    if (!mounted || epoch != _restoreEpoch || !remote.ok) return;
    // 等服务端期间玩家自己开了新局 / 点了开始:那一局归玩家,这份不再覆盖或撤销它。
    if (_runStarted && !(_restored && !_running)) return;
    // 另一台设备结束了这一局,且结束晚于本机快照:本机那份不能还魂。
    if (local != null &&
        remote.endedAt > 0 &&
        remote.endedAt >= local.savedAt) {
      _endRun();
      return;
    }
    final PlayPausedRun? next = PlayPausedRun.newer(local, remote.record);
    if (next == null || identical(next, local)) return;
    await _runStore.write(
      activityId: _scopeActivityId,
      topicId: _scopeTopicId,
      elapsedSeconds: next.elapsedSeconds,
      savedAt: next.savedAt,
    );
    if (!mounted || epoch != _restoreEpoch) return;
    _applyRestoredRun(next, fromOtherDevice: local != null);
  }

  /// 把一份快照接回跑表:只投影成「已暂停」,不重开也不偷跑。
  void _applyRestoredRun(PlayPausedRun run, {required bool fromOtherDevice}) {
    setState(() {
      _elapsedBase = run.elapsedSeconds;
      _runStarted = true;
      _restored = true;
      _running = false;
    });
    CyNativeNotice.show(
      context,
      (fromOtherDevice ? '已同步另一台设备上的进度 · 用时 ' : '已恢复上次暂停的行程 · 用时 ') +
          formatPlayClock(run.elapsedSeconds),
    );
  }

  /// 暂停/离页落盘。本机那份先写,服务端那份排队发 —— 服务端写失败本机仍在,
  /// 不影响本机恢复(和小程序一样尽力而为)。
  Future<void> _persistRun() async {
    final int elapsed = _elapsedSeconds;
    final int savedAt = DateTime.now().millisecondsSinceEpoch;
    await _runStore.write(
      activityId: _scopeActivityId,
      topicId: _scopeTopicId,
      elapsedSeconds: elapsed,
      savedAt: savedAt,
    );
    _enqueueRunSync(
      () => _runApi.save(
        activityId: _scopeActivityId,
        topicId: _scopeTopicId,
        elapsedSeconds: elapsed,
        savedAt: savedAt,
      ),
    );
  }

  /// 作废这一局的落盘(本机 + 服务端留 ENDED 墓碑)。不动运行标志 ——
  /// 新起一局要清的是**上一局**的残留。
  void _clearRunStores() {
    _restoreEpoch++;
    final int savedAt = DateTime.now().millisecondsSinceEpoch;
    unawaited(
      _runStore.clear(activityId: _scopeActivityId, topicId: _scopeTopicId),
    );
    _enqueueRunSync(
      () => _runApi.clear(
        activityId: _scopeActivityId,
        topicId: _scopeTopicId,
        savedAt: savedAt,
      ),
    );
  }

  /// 一局结束的唯一收尾(通关/服务端判终态):停表 + 作废两份落盘。
  void _endRun() {
    _clock.stop();
    _elapsedBase = 0;
    _runStarted = false;
    _restored = false;
    _running = false;
    _clearRunStores();
  }

  void _enqueueRunSync(Future<void> Function() send) {
    _runSync = _runSync.then((_) => send()).catchError((Object _) {});
  }

  void _toggleRun() {
    final bool starting = !_running;
    if (starting) {
      if (_runStarted) {
        _clock.start();
      } else {
        // 新起一局:作废旧暂停快照,否则「开了新的还没落盘就杀进程」会把上一局的用时还魂。
        _runStarted = true;
        _restored = false;
        _elapsedBase = 0;
        _clock
          ..reset()
          ..start();
        _clearRunStores();
      }
    } else {
      _clock.stop();
      unawaited(_persistRun());
    }
    setState(() => _running = starting);
  }

  Future<void> _showPlayTools() async {
    final bool showTeamProgress =
        widget.activityId > 0 &&
        ref.read(teamProgressProvider(widget.activityId)).value?.exists == true;
    final String? selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('游玩工具'),
        actions: <Widget>[
          if (widget.onOpenJournal != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop('journal'),
              child: const Text('旅程手记'),
            ),
          if (showTeamProgress)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop('team-progress'),
              child: const Text('队伍位置'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected == 'journal' && mounted) widget.onOpenJournal?.call();
    if (selected == 'team-progress' && mounted) _openTeamProgress();
  }

  void _openTeamProgress() {
    context.push('/team-lead/${widget.activityId}');
  }

  Future<void> _onScanPressed() async {
    if (_busy) return;
    final String? code = await Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => const _ScannerPage(),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final CheckinReward reward = await ref
          .read(
            playSessionProvider(
              _playKey(widget.activityId, widget.topicId),
            ).notifier,
          )
          .checkin(code);
      if (!mounted) return;
      await showRewardDialog(context, reward);
      // NPC: checkin success + activity finish
      _emitActivityNpc(ref, widget.activityId, NpcEventType.checkinSuccess);
      if (reward.completed) {
        _emitActivityNpc(ref, widget.activityId, NpcEventType.activityFinish);
      }
    } on PlayException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      _showError('打卡失败,请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    CyNativeNotice.show(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final bool disabled = !widget.playable || _busy;
    final TeamProgress? teamProgress = widget.activityId > 0
        ? ref.watch(teamProgressProvider(widget.activityId)).value
        : null;
    final bool showTeamProgress = teamProgress?.exists == true;
    final bool showPlayTools = showTeamProgress || widget.onOpenJournal != null;
    final bool supportsLiquidGlass =
        widget.liquidGlassSupported ??
        NativeLiquidGlassUtils.supportsLiquidGlass;
    final bool showEntryPass =
        widget.mode != _freeExploreMode && (widget.registrationId ?? 0) > 0;
    final Widget scanButton = CyNativeButton(
      label: _busy ? '打卡中...' : '扫码打卡',
      onPressed: disabled ? null : _onScanPressed,
      loading: _busy,
      width: double.infinity,
      height: CyTokens.btnH,
      borderRadius: CyTokens.radiusMd,
      liquidGlassSupported: widget.liquidGlassSupported,
      icon: const CyNativeButtonIcon(
        sfSymbol: 'qrcode.viewfinder',
        fallback: CupertinoIcons.qrcode_viewfinder,
      ),
    );
    if (widget.immersive) {
      return _immersiveBar(
        disabled: disabled,
        showEntryPass: showEntryPass,
        showPlayTools: showPlayTools,
        showTeamProgress: showTeamProgress,
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.space4,
          CyTokens.space2,
          CyTokens.space4,
          CyTokens.space3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!widget.playable && (widget.timeNote?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2),
                child: Text(
                  widget.timeNote!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                  ),
                ),
              ),
            if (showPlayTools)
              Align(
                alignment: Alignment.centerRight,
                child: KeyedSubtree(
                  key: const Key('play-more-tools'),
                  child: supportsLiquidGlass
                      ? LiquidGlassMenu(
                          menuTitle: '游玩工具',
                          label: '更多',
                          icon: NativeLiquidGlassIcon.sfSymbol(
                            'ellipsis.circle',
                          ),
                          height: 44,
                          items: <LiquidGlassMenuItem>[
                            if (widget.onOpenJournal != null)
                              LiquidGlassMenuItem(
                                id: 'journal',
                                title: '旅程手记',
                                icon: NativeLiquidGlassIcon.sfSymbol(
                                  'book.closed.fill',
                                ),
                              ),
                            if (showTeamProgress)
                              LiquidGlassMenuItem(
                                id: 'team-progress',
                                title: '队伍位置',
                                icon: NativeLiquidGlassIcon.sfSymbol(
                                  'person.3.fill',
                                ),
                              ),
                          ],
                          onItemSelected: (String id) {
                            if (id == 'journal') widget.onOpenJournal?.call();
                            if (id == 'team-progress') _openTeamProgress();
                          },
                        )
                      : CupertinoButton(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: CyTokens.space2,
                          ),
                          onPressed: _showPlayTools,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(CupertinoIcons.ellipsis_circle, size: 20),
                              SizedBox(width: CyTokens.space1),
                              Text('更多'),
                            ],
                          ),
                        ),
                ),
              ),
            if (showEntryPass)
              Row(
                children: <Widget>[
                  SizedBox(
                    width: CyTokens.btnH,
                    height: CyTokens.btnH,
                    child: Semantics(
                      // 小程序同一枚按钮的 aria-label 原话(pages/play/index.wxml:607,
                      // 出现条件也是 mode!=2 + 有报名单):说清这一步是**给商家核销**,
                      // 不是「随便看看我的码」。
                      label: '出示入场码给商家核销',
                      button: true,
                      child: CupertinoButton(
                        key: const Key('play-entry-pass'),
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        color: AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                        onPressed: () => context.push(
                          '/ticket/${widget.registrationId}/pass',
                        ),
                        child: const Icon(CupertinoIcons.qrcode),
                      ),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(child: scanButton),
                ],
              )
            else
              scanButton,
          ],
        ),
      ),
    );
  }

  Widget _immersiveBar({
    required bool disabled,
    required bool showEntryPass,
    required bool showPlayTools,
    required bool showTeamProgress,
  }) {
    Widget action({
      required String label,
      String? semantics,
      required IconData icon,
      required VoidCallback? onPressed,
      Color fill = const Color(0xFF999999),
      double size = 54,
    }) => Semantics(
      button: true,
      label: semantics ?? label,
      child: CupertinoButton(
        minimumSize: const Size(72, 72),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: Icon(icon, color: CupertinoColors.white, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: label == (_running ? '暂停' : '开始')
                    ? fill
                    : const Color(0xFF99A1AF),
                fontSize: 12,
                fontWeight: label == (_running ? '暂停' : '开始')
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      key: const Key('play-immersive-actions'),
      color: const Color(0xFF0D0E12),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showTeamProgress)
              Align(
                alignment: Alignment.centerRight,
                child: KeyedSubtree(
                  key: const Key('play-more-tools'),
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: _showPlayTools,
                    child: const Text('更多'),
                  ),
                ),
              )
            else if (showPlayTools)
              SizedBox(
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      top: -11,
                      bottom: -11,
                      left: 0,
                      right: 0,
                      child: CupertinoButton(
                        key: const Key('play-more-tools'),
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        onPressed: _showPlayTools,
                        child: const SizedBox(
                          width: 38,
                          height: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF4A5565),
                              borderRadius: BorderRadius.all(
                                Radius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 38,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFF4A5565),
                      borderRadius: BorderRadius.all(Radius.circular(99)),
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                action(
                  label: '核销',
                  icon: CupertinoIcons.qrcode_viewfinder,
                  onPressed: disabled
                      ? null
                      : showEntryPass
                      ? () => context.push(
                          '/ticket/${widget.registrationId}/pass',
                        )
                      : _onScanPressed,
                ),
                action(
                  label: _running ? '暂停' : '开始',
                  icon: _running
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  fill: _running
                      ? const Color(0xFFF75707)
                      : const Color(0xFF00B503),
                  size: 62,
                  onPressed: disabled ? null : _toggleRun,
                ),
                action(
                  label: '扫码',
                  // 真源这一格说的是它的用途:走到点位扫码到达。
                  semantics: '扫码到达',
                  icon: CupertinoIcons.viewfinder,
                  onPressed: disabled ? null : _onScanPressed,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏扫码页:扫到第一个 barcode 的 rawValue 即 pop 返回该字符串。
class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final Barcode b in capture.barcodes) {
      final String? raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: Colors.black,
        brightness: Brightness.dark,
        border: null,
        middle: Text('扫描节点二维码'),
      ),
      child: Stack(
        children: <Widget>[
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 取景框引导
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.nodeGlow, width: 2),
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              '将二维码对准取景框',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
