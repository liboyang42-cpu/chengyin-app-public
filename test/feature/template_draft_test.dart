import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/template_draft.dart';

void main() {
  group('★ draft 与 publish 的门槛不同', () {
    test('只有标题 → 能存草稿,不能发布', () {
      const d = TemplateDraft(title: '夜跑寻宝');
      expect(d.canSaveDraft, isTrue);
      expect(
        d.canPublish,
        isFalse,
        reason:
            '后端 draft 只判标题,publish 还查重名;'
            '但"能发出去"不等于"值得发出去"',
      );
      expect(d.publishBlocker, '请填写玩法描述');
    });
    test('连标题都没有 → 两个都不行', () {
      const d = TemplateDraft();
      expect(d.canSaveDraft, isFalse);
      expect(d.draftBlocker, '先给玩法起个名字');
      expect(d.publishBlocker, '先给玩法起个名字');
    });
    test('基本信息齐了但没时长 → 仍不能发', () {
      const d = TemplateDraft(title: 'X', description: '按顺序打卡', players: '2-4');
      expect(d.publishBlocker, '请选择玩法时长');
    });
    test('★ 时长 0 挡住(「没填」与「0 分钟」都不合理)', () {
      const d = TemplateDraft(
        title: 'X',
        description: '按顺序打卡',
        players: '2-4',
        duration: 0,
      );
      expect(d.publishBlocker, '时长要大于 0');
    });
    test('都齐了 → 可发布', () {
      const d = TemplateDraft(
        title: 'X',
        description: '按顺序打卡',
        players: '2-4',
        duration: 60,
        activityCategoryids: '1',
        feedbackText: '打卡成功',
      );
      expect(d.canPublish, isTrue);
      expect(d.publishBlocker, isNull);
    });
  });

  group('★ 重名是唯一"改个名就能过"的失败', () {
    test('识别得出重名,且不给重试', () {
      final e = TemplatePublishException('模板名称 夜跑寻宝 已存在');
      expect(e.isDuplicateName, isTrue);
      expect(e.retryable, isFalse, reason: '重试一万次名字还是重的');
    });
    test('内容被拒也不给重试', () {
      expect(TemplatePublishException('内容含有违规信息').retryable, isFalse);
    });
    test('真故障给重试', () {
      for (final String m in <String>['网络异常', '请稍后重试']) {
        expect(TemplatePublishException(m).retryable, isTrue, reason: m);
      }
    });
    test('重名与内容被拒互不误判', () {
      final dup = TemplatePublishException('模板名称 X 已存在');
      expect(dup.isContentRejected, isFalse);
      final bad = TemplatePublishException('含有违规内容');
      expect(bad.isDuplicateName, isFalse);
    });
  });

  group('提交体', () {
    test('标题与描述裁空白', () {
      const d = TemplateDraft(title: '  夜跑寻宝  ', description: ' 说明 ');
      final j = d.toJson();
      expect(j['title'], '夜跑寻宝');
      expect(j['description'], '说明');
    });
    test('空值字段不带出去', () {
      final j = const TemplateDraft(title: 'X').toJson();
      expect(j.containsKey('duration'), isFalse);
      expect(j.containsKey('id'), isFalse);
    });
    test('有 id 时带上(编辑)', () {
      expect(const TemplateDraft(id: 7, title: 'X').toJson()['id'], 7);
    });
  });
}
