import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
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
  @override
  GlobalNpcState build() {
    // ★ 自加载:原先由 map_page / profile_page 各自在 build() 里
    //   `Future.microtask(load)` 触发 —— 每次重建都发一次请求。
    //   放在这里只在 provider 首次被 watch 时跑一次。
    Future.microtask(load);
    return const GlobalNpcState();
  }

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true);
    try {
      final api = ref.read(aiNpcApiProvider);
      final profiles = await api.fetchProfiles(scope: 'global');
      state = GlobalNpcState(
        profile: profiles.isNotEmpty ? profiles.first : null,
      );
    } catch (_) {
      state = const GlobalNpcState(); // 静默降级
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
  NpcSessionState build() => const NpcSessionState();

  Future<void> loadProfiles() async {
    try {
      final api = ref.read(aiNpcApiProvider);
      final npcs = await api.fetchProfiles(
        scope: 'activity',
        activityId: _activityId,
      );
      state = state.copyWith(npcs: npcs);
    } catch (_) {}
  }

  /// 事件触发 → 拉冒泡话术 → 推入队列
  Future<void> onEvent(NpcEventType event, {int? nodeId}) async {
    if (state.npcs.isEmpty) return;
    final primary = state.npcs.first;
    try {
      final api = ref.read(aiNpcApiProvider);
      final line = await api.fetchEventLine(
        profileId: primary.profileId,
        eventType: event.apiValue,
        nodeId: nodeId,
      );
      if (line.line.isNotEmpty) {
        state = state.copyWith(
          bubbleQueue: [...state.bubbleQueue, line],
          history: [...state.history, line],
        );
        // ★ 没有这行,队列只进不出:UI 渲染的是 bubbleQueue.first,
        //   第一条冒泡会永远停在屏幕上,之后所有事件的话术都看不到。
        //   (popBubble 在此之前零调用方 —— 写了但没人调。)
        Future.delayed(_bubbleTtl, () {
          if (ref.mounted) popBubble();
        });
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
    if (state.npcs.isEmpty || state.loading) return;
    state = state.copyWith(loading: true, clearDelta: true);
    final primary = state.npcs.first;
    final buf = StringBuffer();
    try {
      final api = ref.read(aiNpcApiProvider);
      final stream = api.chatStream(
        activityId: _activityId,
        profileId: primary.profileId,
        message: message,
      );
      await for (final data in stream) {
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
    } catch (_) {
      state = state.copyWith(loading: false, clearDelta: true);
    }
  }
}

final npcSessionProvider = NotifierProvider.family<NpcSessionNotifier,
    NpcSessionState, int>(
  NpcSessionNotifier.new,
);
