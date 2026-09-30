import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/network/session_data.dart';
import '../../core/network/request_session_scope.dart';
import '../../data/models/npc.dart';

// --- 全局 NPC 常驻状态 ---

class GlobalNpcState {
  final NpcProfile? profile;
  final bool loading;

  const GlobalNpcState({this.profile, this.loading = false});

  GlobalNpcState copyWith({NpcProfile? profile, bool? loading}) {
    return GlobalNpcState(
      profile: profile ?? this.profile,
      loading: loading ?? this.loading,
    );
  }
}

class GlobalNpcNotifier extends Notifier<GlobalNpcState> {
  int _generation = 0;

  @override
  GlobalNpcState build() {
    // Preserve existing guest loading. Rebuild when the API's
    // session dependency changes, without retaining an earlier response.
    ref.watch(aiNpcApiProvider);
    final generation = ++_generation;
    ref.onDispose(() { _generation++; });
    Future.microtask(() {
      if (ref.mounted && generation == _generation) load();
    });
    return const GlobalNpcState();
  }

  Future<void> load() async {
    if (!ref.mounted || state.loading) return;
    final generation = _generation;
    state = state.copyWith(loading: true);
    try {
      final api = ref.read(aiNpcApiProvider);
      final scope = RequestSessionScope(
        () => ref.mounted && generation == _generation,
        requireAuthentication: false,
      );
      final profiles = await RequestSessionScope.run(
        scope, () => api.fetchProfiles(scope: 'global'),
      );
      if (!ref.mounted || generation != _generation) return;
      state = GlobalNpcState(
        profile: profiles.isNotEmpty ? profiles.first : null,
      );
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = const GlobalNpcState(); // 静默降级
      }
    }
  }
}

final globalNpcProvider =
    NotifierProvider<GlobalNpcNotifier, GlobalNpcState>(
  GlobalNpcNotifier.new,
);

// --- 局内 NPC 会话状态(family by activityId) ---

class NpcSessionState {
  final List<NpcProfile> npcs;
  final List<NpcLine> bubbleQueue; // 待显示的冒泡队列
  final List<NpcLine> history;
  final String? streamDelta; // 追问流式增量(最新 delta)
  final bool loading;

  const NpcSessionState({
    this.npcs = const [],
    this.bubbleQueue = const [],
    this.history = const [],
    this.streamDelta,
    this.loading = false,
  });

  NpcSessionState copyWith({
    List<NpcProfile>? npcs,
    List<NpcLine>? bubbleQueue,
    List<NpcLine>? history,
    String? streamDelta,
    bool? loading,
    bool clearDelta = false,
  }) {
    return NpcSessionState(
      npcs: npcs ?? this.npcs,
      bubbleQueue: bubbleQueue ?? this.bubbleQueue,
      history: history ?? this.history,
      streamDelta: clearDelta ? null : (streamDelta ?? this.streamDelta),
      loading: loading ?? this.loading,
    );
  }
}

/// 单条冒泡的停留时长。
const Duration _bubbleTtl = Duration(seconds: 5);

class NpcSessionNotifier extends Notifier<NpcSessionState> {
  NpcSessionNotifier(this._activityId);

  final int _activityId;

  @override
  NpcSessionState build() {
    _cancelPending();
    _scope = null;
    final generation = ++_generation;
    ref.onDispose(() { _generation++; _cancelPending(); });
    try {
      final session = watchSessionDataScope(ref);
      _scope = RequestSessionScope(() => generation == _generation && session.isCurrent());
    } on SessionDataUnavailable { /* No private session while signed out. */ }
    return const NpcSessionState();
  }

  int _generation = 0;
  RequestSessionScope? _scope;
  StreamIterator<String>? _chat;
  final _bubbleTimers = <Timer>[];

  void _cancelPending() {
    final chat = _chat;
    _chat = null;
    if (chat != null) unawaited(chat.cancel());
    for (final timer in _bubbleTimers) { timer.cancel(); }
    _bubbleTimers.clear();
  }

