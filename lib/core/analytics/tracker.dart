// 埋点上报器 —— 攒批 + 定时 flush。
//
// App 侧有完整的事件白名单(analytics_api.dart,还有一条防漂测试拿后端源码比对)，
// 搜索与广场等页面只通过本 Tracker 上报，避免各页面自行拼请求和隐私字段。
//
// ★★ 攒批不是优化,是必须的:后端一批最多 50 条,而 content_view 这类事件
//   在列表页滚一屏就能产生十几条。逐条发既打后端也打电量。
//
// ⚠️ 埋点**永远不能影响主流程**:
//   · 上报失败一律吞掉(不 toast、不改 UI、不无限重试)
//   · 队列有上限,满了丢**最旧**的 —— 丢新的会让「刚发生的事」永远上报不了,
//     而排查问题时要看的恰恰是最近发生的
//   · track() 不 await,立刻返回
//
// ★ 明确不做的:没有本地持久化,进程被杀会丢掉未发的那批。
//   做持久化要先回答「重启后补发会不会重复」,现在没有答案,
//   所以先不做,而不是做一个半吊子。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/analytics_api.dart';
import '../providers.dart';
import '../../feature/auth/auth_controller.dart';

class _QueuedAnalyticsEvent {
  const _QueuedAnalyticsEvent(this.event, this.actorScope);
  final AnalyticsEvent event;
  final String actorScope;
}

class Tracker {
  Tracker(
    this._api, {
    this.flushAfter = const Duration(seconds: 5),
    String Function()? actorScope,
    this.enabled = true,
  }) : _actorScope = actorScope ?? _anonymousScope;

  final AnalyticsApi _api;
  final Duration flushAfter;
  final bool enabled;
  final String Function() _actorScope;
  int _eventSequence = 0;
  final math.Random _random = math.Random.secure();

  static String _anonymousScope() => 'anonymous';

  /// 攒到一整批就立刻发,别等定时器。
  static const int flushAt = AnalyticsApi.maxBatchSize;

  /// 队列硬上限:后端连不上时不能无限攒。
  static const int maxQueue = 200;

  final List<_QueuedAnalyticsEvent> _q = <_QueuedAnalyticsEvent>[];
  Timer? _timer;
  bool _sending = false;
  int _automaticRetryCount = 0;
  bool _disposed = false;

  static const Duration maxAutomaticRetryDelay = Duration(minutes: 1);
  static const int maxAutomaticRetryAttempts = 8;

  void _scheduleFlush(Duration delay) {
    if (_disposed) return;
    _timer ??= Timer(delay, () => unawaited(flush()));
  }

  @visibleForTesting
  int get pending => _q.length;

  /// 队列里现存事件的 bizId(测试用)——「丢最旧」和「丢最新」
  /// 只看条数是分不出来的,必须看留下的是哪几条。
  @visibleForTesting
  List<int?> get pendingIds =>
      _q.map((_QueuedAnalyticsEvent e) => e.event.bizId).toList();

  /// 记一条。★ 不 await、不抛 —— 埋点不许影响调用方。
  void track(
    String eventName, {
    String? bizType,
    int? bizId,
    String? pagePath,
    Map<String, dynamic>? properties,
    String? idempotencyKey,
  }) {
    if (_disposed || !enabled) return;
    // 白名单在客户端先挡一道:发一条后端不认的只是浪费一次往返。
    if (!AnalyticsApi.allowedEvents.contains(eventName)) return;
    if (_q.length >= maxQueue) {
      _q.removeAt(0);
    }
    final DateTime now = DateTime.now();
    final String stableDeliveryKey =
        idempotencyKey ??
        'analytics-${now.microsecondsSinceEpoch}-'
            '${_random.nextInt(1 << 32).toRadixString(16)}-'
            '${_random.nextInt(1 << 32).toRadixString(16)}-'
            '${_eventSequence++}';
    final String eventActorScope = _actorScope();
    _q.add(
      _QueuedAnalyticsEvent(
        AnalyticsEvent(
          eventName: eventName,
          bizType: bizType,
          bizId: bizId,
          pagePath: pagePath,
          properties: properties,
          idempotencyKey: stableDeliveryKey,
          actorScope: eventActorScope,
          occurredAt: now,
        ),
        eventActorScope,
      ),
    );
    if (_q.length >= flushAt) {
      unawaited(flush());
      return;
    }
    _scheduleFlush(flushAfter);
  }

  /// 发一批。失败**静默吞掉**,并把事件放回队首等下一轮。
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_disposed || _sending || _q.isEmpty) return;
    final String currentScope = _actorScope();
    _q.removeWhere(
      (_QueuedAnalyticsEvent queued) => queued.actorScope != currentScope,
    );
    if (_q.isEmpty) return;
    _sending = true;
    final List<_QueuedAnalyticsEvent> queuedBatch = _q
        .take(AnalyticsApi.maxBatchSize)
        .toList();
    _q.removeRange(0, queuedBatch.length);
    final List<AnalyticsEvent> batch = queuedBatch
        .map((_QueuedAnalyticsEvent queued) => queued.event)
        .toList(growable: false);
    Duration? retryDelay;
    try {
      await _api.report(batch);
      _automaticRetryCount = 0;
    } catch (_) {
      _automaticRetryCount++;
      if (_automaticRetryCount >= maxAutomaticRetryAttempts) {
        _automaticRetryCount = 0;
      } else {
        // 放回队首、保持顺序;超上限时把最旧的挤掉(同 track 的规则)。
        _q.insertAll(0, queuedBatch);
        while (_q.length > maxQueue) {
          _q.removeAt(0);
        }
      }
      final int exponent = _automaticRetryCount > 6 ? 6 : _automaticRetryCount;
      final int multiplier = 1 << exponent;
      final Duration candidate = flushAfter * multiplier;
      retryDelay = candidate > maxAutomaticRetryDelay
          ? maxAutomaticRetryDelay
          : candidate;
    } finally {
      _sending = false;
      if (!_disposed && _q.isNotEmpty) {
        _scheduleFlush(retryDelay ?? flushAfter);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// 全局单例。★ **故意不放进 core/providers.dart** ——
/// 那个文件当前有未提交的在途改动(NPC),往里加会污染那份工作。
final trackerProvider = Provider<Tracker>((Ref ref) {
  final int? principal = ref.watch(
    authControllerProvider.select((AuthState state) => state.user?.id),
  );
  final String generation = principal == null
      ? 'anonymous'
      : 'member:$principal';
  final Tracker t = Tracker(
    AnalyticsApi(ref.watch(dioClientProvider)),
    enabled: principal != null,
    actorScope: () {
      final int? current = ref.read(authControllerProvider).user?.id;
      if (current == principal) return generation;
      return current == null ? 'anonymous' : 'member:$current';
    },
  );
  ref.onDispose(t.dispose);
  return t;
});
