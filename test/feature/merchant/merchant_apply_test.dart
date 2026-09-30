import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';

/// 入驻申请四步向导。
///
/// ★★ 这里的校验是**唯一**的一道:后端 MerchantRegistrationDTO:21 的
///    `@NotBlank(message = "商家名称不能为空")` 被注释掉了,服务端一个字段都不校验,
///    空名字也会被建成一条商家记录。所以这些断言不是"体验优化",是**数据完整性**。
void main() {
  const empty = MerchantApplyForm();

  group('第 1 步:名称 + 手机', () {
    test('都空 → 不放行,并指出先缺哪个', () {
      expect(applyStepReady(1, empty), isFalse);
      expect(applyStepBlocker(1, empty), '请填写品牌名称');
    });
    test('只有名称 → 指出缺手机', () {
      final f = empty.copyWith(name: '城瘾咖啡');
      expect(applyStepReady(1, f), isFalse);
      expect(applyStepBlocker(1, f), '请填写联系手机号');
    });
    test('全空格不算填了', () {
      final f = empty.copyWith(name: '   ', phone: '  ');
      expect(applyStepReady(1, f), isFalse);
    });
    test('都填了 → 放行', () {
      final f = empty.copyWith(name: '城瘾咖啡', phone: '13800000000');
      expect(applyStepReady(1, f), isTrue);
      expect(applyStepBlocker(1, f), isNull);
    });
  });

  group('第 2 步:地址 + 营业时间', () {
    final base = empty.copyWith(name: 'X', phone: '13800000000');
    test('缺地址', () {
      expect(applyStepBlocker(2, base), '请填写门店地址');
    });
    test('缺营业时间', () {
      expect(applyStepBlocker(2, base.copyWith(address: '中山路1号')),
          '请填写营业时间');
    });
    test('齐了放行', () {
      final f = base.copyWith(address: '中山路1号', businessTime: '10:00-22:00');
      expect(applyStepReady(2, f), isTrue);
    });
  });

  group('第 3 步:营业执照', () {
    test('没传 → 挡住', () {
      expect(applyStepReady(3, empty), isFalse);
      expect(applyStepBlocker(3, empty), '请上传营业执照');
    });
    test('传了 → 放行', () {
      expect(applyStepReady(3, empty.copyWith(businessLicense: 'https://x/1.jpg')),
          isTrue);
    });
  });

  test('第 4 步是预览,恒可提交', () {
    expect(applyStepReady(4, empty), isTrue);
    expect(applyStepBlocker(4, empty), isNull);
  });

  group('提交体', () {
    test('字段两端空白被裁掉 —— 否则库里存的是带空格的名字', () {
      final f = empty.copyWith(name: '  城瘾咖啡  ', phone: ' 13800000000 ');
      final json = f.toJson();
      expect(json['name'], '城瘾咖啡');
      expect(json['phone'], '13800000000');
    });
    test('没有 id 时不带 id 字段(新申请)', () {
      expect(empty.toJson().containsKey('id'), isFalse);
    });
    test('有 id 时带上(驳回后重提)', () {
      expect(empty.copyWith(id: 7).toJson()['id'], 7);
    });
  });

  test('四步标题与小程序一致', () {
    expect(kApplyStepTitles, <String>['基础信息', '经营信息', '资质信息', '预览确认']);
  });

  group('账户互斥闸', () {
    // 后端 ApiMerchantController:1187 原话:
    // 「您已是俱乐部主理人,一个账户不能同时是商户与俱乐部主理人」
    //
    // ★ 这条既不是故障、也不是"还不是商家",是**永远不能成为商家**。
    //   三者的界面必须不同:故障给重试、还不是商家给申请入口、
    //   互斥则整页说清原因且**什么按钮都不给** —— 重试一万次也不会变。
    test('识别得出互斥,且不与「还不是商家」混淆', () {
      final conflict = MerchantApiException('您已是俱乐部主理人,一个账户不能同时是商户与俱乐部主理人');
      expect(conflict.isClubLeaderConflict, isTrue);
      expect(conflict.isNotMerchant, isFalse,
          reason: '归成「还不是商家」就会给出「去申请入驻」按钮 —— 而他永远申请不了');
    });

    test('「还不是商家」不会被误判成互斥', () {
      final notMerchant = MerchantApiException('商家信息不存在');
      expect(notMerchant.isClubLeaderConflict, isFalse);
      expect(notMerchant.isNotMerchant, isTrue);
    });

    test('真故障两个都不是 —— 该给重试', () {
      final fault = MerchantApiException('网络异常');
      expect(fault.isClubLeaderConflict, isFalse);
      expect(fault.isNotMerchant, isFalse);
    });
  });
}
