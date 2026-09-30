import 'package:chengyin_app/feature/participation/participation_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 字段真源 = /api/registration/info 回包(CmsRegistration + cmsTopic/cmsActivity)
/// 与 components/scene-member-participation-detail prepareDisplayData 逐条对照。
Map<String, dynamic> _info({
  int ownerType = 1,
  String activityTitle = '',
  Map<String, dynamic>? topic,
  Map<String, dynamic>? activity,
  Object? displayStatus,
  Object? nodeName,
  Object? cooperateDate,
  Object? ruleInstructions,
  Object? templateId,
  Object? totalOrderNum,
  Object? verifiedNum,
  int status = 1,
}) => <String, dynamic>{
  'id': 77,
  'ownerType': ownerType,
  'ownerId': ownerType == 1 ? 11 : 22,
  'registrationStatus': 2,
  'paymentStatus': 2,
  'purchaseKind': 1,
  'status': status,
  if (activityTitle != '') 'activityTitle': activityTitle,
  'cmsTopic': ?topic,
  'cmsActivity': ?activity,
  'displayStatus': ?displayStatus,
  'nodeName': ?nodeName,
  'cooperateDate': ?cooperateDate,
  'ruleInstructions': ?ruleInstructions,
  'templateId': ?templateId,
  'totalOrderNum': ?totalOrderNum,
  'verifiedNum': ?verifiedNum,
};

Map<String, dynamic> _topic({
  String start = '2026-09-10 09:00:00',
  String end = '2026-09-12 18:00:00',
}) => <String, dynamic>{
  'id': 11,
  'name': '夜游苏河',
  'startDate': start,
  'endDate': end,
  'imgUrl': 'https://img.test/topic.jpg',
  'description': '沿河完成城市探索',
  'productType': 1,
};

