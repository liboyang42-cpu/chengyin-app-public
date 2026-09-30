import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/pricing.dart';

/// 终价确认的算术。资金路径 —— 定错了要退票,所以每条边界都锁死。
void main() {
  group('滑杆边界', () {
    test('下界向上取整 —— 向下取整会让终价低于成本地板', () {
      const p = PricingPreview(priceMin: 99.2);
      expect(p.sliderMin, 100);
      expect(p.canConfirm(p.sliderMin), isTrue);
    });

    test('地板正好是整数时下界就是它', () {
      expect(const PricingPreview(priceMin: 100).sliderMin, 100);
    });

    test('上界取三者最大:下界+100 / 地板×2 / 参考价×1.5', () {
      // 地板 100:下界+100=200,地板×2=200,无参考价 → 200
      expect(const PricingPreview(priceMin: 100).sliderMax, 200);
      // 参考价 300 → 450 胜出
      expect(
        const PricingPreview(priceMin: 100, cityReferencePrice: 300, cityReferenceSampleSize: 5)
            .sliderMax,
        450,
      );
      // 地板很高时 地板×2 胜出
      expect(const PricingPreview(priceMin: 500).sliderMax, 1000);
    });

    test('上界永远大于下界 —— 否则滑杆是死的', () {
      for (final double floor in <double>[1, 9.9, 100, 1234.56]) {
        final p = PricingPreview(priceMin: floor);
        expect(p.sliderMax, greaterThan(p.sliderMin), reason: '地板 $floor');
      }
    });
  });

  group('能否确认', () {
    const p = PricingPreview(priceMin: 100);
    test('等于地板可以确认', () => expect(p.canConfirm(100), isTrue));
    test('高于地板可以确认', () => expect(p.canConfirm(101), isTrue));
    test('低于地板不能确认 —— 哪怕只差一分', () {
      expect(p.canConfirm(99.99), isFalse);
    });
  });

  group('参考价文案', () {
    test('有参考价且有样本 → 报均价与样本数', () {
      const p = PricingPreview(
          priceMin: 100,
          cityReferencePrice: 288,
          cityReferenceSampleSize: 12,
          cityReferenceLabel: '上海');
      expect(p.referenceText, '上海同类已开售均价 ¥288(12 个样本)');
    });

    test('样本为 0 → 明说样本不足,不显示没有依据的数', () {
      const p = PricingPreview(priceMin: 100, cityReferencePrice: 288);
      expect(p.referenceText, '样本不足,暂不展示参考价');
    });

    test('有样本但没参考价 → 同样走样本不足', () {
      const p = PricingPreview(priceMin: 100, cityReferenceSampleSize: 9);
      expect(p.referenceText, '样本不足,暂不展示参考价');
    });

    test('没给城市名兜底成「同城」', () {
      const p = PricingPreview(
          priceMin: 100, cityReferencePrice: 200, cityReferenceSampleSize: 3);
      expect(p.referenceText, '同城同类已开售均价 ¥200(3 个样本)');
    });
  });

  group('偏离文案', () {
    const p = PricingPreview(
        priceMin: 100, cityReferencePrice: 200, cityReferenceSampleSize: 5);
    test('高于参考价报百分比', () => expect(p.deltaText(300), '高于同城参考 50%'));
    test('等于参考价不算高于', () => expect(p.deltaText(200), '未高于同城参考价'));
    test('低于参考价不报负百分比', () => expect(p.deltaText(150), '未高于同城参考价'));
    test('没有参考价时整行不显示', () {
      expect(const PricingPreview(priceMin: 100).deltaText(500), '');
    });
  });

  group('解析', () {
    test('地板缺失 → 抛「定价信息不完整」,不许当 0 放行', () {
      expect(() => PricingPreview.fromJson(<String, dynamic>{}),
          throwsA(isA<PricingIncompleteException>()));
    });
    test('正常解析', () {
      final p = PricingPreview.fromJson(<String, dynamic>{
        'priceMin': 128.5,
        'cityReferencePrice': 300,
        'cityReferenceSampleSize': 7,
        'cityReferenceLabel': '杭州',
      });
      expect(p.priceMin, 128.5);
      expect(p.sliderMin, 129);
      expect(p.cityReferenceSampleSize, 7);
    });
  });
}
