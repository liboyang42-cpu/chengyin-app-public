import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_action_sheet.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_native_notice.dart';
import '../../../core/widgets/cy_native_sheet.dart';
import '../../../core/widgets/cy_system_text_input_alert.dart';
import '../../../core/widgets/cy_widgets.dart';
import '../../../data/models/advanced_play.dart';
import 'advanced_play_controller.dart';
import 'advanced_playkit_view.dart';
import 'fullscreen/playkit_fullscreen_parts.dart';
import 'playkit_host.dart';
import 'playkit_projection.dart';

abstract interface class AdvancedPlayAudio {
  Stream<void> get completed;
  Stream<Duration> get positionChanged;
  bool get playing;
  Duration get position;
  Future<void> stop();
  Future<void> setUrl(String url, {MediaItem? mediaItem});
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

class JustAudioAdvancedPlayAudio implements AdvancedPlayAudio {
  JustAudioAdvancedPlayAudio() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get completed => _player.playerStateStream
      .where((state) => state.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<Duration> get positionChanged => _player.positionStream;

  @override
  bool get playing => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setUrl(String url, {MediaItem? mediaItem}) async {
    // tag = MediaItem 是给 just_audio_background 的锁屏/控制中心元数据。
    await _player.setUrl(url, tag: mediaItem);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() => _player.dispose();
}

Future<void> showAdvancedPlaySheet({
  required BuildContext context,
  required AdvancedPlayController controller,
  required String title,
  required VoidCallback onReadyForBase,
}) => showCyNativeSheet<void>(
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  context,
  // 真源高级玩法面近全屏(topGap .12),取大档;长内容由内部滚动兜。
  detents: CyNativeSheetDetents.large,
  builder: (BuildContext sheetContext) => AdvancedPlaySheet(
    controller: controller,
    title: title,
    onReadyForBase: onReadyForBase,
    onClose: () => Navigator.of(sheetContext, rootNavigator: true).pop(),
  ),
);

class AdvancedPlaySheet extends StatefulWidget {
  const AdvancedPlaySheet({
    super.key,
    required this.controller,
    required this.title,
    required this.onReadyForBase,
    this.scrollController,
    this.now = DateTime.now,
    this.audio,
    this.onClose,
  });

  final AdvancedPlayController controller;
  final String title;
  final VoidCallback onReadyForBase;
  final ScrollController? scrollController;
  final DateTime Function() now;
  final AdvancedPlayAudio? audio;
  final VoidCallback? onClose;

  @override
  State<AdvancedPlaySheet> createState() => _AdvancedPlaySheetState();
}

class _AdvancedPlaySheetState extends State<AdvancedPlaySheet> {
  Timer? _timer;
  late final AdvancedPlayAudio _audio;
  StreamSubscription<void>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  String? _playingUrl;
  Duration _audioPosition = Duration.zero;
  bool _audioBusy = false;
  bool _deadlineReadbackRequested = false;

  @override
  void initState() {
    super.initState();
    _audio = widget.audio ?? JustAudioAdvancedPlayAudio();
    widget.controller.addListener(_changed);
    _audioStateSubscription = _audio.completed.listen((_) {
      if (!mounted) return;
      setState(() {
        _playingUrl = null;
        _audioPosition = Duration.zero;
      });
    });
    _audioPositionSubscription = _audio.positionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _audioPosition = position);
    });
    if (widget.controller.phase == AdvancedPlayPhase.idle) {
      Future<void>.microtask(widget.controller.start);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant AdvancedPlaySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      if (widget.controller.phase == AdvancedPlayPhase.idle) {
        Future<void>.microtask(widget.controller.start);
      }
      _syncTimer();
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _syncTimer();
  }

