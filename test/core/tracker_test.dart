// 埋点上报器:攒批、丢弃策略、失败不影响主流程。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/analytics/tracker.dart';
import 'package:chengyin_app/data/api/analytics_api.dart';

class _FakeApi implements AnalyticsApi {
  _FakeApi({this.fail = false, this.hang = false});
  bool fail;

  /// 永不返回。★ 用来把 flush **隔离掉**:否则自动 flush 会不停地
  ///   把事件搬出搬回,测「队列满了丢谁」时测到的是搬运的中间态,
  ///   两种丢弃策略都能绿(第一版负控就是这么假绿的)。
  final bool hang;
  final List<List<AnalyticsEvent>> batches = <List<AnalyticsEvent>>[];
  int attempts = 0;

  @override
  Future<Map<String, String>> report(List<AnalyticsEvent> events) {
    attempts++;
    if (hang) return Completer<Map<String, String>>().future;
    if (fail) return Future<Map<String, String>>.error(Exception('network'));
    batches.add(events);
    return Future<Map<String, String>>.value(<String, String>{});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _ControlledApi implements AnalyticsApi {
  final Completer<Map<String, String>> first = Completer<Map<String, String>>();
  final List<List<AnalyticsEvent>> batches = <List<AnalyticsEvent>>[];

  @override
  Future<Map<String, String>> report(List<AnalyticsEvent> events) {
    batches.add(events);
    if (batches.length == 1) return first.future;
    return Future<Map<String, String>>.value(<String, String>{});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('★ 白名单外的事件根本不入队 —— 发一条后端不认的只是浪费往返', () {
    final t = Tracker(_FakeApi());
    t.track('nope_not_a_real_event');
    expect(t.pending, 0);
    t.dispose();
  });

  test('匿名态关闭采集，不制造必然被鉴权拒绝的后台请求', () async {
    final api = _FakeApi();
    final t = Tracker(api, enabled: false);
    t.track('community_post_impression', bizType: 'community_post', bizId: 42);
    await t.flush();
    expect(t.pending, 0);
    expect(api.attempts, 0);
    t.dispose();
  });

  test('攒够一整批就立刻发,不等定时器', () async {
    final api = _FakeApi();
    final t = Tracker(api, flushAfter: const Duration(hours: 1));
    for (int i = 0; i < AnalyticsApi.maxBatchSize; i++) {
      t.track('content_view', bizId: i);
    }
    await Future<void>.delayed(Duration.zero);
    expect(api.batches.length, 1);
    expect(api.batches.single.length, AnalyticsApi.maxBatchSize);
    expect(t.pending, 0);
    t.dispose();
  });

  test('★★ 队列满了丢**最旧**的 —— 丢新的会让「刚发生的事」永远上报不了', () async {
    // hang:第一次 flush 后 _sending 恒 true,之后 flush 全是空操作 ⇒
    // 队列只增不减,正好用来看丢弃策略。
    final api = _FakeApi(hang: true);
    final t = Tracker(api, flushAfter: const Duration(hours: 1));
    // ⚠️ 条数要**大于 maxQueue + flushAt**:第一次 flush 会先搬走一整批(50),
    //   只发 220 条的话队列最多到 170,压根碰不到上限 ——
    //   那样这条测试测的是「没溢出时不丢」,两种策略当然都绿。
    const int n = Tracker.maxQueue + Tracker.flushAt + 20;
    for (int i = 0; i < n; i++) {
      t.track('content_view', bizId: i);
    }
    await Future<void>.delayed(Duration.zero);
    expect(t.pending, lessThanOrEqualTo(Tracker.maxQueue));
    // ★★ 只查条数**分不出丢新还是丢旧** —— 那样的断言两种策略都绿。
    //   要查留下的是哪几条:最后一条必须还在,最早那条必须已经被挤掉。
    final List<int?> ids = t.pendingIds;
    expect(ids.last, n - 1, reason: '最新的一条必须在');
    expect(
      ids.contains(Tracker.flushAt),
      isFalse,
      reason: '溢出后最早留在队列里的那条应该被挤掉',
    );
    t.dispose();
  });

  test('★★ 上报失败不抛 —— 埋点不许影响调用方', () async {
    final api = _FakeApi(fail: true);
    final t = Tracker(api, flushAfter: const Duration(milliseconds: 1));
    t.track('content_view', bizId: 1);
    // flush 会失败;不该有异常逃出来。
    await t.flush();
    expect(t.pending, 1, reason: '失败的那批要放回去,下一轮再试');
    t.dispose();
  });

  test('失败后恢复:下一次 flush 能把攒下的发出去', () async {
    final api = _FakeApi(fail: true);
    final t = Tracker(api, flushAfter: const Duration(hours: 1));
    t.track('content_view', bizId: 1);
    await t.flush();
    expect(api.batches, isEmpty);
    api.fail = false;
    await t.flush();
    expect(api.batches.single.single.bizId, 1);
    expect(t.pending, 0);
    t.dispose();
  });

  test('单次失败后即使没有新事件也会自动重试', () async {
    final api = _FakeApi(fail: true);
    final t = Tracker(api, flushAfter: const Duration(milliseconds: 1));
    t.track('content_view', bizId: 1);
    await t.flush();
    api.fail = false;

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(api.batches.single.single.bizId, 1);
    expect(t.pending, 0);
    t.dispose();
  });

  test('慢请求期间新事件的 timer 触发后仍会在首批完成时续发', () async {
    final api = _ControlledApi();
    final t = Tracker(api, flushAfter: const Duration(milliseconds: 1));
    t.track('content_view', bizId: 1);
    final Future<void> firstFlush = t.flush();
    await Future<void>.delayed(Duration.zero);
    t.track('content_view', bizId: 2);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(api.batches, hasLength(1));

    api.first.complete(<String, String>{});
    await firstFlush;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(api.batches, hasLength(2));
    expect(api.batches.last.single.bizId, 2);
    t.dispose();
  });

  test('dispose 后在途失败不能重新挂重试 timer', () async {
    final api = _ControlledApi();
    final t = Tracker(api, flushAfter: const Duration(milliseconds: 1));
    t.track('content_view', bizId: 1);
    final Future<void> inFlight = t.flush();
    await Future<void>.delayed(Duration.zero);
    t.dispose();

    api.first.completeError(Exception('network'));
    await inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(api.batches, hasLength(1));
  });

  test('空队列 flush 是空操作,不发空请求', () async {
    final api = _FakeApi();
    final t = Tracker(api);
    await t.flush();
    expect(api.batches, isEmpty);
    t.dispose();
  });

  test('切换账号后丢弃旧 principal 的排队事件，不能归因到新账号', () async {
    String principal = 'member:1';
    final api = _FakeApi();
    final t = Tracker(
      api,
      flushAfter: const Duration(hours: 1),
      actorScope: () => principal,
    );
    t.track('content_view', bizId: 7);

    principal = 'member:2';
    await t.flush();

    expect(api.batches, isEmpty);
    expect(t.pending, 0);
    t.dispose();
  });

  test('每个逻辑事件在入队时获得稳定且彼此不同的幂等键', () async {
    final api = _FakeApi();
    final t = Tracker(api, flushAfter: const Duration(hours: 1));
    t.track('content_view', bizId: 1);
    t.track('content_view', bizId: 1);

    await t.flush();

    final keys = api.batches.single
        .map((AnalyticsEvent event) => event.idempotencyKey)
        .toList();
    expect(keys, everyElement(isNotNull));
    expect(keys.toSet(), hasLength(2));
    expect(
      api.batches.single.map((AnalyticsEvent event) => event.actorScope),
      everyElement('anonymous'),
    );
    t.dispose();
  });

  test('连续失败达到上限后丢弃该批，不能无限后台重试', () async {
    final api = _FakeApi(fail: true);
    final t = Tracker(api, flushAfter: const Duration(hours: 1));
    t.track('content_view', bizId: 1);

    for (int i = 0; i < Tracker.maxAutomaticRetryAttempts; i++) {
      await t.flush();
    }

    expect(api.attempts, Tracker.maxAutomaticRetryAttempts);
    expect(t.pending, 0);
    t.dispose();
  });
}
