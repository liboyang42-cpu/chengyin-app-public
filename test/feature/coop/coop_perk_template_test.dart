import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_perk_template.dart';

void main() {
  group('CoopPerkTemplate.usable', () {
    test('★ 与小程序 isUsableTemplate 同判据:零售价>0 且 配额为正整数', () {
      CoopPerkTemplate t({double? retail, int? quota}) => CoopPerkTemplate.fromJson(
          <String, dynamic>{'id': 1, 'name': 'X', 'retailValue': retail, 'quota': quota});
      expect(t(retail: 28, quota: 10).usable, isTrue);
      expect(t(retail: 0, quota: 10).usable, isFalse, reason: '零售价必须>0');
      expect(t(retail: 28, quota: 0).usable, isFalse, reason: '配额必须是正整数,0 不算');
      expect(t(retail: null, quota: 10).usable, isFalse, reason: '没填零售价不能选');
      expect(t(retail: 28, quota: null).usable, isFalse, reason: '没填配额不能选');
    });
  });

  group('CoopPerkTemplate.typeText / validText', () {
    test('三种类型文案', () {
      String typeOf(int t) =>
          CoopPerkTemplate.fromJson(<String, dynamic>{'id': 1, 'name': 'x', 'perkType': t}).typeText;
      expect(typeOf(0), '礼品');
      expect(typeOf(1), '优惠券');
      expect(typeOf(2), '折扣');
      expect(typeOf(9), '权益', reason: '未知类型兜底,不能崩');
    });
    test('有效期只截前 10 位', () {
      final t = CoopPerkTemplate.fromJson(
          <String, dynamic>{'id': 1, 'name': 'x', 'validEnd': '2026-12-31 00:00:00'});
      expect(t.validText, '2026-12-31');
    });
    test('没填有效期 → null,不编"长期有效"这句话', () {
      final t = CoopPerkTemplate.fromJson(<String, dynamic>{'id': 1, 'name': 'x'});
      expect(t.validText, isNull);
    });
  });

  group('CoopPerk(申报快照) —— unitCost 商业机密闸', () {
    test('★★ 后端对发起方清空 unitCost 时,前端也必须是 null,不许兜成 0', () {
      final p = CoopPerk.fromJson(<String, dynamic>{'id': 1, 'name': 'x', 'perkType': 0});
      expect(p.unitCost, isNull);
    });
    test('受邀方本人能看到时,原样透出', () {
      final p = CoopPerk.fromJson(<String, dynamic>{'id': 1, 'name': 'x', 'unitCost': 12.5});
      expect(p.unitCost, 12.5);
    });
  });
}
