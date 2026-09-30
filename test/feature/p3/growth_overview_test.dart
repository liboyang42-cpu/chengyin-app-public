import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/feature/p3/growth/growth_overview.dart';

void main() {
  group('★ 没拿到 ≠ 值是 0(三个源各自独立降级)', () {
    test('三源全 null → 四项统计全 "—",等级显示兜底文案', () {
      final o = buildGrowthOverview();
      expect(o.levelText, '成长概览');
      for (final s in o.stats) {
        expect(s.value, isNull, reason: '${s.label} 没拿到时不能显示 0');
      }
    });

    test('center 拿到且 expValue=0 → 显示真实 "0",不是 "—"', () {
      final center = GrowthCenter(
        levelNo: 1,
        expValue: 0,
        points: 0,
        badges: <MedalBadge>[],
        missions: <GrowthMission>[],
      );
      final o = buildGrowthOverview(center: center);
      final exp = o.stats.firstWhere((s) => s.key == 'exp');
      expect(exp.value, '0', reason: '0 是真实的探索值,不能伪装成没拿到');
      final badge = o.stats.firstWhere((s) => s.key == 'badge');
      expect(badge.value, '0');
    });

    test('play 拿到且里程 0 → 显示 "0";play 没拿到 → "—"', () {
      final withZero = buildGrowthOverview(
        play: const PlayGrowth(
          level: 1,
          totalCheckins: 0,
          totalMileage: 0,
          streakDays: 0,
        ),
      );
      final distance =
          withZero.stats.firstWhere((s) => s.key == 'distance');
      expect(distance.value, '0');

      final without =
          buildGrowthOverview().stats.firstWhere((s) => s.key == 'distance');
      expect(without.value, isNull);
    });

    test('completed 空列表 → 主题数 "0";completed 没拿到 → "—"', () {
      final withEmpty = buildGrowthOverview(completed: <CompletedActivity>[]);
      expect(
        withEmpty.stats.firstWhere((s) => s.key == 'topic').value,
        '0',
      );
      final without =
          buildGrowthOverview().stats.firstWhere((s) => s.key == 'topic');
      expect(without.value, isNull);
    });

    test('等级 0 或负数 → 显示 Lv.1 不下探', () {
      final center = GrowthCenter(
        levelNo: 0,
        expValue: 1,
        points: 0,
        badges: <MedalBadge>[],
        missions: <GrowthMission>[],
      );
      expect(buildGrowthOverview(center: center).levelText, 'Lv.1');
    });
  });

  group('formatInteger 千分位', () {
    test('12345 → 12,345', () => expect(formatInteger(12345), '12,345'));
    test('999 不加逗号', () => expect(formatInteger(999), '999'));
    test('1000000 → 1,000,000', () {
      expect(formatInteger(1000000), '1,000,000');
    });
    test('0 → 0', () => expect(formatInteger(0), '0'));
    test('null / 垃圾 → null 不显示假数字', () {
      expect(formatInteger(null), isNull);
      expect(formatInteger('abc'), isNull);
      expect(formatInteger(double.nan), isNull);
    });
  });

  group('formatMileage 一位小数', () {
    test('3 → 3', () => expect(formatMileage(3), '3'));
    test('3.45 → 3.5', () => expect(formatMileage(3.45), '3.5'));
    test('3.04 → 3', () => expect(formatMileage(3.04), '3'));
    test('null → null', () => expect(formatMileage(null), isNull));
  });

  group('completedTopicCount 去重', () {
    test('同一 topic 多活动 → 只算 1 个主题', () {
      final list = <CompletedActivity>[
        CompletedActivity(
          activityId: 1,
          topicId: 5,
          name: 'a',
          cover: '',
          total: 3,
          doneCount: 3,
        ),
        CompletedActivity(
          activityId: 2,
          topicId: 5,
          name: 'b',
          cover: '',
          total: 3,
          doneCount: 3,
        ),
        CompletedActivity(
          activityId: 3,
          topicId: 7,
          name: 'c',
          cover: '',
          total: 3,
          doneCount: 3,
        ),
      ];
      expect(completedTopicCount(list), 2);
    });
    test('null → null(没接到接口 ≠ 0 个主题)', () {
      expect(completedTopicCount(null), isNull);
    });
  });

  group('unlockMomentText 中国时间串', () {
    test('yyyy-MM-dd HH:mm:ss → 中文时刻', () {
      expect(unlockMomentText('2026-07-12 10:30:00'), '2026年7月12日 10:30');
    });
    test('T 分隔也认', () {
      expect(unlockMomentText('2026-07-12T10:30:00'), '2026年7月12日 10:30');
    });
    test('带毫秒后缀也认', () {
      expect(
        unlockMomentText('2026-07-12 10:30:00.123'),
        '2026年7月12日 10:30',
      );
    });
    test('非法日期/时间 → null 不编造', () {
      expect(unlockMomentText('2026-13-40 99:99:99'), isNull);
      expect(unlockMomentText('garbage'), isNull);
    });
    test('null → null(拿不到就整块不展示)', () {
      expect(unlockMomentText(null), isNull);
    });
  });

  group('badgeDisplayName / nameInitial', () {
    test('三级兜底:名称 → 码 → 徽章', () {
      MedalBadge b(String name, String? code) =>
          MedalBadge(badgeName: name, iconUrl: '', badgeCode: code);
      expect(badgeDisplayName(b('城市徽章', 'CITY')), '城市徽章');
      expect(badgeDisplayName(b('', 'FIRST_STEP')), 'FIRST_STEP');
      expect(badgeDisplayName(b('', null)), '徽章');
    });
    test('首字符:空名 → ?', () {
      expect(nameInitial('阿兰'), '阿');
      expect(nameInitial('  '), '?');
      expect(nameInitial(null), '?');
    });
  });
}
