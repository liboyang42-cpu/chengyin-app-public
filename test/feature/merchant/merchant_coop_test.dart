import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';

void main() {
  group('开放路线', () {
    test('后端没下发截止日 → 不显示这一行,不编「长期开放」', () {
      final r = RecruitingRoute.fromJson(<String, dynamic>{'id': 1, 'name': 'X'});
      expect(r.deadlineText, isNull,
          reason: '编一句「长期开放」是在替运营做承诺,而我们并不知道');
    });
    test('有截止日 → 截到日期,不带时分秒', () {
      final r = RecruitingRoute.fromJson(<String, dynamic>{
        'id': 1,
        'name': 'X',
        'merchantSignUpEndDate': '2026-09-30 23:59:59',
      });
      expect(r.deadlineText, '报名截止 2026-09-30');
    });
    test('空串等同没有', () {
      final r = RecruitingRoute.fromJson(
          <String, dynamic>{'id': 1, 'name': 'X', 'merchantSignUpEndDate': ''});
      expect(r.deadlineText, isNull);
    });
    test('没给名字兜底,不显示空白卡片', () {
      expect(RecruitingRoute.fromJson(<String, dynamic>{'id': 1}).name, '未命名路线');
    });
  });

  group('承接邀约', () {
    test('待处理才摆按钮 —— 已处理的摆了点下去必然失败', () {
      expect(MerchantInvite.fromJson(<String, dynamic>{'state': 'PENDING'}).actionable, isTrue);
      expect(MerchantInvite.fromJson(<String, dynamic>{'state': 'INVITED'}).actionable, isTrue);
      expect(MerchantInvite.fromJson(<String, dynamic>{}).actionable, isTrue);
      expect(MerchantInvite.fromJson(<String, dynamic>{'state': 'ACCEPTED'}).actionable, isFalse);
      expect(MerchantInvite.fromJson(<String, dynamic>{'state': 'DECLINED'}).actionable, isFalse);
      expect(MerchantInvite.fromJson(<String, dynamic>{'state': 'EXPIRED'}).actionable, isFalse);
    });
    test('状态文案不留空白', () {
      String t(String? s) =>
          MerchantInvite.fromJson(<String, dynamic>{'state': s}).stateText;
      expect(t('ACCEPTED'), '已接受');
      expect(t('DECLINED'), '已拒绝');
      expect(t('EXPIRED'), '已过期');
      expect(t(null), '待处理');
    });
    test('id 两种命名都收', () {
      expect(MerchantInvite.fromJson(<String, dynamic>{'partyId': 7}).id, 7);
      expect(MerchantInvite.fromJson(<String, dynamic>{'id': 9}).id, 9);
    });
  });

  group('身份态识别', () {
    // ★ 这几句是后端**原话**。识别不到就会把「你不是商家」渲染成
    //   「加载失败 + 重试」,非商家点多少次都不会变成商家。
    test('四种「非商家」措辞都要认出来', () {
      for (final String msg in <String>[
        '商家信息不存在',
        '数据获取失败',
        '仅商家可访问',
        '仅商家可查看章节承接',
      ]) {
        expect(MerchantApiException(msg).isNotMerchant, isTrue, reason: msg);
      }
    });
    test('真故障不能被误判成身份态 —— 否则不给重试', () {
      for (final String msg in <String>['网络异常', '请稍后重试', '服务不可用']) {
        expect(MerchantApiException(msg).isNotMerchant, isFalse, reason: msg);
      }
    });
  });
}