void main() {
  final DateTime now = DateTime.parse('2026-08-23T12:00:00Z');

  ParticipationDetail parse(Map<String, dynamic> json) =>
      ParticipationDetail.fromJson(77, json, now: now);

  group('A2 字段映射换回玩家侧读模型', () {
    test('名称/日期/封面取 cmsTopic,状态与列表同口径', () {
      final ParticipationDetail detail = parse(
        _info(topic: _topic(), totalOrderNum: 5, verifiedNum: 2),
      );

      expect(detail.id, 77);
      expect(detail.topicName, '夜游苏河');
      expect(detail.dateText, '2026.09.10 - 2026.09.12');
      expect(detail.coverUrl, 'https://img.test/topic.jpg');
      expect(detail.statusText, '未开始');
      expect(detail.modeText, '城市定向');
      expect(detail.isTopic, isTrue);
      expect(detail.ownerId, 11);
    });

    test('activityTitle 优先于 cmsTopic.name;双缺才落「未知主题」', () {
      expect(
        parse(_info(activityTitle: '金秋专场', topic: _topic())).topicName,
        '金秋专场',
      );
      expect(parse(_info()).topicName, '未知主题');
    });

    test('活动记录走 cmsActivity 与「线下活动」', () {
      final ParticipationDetail detail = parse(
        _info(
          ownerType: 2,
          activity: <String, dynamic>{
            'id': 22,
            'name': '街区快闪',
            'startDate': '2026-08-20 10:00:00',
            'endDate': '2026-08-30 20:00:00',
            'imgArr': <String>['https://img.test/a.jpg'],
          },
        ),
      );

      expect(detail.topicName, '街区快闪');
      expect(detail.modeText, '线下活动');
      expect(detail.coverUrl, 'https://img.test/a.jpg');
      expect(detail.isTopic, isFalse);
    });

    test('活动说明 = activityDesc 优先,否则 cmsTopic.description', () {
      expect(parse(_info(topic: _topic())).activityDescription, '沿河完成城市探索');
      final Map<String, dynamic> withOwn = _info(topic: _topic())
        ..['activityDesc'] = '本单专属说明';
      expect(parse(withOwn).activityDescription, '本单专属说明');
    });
  });

  group('A4 没有真值整行不渲染(假数据行拆除)', () {
    test('玩家侧不带 nodeName 时不摆「待分配」占位', () {
      expect(parse(_info(topic: _topic())).nodeName, isNull);
      expect(parse(_info(topic: _topic(), nodeName: '苏河湾站')).nodeName, '苏河湾站');
    });

    test('接待时间取 cooperateDate,没有就不渲染', () {
      expect(parse(_info(topic: _topic())).cooperateDate, isNull);
      expect(
        parse(
          _info(topic: _topic(), cooperateDate: '每日 10:00-22:00'),
        ).cooperateDate,
        '每日 10:00-22:00',
      );
    });

    test('日期缺任一端返回空串(真源:徽标整块不渲染)', () {
      expect(
        parse(
          _info(
            topic: _topic(start: '2026-09-10 09:00:00', end: ''),
          ),
        ).dateText,
        '',
      );
    });

    test('核销进度只随 status==1 出块;数值不可确认时给「—」不给 0', () {
      final ParticipationDetail known = parse(
        _info(topic: _topic(), totalOrderNum: 5, verifiedNum: 2),
      );
      expect(known.showOrderStats, isTrue);
      expect(known.pendingVerification, 3);
      expect(known.verifiedCount, 2);
      expect(known.totalOrderCount, 5);

      final ParticipationDetail unknown = parse(_info(topic: _topic()));
      expect(unknown.showOrderStats, isTrue);
      expect(unknown.pendingVerification, isNull);

      final ParticipationDetail off = parse(
        _info(topic: _topic(), totalOrderNum: 5, verifiedNum: 2, status: 0),
      );
      expect(off.showOrderStats, isFalse);
    });
  });

  group('A3 动作按钮显隐逐条对齐真源', () {
    test('开始前3天以上:出「取消参与」,不出「联系客服」', () {
      final ParticipationDetail detail = parse(_info(topic: _topic()));
      expect(detail.canCancel, isTrue);
      expect(detail.showContactService, isFalse);
      expect(detail.showRemainingBadge, isFalse);
    });

    test('开始前3天内:出「剩余N天」徽标与「联系客服」,取消关闭', () {
      final ParticipationDetail detail = parse(
        _info(
          topic: _topic(
            start: '2026-08-25 09:00:00',
            end: '2026-08-27 18:00:00',
          ),
        ),
      );
      // now=08-23T12:00Z(=中国 08-23 20:00),开始 08-25 中国零点差 2 天。
      expect(detail.showRemainingBadge, isTrue);
      expect(detail.remainingDaysText, '距离路线开始还剩2天');
      expect(detail.canCancel, isFalse);
      expect(detail.showContactService, isTrue);
    });

    test('已开始:联系客服;未结束不出徽标', () {
      final ParticipationDetail detail = parse(
        _info(
          topic: _topic(
            start: '2026-08-22 09:00:00',
            end: '2026-08-30 18:00:00',
          ),
        ),
      );
      expect(detail.showContactService, isTrue);
      expect(detail.canCancel, isFalse);
      expect(detail.showRemainingBadge, isFalse);
    });

    test('需修改状态既不能取消也不给客服,只出「去修改」判据', () {
      final ParticipationDetail detail = parse(
        _info(topic: _topic(), displayStatus: '需修改'),
      );
      expect(detail.needModify, isTrue);
      expect(detail.canCancel, isFalse);
      expect(detail.showContactService, isFalse);
    });

    test('paymentStatus==2 已支付判据透传(决定 cancel 还是 cancel-refund)', () {
      final ParticipationDetail unpaid = parse(_info(topic: _topic()));
      expect(unpaid.paymentStatus, 2);
      final Map<String, dynamic> raw = _info(topic: _topic())
        ..['paymentStatus'] = 1;
      expect(parse(raw).paymentStatus, 1);
    });
  });

  group('模板与规则块', () {
    test('templateId 是模板块存不存在的开关(R1-C04),图只是锦上添花', () {
      final Map<String, dynamic> raw = _info(topic: _topic(), templateId: 9)
        ..['templateName'] = '经典定向模板'
        ..['topicImgArr'] = <String>['https://img.test/banner.jpg'];
      final ParticipationDetail detail = parse(raw);
      expect(detail.templateId, 9);
      expect(detail.templateName, '经典定向模板');
      expect(detail.templateBannerUrl, 'https://img.test/banner.jpg');
      expect(parse(_info(topic: _topic())).templateId, isNull);
    });

    test('规则块渲染开关 = ruleInstructions 有值', () {
      expect(parse(_info(topic: _topic())).hasRuleInstructions, isFalse);
      expect(
        parse(
          _info(topic: _topic(), ruleInstructions: '商家仅可在…'),
        ).hasRuleInstructions,
        isTrue,
      );
    });
  });
}
