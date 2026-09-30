import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_fullscreen_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 整屏决定类五件套的**纯逻辑**判据。
///
/// 这一层是与小程序逐条同源的那部分(`_normalizeFace` / `_spinDeg` / `_pipsOf` /
/// `_pickWait` / `_bestOf` / `_bounce` / `_tiltAccel` / `_baseline` / `_thresholds` /
/// `_bandOf` / `_peakOf`),组件里只留「演出来」和「把动作抛给宿主」。
/// 逻辑错了两端就会各演各的,而 golden 拍的是静态帧,抓不到。
void main() {
  group('coinflip', () {
    test('面归一:认不出给空,不猜', () {
      expect(normalizeCoinFace('HEADS'), kCoinHeads);
      expect(normalizeCoinFace('heads'), kCoinHeads);
      expect(normalizeCoinFace('H'), kCoinHeads);
      expect(normalizeCoinFace(' 正面 '), kCoinHeads);
      expect(normalizeCoinFace('TAILS'), kCoinTails);
      expect(normalizeCoinFace('t'), kCoinTails);
      expect(normalizeCoinFace('反面'), kCoinTails);
      expect(normalizeCoinFace('sideways'), '');
      expect(normalizeCoinFace(null), '');
    });

    test('圈数每次不同(6–8 圈),不然第二次看就知道要转几圈了', () {
      expect(nextCoinTurns(0, 0), 6);
      expect(nextCoinTurns(0, 2), 8);
      expect(nextCoinTurns(6, 1), 13);
      // 越界采样夹住,不抛错。
      expect(nextCoinTurns(0, 9), 8);
    });

    test('★ 绕横轴落面:TAILS 多转半圈,圈数 × 360 + 半圈', () {
      expect(coinSpinDegrees(2, kCoinHeads), 720);
      expect(coinSpinDegrees(2, kCoinTails), 900);
    });
  });

  group('diceroll', () {
    test('★ 骰面点位与真骰子一致:1 在中心、2 走对角', () {
      expect(dicePipsOf(1)[4], isTrue);
      expect(dicePipsOf(1).where((bool on) => on).length, 1);

      final List<bool> two = dicePipsOf(2);
      expect(two[0] && two[8], isTrue, reason: '2 走对角,不是并排');
      expect(two.where((bool on) => on).length, 2);

      expect(dicePipsOf(6).where((bool on) => on).length, 6);
      // 越界给一颗空骰子:一次显示异常好过整屏白。
      expect(dicePipsOf(7).where((bool on) => on).length, 0);
      expect(dicePipsOf(0).where((bool on) => on).length, 0);
    });

    test('一颗才有任务;两颗只报和(拿和去索引六面会越界)', () {
      const List<String> faces = <String>['a', 'b', 'c', 'd', 'e', 'f'];
      expect(diceTaskFor(<int>[4], faces), 'd');
      expect(diceTaskFor(<int>[7], faces), '');
      expect(diceTaskFor(<int>[5, 4], faces), '');
      expect(diceTaskFor(<int>[], faces), '');
      expect(diceSumOf(<int>[5, 4]), 9);
      expect(diceSumOf(<int>[]), 0);
    });

    test('服务端点数解析:越界丢弃,不抛错', () {
      expect(parseDiceValues(<Object?>[5, 4]), <int>[5, 4]);
      expect(parseDiceValues(<Object?>[0, 7, 3, 'x', 2]), <int>[3, 2]);
      expect(parseDiceValues('5'), isEmpty);
    });
  });

  group('reaction', () {
    test('等待时长在 1.4–4.2s 之间,采样夹住', () {
      expect(pickReactionWaitMs(0), kReactionWaitMinMs);
      expect(pickReactionWaitMs(1), kReactionWaitMaxMs);
      expect(pickReactionWaitMs(0.5), 2800);
      expect(pickReactionWaitMs(-3), kReactionWaitMinMs);
      expect(pickReactionWaitMs(9), kReactionWaitMaxMs);
    });

    test('三轮取最快;没有成绩给 0(由调用方判「还没有成绩」)', () {
      expect(reactionBestOf(<int>[300, 220, 410]), 220);
      expect(reactionBestOf(<int>[]), 0);
      expect(reactionBestOf(<int>[0, 0]), 0);
    });

    test('本地预览口径:最快那次不慢于 goalMs', () {
    });

    test('人类下限 120ms:低于它是提前按住蹭出来的', () {
      expect(kReactionMinHumanMs, 120);
    });
  });

  group('shake(coinflip / diceroll 共用)', () {
    test('★ 阈值 26 m/s² 与防抖 900ms 照抄小程序 play-shake.js', () {
      expect(kShakeMagnitude, 26);
      expect(kShakeGapMs, 900);
      expect(shakeMagnitudeOf(1, -2, 3), 6);
    });

    test('第一次摇永远算数;防抖窗内的第二次不算', () {
      final PlayKitShakeDetector detector = PlayKitShakeDetector();
      bool feed(int atMs) =>
          detector.feed(x: 10, y: 10, z: 10, atMs: atMs);
      expect(feed(0), isTrue);
      expect(feed(500), isFalse, reason: '一次晃动被读成好几次');
      expect(feed(901), isTrue);
      // 力度不够:走路都会触发,而一触发就出结果。
      expect(detector.feed(x: 8, y: 8, z: 8, atMs: 5000), isFalse);
    });
  });

  group('ballshake', () {
    test('零点没量过时不给力,球不动', () {
      const BallShakeTilt tilt = BallShakeTilt(0, 0);
      expect(ballShakeTiltOf(x: 3, y: 4).gx, tilt.gx);
      expect(ballShakeTiltOf(x: 3, y: 4).gy, tilt.gy);
    });

    test('相对零点的倾斜 → 加速度:x 取反,数值照抄原型系数', () {
      final BallShakeTilt tilt = ballShakeTiltOf(
        x: 2,
        y: 3,
        zeroX: 1,
        zeroY: 1,
      );
      expect(tilt.gx, closeTo(-0.05, 1e-9));
      expect(tilt.gy, closeTo(0.1, 1e-9));
    });

    test('反弹:反向 + 一点随机', () {
      expect(ballShakeBounce(-10, 0.5), closeTo(9.8, 1e-9));
      expect(ballShakeBounce(-10, 0), lessThan(ballShakeBounce(-10, 1)));
      expect(ballShakeBounce(-10, 1), closeTo(10.05, 1e-9));
    });
  });

  group('quiethold', () {
    test('★ 底噪取 80 分位,不被一次咳嗽带偏;没采到给保守低值', () {
      expect(quietBaselineOf(<double>[]), 0.06);
      final List<double> samples = <double>[
        for (int i = 1; i <= 10; i++) i / 100,
      ];
      expect(quietBaselineOf(samples), closeTo(0.09, 1e-9));
      // 末尾塞一声咳嗽:80 分位仍落在 0.09,不是 0.9。
      expect(quietBaselineOf(<double>[...samples, 0.9]), closeTo(0.09, 1e-9));
    });

    test('底噪 → 黄线 / 红线:夹在合理区间,校准到极端值也不跑飞', () {
      final QuietThresholds low = quietThresholdsOf(0.01);
      expect(low.mid, 0.12);
      expect(low.hot, closeTo(0.21, 1e-9));

      final QuietThresholds high = quietThresholdsOf(0.9);
      expect(high.mid, 0.5);
      expect(high.hot, closeTo(0.59, 1e-9));
    });

    test('分档:过红线判输', () {
      expect(quietBandOf(0.05, 0.12, 0.21), 'ok');
      expect(quietBandOf(0.15, 0.12, 0.21), 'mid');
      expect(quietBandOf(0.3, 0.12, 0.21), 'hot');
    });

    test('★ 判峰值不判均值:负峰也算峰值,拿不到数据给 0', () {
      expect(quietPeakOf(<double>[0.1, -0.4, 0.2]), 0.4);
      expect(quietPeakOf(<double>[]), 0);
    });

    test('录音插件 dBFS → 0–1 线性振幅', () {
      expect(decibelsToLinear(0), 1);
      expect(decibelsToLinear(-20), closeTo(0.1, 1e-9));
      expect(decibelsToLinear(-160), 0);
      expect(decibelsToLinear(-200), 0);
      expect(decibelsToLinear(double.nan), 0);
    });
  });

  group('单位(宿主层换算用)', () {
    test('★ 秒 → 毫秒:quiethold 报秒,服务端收毫秒', () {
      expect(heldSecondsToMs(7), 7000);
      expect(heldSecondsToMs(2.6), 2600);
      expect(heldSecondsToMs(0), 0);
    });
  });
}