  void _syncTimer() {
    final AdvancedPlayState? state = widget.controller.state;
    final bool enabled =
        state?.mechanics.timerEnabled == true && state?.deadlineAt != null;
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
      _deadlineReadbackRequested = false;
      return;
    }
    final int remaining =
        widget.controller.state?.remainingSeconds(widget.now()) ?? 0;
    if (remaining > 0) _deadlineReadbackRequested = false;
    if (remaining == 0) _readbackExpiredState();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final int remaining =
          widget.controller.state?.remainingSeconds(widget.now()) ?? 0;
      if (remaining == 0) _readbackExpiredState();
      setState(() {});
    });
  }

  void _readbackExpiredState() {
    if (_deadlineReadbackRequested ||
        widget.controller.phase != AdvancedPlayPhase.ready) {
      return;
    }
    _deadlineReadbackRequested = true;
    unawaited(widget.controller.refreshAuthoritative());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioStateSubscription?.cancel();
    _audioPositionSubscription?.cancel();
    _audio.dispose();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AdvancedPlayController controller = widget.controller;
    return CupertinoPageScaffold(
      // 原生 sheet 承载时透明,透出系统材质(S3);回退路径维持真源底。
      backgroundColor: isCyNativeSheet(context)
          ? CupertinoColors.transparent
          : CyTokens.bgPage,
      child: SafeArea(
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space5,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: CyTokens.textPrimary,
                      fontSize: CyTokens.typeSectionTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  CupertinoButton(
                    minimumSize: const Size.square(44),
                    padding: EdgeInsets.zero,
                    onPressed: widget.onClose,
                    child: const Icon(
                      CupertinoIcons.xmark,
                      color: CyTokens.textPrimary,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: CyTokens.space2),
            const Text(
              '高级玩法',
              style: TextStyle(
                color: CyTokens.textSecondary,
                fontSize: CyTokens.typeCaption,
              ),
            ),
            const SizedBox(height: CyTokens.space4),
            ..._body(controller),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(AdvancedPlayController controller) {
    switch (controller.phase) {
      case AdvancedPlayPhase.idle:
      case AdvancedPlayPhase.loading:
        return <Widget>[
          const Center(child: CupertinoActivityIndicator(radius: 14)),
          const SizedBox(height: CyTokens.space3),
          const Center(child: _MutedText('正在读取服务端权威状态…')),
        ];
      case AdvancedPlayPhase.unsupported:
        return <Widget>[
          _NoticeCard(
            icon: CupertinoIcons.exclamationmark_shield,
            title: '当前玩法暂不可用',
            detail: controller.message,
          ),
        ];
      case AdvancedPlayPhase.unknown:
        return <Widget>[
          _NoticeCard(
            icon: CupertinoIcons.arrow_2_circlepath,
            title: '结果尚未确认',
            detail: controller.message,
          ),
          const SizedBox(height: CyTokens.space3),
          CyNativeButton(
            label: '再核对一次',
            role: CyNativeButtonRole.secondary,
            width: double.infinity,
            onPressed: controller.resolveUnknown,
          ),
        ];
      case AdvancedPlayPhase.retryable:
        return <Widget>[
          _NoticeCard(
            icon: CupertinoIcons.checkmark_shield,
            title: '已核对权威状态',
            detail: controller.message,
          ),
          const SizedBox(height: CyTokens.space3),
          CyNativeButton(
            label: '安全重试刚才的动作',
            width: double.infinity,
            onPressed: controller.retryPending,
          ),
        ];
      case AdvancedPlayPhase.error:
        return <Widget>[
          _NoticeCard(
            icon: CupertinoIcons.exclamationmark_circle,
            title: '暂时无法继续',
            detail: controller.message,
          ),
          const SizedBox(height: CyTokens.space3),
          CyNativeButton(
            label: '重新读取',
            role: CyNativeButtonRole.secondary,
            width: double.infinity,
            onPressed: controller.start,
          ),
        ];
      case AdvancedPlayPhase.acting:
      case AdvancedPlayPhase.ready:
        return _session(controller);
    }
  }

  List<Widget> _session(AdvancedPlayController controller) {
    final AdvancedPlayState? state = controller.state;
    if (state == null) return const <Widget>[];
    final List<Widget> content = <Widget>[
      _StatusCard(state: state, now: widget.now()),
      const SizedBox(height: CyTokens.space3),
    ];
    if (controller.message.isNotEmpty) {
      content.addAll(<Widget>[
        _MutedText(controller.message),
        const SizedBox(height: CyTokens.space3),
      ]);
    }
    if (state.mechanics.randomEnabled) {
      content.add(_randomCard(controller, state));
      content.add(const SizedBox(height: CyTokens.space3));
    }
    if (state.mechanics.branchEnabled && state.branch?.currentStep != null) {
      content.add(_branchCard(controller, state.branch!.currentStep!));
      content.add(const SizedBox(height: CyTokens.space3));
    }
    if (state.isMultiplayer) {
      content.add(_multiplayerCard(controller, state));
      content.add(const SizedBox(height: CyTokens.space3));
    }
    for (final PlayKitCard card in projectPlayKit(
      state.playKit,
      present: playKitPresentationOf(state.present),
    )) {
      content.add(_playKitCard(controller, card));
      content.add(const SizedBox(height: CyTokens.space3));
    }
    if (state.mechanics.leaderboardEnabled) {
      content.add(_leaderboardCard(controller, state));
      content.add(const SizedBox(height: CyTokens.space4));
    }
    content.add(
      CyNativeButton(
        label: controller.readyForBase ? '继续基础任务' : '先完成上面的玩法',
        width: double.infinity,
        loading: controller.phase == AdvancedPlayPhase.acting,
        onPressed: controller.readyForBase ? widget.onReadyForBase : null,
      ),
    );
    return content;
  }

  Widget _randomCard(
    AdvancedPlayController controller,
    AdvancedPlayState state,
  ) {
    final bool complete = state.draws.length >= state.mechanics.randomDrawCount;
    return _GameCard(
      title: '随机盲盒',
      subtitle: '已抽 ${state.draws.length} / ${state.mechanics.randomDrawCount}',
      children: <Widget>[
        for (final AdvancedPlayDraw draw in state.draws)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              '${draw.label}\n${draw.content}',
              style: const TextStyle(
                color: CyTokens.textPrimary,
                height: CyTokens.leadingNormal,
              ),
            ),
          ),
        const SizedBox(height: CyTokens.space3),
        Semantics(
          label: '抽取随机任务',
          button: true,
          enabled: controller.canWrite && !complete,
          child: ExcludeSemantics(
            child: CyNativeButton(
              key: const Key('advanced-play-draw'),
              label: '抽一次',
              width: double.infinity,
              onPressed: controller.canWrite && !complete
                  ? () => controller.submit('DRAW')
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _branchCard(
    AdvancedPlayController controller,
    AdvancedPlayBranchStep step,
  ) => _GameCard(
    title: step.title.isEmpty ? '分支剧情' : step.title,
    subtitle: step.body,
    children: <Widget>[
      for (final AdvancedPlayBranchOption option in step.options)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space2),
          child: CyNativeButton(
            label: option.label,
            role: CyNativeButtonRole.secondary,
            width: double.infinity,
            onPressed: controller.canWrite
                ? () => controller.submit('CHOOSE', <String, Object?>{
                    'optionId': option.id,
                  })
                : null,
          ),
        ),
      if (step.terminal) ...<Widget>[
        const SizedBox(height: CyTokens.space2),
        const _MutedText('这一段剧情已抵达终点'),
      ],
    ],
  );

  Widget _playKitCard(AdvancedPlayController controller, PlayKitCard card) {
    if (card.kind == PlayKitKind.blindTaste ||
        card.kind == PlayKitKind.musicCorner ||
        card.kind == PlayKitKind.slowTask) {
      return AdvancedPlayKitView(
        card: card,
        enabled: controller.canWrite,
        acting: controller.phase == AdvancedPlayPhase.acting,
        audioPlaying: _playingUrl == card.mediaUrl && _audio.playing,
        audioPosition: _playingUrl == card.mediaUrl
            ? _audioPosition
            : Duration.zero,
        onToggleAudio: card.mediaUrl == null
            ? null
            : () {
                playKitHaptic(context, PlayKitHaptic.light);
                unawaited(_toggleMusic(card));
              },
        onAction: (PlayKitAction action) {
          playKitHaptic(context, PlayKitHaptic.medium);
          unawaited(controller.submit(action.action, action.payload));
        },
      );
    }
    // v5.2 那批(整屏族 + 两件 sheet)不在这一格内联:整屏族压在半屏里
    // 「整屏就是判定区」当场不成立(真源注释原文),所以它们走呈现层 ——
    // 整屏走全屏路由、gameTimer/stickerBook 走底部 sheet。
    // 判据是缝的注册表(不是「构建一遍看是不是 null」):注册表里没有的 kind
    // 继续回落下面那张通用卡 —— 不崩、不报错。
    if (hasPlayKitComponent(card.kind)) {
      return _GameCard(
        title: card.title,
        subtitle: card.detail,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: CyNativeButton(
              label: '进入玩法',
              width: double.infinity,
              onPressed: () => unawaited(
                showPlayKitOverlay(
                  context: context,
                  controller: controller,
                  kind: card.kind,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _GameCard(
      title: card.title,
      subtitle: card.detail,
      children: <Widget>[
        for (final PlayKitAction choice in card.choices)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: CyNativeButton(
              label: choice.label,
              role: CyNativeButtonRole.secondary,
              width: double.infinity,
              onPressed: controller.canWrite
                  ? () => controller.submit(choice.action, choice.payload)
                  : null,
            ),
          ),
        if (card.kind == PlayKitKind.diyName && !card.complete)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: CyNativeButton(
              label: '输入名字',
              width: double.infinity,
              onPressed: controller.canWrite
                  ? () => _submitDiyName(
                      controller,
                      card.maxLength ?? 16,
                      card.suggestions,
                    )
                  : null,
            ),
          ),
        if (card.primaryAction case final PlayKitAction action)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: CyNativeButton(
              label: action.label,
              width: double.infinity,
              onPressed: controller.canWrite
                  ? () => controller.submit(action.action, action.payload)
                  : null,
            ),
          ),
        if (card.kind == PlayKitKind.musicCorner && card.mediaUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: CyNativeButton(
              label: _playingUrl == card.mediaUrl ? '暂停' : '播放',
              role: CyNativeButtonRole.secondary,
              width: double.infinity,
              loading: _audioBusy,
              onPressed: _audioBusy ? null : () => _toggleMusic(card),
            ),
          ),
        if (card.kind == PlayKitKind.steps && !card.complete)
          const Padding(
            padding: EdgeInsets.only(top: CyTokens.space2),
            child: _MutedText('该计步契约需微信运动授权，App 不会伪造步数提交'),
          ),
      ],
    );
  }

  Widget _multiplayerCard(
    AdvancedPlayController controller,
    AdvancedPlayState state,
  ) {
    final AdvancedPlayMultiplayerConfig config = state.mechanics.multiplayer;
    final AdvancedPlayMultiplayerState multiplayer = state.multiplayer;
    return _GameCard(
      title: '多人协作',
      subtitle:
          '已完成 ${multiplayer.completedUnitIds.length} / ${config.requiredTurns} 轮',
      children: <Widget>[
        for (final AdvancedPlayMember member in multiplayer.members)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: _MultiplayerMemberRow(
              member: member,
              roleLabel: config.roleLabel(member.roleId),
              canAssign:
                  config.assignment == 'LEADER' &&
                  config.roles.isNotEmpty &&
                  controller.canWrite,
              onAssign: () => _assignRole(controller, config, member),
            ),
          ),
        if (multiplayer.members.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: CyTokens.space2),
            child: _MutedText('等待队伍成员加入'),
          ),
        const SizedBox(height: CyTokens.space3),
        CyNativeButton(
          key: const Key('advanced-play-complete-unit'),
          label: controller.phase == AdvancedPlayPhase.acting
              ? '提交中…'
              : '完成我的当前轮次',
          width: double.infinity,
          loading: controller.phase == AdvancedPlayPhase.acting,
          onPressed: controller.canWrite
              ? controller.completeCurrentUnit
              : null,
        ),
      ],
    );
  }

  Future<void> _assignRole(
    AdvancedPlayController controller,
    AdvancedPlayMultiplayerConfig config,
    AdvancedPlayMember member,
  ) async {
    final String? roleId = await showCyNativeActionSheet<String>(
      context: context,
      title: member.name.isEmpty ? '分配角色' : '为 ${member.name} 分配角色',
      actions: config.roles
          .map(
            (AdvancedPlayRole role) => CyNativeAction<String>(
              value: role.id,
              label: role.label,
              systemImage: member.roleId == role.id
                  ? 'checkmark.circle.fill'
                  : 'person.crop.circle',
            ),
          )
          .toList(growable: false),
    );
    if (!mounted || roleId == null) return;
    await controller.assignRole(member.memberId, roleId);
  }

  Future<void> _submitDiyName(
    AdvancedPlayController controller,
    int maxLength,
    List<String> suggestions,
  ) async {
    // 输入弹窗走原生桥(iOS 系统 alert + UITextField):对照表「input 弹窗 →
    // showCySystemTextInputAlert」,与同域 circle_theme_play_page 同一口径。
    //
    // 商家配的备选词(真源 `buildDiyName` 的 `suggestions`)在系统 alert 里没有
    // 渲染位,所以先过一遍系统的选择表(与同文件 `_assignRole` 同一颗缝)。
    // 点选 = **填进输入框**,不是直接提交 —— 与真源同口径:它的
    // `onPickSuggestion` 发的也是 `namechange`(改值),提交是另一颗按钮。
    String initialValue = '';
    if (suggestions.isNotEmpty) {
      final String? picked = await showCyNativeActionSheet<String>(
        context: context,
        title: '猫向导递来几个备选',
        actions: <CyNativeAction<String>>[
          for (final String suggestion in suggestions)
            CyNativeAction<String>(value: suggestion, label: '「$suggestion」'),
          const CyNativeAction<String>(value: '', label: '自己输入'),
        ],
      );
      if (!mounted || picked == null) return;
      initialValue = picked;
    }
    final String? result = await showCySystemTextInputAlert(
      context: context,
      title: '给今天起个名字',
      placeholder: '输入名字',
      confirmText: '提交',
      initialValue: initialValue,
      keyboardKind: CySystemKeyboardKind.text,
    );
    final String name = result?.trim() ?? '';
    if (name.isNotEmpty) {
      // ponytail: 原生 alert 没有 maxlength,服务端字段长度按码点截一次;
      // 要按字素簇精确截断(含 ZWJ emoji)时再接 characters。
      final String clipped = name.runes.length > maxLength
          ? String.fromCharCodes(name.runes.take(maxLength))
          : name;
      // 字段名是 `value`,不是 `name`:小程序那边这一页发的是
      // `playkit-diyname/index.js` 的 `triggerEvent('submit', { value })`,
      // 分发器原样透传(`playkit-view.js` 的 `serverPayload` 对它走 default),
      // 服务端实收 `{ value }`。段数据里那格确实叫 `name`,但那是**视图字段**。
      // 发错字段的后果不是报错:服务端读不到就按 0 判,玩家永远不通过。
      await controller.submit('SUBMIT_DIY_NAME', <String, Object?>{
        'value': clipped,
      });
    }
  }

  /// 锁屏/控制中心元数据。曲名取服务端下发的 track/卡标题,专辑取卡标题,
  /// 时长用 musicCorner 下发的 durationSeconds —— 全部真实字段。
  /// ⚠️ duration 不许为 null:just_audio_background 的锁屏拖动对
  ///   `MediaItem.duration!` 强解包;下发缺失时落到 1ms 防炸。
  MediaItem _mediaItemFor(PlayKitCard card) => MediaItem(
    id: 'playkit-${card.kind.name}-${card.mediaUrl}',
    title: card.detail.isNotEmpty ? card.detail : card.title,
    album: card.title,
    duration: card.durationSeconds > 0
        ? Duration(seconds: card.durationSeconds)
        : const Duration(milliseconds: 1),
  );

  Future<void> _toggleMusic(PlayKitCard card) async {
    final String url = card.mediaUrl!;
    setState(() => _audioBusy = true);
    try {
      if (_playingUrl == url && _audio.playing) {
        await _audio.pause();
        if (mounted) setState(() => _playingUrl = null);
        return;
      }
      await _audio.stop();
      await _audio.setUrl(url, mediaItem: _mediaItemFor(card));
      if (!mounted) return;
      setState(() {
        _playingUrl = url;
        _audioPosition = _audio.position;
      });
      unawaited(
        _audio.play().catchError((Object _) {
          if (mounted) setState(() => _playingUrl = null);
        }),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _playingUrl = null);
      // 纯告知,不弹 alert(S7):文案照原样,合并不改写。
      CyNativeNotice.show(context, '音频暂时无法播放，请检查网络后重试', isError: true);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Widget _leaderboardCard(
    AdvancedPlayController controller,
    AdvancedPlayState state,
  ) => _GameCard(
    title: '排行榜',
    subtitle: controller.leaderboard.isEmpty ? '还没有排名数据' : '',
    children: <Widget>[
      for (final AdvancedPlayLeaderboardRow row in controller.leaderboard)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 34,
                child: Text(
                  '${row.rank}',
                  style: const TextStyle(color: CyTokens.textSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  row.displayName,
                  style: const TextStyle(color: CyTokens.textPrimary),
                ),
              ),
              Text(
                row.metricValue(state.mechanics.leaderboardMetric),
                style: const TextStyle(
                  color: CyTokens.textPrimary,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: CyTokens.space2),
      CyNativeButton(
        label: '刷新排行榜',
        role: CyNativeButtonRole.secondary,
        width: double.infinity,
        onPressed: controller.loadLeaderboard,
      ),
    ],
  );
}

class _MultiplayerMemberRow extends StatelessWidget {
  const _MultiplayerMemberRow({
    required this.member,
    required this.roleLabel,
    required this.canAssign,
    required this.onAssign,
  });

  final AdvancedPlayMember member;
  final String roleLabel;
  final bool canAssign;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final String name = member.name.isEmpty
        ? '成员 ${member.memberId}'
        : member.name;
    final String initial = name.characters.first;
    return Row(
      children: <Widget>[
        // 头像走共用件 `CyAvatar`(同域 `play_leaderboard_sheet.dart` 的榜内行用的
        // 就是它):自带描边、URL 失效兜成首字母,不再在此手搓一份 ClipOval +
        // Image.network + 兜底块(三处重复 = 改一次要改三处)。
        CyAvatar(
          url: member.avatar.isEmpty ? null : member.avatar,
          fallback: initial,
          size: 40,
        ),
        const SizedBox(width: CyTokens.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CyTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: CyTokens.space1),
              Text(
                roleLabel.isEmpty ? '待分配' : roleLabel,
                style: const TextStyle(
                  color: CyTokens.textSecondary,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
            ],
          ),
        ),
        if (canAssign)
          SizedBox(
            width: 104,
            child: CyNativeButton(
              label: '分配角色',
              role: CyNativeButtonRole.secondary,
              onPressed: onAssign,
            ),
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.now});
  final AdvancedPlayState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final int remaining = state.remainingSeconds(now);
    return Semantics(
      container: true,
      label:
          '当前状态 ${state.status}，得分 ${state.score}${state.deadlineAt == null ? '' : '，剩余 $remaining 秒'}',
      child: ExcludeSemantics(
        child: _GameCard(
          title: state.status == 'RUNNING' ? '进行中' : state.status,
          subtitle: state.deadlineAt == null
              ? '得分 ${state.score}'
              : '剩余 $remaining 秒 · 得分 ${state.score}',
          children: const <Widget>[],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
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
          title,
          style: const TextStyle(
            color: CyTokens.textPrimary,
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          _MutedText(subtitle),
        ],
        ...children,
      ],
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => _GameCard(
    title: title,
    subtitle: detail,
    children: <Widget>[
      const SizedBox(height: CyTokens.space3),
      Icon(icon, color: CyTokens.textSecondary, size: 30),
    ],
  );
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: const TextStyle(
      color: CyTokens.textSecondary,
      fontSize: CyTokens.typeBody,
      height: CyTokens.leadingNormal,
    ),
  );
}
