import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_timer_logic.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 计时/传感器族的**纯逻辑**门禁。
///
/// 判据全部来自小程序 `pages/play/components/playkit-{countdown,stopwatch,walk}`、
/// `game-timer`、`playkit-stickerbook` 的「纯算法出口」一节(逐条同源)。
/// 这些函数有对错:差一步就是另一个读数,而且它们**不会报错** ——
/// 油面退到哪儿、还剩几秒、容差是 ±0.30 还是 ±0.05,错了只会「看着怪」。

void main() {
  group('countdown', () {
    test('油面:0 = 满、1 = 空,总时长缺失时不退', () {
      expect(countdownOilFraction(0, 90), 0);
      expect(countdownOilFraction(45000, 90), 0.5);
      expect(countdownOilFraction(90000, 90), 1);
      // 走过头不越界(真源 Math.max(0, Math.min(100, ...)))
      expect(countdownOilFraction(200000, 90), 1);
      // 总时长缺失:不退 —— 画成 0 与画成 100 都会读错一行
      expect(countdownOilFraction(5000, 0), 0);
      expect(countdownOilFraction(5000, -3), 0);
    });

    test('剩余秒数向上取整:还剩 0.4 秒时显示 0 会让人以为已经到点', () {
      expect(countdownRemainSeconds(0, 90), 90);
      expect(countdownRemainSeconds(89600, 90), 1);
      expect(countdownRemainSeconds(90000, 90), 0);
      expect(countdownRemainSeconds(120000, 90), 0);
      expect(countdownRemainSeconds(1000, 0), 0);
    });
  });

  group('stopwatch', () {
    test('读数:秒两位小数 / mm:ss.xx', () {
      expect(stopwatchSecondsText(0), '0.00');
      expect(stopwatchSecondsText(1234), '1.23');
      // 负值当 0,不给 '-0.00'
      expect(stopwatchSecondsText(-5), '0.00');
      expect(stopwatchClockText(0), '00:00.00');
      expect(stopwatchClockText(65432), '01:05.43');
    });

    test('差值与三档措辞:优秀那一档不能比容差还宽', () {
      expect(stopwatchDiffSeconds(9800, 10), closeTo(0.2, 1e-9));
      expect(stopwatchDiffSeconds(10500, 10), closeTo(0.5, 1e-9));
      // 容差 0.30 → fine = min(0.05, 0.15) = 0.05
      expect(stopwatchTierLabel(0.04, 0.30), '优秀');
      expect(stopwatchTierLabel(0.05, 0.30), '优秀');
      expect(stopwatchTierLabel(0.06, 0.30), '达标');
      expect(stopwatchTierLabel(0.31, 0.30), '差一点');
      // 容差配得极小时「优秀」跟着收:0.04 → fine = 0.02
      expect(stopwatchTierLabel(0.03, 0.04), '达标');
    });

    test('停在哪儿了 / 超目标 30 秒作废', () {
      expect(
        stopwatchStopDetail(
          elapsedMs: 10000,
          targetSeconds: 10,
          toleranceSeconds: 0.3,
        ),
        '正好命中',
      );
      expect(
        stopwatchStopDetail(
          elapsedMs: 10200,
          targetSeconds: 10,
          toleranceSeconds: 0.3,
        ),
        '晚 0.20 秒',
      );
      expect(
        stopwatchStopDetail(
          elapsedMs: 9800,
          targetSeconds: 10,
          toleranceSeconds: 0.3,
        ),
        '早 0.20 秒',
      );
      expect(stopwatchAborted(39000, 10), isFalse);
      expect(stopwatchAborted(40001, 10), isTrue);
    });
  });

  group('walk', () {
    test('千分位 / 还差多少(不给负数)/ 百分比', () {
      expect(walkGroup(0), '0');
      expect(walkGroup(6000), '6,000');
      expect(walkGroup(1234567), '1,234,567');
      expect(walkRemain(1000, 6000), 5000);
      expect(walkRemain(9000, 6000), 0);
      expect(walkPercent(3000, 6000), 50);
      expect(walkPercent(9000, 6000), 100);
      // 目标为 0:给 0,不给 NaN 也不给 100
      expect(walkPercent(300, 0), 0);
    });

    test('少排碳两位小数 / 目标对齐到 500 步且下限一格', () {
      expect(walkCo2(1000), '0.08');
      expect(walkCo2(0), '0.00');
      expect(walkNormalizeGoal(6234), 6000);
      expect(walkNormalizeGoal(6260), 6500);
      // 下限一格:目标 0 步不是一个目标
      expect(walkNormalizeGoal(0), 500);
      expect(walkNormalizeGoal(-200), 500);
    });
  });

  group('gameTimer', () {
    test('MM:SS 向下取整、补零,负数当 0(与 formatElapsed 同源)', () {
      expect(formatPlayClock(0), '00:00');
      expect(formatPlayClock(9), '00:09');
      expect(formatPlayClock(90), '01:30');
      expect(formatPlayClock(3599), '59:59');
      expect(formatPlayClock(-5), '00:00');
    });

    test('环:总时长缺失时画满,不画成 0', () {
      expect(gameTimerRemainPercent(30, 60), 50);
      expect(gameTimerRemainPercent(0, 60), 0);
      expect(gameTimerRemainPercent(-3, 60), 0);
      expect(gameTimerRemainPercent(120, 60), 100);
      expect(gameTimerRemainPercent(30, 0), 100);
    });
  });

  group('stickerBook', () {
    test('网格:已收集在前、空槽在后,key 稳定,角度按 TILTS 循环', () {
      final List<PlayKitStickerCell> cells = buildStickerCells(
        const <PlayKitSticker>[
          PlayKitSticker(id: 7, label: '晨光'),
          PlayKitSticker(id: 8, label: '路灯', isNew: true),
        ],
        2,
      );
      expect(cells.map((cell) => cell.key).toList(), <String>[
        's-7',
        's-8',
        'lock-0',
        'lock-1',
      ]);
      expect(cells.map((cell) => cell.tilt).toList(), <int>[4, -3, 2, -5]);
      expect(cells[1].isNew, isTrue);
      expect(cells[2].locked, isTrue);
      // 空槽没有 id:未解锁的格子点了不该有任何反馈
      expect(cells[2].id, isNull);
      expect(cells[2].label, isEmpty);
    });

    test('没有 id 的已收集项也不崩,key 兜一个下标(不产生重复 key)', () {
      final List<PlayKitStickerCell> cells = buildStickerCells(
        const <PlayKitSticker>[
          PlayKitSticker(label: 'A'),
          PlayKitSticker(label: 'B'),
        ],
        0,
      );
      expect(cells.map((cell) => cell.key).toSet().length, 2);
      expect(cells.every((cell) => cell.id == null), isTrue);
    });
  });

  group('timeWindow', () {
    // 判据逐条照抄真源 `tests/unit/playkit-view-contract.test.js:155-159`
    // 与 `utils/playkit-view.js` 的 `minuteOfDay` / `secondsUntilOpen` / `formatClock`。
    test('开点前一小时 = 3600 秒', () {
      expect(
        playKitSecondsUntilOpen('23:00', DateTime(2026, 8, 26, 22, 0)),
        3600,
      );
    });

    test('今天的开点已过 ⇒ 等明天这个点,不是负数、也不是一整天', () {
      // 23:30 已过 23:00 ⇒ 差 23.5 小时(真源同一条断言)
      expect(
        playKitSecondsUntilOpen('23:00', DateTime(2026, 8, 26, 23, 30)),
        (23 * 60 + 30) * 60,
      );
    });

    test('格式不对给 0,不炸', () {
      final DateTime noon = DateTime(2026, 8, 26, 12, 0);
      expect(playKitSecondsUntilOpen('', noon), 0);
      expect(playKitSecondsUntilOpen('25:00', noon), 0);
      expect(playKitSecondsUntilOpen('9:00', noon), 0, reason: '必须补零的 HH:mm');
      expect(playKitSecondsUntilOpen('09:0a', noon), 0);
    });

    test('读数 HH:MM:SS,负数归零', () {
      expect(playKitClockText(3599), '00:59:59');
      expect(playKitClockText(3600), '01:00:00');
      expect(playKitClockText(0), '00:00:00');
      expect(playKitClockText(-5), '00:00:00', reason: '不显示 -1:59:59');
    });
  });

  test('本地 kind 与段名 kind 不互相顶替:walk 不是 steps', () {
    // walk 是本地 kind,服务端段名表里没有它;steps 才是 v5.1 半屏那套。
    // 这条是防「同名就以为换个 kit 能切」——真源注释原文如此。
    expect(kLocalPlayKitKinds, contains(PlayKitKind.walk));
    expect(
      kLocalPlayKitKinds.contains(PlayKitKind.steps),
      isFalse,
      reason: 'steps 是服务端段名那套,不是本地 kind',
    );
  });
}
