import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_relation.dart';

void main() {
  group('★ 没名字的整条丢掉', () {
    // 小程序 relation/index.js:15 `if (displayName === '—') return null`
    // 渲染一张只有「—」的卡片,用户点进去也不知道是谁。
    test('没有 name → null', () {
      expect(MerchantRelation.tryFromJson(<String, dynamic>{'id': 1}), isNull);
    });
    test('name 全空格 → null', () {
      expect(
          MerchantRelation.tryFromJson(<String, dynamic>{'name': '   '}), isNull);
    });
    test('有名字 → 解析出来,且两端空白裁掉', () {
      final r = MerchantRelation.tryFromJson(<String, dynamic>{'name': ' 城瘾咖啡 '});
      expect(r?.name, '城瘾咖啡');
    });
    test('列表里无名的被过滤,不占位', () {
      final home = MerchantRelationHome.fromJson(<String, dynamic>{
        'relations': <dynamic>[
          <String, dynamic>{'name': 'A'},
          <String, dynamic>{'id': 2},
          <String, dynamic>{'name': ''},
          <String, dynamic>{'name': 'B'},
        ],
      });
      expect(home.relations.map((MerchantRelation r) => r.name).toList(),
          <String>['A', 'B']);
    });
  });

  group('副标题三选一', () {
    MerchantRelation r(Map<String, dynamic> extra) =>
        MerchantRelation.tryFromJson(<String, dynamic>{'name': 'X', ...extra})!;
    test('优先地址', () {
      expect(r(<String, dynamic>{'address': '中山路1号', 'city': '上海'})
          .displayDescription, '中山路1号');
    });
    test('无地址取品类', () {
      expect(r(<String, dynamic>{'categoryName': '咖啡', 'city': '上海'})
          .displayDescription, '咖啡');
    });
    test('只剩城市', () {
      expect(r(<String, dynamic>{'city': '上海'}).displayDescription, '上海');
    });
    test('全空 → 给一句提示,不留空白', () {
      expect(r(<String, dynamic>{}).displayDescription, '查看商家资料');
      expect(r(<String, dynamic>{'type': 'club'}).displayDescription, '查看俱乐部资料');
    });
    test('空串不算有值', () {
      expect(r(<String, dynamic>{'address': '  ', 'city': '上海'})
          .displayDescription, '上海');
    });
  });

  group('统计', () {
    test('缺字段当 0,不抛', () {
      const s = MerchantRelationStats();
      expect(s.merchantCount, 0);
      expect(s.pendingCoopCount, 0);
    });
    test('discovery 不是对象时不炸', () {
      final home = MerchantRelationHome.fromJson(<String, dynamic>{
        'discovery': 'oops',
        'stats': 'oops',
      });
      expect(home.discoveryMerchants, isEmpty);
      expect(home.stats.merchantCount, 0);
    });
  });
}
