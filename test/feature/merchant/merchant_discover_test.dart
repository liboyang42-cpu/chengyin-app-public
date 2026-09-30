// 按调性发现商家。
//
// ★★ 标签是**匹配用的字符串**(后端 MmsMerchantMapper.xml:60 `tags like '%x%'`),
//   不是展示文案 —— 改一个字就搜不到同一批店了。
//   所以 kHotMerchantTags 必须与小程序 HOT_TAGS 逐字一致,有断言锁着。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant.dart';
import 'package:chengyin_app/feature/merchant/merchant_discover_page.dart';

Merchant _m(Map<String, dynamic> extra) =>
    Merchant.fromJson(<String, dynamic>{'id': 1, 'name': '静安咖啡', ...extra});

void main() {
  test('★★ 热门标签与小程序 HOT_TAGS 逐字一致 —— 它是查询串不是文案', () {
    expect(kHotMerchantTags, <String>[
      '夜间友好',
      '可拍照',
      '适合组队',
      '宠物友好',
      '安静',
      '适合亲子',
    ]);
  });

  group('卡片标签:城市角色排第一,最多 3 个', () {
    test('cityRole + tags 按顺序拼', () {
      expect(
          merchantChips(_m(<String, dynamic>{
            'cityRole': '夜归人的最后一站',
            'tags': '夜间友好,可拍照',
          })),
          <String>['夜归人的最后一站', '夜间友好', '可拍照']);
    });

    test('★ 后端 tags 是**分隔字符串**不是数组 —— 中英文标点都要切', () {
      expect(merchantChips(_m(<String, dynamic>{'tags': '安静，可拍照;适合组队'})).length,
          3);
    });

    test('最多 3 个', () {
      expect(
          merchantChips(_m(<String, dynamic>{
            'cityRole': 'A',
            'tags': 'B,C,D,E',
          })).length,
          3);
    });

    test('空标签整个丢掉,不留空 chip', () {
      expect(merchantChips(_m(<String, dynamic>{'tags': ' , ,可拍照'})),
          <String>['可拍照']);
    });

    test('都没有 ⇒ 空列表(整行不渲染)', () {
      expect(merchantChips(_m(const <String, dynamic>{})), isEmpty);
    });
  });
}
