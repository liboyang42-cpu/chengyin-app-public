import 'package:chengyin_app/feature/roam/city_stamp_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 城市贴纸那些纯函数的契约测试。
///
/// ★ 条码不是「随机装饰」:同一个签号在两端必须画出同一张条形。
///   下面的期望值是用**小程序的 `barcodeOf` 原件**(`node -e`)跑出来的,
///   不是这边照着实现反抄的 —— 反抄等于自己给自己出题。
void main() {
  group('条形码 = 签号的样子', () {
    test('固定 46 条,宽 1–3、缝 1–2', () {
      final List<({int width, int gap})> bars = cityStampBarcode(7);
      expect(bars.length, 46);
      for (final ({int width, int gap}) bar in bars) {
        expect(bar.width, inInclusiveRange(1, 3));
        expect(bar.gap, inInclusiveRange(1, 2));
      }
    });

    test('同一个签号每次画出来一模一样', () {
      expect(cityStampBarcode(7), cityStampBarcode(7));
      expect(cityStampBarcode('7'), cityStampBarcode(7));
    });

    test('不同签号画出不同条形', () {
      expect(cityStampBarcode(7), isNot(cityStampBarcode(8)));
    });

    test('★ 与小程序 LCG 逐位对拍(serial=7 / 1234,值来自 node 跑原件)', () {
      expect(
        cityStampBarcode(7).map((({int width, int gap}) b) => b.width).toList(),
        <int>[
          1, 2, 1, 1, 1, 1, 3, 2, 1, 1, 2, 1, 2, 3, 2, 1, 1, 2, 2, 3, 1, 2, 3,
          1, 2, 1, 1, 1, 1, 3, 1, 1, 2, 1, 3, 2, 2, 2, 2, 2, 3, 2, 2, 1, 2, 1,
        ],
      );
      expect(
        cityStampBarcode(7).map((({int width, int gap}) b) => b.gap).toList(),
        <int>[
          2, 2, 2, 2, 2, 1, 2, 2, 2, 1, 1, 2, 2, 1, 1, 1, 2, 2, 2, 1, 2, 1, 1,
          2, 2, 1, 1, 2, 1, 2, 1, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 1, 2, 1, 2, 2,
        ],
      );
      expect(
        cityStampBarcode(1234)
            .map((({int width, int gap}) b) => b.width)
            .toList(),
        <int>[
          3, 1, 2, 1, 1, 3, 2, 3, 2, 1, 1, 1, 1, 3, 1, 2, 3, 3, 1, 1, 1, 3, 1,
          1, 2, 2, 1, 1, 1, 1, 1, 2, 1, 1, 2, 3, 3, 1, 1, 1, 2, 2, 3, 1, 1, 2,
        ],
      );
    });

    test('空签号不崩(签号 0 也有条形)', () {
      expect(cityStampBarcode(null).length, 46);
      expect(cityStampBarcode('').length, 46);
      expect(cityStampBarcode('abc').length, 46);
    });
  });

  group('签号显示', () {
    test('取后四位并补零', () {
      expect(cityStampSerialLabel(0), 'NO. 0000');
      expect(cityStampSerialLabel(1), 'NO. 0001');
      expect(cityStampSerialLabel(42), 'NO. 0042');
      expect(cityStampSerialLabel(12345), 'NO. 2345');
      expect(cityStampSerialLabel('7'), 'NO. 0007');
    });

    test('空值按 0,不抛', () {
      expect(cityStampSerialLabel(null), 'NO. 0000');
    });
  });

  group('留签时间', () {
    test('截到分钟并把 T 换空格(后端下发 ISO)', () {
      expect(
        cityStampAtLabel('2026-09-15T07:09:17'),
        '2026-09-15 07:09',
      );
      expect(cityStampAtLabel('2026-09-15 07:09:00'), '2026-09-15 07:09');
    });

    test('短的、空的照原样返回,不越界', () {
      expect(cityStampAtLabel(''), '');
      expect(cityStampAtLabel(null), '');
      expect(cityStampAtLabel('2026-09-15'), '2026-09-15');
    });
  });
}
