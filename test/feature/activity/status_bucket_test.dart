// 活动状态表与三档筛选 —— 逐条对齐小程序 `utils/activity-status.js:11-18`
// 与 `pages/activity/list/index.js:205-207`。
//
// ★ 为什么值得单独测:这张表在**三处**共用 —— 列表筛选、状态文案、空态文案。
//   小程序把它抽成 utils 就是因为散开写必漂移;移植过来同样要锁住。
//
// ★ 判据逐条来自源码,不是概括:
//   live = status 2(报名中)/ 3(进行中);其余全 false ——
//   注意 **4 结算中不算 live**,这条最容易凭直觉写错。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/activity_status.dart';

void main() {
  group('状态文案(公开视角)', () {
    test('逐条对齐小程序 STATUS 表', () {
      expect(activityStatusMeta(1).text, '即将开始');
      expect(activityStatusMeta(2).text, '报名中');
      expect(activityStatusMeta(3).text, '进行中');
      expect(activityStatusMeta(4).text, '结算中');
      expect(activityStatusMeta(5).text, '已结束');
      expect(activityStatusMeta(6).text, '已结束');
      expect(activityStatusMeta(9).text, '已下线');
    });

    test('status=1 取公开视角「即将开始」,不是发布者视角的「待发布」', () {
      // 小程序注释明确写了这处真实文案差异;App 只做玩家侧。
      expect(activityStatusMeta(1).text, isNot('待发布'));
    });

    test('未知状态兜底为空文案且非 live,不崩', () {
      expect(activityStatusMeta(null).text, '');
      expect(activityStatusMeta(999).live, isFalse);
    });
  });

  group('三档筛选', () {
    test('进行中 = 报名中 + 进行中,★ 结算中不算', () {
      expect(activityInBucket(2, ActivityBucket.live), isTrue);
      expect(activityInBucket(3, ActivityBucket.live), isTrue);
      expect(activityInBucket(4, ActivityBucket.live), isFalse,
          reason: '4 结算中在小程序表里 live:false —— 凭直觉最容易写成 true');
      expect(activityInBucket(1, ActivityBucket.live), isFalse);
    });

    test('即将 = status == 1', () {
      expect(activityInBucket(1, ActivityBucket.upcoming), isTrue);
      expect(activityInBucket(2, ActivityBucket.upcoming), isFalse);
    });

    test('已结束 = status >= 5(含 6 与 9)', () {
      expect(activityInBucket(5, ActivityBucket.ended), isTrue);
      expect(activityInBucket(6, ActivityBucket.ended), isTrue);
      expect(activityInBucket(9, ActivityBucket.ended), isTrue);
      expect(activityInBucket(4, ActivityBucket.ended), isFalse);
    });

    test('三档互斥:同一状态不会落进两档', () {
      for (final int s in <int>[1, 2, 3, 4, 5, 6, 9]) {
        final int n = ActivityBucket.values
            .where((ActivityBucket b) => activityInBucket(s, b))
            .length;
        expect(n, lessThanOrEqualTo(1), reason: 'status=$s 落进了 $n 档');
      }
    });
  });

  group('搜索匹配(小程序 index.js:210-214)', () {
    test('标题 / 副标 / 城市三个字段都参与匹配', () {
      expect(
        activityMatchesKeyword(keyword: '静安', title: '静安探店日'),
        isTrue,
      );
      expect(
        activityMatchesKeyword(keyword: '梧桐', title: 'x', subtitle: '梧桐树荫'),
        isTrue,
      );
      expect(
        activityMatchesKeyword(keyword: '上海', title: 'x', city: '上海'),
        isTrue,
      );
      expect(activityMatchesKeyword(keyword: '不存在', title: 'x'), isFalse);
    });

    test('大小写不敏感', () {
      expect(activityMatchesKeyword(keyword: 'CITY', title: 'city walk'), isTrue);
    });

    test('空关键词一律放行(不是一律拦截)', () {
      expect(activityMatchesKeyword(keyword: '   ', title: 'x'), isTrue);
    });
  });

  group('计数行(小程序 index.js:219/224)', () {
    test('无关键词:档名 · 共 N 个活动', () {
      expect(
        activitySummary(keyword: '', bucketLabel: '进行中', count: 3),
        '进行中 · 共 3 个活动',
      );
    });

    test('有关键词:「kw」N 个结果', () {
      expect(
        activitySummary(keyword: ' 静安 ', bucketLabel: '进行中', count: 2),
        '「静安」2 个结果',
      );
    });
  });

  group('空态文案(小程序 EMPTY_COPY)', () {
    test('三档各有各的文案,不共用一句', () {
      expect(activityEmptyCopy(ActivityBucket.live).title, '暂无进行中的活动');
      expect(activityEmptyCopy(ActivityBucket.upcoming).title, '暂无即将开始的活动');
      expect(activityEmptyCopy(ActivityBucket.ended).title, '暂无已结束的活动');
      // 已结束那档副标不同 —— 小程序特意写的「往期活动归档后会出现在这里」
      expect(activityEmptyCopy(ActivityBucket.ended).sub, '往期活动归档后会出现在这里');
      expect(
        activityEmptyCopy(ActivityBucket.live).sub,
        isNot(activityEmptyCopy(ActivityBucket.ended).sub),
      );
    });

    test('「我的」档单独一句', () {
      expect(activityEmptyCopy(ActivityBucket.live, mine: true).title, '还没有参与的活动');
    });
  });

  // 2026-09-18(F1):活动目录页 `/activities` 的三档**不能**再用 status 判 ——
  // 生产 `/api/activity/list` 的响应里没有 status 键(实测 8/8 行缺),
  // 照 status 判 ⇒ 三档恒空。改用真实下发的 startDate/endDate 推。
  group('活动目录三档按时间推(F1 修复)', () {
    final DateTime now = DateTime(2026, 9, 18, 12);

    bool hit(String? start, String? end, ActivityBucket b) =>
        activityInTimeBucket(
            startDate: start, endDate: end, bucket: b, now: now);

    test('进行中 = 已开始且未结束', () {
      expect(
          hit('2026-09-01 10:00:00', '2026-10-01 20:00:00', ActivityBucket.live),
          isTrue);
      // 边界:正好落在开始/结束那一刻,算进行中(闭区间)
      expect(
          hit('2026-09-18 12:00:00', '2026-09-18 12:00:00', ActivityBucket.live),
          isTrue);
    });

    test('即将 = 还没开始(只有开始时间也算)', () {
      expect(
          hit('2026-09-19 09:00:00', '2026-10-08 20:00:00',
              ActivityBucket.upcoming),
          isTrue);
      expect(hit('2026-09-18 12:00:00', null, ActivityBucket.upcoming), isFalse);
    });

    test('已结束 = 过了结束时间', () {
      expect(
          hit('2026-08-01 09:00:00', '2026-09-17 20:00:00',
              ActivityBucket.ended),
          isTrue);
      expect(hit('2026-08-01 09:00:00', null, ActivityBucket.ended), isFalse);
    });

    test('缺 endDate 的已开始活动算进行中(不判成已结束)', () {
      expect(hit('2026-08-24 14:00:00', null, ActivityBucket.live), isTrue);
    });

    test('两个时间都缺 → 三档都不进(没有依据就不猜)', () {
      for (final ActivityBucket b in ActivityBucket.values) {
        expect(hit(null, null, b), isFalse, reason: '$b');
      }
      expect(hit('', '  ', ActivityBucket.live), isFalse);
    });

    test('同一行按时间只落一档', () {
      const String start = '2026-09-01 10:00:00';
      const String end = '2026-10-01 20:00:00';
      final int n = ActivityBucket.values
          .where((ActivityBucket b) => hit(start, end, b))
          .length;
      expect(n, 1);
    });

    test('日期解析:后端 "yyyy-MM-dd HH:mm:ss" 能解析,垃圾值当缺', () {
      expect(parseActivityDate('2026-08-27 13:00:00'), DateTime(2026, 8, 27, 13));
      expect(parseActivityDate(''), isNull);
      expect(parseActivityDate('昨天'), isNull);
    });
  });

  // 上面那组只证判据函数;这条从**生产响应的原样字段**走一遍
  // Activity.fromJson(含 endDate 解析)→ 分档,把「模型没解析出日期」这种
  // 断链也罩住。字段值照抄 2026-09-18 生产 /api/activity/list 实测(游客口径,
  // 总 8 行里的 2 行);now 固定,日期不再随日历漂。
  group('生产响应实证:原样字段 → 模型 → 分档', () {
    final DateTime now = DateTime(2026, 9, 18, 11, 30);

    Activity row(int id, String start, String end) => Activity.fromJson(
        <String, dynamic>{'id': id, 'name': 'x', 'startDate': start, 'endDate': end});

    bool inBucket(Activity a, ActivityBucket b) => activityInTimeBucket(
        startDate: a.startDate, endDate: a.endDate, bucket: b, now: now);

    test('startDate/endDate 原样进模型,不被吞', () {
      final Activity a = row(9, '2026-08-27 13:00:00', '2026-10-07 20:00:00');
      expect(a.startDate, '2026-08-27 13:00:00');
      expect(a.endDate, '2026-10-07 20:00:00');
    });

    test('窗口盖住今天的那行落「进行中」(id=9)', () {
      expect(
          inBucket(
              row(9, '2026-08-27 13:00:00', '2026-10-07 20:00:00'),
              ActivityBucket.live),
          isTrue);
    });

    test('还没开始的那行落「即将」(id=13)', () {
      expect(
          inBucket(
              row(13, '2026-09-19 09:00:00', '2026-10-08 20:00:00'),
              ActivityBucket.upcoming),
          isTrue);
    });
  });
}
