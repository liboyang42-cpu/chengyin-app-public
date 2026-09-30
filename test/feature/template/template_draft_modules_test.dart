import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/template_draft.dart';

void main() {
  test('模板 D4 全部真实落库字段进入提交 payload', () {
    const TemplateDraft draft = TemplateDraft(
      originalTemplateId: 9,
      title: '老城密语',
      description: '在现场观察并解谜',
      imgUrl: 'https://cdn/cover.png',
      players: '2-4',
      duration: 30,
      difficulty: '一般',
      usageLocation: '古镇老街',
      requiredMaterials: '手机、纸笔',
      ruleInstructions: '到达后先读故事',
      categoryId: 4,
      activityCategoryids: '4,7',
      isSync: 1,
      validationMethod: 3,
      questionName: '石碑上是什么图案？',
      questionA: '鹤',
      questionB: '鹿',
      questionC: '龙',
      correctAnswer: 'B',
      questionImg: 'https://cdn/question.png',
      questionAudio: 'https://cdn/question.m4a',
      questionOptionMediaJson: '{"A":{"img":"https://cdn/a.png"}}',
      hint1: '看左下角',
      hint2: '有角的动物',
      answerReveal: '答案是鹿',
      photoRequireDesc: '与石碑合影',
      photoReview: 1,
      feedbackText: '你找到了老城的秘密',
      couponId: 88,
      medalImg: 'https://cdn/medal.png',
      medalName: '老城探秘者',
      storyEnabled: true,
      storyJson: '[{"text":"1930年","tag":"序章","imgs":[]}]',
      voiceEnabled: true,
      audioUrl: 'https://cdn/guide.mp3',
      audioDuration: 45,
    );

    final Map<String, dynamic> json = draft.toJson();
    expect(json['originalTemplateId'], 9);
    expect(json['activityCategoryids'], '4,7');
    expect(json['validationMethod'], 3);
    expect(json['questionOptionMediaJson'], contains('a.png'));
    expect(json['hint2'], '有角的动物');
    expect(json['couponId'], 88);
    expect(json['storyJson'], contains('1930'));
    expect(json['audioDuration'], 45);
  });

  test('后端不落库字段 fail-closed：不允许伪造已保存的勋章样式/反馈方式', () {
    const TemplateDraft draft = TemplateDraft(title: '测试');
    expect(draft.toJson(), isNot(contains('medalStyle')));
    expect(draft.toJson(), isNot(contains('feedbackMethod')));
  });

  test('移除模块或切换完成方式后，隐藏字段不得继续提交', () {
    const TemplateDraft removed = TemplateDraft(
      title: '测试',
      finishEnabled: false,
      rewardEnabled: false,
      storyEnabled: false,
      voiceEnabled: false,
      validationMethod: 0,
      questionName: '旧问题',
      questionAnswer: '旧答案',
      photoRequireDesc: '旧拍照要求',
      couponId: 8,
      feedbackText: '旧反馈',
      medalImg: 'https://cdn/old.png',
      medalName: '旧勋章',
      storyJson: '[{"text":"old"}]',
      audioUrl: 'https://cdn/old.mp3',
    );
    final Map<String, dynamic> payload = removed.toJson();
    for (final String key in <String>[
      'questionName',
      'questionAnswer',
      'photoRequireDesc',
      'couponId',
      'feedbackText',
      'medalImg',
      'medalName',
      'storyJson',
      'audioUrl',
    ]) {
      expect(payload, isNot(contains(key)), reason: key);
    }
  });

  group('发布门槛与小程序 temp 一致', () {
    const TemplateDraft base = TemplateDraft(
      title: '老城密语',
      description: '在现场观察并解谜',
      players: '2-4',
      duration: 30,
      categoryId: 4,
      activityCategoryids: '4',
      finishEnabled: true,
      rewardEnabled: false,
      validationMethod: 0,
    );

    test('无需验证可发布，玩法规则是选填', () {
      expect(base.publishBlocker, isNull);
    });

    test('文字问答必须有问题和答案', () {
      expect(
        base.copyWith(validationMethod: 1).publishBlocker,
        contains('问题和正确答案'),
      );
    });

    test('选项问答必须有至少两项和正确答案', () {
      expect(
        base
            .copyWith(validationMethod: 3, questionName: '选什么？', questionA: 'A')
            .publishBlocker,
        contains('至少需要 2 个选项'),
      );
    });

    test('可选模块一旦开启就不能空配置', () {
      expect(
        base.copyWith(rewardEnabled: true).publishBlocker,
        contains('至少配置一种奖励'),
      );
      expect(
        base.copyWith(voiceEnabled: true).publishBlocker,
        contains('上传音频'),
      );
    });
  });
}
