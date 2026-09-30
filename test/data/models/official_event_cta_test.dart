import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/official_event.dart';

/// 官方活动底部按钮状态机的**全表**。
///
/// ★ 为什么要列成表:这个按钮有 10 条分支,靠看图永远看不全 —— 会漏的恰恰是
///   「暂停中的已报名用户」「V2 已报名但运营还没配任务」这种组合态。
///   把「状态 × 已报名 × 契约版本 × 任务」摊平成表,漏的分支一眼就露出来。
OfficialEvent ev({
  int status = 2,
  bool signed = false,
  bool paused = false,
  bool roamEnabled = false,
  int contractVersion = 1,
  List<OfficialMission> missions = const <OfficialMission>[],
}) {
  return OfficialEvent(
    id: 1,
    title: 't',
    status: status,
    signed: signed,
    paused: paused,
    roamEnabled: roamEnabled,
    contractVersion: contractVersion,
    missions: missions,
  );
}

void main() {
  group('CTA 全表', () {
    final cases = <String, (OfficialEvent, String, OfficialCtaType)>{
      '已结束(status=5)压过一切': (
        ev(status: 5, signed: true, paused: true),
        '活动已结束',
        OfficialCtaType.ended,
      ),
      '已结束(status=6)': (ev(status: 6), '活动已结束', OfficialCtaType.ended),
      '暂停压过已报名': (
        ev(status: 3, signed: true, paused: true, roamEnabled: true),
        '活动已暂停',
        OfficialCtaType.wait,
      ),
      '未报名·报名中': (ev(status: 2), '立即报名', OfficialCtaType.signup),
      '未报名·进行中仍可报': (ev(status: 3), '立即报名', OfficialCtaType.signup),
      '未报名·即将开始': (ev(status: 1), '报名即将开放', OfficialCtaType.wait),
      '未报名·结算中': (ev(status: 4), '暂不可报名', OfficialCtaType.wait),
      '已报名·即将开始': (
        ev(status: 1, signed: true),
        '已报名 · 待开始',
        OfficialCtaType.wait,
      ),
      '已报名·报名中': (ev(status: 2, signed: true), '已报名', OfficialCtaType.wait),
      '已报名·进行中·绑漫游': (
        ev(status: 3, signed: true, roamEnabled: true),
        '去点亮 · 点亮城市',
        OfficialCtaType.roam,
      ),
      '已报名·进行中·不绑漫游': (
        ev(status: 3, signed: true),
        '去探索 · 完成任务',
        OfficialCtaType.explore,
      ),
      'V2·进行中·有可验证到达': (
        ev(
          status: 3,
          signed: true,
          contractVersion: 2,
          missions: <OfficialMission>[
            const OfficialMission(
              missionCode: 'a',
              title: 'a',
              canVerifyArrival: true,
            ),
          ],
        ),
        '去漫游 · 验证到达',
        OfficialCtaType.roam,
      ),
      'V2·进行中·只有主题完成任务': (
        ev(
          status: 3,
          signed: true,
          contractVersion: 2,
          missions: <OfficialMission>[
            const OfficialMission(
              missionCode: 'a',
              title: 'a',
              missionType: 'THEME_VERIFIED_FINISH',
            ),
          ],
        ),
        '完成绑定主题后自动同步',
        OfficialCtaType.wait,
      ),
      'V2·进行中·运营没配任务': (
        ev(status: 3, signed: true, contractVersion: 2),
        '等待可验证任务',
        OfficialCtaType.wait,
      ),
    };

    cases.forEach((String name, (OfficialEvent, String, OfficialCtaType) c) {
      test(name, () {
        final cta = officialEventCta(c.$1);
        expect(cta.text, c.$2);
        expect(cta.type, c.$3);
      });
    });
  });

  test('wait / ended 一律不可点 —— 不让用户点出一个必然失败的动作', () {
    for (final OfficialEvent e in <OfficialEvent>[
      ev(status: 5),
      ev(status: 1),
      ev(status: 3, signed: true, paused: true),
      ev(status: 3, signed: true, contractVersion: 2),
    ]) {
      expect(
        officialEventCta(e).enabled,
        isFalse,
        reason: '${officialEventCta(e).text} 不该可点',
      );
    }
    for (final OfficialEvent e in <OfficialEvent>[
      ev(status: 2),
      ev(status: 3, signed: true, roamEnabled: true),
    ]) {
      expect(officialEventCta(e).enabled, isTrue);
    }
  });

  group('奖励标签', () {
    test('按 rewardJson 逐项展开', () {
      final e = OfficialEvent(
        id: 1,
        title: 't',
        rewardJson: '{"settleBadge":1,"settleXp":300,"collectiveCouponId":9}',
      );
      expect(officialEventRewards(e), <String>[
        '🏅 限定徽章',
        '✨ 300 成长值',
        '🎉 集体达标全员奖',
      ]);
    });

    test('后台填了非法 JSON 也不许整页挂,走兜底文案', () {
      const e = OfficialEvent(id: 1, title: 't', rewardJson: '{不是合法json');
      // ⚠️ 兜底**不是**「参与即有惊喜」那种默认承诺(小程序 F22:不摆默认承诺)。
      //    解析不出来 = 没配奖励,页面如实说没配。
      expect(officialEventRewards(e), isEmpty);
    });

    test('没配奖励就是空 —— 页面说「主办方尚未配置奖励」,不许替主办方许愿', () {
      expect(
        officialEventRewards(const OfficialEvent(id: 1, title: 't')),
        isEmpty,
      );
    });

    test('集体券是否可用:决定集体进度区敢不敢承诺发放', () {
      expect(
        officialEventHasCollectiveReward(
          const OfficialEvent(
            id: 1,
            title: 't',
            rewardJson: '{"collectiveCouponId":9}',
          ),
        ),
        isTrue,
      );
      // 0 / 负数 / 字符串 0 都不算"配了"。
      for (final String raw in <String>[
        '{"collectiveCouponId":0}',
        '{"collectiveCouponId":-1}',
        '{"collectiveCouponId":"0"}',
        '{"settleBadge":1}',
        '{}',
        '{不是合法json',
      ]) {
        expect(
          officialEventHasCollectiveReward(
            OfficialEvent(id: 1, title: 't', rewardJson: raw),
          ),
          isFalse,
          reason: raw,
        );
      }
    });
  });

  group('倒计时', () {
    final now = DateTime(2026, 8, 19, 12);
    test('即将开始 → 倒计到开始', () {
      final e = OfficialEvent(
        id: 1,
        title: 't',
        status: 1,
        activityStart: now.add(const Duration(hours: 50)),
      );
      expect(officialEventCountdown(e, now), '距开始 2 天');
    });
    test('进行中 → 倒计到结束', () {
      final e = OfficialEvent(
        id: 1,
        title: 't',
        status: 3,
        activityEnd: now.add(const Duration(hours: 3)),
      );
      expect(officialEventCountdown(e, now), '距结束 3 小时');
    });
    test('不足一分钟说 1 分钟,不说 0 分钟', () {
      final e = OfficialEvent(
        id: 1,
        title: 't',
        status: 3,
        activityEnd: now.add(const Duration(seconds: 20)),
      );
      expect(officialEventCountdown(e, now), '距结束 1 分钟');
    });
    test('已过期不显示负数', () {
      final e = OfficialEvent(
        id: 1,
        title: 't',
        status: 3,
        activityEnd: now.subtract(const Duration(hours: 1)),
      );
      expect(officialEventCountdown(e, now), '');
    });
    test('结算中/已结束不显示倒计时', () {
      final e = OfficialEvent(
        id: 1,
        title: 't',
        status: 4,
        activityEnd: now.add(const Duration(hours: 3)),
      );
      expect(officialEventCountdown(e, now), '');
    });
  });
}
