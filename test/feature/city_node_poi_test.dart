import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/city_node_poi.dart';

void main() {
  CityNodePoi n(Map<String, dynamic> m) =>
      CityNodePoi.fromJson(<String, dynamic>{'poiId': 1, 'name': 'X', ...m});

  group('★★ 坐标缺失不能默认成 0', () {
    test('缺经纬度 → hasCoords 假,不该标到地图上', () {
      expect(n(<String, dynamic>{}).hasCoords, isFalse);
      expect(n(<String, dynamic>{'lat': 31.2}).hasCoords, isFalse);
    });
    test('★ (0,0) 也当无效 —— 那是几内亚湾', () {
      expect(n(<String, dynamic>{'lat': 0, 'lng': 0}).hasCoords, isFalse,
          reason: '默认成 0 会把点标到大西洋里去');
    });
    test('正常坐标 → 有效', () {
      expect(n(<String, dynamic>{'lat': 31.2304, 'lng': 121.4737}).hasCoords,
          isTrue);
    });
    test('只有一个是 0(合法边界)→ 仍有效', () {
      expect(n(<String, dynamic>{'lat': 0, 'lng': 121.4737}).hasCoords, isTrue,
          reason: '赤道上的点纬度就是 0,不能一刀切');
    });
  });

  group('打卡方式:与全 App 共用 0–7 码表', () {
    String t(int? v) =>
        n(<String, dynamic>{'validationMethod': v}).interactionText;
    test('码 0–7', () {
      expect(t(0), '无需验证');
      expect(t(1), '文字作答');
      expect(t(2), '拍照打卡');
      expect(t(3), '选项问答');
      expect(t(4), '到店扫码');
      expect(t(5), 'GPS 到达');
      expect(t(6), '偏好题组');
      expect(t(7), '传感器挑战');
    });
    test('null 保持原语义(到点打卡),未知码明确「其他」', () {
      expect(t(null), '到点打卡');
      expect(t(99), '其他');
    });
  });

  group('距离与标签', () {
    test('没给距离不显示,不写 0m', () {
      expect(n(<String, dynamic>{}).distanceText, isNull);
      expect(n(<String, dynamic>{'distance': -1}).distanceText, isNull);
    });
    test('米 / 公里', () {
      expect(n(<String, dynamic>{'distance': 850}).distanceText, '850m');
      expect(n(<String, dynamic>{'distance': 2500}).distanceText, '2.5km');
    });
    test('标签多种分隔符都能切', () {
      expect(n(<String, dynamic>{'tags': '咖啡,甜点、烘焙;轻食'}).tagList,
          <String>['咖啡', '甜点', '烘焙', '轻食']);
    });
    test('空标签给空表', () {
      expect(n(<String, dynamic>{'tags': ' , ; '}).tagList, isEmpty);
    });
  });

  group('收藏切换', () {
    test('copyWith 只改 favorited,不动其他字段', () {
      final a = n(<String, dynamic>{'lat': 31.2, 'lng': 121.4, 'merchantName': '小店'});
      final b = a.copyWith(favorited: true);
      expect(b.favorited, isTrue);
      expect(b.merchantName, '小店');
      expect(b.lat, 31.2);
    });
  });

  test('名字兜底', () {
    expect(n(<String, dynamic>{'name': '  '}).name, '未命名地点');
  });
}
