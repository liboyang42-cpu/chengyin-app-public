// 招商承接链路上的标签与可操作态。
//
// ★★ 这一组几乎全在盯同一件事:**「没拿到」不许说成「没有」**。
//   本轮在这条链路上找到六处会犯它的位置:
//     · 剩余名额 null(=不限)被渲成 0(=已满);
//     · 场次人数 null(没查到)被渲成「0 人」;
//     · 点位审核态 null 被兜成「待审核」——那是一个真实状态;
//     · 章节 required 缺席被兜成「必选章节」;
//     · 条款档读不出来被兜成「权益承接」——于是表单收错数据、提交必被拒;
//     · 预计到店窗口只有一端时自己补另一端。
//
// ★ 另一半盯的是「摆一个点下去必被拒的按钮」:
//   `canSubmitOffer` 的三个条件各自对应服务端的一道闸。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/chapter_application.dart';
import 'package:chengyin_app/data/models/merchant_recruit.dart';

RecruitChapter chapter(Map<String, dynamic> recruit,
        {Map<String, dynamic> extra = const <String, dynamic>{}}) =>
    RecruitChapter.fromJson(<String, dynamic>{
      'id': 7,
      'name': '第一章',
      ...extra,
      'recruitStatus': recruit,
    });

void main() {
  group('★★ 名额:null 不限 / 0 已满 —— 两者不是一回事', () {
    test('remainingMerchantCount 缺席 = 不限,不许说成已满', () {
      expect(chapter(<String, dynamic>{'maxMerchant': 4}).merchantLimitLabel,
          '名额不限');
    });

    test('剩 0 家就是真的满了', () {
      expect(
        chapter(<String, dynamic>{
          'maxMerchant': 4,
          'remainingMerchantCount': 0,
        }).merchantLimitLabel,
        '名额已满',
      );
    });

    test('剩 2 家(上限 4)', () {
      expect(
        chapter(<String, dynamic>{
          'maxMerchant': 4,
          'remainingMerchantCount': 2,
        }).merchantLimitLabel,
        '剩余 2 / 4 家可承接',
      );
    });

    test('上限没配时只说还剩几家,不拼出「/ 0」', () {
      final String label = chapter(<String, dynamic>{
        'remainingMerchantCount': 2,
      }).merchantLimitLabel;
      expect(label, '剩余 2 家可承接');
      expect(label.contains('/ 0'), isFalse);
    });
  });

  group('★ 章节公示项', () {
    test('required 缺席不许兜成「必选章节」', () {
      expect(chapter(const <String, dynamic>{}).requiredLabel, '章节类型未标注');
    });

    test('required=0 可选 / 1 必选', () {
      expect(
        chapter(const <String, dynamic>{},
            extra: <String, dynamic>{'required': 0}).requiredLabel,
        '可选章节',
      );
      expect(
        chapter(const <String, dynamic>{},
            extra: <String, dynamic>{'required': 1}).requiredLabel,
        '必选章节',
      );
    });

    test('★★ 条款档读不出来说实话,不默认成权益承接', () {
      expect(chapter(const <String, dynamic>{}).termsLabel, '承接档位未标注');
      expect(chapter(const <String, dynamic>{'termsMode': 'PERK'}).termsLabel,
          '权益承接');
      expect(
          chapter(const <String, dynamic>{'termsMode': 'REVSHARE'}).termsLabel,
          '计酬承接');
      expect(
          chapter(const <String, dynamic>{'termsMode': 'TRAFFIC'}).termsLabel,
          '引流承接');
    });

    test('玩法边界按公示项拼:验证方式 + 探索值上限', () {
      expect(
        chapter(const <String, dynamic>{
          'allowedValidationMethods': '1,4',
          'maxNodeXp': 30,
        }).boundaryLabel,
        '玩法限 文字作答/到店扫码 · 探索值上限 30',
      );
    });

    test('★★ 码 1 用权威文案「文字作答」,不再自说自话叫「文字暗号」', () {
      expect(
        chapter(const <String, dynamic>{'allowedValidationMethods': '1'})
            .boundaryLabel,
        '玩法限 文字作答',
      );
    });

    test('认不出的码回落「其他」;空段/非数字段丢弃,不拼出空名字', () {
      expect(
        chapter(const <String, dynamic>{'allowedValidationMethods': '1,,99,abc'})
            .boundaryLabel,
        '玩法限 文字作答/其他',
      );
    });

    test('边界两项都空 = 不限,返回空串让调用方整行不渲染', () {
      expect(chapter(const <String, dynamic>{}).boundaryLabel, '');
      // maxNodeXp=0 在这里的含义是「不限」,不是「上限 0」。
      expect(chapter(const <String, dynamic>{'maxNodeXp': 0}).boundaryLabel, '');
    });

    test('权益门槛只在权益档出现;非权益档即使有值也不显示', () {
      expect(
        chapter(const <String, dynamic>{
          'termsMode': 'PERK',
          'perkMinValue': 30,
        }).perkMinValueLabel,
        '权益零售价不少于 ¥30',
      );
      expect(
        chapter(const <String, dynamic>{
          'termsMode': 'TRAFFIC',
          'perkMinValue': 30,
        }).perkMinValueLabel,
        '',
      );
    });
  });

  group('★★ 点位审核态:null 不许兜成「待审核」', () {
    MyChapterNode node(Map<String, dynamic> j) =>
        MyChapterNode.fromJson(<String, dynamic>{'id': 1, 'name': '门店', ...j});

    test('缺席 → 审核状态未知', () {
      expect(node(const <String, dynamic>{}).auditLabel, '审核状态未知');
      expect(node(const <String, dynamic>{}).isApproved, isFalse);
      expect(node(const <String, dynamic>{}).isRejected, isFalse);
    });

    test('0/1/2 三档各自说清楚', () {
      expect(node(const <String, dynamic>{'nodeAuditStatus': 0}).auditLabel,
          '待审核');
      expect(node(const <String, dynamic>{'nodeAuditStatus': 1}).auditLabel,
          '已通过');
      expect(node(const <String, dynamic>{'nodeAuditStatus': 2}).auditLabel,
          '已驳回');
    });

    test('地址空 = 没填,照实说', () {
      expect(node(const <String, dynamic>{}).addressLabel, '未填地址');
      expect(node(const <String, dynamic>{'address': ' 南京西路 1 号 '}).addressLabel,
          '南京西路 1 号');
    });
  });

  group('★★ 场次:人数 null 与 0 是两句话', () {
    UpcomingRun run(Map<String, dynamic> j) => UpcomingRun.fromJson(j);

    test('paidCount 缺席 → 人数未知,不许写「0 人」', () {
      final String meta = run(const <String, dynamic>{}).metaLabel;
      expect(meta, '人数未知');
      expect(meta.contains('0 人'), isFalse,
          reason: '把"没查到人数"说成"没人来",商家会照着它撤掉当天的人手');
    });

    test('paidCount 真的是 0 就照实说 0 人', () {
      expect(run(const <String, dynamic>{'paidCount': 0}).metaLabel, '0 人');
    });

    test('人数 + 成团状态拼成一行', () {
      expect(
        run(const <String, dynamic>{'paidCount': 6, 'teamStatus': 'FORMED'})
            .metaLabel,
        '6 人 · 已成团',
      );
    });

    test('★ 预计到店窗口只有一端时不给区间,不自己补另一端', () {
      expect(
          run(const <String, dynamic>{'arrivalStart': '2026-08-20 14:00:00'})
              .arrivalLabel,
          '');
      expect(
        run(const <String, dynamic>{
          'arrivalStart': '2026-08-20 14:00:00',
          'arrivalEnd': '2026-08-20 15:30:00',
        }).arrivalLabel,
        '预计 14:00-15:30 到店',
      );
    });

    test('★ 第几站两个数都齐才说', () {
      expect(run(const <String, dynamic>{'nodeOrder': 3}).stepLabel, '');
      expect(
          run(const <String, dynamic>{'nodeOrder': 3, 'nodeTotal': 0}).stepLabel,
          '');
      expect(
        run(const <String, dynamic>{'nodeOrder': 3, 'nodeTotal': 5}).stepLabel,
        '第 3/5 站',
      );
    });

    test('开场时间拿不到就说拿不到;拿得到只切秒,不重新解析时间', () {
      expect(run(const <String, dynamic>{}).startLabel, '开场时间未知');
      expect(
        run(const <String, dynamic>{'startTime': '2026-08-22 10:00:00'})
            .startLabel,
        '2026-08-22 10:00',
      );
      // 格式不认识时原样显示,绝不猜。
      expect(run(const <String, dynamic>{'startTime': '下周二'}).startLabel, '下周二');
    });

    test('来源:没有俱乐部名 = 自由报名场', () {
      expect(run(const <String, dynamic>{}).sourceLabel, '自由报名场');
      expect(run(const <String, dynamic>{'clubName': '夜行者'}).sourceLabel, '夜行者');
    });
  });

  group('★★ 圈层供给的复核动作:三个条件与小程序一字不差', () {
    ChapterApplicationAction act({
      bool offerActive = false,
      int? offerId,
      String? circleThemeCode,
    }) =>
        ChapterApplicationAction(
          status: 1,
          source: 0,
          offerActive: offerActive,
          offerId: offerId,
          circleThemeCode: circleThemeCode,
        );

    test('offerActive / offerId / circleThemeCode 缺一个就不给', () {
      expect(
          act(offerActive: true, offerId: 55, circleThemeCode: 'CIRCLE-9')
              .canReconfirmCircleSupply,
          isTrue);
      // 没有编号:后端恒回「缺少供给记录」。
      expect(
          act(offerActive: true, circleThemeCode: 'CIRCLE-9')
              .canReconfirmCircleSupply,
          isFalse);
      // 不是圈层供给:30 天复核不成立。
      expect(
          act(offerActive: true, offerId: 55).canReconfirmCircleSupply, isFalse);
      // 供给还没生效:没有可复核的东西。
      expect(
          act(offerId: 55, circleThemeCode: 'CIRCLE-9')
              .canReconfirmCircleSupply,
          isFalse);
    });
  });

  group('★★ 「填实际供给」的三个条件,每个对应服务端一道闸', () {
    ChapterApplicationAction act({
      int status = 1,
      int source = 0,
      bool offerActive = false,
      String? termsMode = 'PERK',
    }) =>
        ChapterApplicationAction(
          status: status,
          source: source,
          offerActive: offerActive,
          termsMode: termsMode,
        );

    test('申请没通过就不给 —— 服务端的授权闸是「本章申请已通过」', () {
      expect(act(status: 0).canSubmitOffer, isFalse);
      expect(act(status: 2).canSubmitOffer, isFalse);
      expect(act().canSubmitOffer, isTrue);
    });

    test('已有生效供给不给就地改 —— 要改得先撤回', () {
      expect(act(offerActive: true).canSubmitOffer, isFalse);
      expect(act(offerActive: true).offerReadOnly, isTrue);
    });

    test('★★ 档位读不出来一律不给 —— 点下去必被判成档位不合法', () {
      expect(act(termsMode: null).canSubmitOffer, isFalse);
      expect(act(termsMode: '').canSubmitOffer, isFalse);
      expect(act(termsMode: 'WHATEVER').canSubmitOffer, isFalse);
    });

    test('撤回:只有自己申请的、还在审核中的能撤', () {
      expect(act(status: 0).canWithdraw, isTrue);
      // 主办方邀请来的不该由商家撤。
      expect(act(status: 0, source: 1).canWithdraw, isFalse);
      expect(act(status: 1).canWithdraw, isFalse);
    });
  });

  group('offerActive 解析', () {
    ChapterApplication app(Map<String, dynamic> j) =>
        ChapterApplication.fromJson(<String, dynamic>{'id': 1, ...j});

    test('服务端算的是 case when ... then 1 else 0,两种形态都要认', () {
      expect(app(const <String, dynamic>{'offerActive': 1}).offerActive, isTrue);
      expect(
          app(const <String, dynamic>{'offerActive': true}).offerActive, isTrue);
      expect(
          app(const <String, dynamic>{'offerActive': 0}).offerActive, isFalse);
      // 字段缺席(owner-list 那条 SQL 不算它)按 false —— 保守到「不给按钮」那侧。
      expect(app(const <String, dynamic>{}).offerActive, isFalse);
    });
  });

  group('报名详情', () {
    MerchantRegistrationDetail detail(Map<String, dynamic> j) =>
        MerchantRegistrationDetail.fromJson(<String, dynamic>{'id': 9, ...j});

    test('★ 可改口径与服务端闸二同:只有审核中/已驳回', () {
      expect(detail(const <String, dynamic>{'status': 0}).canEdit, isTrue);
      expect(detail(const <String, dynamic>{'status': 2}).canEdit, isTrue);
      expect(detail(const <String, dynamic>{'status': 1}).canEdit, isFalse);
      // status 缺席 = 不知道在哪一档,不给编辑表单。
      expect(detail(const <String, dynamic>{}).canEdit, isFalse);
    });

    test('已中标看 auditStatus,不看 status', () {
      expect(
          detail(const <String, dynamic>{'status': 0, 'auditStatus': 1}).isWon,
          isTrue);
      expect(detail(const <String, dynamic>{'status': 1}).isWon, isFalse);
    });

    test('picUrl 逗号串拆成列表,空段丢掉', () {
      expect(detail(const <String, dynamic>{'picUrl': 'a.jpg, ,b.jpg'}).pics,
          <String>['a.jpg', 'b.jpg']);
      expect(detail(const <String, dynamic>{}).pics, isEmpty);
    });
  });
}
