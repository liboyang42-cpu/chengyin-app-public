import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_mybiz.dart';

void main() {
  group('★★ 均分=0 和「还没有评价」是两回事', () {
    test('reviewCount=0 时 avgRating 也是后端给的 0,不是"评分很差"', () {
      final biz = CoopMyBiz.fromJson(<String, dynamic>{
        'credit': <String, dynamic>{'fulfillmentRate': 100, 'violationCount': 0},
        'review': <String, dynamic>{'avgRating': 0, 'reviewCount': 0},
        'settlements': <dynamic>[],
      });
      expect(biz.avgRating, 0);
      expect(biz.reviewCount, 0, reason: '页面必须靠这个字段而不是 avgRating 本身来判"有没有评价"');
    });
  });

  test('结算行 topicTitle 兜底(mySettlements 不带 topicName)', () {
    final row = CoopSettlementRow.fromJson(<String, dynamic>{'id': 1, 'topicId': 7});
    expect(row.topicTitle, '主题 #7');
    final rowNoTopic = CoopSettlementRow.fromJson(<String, dynamic>{'id': 1});
    expect(rowNoTopic.topicTitle, '未命名主题');
  });

  group('结算状态文案', () {
    test('三态 + 未知兜底', () {
      String s(int? st) => CoopSettlementRow.fromJson(<String, dynamic>{'id': 1, 'status': st}).statusText;
      expect(s(0), '待入账');
      expect(s(1), '已入余额');
      expect(s(2), '已作废');
      expect(s(null), '状态待确认');
    });
  });

  group('收款方文案', () {
    test('club → 俱乐部分润;merchant/空/未知 → 商家分润', () {
      String p(String? t) => CoopSettlementRow.fromJson(<String, dynamic>{'id': 1, 'payeeType': t}).payeeText;
      expect(p('club'), '俱乐部分润');
      expect(p('merchant'), '商家分润');
      expect(p(null), '商家分润');
    });
  });

  group('分润方式文案', () {
    test('三种模式', () {
      expect(
          CoopSettlementRow.fromJson(<String, dynamic>{'id': 1, 'shareMode': 0}).shareRuleText, '引流');
      expect(
          CoopSettlementRow.fromJson(
                  <String, dynamic>{'id': 1, 'shareMode': 1, 'shareRate': 30}).shareRuleText,
          '分成 · 30.0%');
      expect(
          CoopSettlementRow.fromJson(
                  <String, dynamic>{'id': 1, 'shareMode': 2, 'fixedFee': 8.5}).shareRuleText,
          '固定 · ¥8.50/人');
    });
  });
}
