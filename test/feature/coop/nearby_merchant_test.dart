import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/nearby_merchant.dart';

void main() {
  NearbyMerchant m(Map<String, dynamic> extra) =>
      NearbyMerchant.fromJson(<String, dynamic>{'name': 'X', ...extra});

  group('★ 电话:不做前端脱敏,只诚实反映后端', () {
    test('canCall=false → 没有可拨号码', () {
      // 后端此时本就不会下发 phone,但即使下发了也不该给拨号入口。
      expect(m(<String, dynamic>{'canCall': false, 'phone': '13800000000'})
          .dialablePhone, isNull);
    });
    test('canCall=true 但号码为空 → 也不给入口', () {
      expect(m(<String, dynamic>{'canCall': true, 'phone': ''}).dialablePhone,
          isNull, reason: '摆一个点了没反应的拨号按钮比没有更糟');
      expect(m(<String, dynamic>{'canCall': true}).dialablePhone, isNull);
      expect(m(<String, dynamic>{'canCall': true, 'phone': '   '}).dialablePhone,
          isNull);
    });
    test('两者都满足 → 给原号,不做掩码', () {
      expect(
          m(<String, dynamic>{'canCall': true, 'phone': ' 13800000000 '})
              .dialablePhone,
          '13800000000');
    });
  });

  group('★ 距离:没给就不显示,不写 0m', () {
    test('null → 整行不显示', () {
      expect(m(<String, dynamic>{}).distanceText, isNull,
          reason: '写「0m」会让人以为商家就在脚下');
    });
    test('负数(异常)也不显示', () {
      expect(m(<String, dynamic>{'distance': -5}).distanceText, isNull);
    });
    test('米 / 公里两档', () {
      expect(m(<String, dynamic>{'distance': 0}).distanceText, '0m');
      expect(m(<String, dynamic>{'distance': 850.4}).distanceText, '850m');
      expect(m(<String, dynamic>{'distance': 1000}).distanceText, '1.0km');
      expect(m(<String, dynamic>{'distance': 12345}).distanceText, '12.3km');
    });
  });

  group('邀约', () {
    test('canInvite 直接用后端的判定', () {
      expect(m(<String, dynamic>{'canInvite': true}).canInvite, isTrue);
      expect(m(<String, dynamic>{}).canInvite, isFalse);
    });
    test('memberId 缺失时记下来 —— 邀约要它', () {
      expect(m(<String, dynamic>{}).memberId, isNull);
      expect(m(<String, dynamic>{'memberId': 7}).memberId, 7);
    });
  });

  group('标签与兜底', () {
    test('逗号顿号空格都能切', () {
      expect(m(<String, dynamic>{'tags': '咖啡, 甜点、烘焙  轻食'}).tagList,
          <String>['咖啡', '甜点', '烘焙', '轻食']);
    });
    test('空标签给空表,不给 ['']', () {
      expect(m(<String, dynamic>{'tags': ''}).tagList, isEmpty);
      expect(m(<String, dynamic>{}).tagList, isEmpty);
      expect(m(<String, dynamic>{'tags': ' , 、 '}).tagList, isEmpty);
    });
    test('名字兜底', () {
      expect(NearbyMerchant.fromJson(<String, dynamic>{'name': '  '}).name,
          '未命名商家');
    });
  });
}
