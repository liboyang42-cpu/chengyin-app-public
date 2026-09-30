import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_customer.dart';

void main() {
  final now = DateTime(2026, 8, 19, 12);

  group('★ 兜底文案不能进头像', () {
    test('没留姓名时:标题兜底,头像名留空', () {
      const c = MerchantCustomer();
      expect(c.displayName, '未留姓名');
      expect(c.avatarName, '',
          reason: '用 displayName 会把「未」字渲成姓氏首字母');
    });
    test('有名字时两者一致', () {
      const c = MerchantCustomer(name: '张三');
      expect(c.displayName, '张三');
      expect(c.avatarName, '张三');
    });
    test('全空格等同没名字', () {
      const c = MerchantCustomer(name: '   ');
      expect(c.displayName, '未留姓名');
      expect(c.avatarName, '');
    });
  });

  group('★ 两截都可能空,别拼出孤零零的「·」', () {
    test('都有 → 用 · 连接', () {
      const c = MerchantCustomer(lastAction: '核销了夜跑咖啡路线', lastTime: '2026-08-16 10:00:00');
      expect(c.actionText(now), '核销了夜跑咖啡路线 · 3 天前');
    });
    test('只有动作 → 不带分隔符', () {
      const c = MerchantCustomer(lastAction: '核销了夜跑咖啡路线');
      expect(c.actionText(now), '核销了夜跑咖啡路线');
    });
    test('只有时间 → 不带分隔符', () {
      const c = MerchantCustomer(lastTime: '2026-08-18 10:00:00');
      expect(c.actionText(now), '昨天');
    });
    test('都没有 → 空串,不是「 · 」', () {
      expect(const MerchantCustomer().actionText(now), '');
    });
  });

  group('相对时间', () {
    String t(String? v) => relativeTime(v, now);
    test('今天 / 昨天', () {
      expect(t('2026-08-19 08:00:00'), '今天');
      expect(t('2026-08-18 08:00:00'), '昨天');
    });
    test('天 / 月 / 年', () {
      expect(t('2026-08-09 12:00:00'), '10 天前');
      expect(t('2026-06-19 12:00:00'), '2 个月前');
      expect(t('2024-08-19 12:00:00'), '2 年前');
    });
    test('未来时间不显示负数', () {
      expect(t('2026-09-01 12:00:00'), '');
    });
    test('解析不了 / 空 → 空串,不抛', () {
      expect(t('乱七八糟'), '');
      expect(t(''), '');
      expect(t(null), '');
    });
  });

  group('分层文案', () {
    test('三档 + 未知兜底成新客', () {
      String s(String? tier) => MerchantCustomer(tier: tier).tierText;
      expect(s('loyal'), '常客');
      expect(s('active'), '活跃');
      expect(s('new'), '新客');
      expect(s(null), '新客');
      expect(s('whatever'), '新客');
    });
  });
}
