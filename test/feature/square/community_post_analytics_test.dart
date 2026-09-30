import 'package:chengyin_app/core/analytics/tracker.dart';
import 'package:chengyin_app/data/api/analytics_api.dart';
import 'package:chengyin_app/feature/square/community_post_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

class _FakeApi implements AnalyticsApi {
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];

  @override
  Future<Map<String, String>> report(List<AnalyticsEvent> batch) async {
    events.addAll(batch);
    return <String, String>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('广场曝光、打开、有效阅读与正向互动使用统一可聚合合同', () async {
    final _FakeApi api = _FakeApi();
    final Tracker tracker = Tracker(
      api,
      flushAfter: const Duration(hours: 1),
      actorScope: () => 'member:7',
    );

    CommunityPostAnalytics.impression(tracker, 42, feedMode: 'LATEST');
    CommunityPostAnalytics.opened(tracker, 42);
    CommunityPostAnalytics.qualified(tracker, 42, qualification: 'dwell_10s');
    CommunityPostAnalytics.liked(tracker, 42, enabled: false);
    CommunityPostAnalytics.liked(tracker, 42, enabled: true);
    CommunityPostAnalytics.favorited(tracker, 42, enabled: true);
    CommunityPostAnalytics.shared(tracker, 42);
    await tracker.flush();

    expect(
      api.events.map((AnalyticsEvent event) => event.eventName),
      <String>[
        'community_post_impression',
        'community_post_open',
        'community_post_qualified_view',
        'content_like',
        'content_favorite',
        'content_share',
      ],
      reason: '取消赞不应伪装成一次新的正向互动',
    );
    for (final AnalyticsEvent event in api.events) {
      expect(event.bizType, 'community_post');
      expect(event.bizId, 42);
      expect(event.idempotencyKey, isNotNull, reason: '至少一次投递下每条逻辑事件都必须可去重');
    }
    expect(api.events.first.pagePath, '/square');
    for (final AnalyticsEvent event in api.events.skip(1)) {
      expect(event.pagePath, '/square/:id');
    }
    expect(api.events[0].properties, <String, dynamic>{
      'stage': 'impression',
      'feed_mode': 'LATEST',
    });
    expect(api.events[1].properties, <String, dynamic>{'stage': 'open'});
    expect(api.events[2].properties, <String, dynamic>{
      'stage': 'qualified',
      'qualification': 'dwell_10s',
    });
    expect(
      api.events[2].idempotencyKey,
      'community-post-qualified-42',
      reason: 'actor_scope 已区分用户，稳定 post key 才能跨重开和跨日排除重复 user-post',
    );
    tracker.dispose();
  });

  test('同一用户重复达到有效阅读阈值仍使用同一 user-post 幂等键', () async {
    final _FakeApi api = _FakeApi();
    final Tracker tracker = Tracker(
      api,
      flushAfter: const Duration(hours: 1),
      actorScope: () => 'member:7',
    );

    CommunityPostAnalytics.qualified(tracker, 42, qualification: 'dwell_10s');
    CommunityPostAnalytics.qualified(tracker, 42, qualification: 'scroll_70');
    await tracker.flush();

    expect(
      api.events.map((AnalyticsEvent event) => event.idempotencyKey).toSet(),
      <String>{'community-post-qualified-42'},
    );
    tracker.dispose();
  });

  test('只有明确完成的系统分享才计入分享转化', () {
    expect(
      CommunityPostAnalytics.shouldCountShare(ShareResultStatus.success),
      isTrue,
    );
    expect(
      CommunityPostAnalytics.shouldCountShare(ShareResultStatus.dismissed),
      isFalse,
    );
    expect(
      CommunityPostAnalytics.shouldCountShare(ShareResultStatus.unavailable),
      isFalse,
    );
  });

  test('有效阅读的70%阈值只在用户滚过目标线后成立', () {
    expect(
      CommunityPostAnalytics.consumedAtLeast70Percent(
        pixels: 299,
        viewportDimension: 400,
        contentExtent: 1000,
      ),
      isFalse,
    );
    expect(
      CommunityPostAnalytics.consumedAtLeast70Percent(
        pixels: 300,
        viewportDimension: 400,
        contentExtent: 1000,
      ),
      isTrue,
    );
  });

  test('有效阅读停留不继承匿名、作者或另一个账号的累计时长', () {
    final CommunityPostQualifiedDwell dwell = CommunityPostQualifiedDwell();

    for (int i = 0; i < 9; i++) {
      expect(dwell.tick(viewerId: 7, authorId: 99), isFalse);
    }
    expect(dwell.tick(viewerId: null, authorId: 99), isFalse);
    expect(dwell.tick(viewerId: 99, authorId: 99), isFalse);
    for (int i = 0; i < 9; i++) {
      expect(dwell.tick(viewerId: 8, authorId: 99), isFalse);
    }
    expect(dwell.tick(viewerId: 8, authorId: 99), isTrue);
  });

  test('切换账号后不能继承上一账号已经滚到70%的页面位置', () {
    final CommunityPostQualifiedScroll scroll = CommunityPostQualifiedScroll();
    scroll.begin(viewerId: 7, authorId: 99, pixels: 0);
    expect(
      scroll.consumed(
        viewerId: 7,
        authorId: 99,
        pixels: 300,
        viewportDimension: 400,
        contentExtent: 1000,
      ),
      isTrue,
    );

    scroll.begin(viewerId: 8, authorId: 99, pixels: 300);
    expect(
      scroll.consumed(
        viewerId: 8,
        authorId: 99,
        pixels: 301,
        viewportDimension: 400,
        contentExtent: 1000,
      ),
      isFalse,
      reason: '新账号不能继承旧账号已达到的阅读深度',
    );
    expect(
      scroll.consumed(
        viewerId: 8,
        authorId: 99,
        pixels: 0,
        viewportDimension: 400,
        contentExtent: 1000,
      ),
      isFalse,
    );
    expect(
      scroll.consumed(
        viewerId: 8,
        authorId: 99,
        pixels: 300,
        viewportDimension: 400,
        contentExtent: 1000,
      ),
      isTrue,
    );
  });

  test('同一页面每个合格账号都能独立上报一次', () {
    final CommunityPostQualifiedMembers members =
        CommunityPostQualifiedMembers();

    expect(members.mark(viewerId: 7, authorId: 99), isTrue);
    expect(members.mark(viewerId: 7, authorId: 99), isFalse);
    expect(members.mark(viewerId: null, authorId: 99), isFalse);
    expect(members.mark(viewerId: 99, authorId: 99), isFalse);
    expect(members.mark(viewerId: 8, authorId: 99), isTrue);
  });

  test('同一页面换号后每个登录账号都有独立打开事件资格', () {
    final CommunityPostOpenedMembers members = CommunityPostOpenedMembers();

    expect(members.mark(null), isFalse);
    expect(members.mark(7), isTrue);
    expect(members.mark(7), isFalse);
    expect(members.mark(8), isTrue);
  });
}
