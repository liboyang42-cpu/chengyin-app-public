import 'package:chengyin_app/feature/roam/roam_hangout_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 附近的局那批纯函数的契约测试。
///
/// ★ 期望值不是「我觉得合理」,是从小程序真源逐条读出来的:
///   `github/master:chengyinhub-xcx/utils/roam-hangout.js` 与
///   `utils/roam-hangout-marker.js`(`fmtKm` / `whenParts` /
///   `emptyStateCopy` / `validateHangoutForm`)。
///   两端文案必须一模一样 —— 差一个字就会在对照台上被当成"App 自己编的"。
void main() {
  group('距离口语化 fmtKm', () {
    test('1000 以下取整到米', () {
      expect(roamFmtKm(0), '0m');
      expect(roamFmtKm(299.6), '300m');
      expect(roamFmtKm(999), '999m');
    });

    test('1000–9999 一位小数,10000 以上取整', () {
      expect(roamFmtKm(1000), '1.0km');
      expect(roamFmtKm(3500), '3.5km');
      expect(roamFmtKm(10000), '10km');
      expect(roamFmtKm(23400), '23km');
    });

    test('没有坐标给空串,不是 0m —— 空值不能当零', () {
      expect(roamFmtKm(null), '');
      expect(roamFmtKm(''), '');
      expect(roamFmtKm('abc'), '');
      expect(roamFmtKm(double.nan), '');
    });

    test('字符串数字也认(后端有的字段是 String)', () {
      expect(roamFmtKm('350'), '350m');
      expect(roamFmtKm('3000'), '3.0km');
    });
  });

  group('卡片三格的距离拆数', () {
    test('null 给空数字 + m,而不是 0', () {
      expect(roamSplitDist(null), (num: '', unit: 'm'));
    });

    test('米与千米的拆分', () {
      expect(roamSplitDist(350), (num: '350', unit: 'm'));
      expect(roamSplitDist(999.4), (num: '999', unit: 'm'));
      expect(roamSplitDist(1000), (num: '1.0', unit: 'km'));
      expect(roamSplitDist(10000), (num: '10', unit: 'km'));
    });
  });

  group('时间口语化 whenParts', () {
    // 2026-09-15 是周二,注入 now 让「今晚/明天/周六」可复现。
    final DateTime now = DateTime(2026, 9, 15, 12);

    test('当天 17:00 以后叫「今晚」,并用 12 小时制', () {
      expect(roamWhenParts('2026-09-15 20:00', now: now).label, '今晚');
      expect(roamWhenParts('2026-09-15 20:00', now: now).short, '今晚 8:00');
      expect(roamWhenParts('2026-09-15 17:00', now: now).label, '今晚');
    });

    test('当天 17:00 以前叫「今天」,保留 24 小时制', () {
      expect(roamWhenParts('2026-09-15 09:30', now: now).label, '今天');
      expect(roamWhenParts('2026-09-15 09:30', now: now).short, '今天 09:30');
    });

    test('次日「明天」;一周内报星期;更远报月/日', () {
      expect(roamWhenParts('2026-09-16 07:30', now: now).short, '明天 07:30');
      expect(roamWhenParts('2026-09-19 20:00', now: now).short, '周六 20:00');
      expect(roamWhenParts('2026-09-25 20:00', now: now).short, '9/25 20:00');
    });

    test('只有日期没有时分:hm 为空,short 只剩 label', () {
      expect(roamWhenParts('2026-09-15', now: now).short, '今天');
      expect(roamWhenParts('2026-09-15', now: now).hm, '');
      // 明确的零点仍然是「有时分」,不能被当成纯日期吞掉
      expect(roamWhenParts('2026-09-15T00:00', now: now).short, '今天 00:00');
    });

    test('解析不了的时间给三个空串,不猜', () {
      expect(roamWhenParts(null).short, '');
      expect(roamWhenParts('常驻').short, '');
    });
  });

  group('空态文案', () {
    test('后端给了拉远建议 → 主键是「看远一点」', () {
      final ({String title, String sub, String primary, bool expand}) copy =
          roamEmptyStateCopy(
            radiusM: 3000,
            suggestedRadius: 20000,
            suggestedCount: 7,
          );
      expect(copy.title, '还没有局');
      expect(copy.sub, '雾再远一点,20km 内有 7 个局在约。');
      expect(copy.primary, '看远一点');
      expect(copy.expand, isTrue);
    });

    test('没有建议 → 引导开局', () {
      final ({String title, String sub, String primary, bool expand}) copy =
          roamEmptyStateCopy(radiusM: 3000);
      expect(copy.title, '还没有局');
      expect(copy.sub, '开一个,让附近的人找到你。');
      expect(copy.primary, '在这里开一局');
      expect(copy.expand, isFalse);
    });
  });

  group('建局表单校验(与后端同一套闸)', () {
    test('标题 2–30 字', () {
      expect(
        validateRoamHangoutForm(title: '', description: '', lat: 1, lng: 1),
        '标题 2–30 字',
      );
      expect(
        validateRoamHangoutForm(title: '一', description: '', lat: 1, lng: 1),
        '标题 2–30 字',
      );
      expect(
        validateRoamHangoutForm(
          title: 'a' * 31,
          description: '',
          lat: 1,
          lng: 1,
        ),
        '标题 2–30 字',
      );
      expect(
        validateRoamHangoutForm(
          title: ' 打 UNO 找搭子 ',
          description: '',
          lat: 1,
          lng: 1,
        ),
        isNull,
      );
    });

    test('说明最多 120 字', () {
      expect(
        validateRoamHangoutForm(
          title: '打 UNO',
          description: '字' * 121,
          lat: 1,
          lng: 1,
        ),
        '说明最多 120 字',
      );
      expect(
        validateRoamHangoutForm(
          title: '打 UNO',
          description: '字' * 120,
          lat: 1,
          lng: 1,
        ),
        isNull,
      );
    });

    test('地点必选 —— 没有坐标不给开局', () {
      expect(
        validateRoamHangoutForm(title: '打 UNO', description: '', lat: null, lng: 1),
        '请选择地点',
      );
      expect(
        validateRoamHangoutForm(title: '打 UNO', description: '', lat: 1, lng: null),
        '请选择地点',
      );
    });
  });

  group('在走时长', () {
    test('一小时内是 分:秒,过一小时才补小时位', () {
      expect(roamElapsedLabel(0), '00:00');
      expect(roamElapsedLabel(38 * 60 + 20), '38:20');
      expect(roamElapsedLabel(3600), '1:00:00');
      expect(roamElapsedLabel(3600 + 12 * 60 + 4), '1:12:04');
    });

    test('负数按 0 算,不出现负号', () {
      expect(roamElapsedLabel(-5), '00:00');
    });

    test('since 那三句按真时长分档', () {
      expect(roamSinceLabel(0), '刚出发');
      expect(roamSinceLabel(599), '刚出发');
      expect(roamSinceLabel(600), '走了半小时上下');
      expect(roamSinceLabel(3599), '走了半小时上下');
      expect(roamSinceLabel(3600), '走了一个多小时');
    });
  });

  group('每人一个环色', () {
    test('同一个人恒同色,不同人不同色', () {
      expect(roamRunnerColor(7), roamRunnerColor(7));
      expect(roamRunnerColor(7), isNot(roamRunnerColor(8)));
      expect(kRoamRunnerColors.contains(roamRunnerColor(7)), isTrue);
    });

    test('负数 memberId 不会越界', () {
      expect(kRoamRunnerColors.contains(roamRunnerColor(-3)), isTrue);
      expect(kRoamRunnerColors.contains(roamRunnerColor(0)), isTrue);
    });
  });
}