  Future<void> loadProfiles() async {
    final scope = _scope;
    if (scope == null || !scope.isCurrent()) return;
    try {
      final api = ref.read(aiNpcApiProvider);
      final npcs = await RequestSessionScope.run(scope, () => api.fetchProfiles(
        scope: 'activity',
        activityId: _activityId,
      ));
      if (!scope.isCurrent()) return;
      state = state.copyWith(npcs: npcs);
    } catch (_) {}
  }

  /// 事件触发 → 拉冒泡话术 → 推入队列
  Future<void> onEvent(NpcEventType event, {int? nodeId}) async {
    final scope = _scope;
    if (state.npcs.isEmpty || scope == null || !scope.isCurrent()) return;
    final primary = state.npcs.first;
    try {
      final api = ref.read(aiNpcApiProvider);
      final line = await RequestSessionScope.run(scope, () => api.fetchEventLine(
        profileId: primary.profileId,
        eventType: event.apiValue,
        nodeId: nodeId,
      ));
      if (!scope.isCurrent()) return;
      if (line.line.isNotEmpty) {
        state = state.copyWith(
          bubbleQueue: [...state.bubbleQueue, line],
          history: [...state.history, line],
        );
        // ★ 没有这行,队列只进不出:UI 渲染的是 bubbleQueue.first,
        //   第一条冒泡会永远停在屏幕上,之后所有事件的话术都看不到。
        //   (popBubble 在此之前零调用方 —— 写了但没人调。)
        late final Timer timer;
        timer = Timer(_bubbleTtl, () {
          _bubbleTimers.remove(timer);
          if (scope.isCurrent()) popBubble();
        });
        _bubbleTimers.add(timer);
      }
    } catch (_) {}
  }

  /// 从队列移除已显示的冒泡
  void popBubble() {
    if (state.bubbleQueue.isEmpty) return;
    final q = List<NpcLine>.from(state.bubbleQueue)..removeAt(0);
    state = state.copyWith(bubbleQueue: q);
  }

  /// 追问: SSE 流式累加 delta
  Future<void> sendChat(String message) async {
    final scope = _scope;
    if (state.npcs.isEmpty || state.loading || scope == null || !scope.isCurrent()) return;
    state = state.copyWith(loading: true, clearDelta: true);
    final primary = state.npcs.first;
    final buf = StringBuffer();
    StreamIterator<String>? iterator;
    try {
      await RequestSessionScope.run(scope, () async {
        final api = ref.read(aiNpcApiProvider);
        final stream = api.chatStream(
          activityId: _activityId,
          profileId: primary.profileId,
          message: message,
        );
        final current = StreamIterator<String>(stream);
        iterator = current;
        _chat = current;
        while (await current.moveNext()) {
          if (!scope.isCurrent()) return;
          final data = current.current;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (json['done'] == true) {
              // 完成: 将完整回复加入历史
              final fullLine = NpcLine(
                profileId: primary.profileId,
                name: primary.name,
                avatar: primary.avatar,
                line: buf.toString(),
              );
              state = state.copyWith(
                history: [...state.history, fullLine],
                loading: false,
                clearDelta: true,
              );
              return;
            }
            final delta = json['delta'] as String?;
            if (delta != null) {
              buf.write(delta);
              state = state.copyWith(streamDelta: buf.toString());
            }
          } catch (_) {}
        }
      });
    } catch (_) {
      // Failed/stale streams never contribute a completed reply.
    } finally {
      final current = iterator;
      if (current != null) await current.cancel();
      if (identical(_chat, current)) _chat = null;
      if (scope.isCurrent()) state = state.copyWith(loading: false, clearDelta: true);
    }
  }
}

final npcSessionProvider = NotifierProvider.family<NpcSessionNotifier,
    NpcSessionState, int>(
  NpcSessionNotifier.new,
);
