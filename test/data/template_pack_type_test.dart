// 模板市场的形态筛选轴 + 套用链路。
//
// ★★ 这里最要紧的两条:
//   ① 「全部」是 null 不是 0 —— 0 是「单节点玩法」这个真实形态,
//      拿它当全部会让剧情包与 IP 包在默认视图里凭空消失。
//   ② 套用出来的草稿**必须带 originalTemplateId** —— 后端按它给来源模板
//      采用数 +1,而模板市场的排序就是按采用数来的。丢了它整个热度榜是死的。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/data/models/template_draft.dart';

PlayTemplate _template({int packType = 0}) => PlayTemplate(
  id: 42,
  title: '隐藏菜单',
  description: '到店说出暗号',
  players: '1-2 人',
  duration: 15,
  categoryId: 4,
  packType: packType,
);

void main() {
  group('形态解析', () {
    test('packType 缺席按 0(单节点玩法)—— 与后端服务端归一同口径', () {
      final t = PlayTemplate.fromJson(<String, dynamic>{
        'id': 1,
        'title': '某玩法',
      });
      expect(t.packType, 0);
    });

    test('三种形态各有名字', () {
      expect(PlayTemplate.fromJson(<String, dynamic>{'id': 1, 'packType': 0}).packTypeLabel, '单节点玩法');
      expect(PlayTemplate.fromJson(<String, dynamic>{'id': 1, 'packType': 1}).packTypeLabel, '剧情包');
      expect(PlayTemplate.fromJson(<String, dynamic>{'id': 1, 'packType': 2}).packTypeLabel, '店铺 IP 包');
    });

    test('★ 认不出的形态不编名字 —— 编一个「其它」出来,用户会以为那是真实分类', () {
      expect(
        PlayTemplate.fromJson(<String, dynamic>{'id': 1, 'packType': 9}).packTypeLabel,
        isNull,
      );
      expect(
        PlayTemplate.fromJson(<String, dynamic>{'id': 1, 'packType': -1}).packTypeLabel,
        isNull,
      );
    });
  });

  group('套用出来的草稿', () {
    // 与 template_detail_page._adopt 同一份构造。改那边要改这里。
    TemplateDraft adopt(PlayTemplate t) => TemplateDraft(
      originalTemplateId: t.id,
      title: t.title,
      description: (t.description ?? '').trim(),
      imgUrl: t.imgUrl,
      players: t.players,
      duration: t.duration,
      difficulty: t.difficulty,
      usageLocation: t.usageLocation,
      requiredMaterials: t.requiredMaterials,
      ruleInstructions: t.ruleInstructions,
      categoryId: t.categoryId,
    );

    test('★★ 必须带 originalTemplateId —— 丢了它来源模板的采用数永远是 0', () {
      expect(adopt(_template()).originalTemplateId, 42);
    });

    test('带上可公开的展示字段', () {
      final d = adopt(_template());
      expect(d.title, '隐藏菜单');
      expect(d.description, '到店说出暗号');
      expect(d.players, '1-2 人');
      expect(d.duration, 15);
      expect(d.categoryId, 4);
    });

    test('★★ 不带答案类字段 —— 公开投影本来就剥掉了,凑一份出来等于把答案发给所有人', () {
      final d = adopt(_template());
      expect(d.questionAnswer, isNull);
      expect(d.correctAnswer, isNull);
      expect(d.questionA, isNull);
      expect(d.hint1, isNull);
      expect(d.answerReveal, isNull);
    });

    test('套用出来的草稿仍要走本地校验 —— 只有标题不算配好', () {
      // 只有标题时可以存草稿,但不能发布(描述、人数、时长、类别都还没填)。
      final d = adopt(PlayTemplate(id: 7, title: '只有名字'));
      expect(d.canSaveDraft, isTrue);
      expect(d.canPublish, isFalse);
      expect(d.publishBlocker, isNotNull);
    });
  });
}
