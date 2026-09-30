// 发券表单的校验与类型下标。
//
// ★★ couponType 有个 off-by-one:picker 里 0 是「请选择」,
//   提交要 -1 才是后端的类型值(小程序 coupon-form.js:47 的既有约定)。
//   自己重新编号的话,历史券的类型就对不上了。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/coupon/coupon_publish_sheet.dart';

void main() {
  test('★★ picker 下标 → 后端类型值差 1,且「请选择」不合法', () {
    expect(couponTypeWire(0), isNull, reason: '0 是「请选择」,不是一个真类型');
    expect(couponTypeWire(1), 0, reason: '礼品券');
    expect(couponTypeWire(2), 1, reason: '9折券');
    expect(couponTypeWire(3), 2, reason: '8折券');
    expect(couponTypeWire(4), 3, reason: '体验卡');
    expect(couponTypeWire(99), isNull);
    expect(couponTypeWire(-1), isNull);
  });

  test('类型文案与小程序 coupon-form.js COUPON_TYPE_LABELS 逐字对齐', () {
    expect(kCouponTypePicker, <String>[
      '请选择',
      '礼品券',
      '9折券',
      '8折券',
      '体验卡',
    ], reason: '缺「体验卡」= 既发不了体验卡,存量体验卡列表文案也对不上');
  });

  test('couponTypeLabel:后端类型值 → 展示文案;-1/未知回落「优惠券」', () {
    expect(couponTypeLabel(0), '礼品券');
    expect(couponTypeLabel(1), '9折券');
    expect(couponTypeLabel(2), '8折券');
    expect(couponTypeLabel(3), '体验卡');
    expect(couponTypeLabel(-1), '优惠券', reason: '存量无类型不许冒充 [0]=请选择');
    expect(couponTypeLabel(null), '优惠券');
    expect(couponTypeLabel(9), '优惠券');
  });

  group('校验顺序与小程序 validate() 一致 —— 一次只说一条', () {
    final DateTime s = DateTime(2026, 9, 1);
    final DateTime e = DateTime(2026, 9, 30);

    String? run({
      String name = '券',
      DateTime? start,
      DateTime? end,
      int type = 1,
      int? count = 10,
    }) => couponFormBlocker(
      name: name,
      startTime: start ?? s,
      endTime: end ?? e,
      typePickerIndex: type,
      publishCount: count,
    );

    test('先说名称', () => expect(run(name: ' '), '请输入优惠券名称'));
    test('再说日期', () {
      expect(
        couponFormBlocker(
          name: '券',
          startTime: null,
          endTime: e,
          typePickerIndex: 1,
          publishCount: 10,
        ),
        '请选择优惠券日期',
      );
    });
    test('再说类型', () => expect(run(type: 0), '请选择优惠券类型'));
    test('再说数量', () {
      expect(run(count: 0), '请输入大于0的投放数量');
      expect(run(count: null), '请输入大于0的投放数量');
    });
    test('★ 结束早于开始也拦 —— 小程序没拦,发出去就是死券', () {
      expect(run(start: e, end: s), '结束时间要晚于开始时间');
      expect(
        run(start: s, end: s),
        '结束时间要晚于开始时间',
        reason: '相等也不行',
      );
    });
    test('都填对了就没有 blocker', () => expect(run(), isNull));
  });
}
