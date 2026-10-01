// 节点玩法模板的校验,与后端 validationMethodError 逐条同口径。
//
// ★★ 配不全的后果**不是提交报错,是玩家怎么做都不对**。后端注释原话:
//   「vm=3 比 correctAnswer,且正确项得真有内容 ——
//     缺了后端拿 null 去比,玩家怎么答都错」。
//   闸在服务端才算数;表单也拦一道,只是为了让商家在填的时候就知道缺什么。
//
// ★★ 最容易犯又最难发现的一条:**正确答案指到一个空选项**。
//   题目在、选项有两个、正确答案也选了 —— 看起来全填了,
//   但指的那个选项是空的,玩家怎么选都不对。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/l10n/app_localizations_zh.dart';

import 'package:chengyin_app/data/models/node_template.dart';
import '../../support/source_text.dart';

NodeTemplateDraft d({
  String title = '拍张照',
  NodeValidationMethod? method,
  String questionAnswer = '',
  String questionName = '',
  String a = '',
  String b = '',
  String c = '',
  String dd = '',
  String correct = '',
}) =>
    NodeTemplateDraft(
      title: title,
      method: method,
      questionAnswer: questionAnswer,
      questionName: questionName,
      optionA: a,
      optionB: b,
      optionC: c,
      optionD: dd,
      correctAnswer: correct,
    );

void main() {
  group('基础', () {
    test('没填标题', () {
      expect(d(title: '', method: NodeValidationMethod.photo).validate(),
          '请填写标题');
    });

    test('★ 没选验证方式就不许提交', () {
      // 后端 vm==null 时「不传按老默认走」,但表单不该让人不选就交 ——
      // 那会落一条谁也说不清怎么完成的玩法。
      expect(d().validate(), '请选择玩家怎么算完成');
    });

    test('不需要答案的三种直接过', () {
      for (final NodeValidationMethod m in <NodeValidationMethod>[
        NodeValidationMethod.photo,
        NodeValidationMethod.posterCode,
        NodeValidationMethod.gps,
      ]) {
        expect(d(method: m).validate(), isNull, reason: '${m.label} 不该要答案');
        expect(m.needsAnswer, isFalse);
      }
    });
  });

  group('文字作答(vm=1)', () {
    test('缺答案', () {
      expect(d(method: NodeValidationMethod.secretWord).validate(),
          '文字作答要填答案');
    });

    test('只有空格也算缺', () {
      expect(
        d(method: NodeValidationMethod.secretWord, questionAnswer: '   ')
            .validate(),
        '文字作答要填答案',
      );
    });

    test('填了就过', () {
      expect(
        d(method: NodeValidationMethod.secretWord, questionAnswer: '城瘾')
            .validate(),
        isNull,
      );
    });
  });

  group('选项问答(vm=3)', () {
    test('缺题目', () {
      expect(d(method: NodeValidationMethod.quiz).validate(), '选项问答要填题目');
    });

    test('只有一个选项', () {
      expect(
        d(method: NodeValidationMethod.quiz, questionName: '本店招牌是?', a: '手冲')
            .validate(),
        '选项问答至少要两个选项',
      );
    });

    test('两个选项但没指正确答案', () {
      expect(
        d(
          method: NodeValidationMethod.quiz,
          questionName: '本店招牌是?',
          a: '手冲',
          b: '拿铁',
        ).validate(),
        '请把正确答案指到一个填了内容的选项上',
      );
    });

    test('★★ 正确答案指到**空选项** —— 看起来全填了,其实玩家怎么选都不对', () {
      expect(
        d(
          method: NodeValidationMethod.quiz,
          questionName: '本店招牌是?',
          a: '手冲',
          b: '拿铁',
          correct: 'C', // C 是空的
        ).validate(),
        '请把正确答案指到一个填了内容的选项上',
      );
    });

    test('正确答案不是 A-D', () {
      for (final String bad in <String>['E', '1', 'AB', '']) {
        expect(
          d(
            method: NodeValidationMethod.quiz,
            questionName: 'x',
            a: '1',
            b: '2',
            correct: bad,
          ).validate(),
          '请把正确答案指到一个填了内容的选项上',
          reason: '「$bad」不该被接受',
        );
      }
    });

    test('小写也认(后端 toUpperCase)', () {
      expect(
        d(
          method: NodeValidationMethod.quiz,
          questionName: 'x',
          a: '1',
          b: '2',
          correct: 'b',
        ).validate(),
        isNull,
      );
    });

    test('配全了就过', () {
      expect(
        d(
          method: NodeValidationMethod.quiz,
          questionName: '本店招牌是?',
          a: '手冲',
          b: '拿铁',
          correct: 'A',
        ).validate(),
        isNull,
      );
    });
  });

  group('提交体', () {
    test('★ 空字段**不出现**在 body 里,而不是发空串', () {
      // 编辑已有模板时,发空串会把原来填过的内容清掉。
      final Map<String, dynamic> j =
          d(method: NodeValidationMethod.photo).toJson();
      expect(j.keys.toSet(), <String>{'title', 'validationMethod'});
      expect(j['validationMethod'], 2);
    });

    test('选项问答把四个选项按后端键名发', () {
      final Map<String, dynamic> j = d(
        method: NodeValidationMethod.quiz,
        questionName: 'x',
        a: '1',
        b: '2',
        correct: 'A',
      ).toJson();
      // 后端实体是 questionA..questionD,不是 optionA。
      expect(j['questionA'], '1');
      expect(j['questionB'], '2');
      expect(j.containsKey('optionA'), isFalse);
    });

    test('五种方式的 wire 值与后端一致', () {
      expect(
        <NodeValidationMethod, int>{
          for (final NodeValidationMethod m in NodeValidationMethod.values)
            m: m.wire,
        },
        <NodeValidationMethod, int>{
          NodeValidationMethod.secretWord: 1,
          NodeValidationMethod.photo: 2,
          NodeValidationMethod.quiz: 3,
          NodeValidationMethod.posterCode: 4,
          NodeValidationMethod.gps: 5,
        },
      );
    });
  });

  group('页面', () {
    final String page =
        codeOf('lib/feature/merchant/node_template_edit_page.dart');

    test('★★ 按验证方式只显示要填的那几栏', () {
      expect(page.contains('if (m == NodeValidationMethod.secretWord)'), isTrue);
      expect(page.contains('if (m == NodeValidationMethod.quiz)'), isTrue);
    });

    test('★ 验证方式初值是 null,不预设', () {
      expect(page.contains('NodeValidationMethod.photo;'), isFalse,
          reason: '预设一个的话,商家可能一路点到提交都没意识到自己选过');
    });

    test('★★ 说清"指到空选项等于没答案"', () {
      expect(page.contains('merchantNodeCorrectAnswerHint'), isTrue,
          reason: '那是最容易犯又最难发现的错 —— 不说的话商家看不出问题在哪');
    });

    test('★ 提交前本地先拦一道,服务端的话术仍原文显示', () {
      expect(page.contains('d.validate()'), isTrue);
      expect(page.contains('_error = e.message'), isTrue,
          reason: '服务端知道全部规则,它的话比本地的准');
    });

    test('★ 免人工审要说清 —— 免得商家一直等审核', () {
      expect(page.contains('merchantNodeImmediateEffect'), isTrue);
      expect(AppLocalizationsZh().merchantNodeImmediateEffect, contains('保存后即刻生效'));
      expect(AppLocalizationsZh().merchantNodeCorrectAnswerHint, contains('指到空的等于没答案'));
    });

    test('五种方式各带一句说明', () {
      for (final NodeValidationMethod m in NodeValidationMethod.values) {
        expect(m.hint.isNotEmpty, isTrue,
            reason: '只写名字的话,商家分不清「到店扫码」和「拍照打卡」差在哪');
      }
    });
  });

  test('★★ 不能保存时说出是哪一条,而不是给个可点的按钮', () {
    // 与「据点报名」「提现」两页一致。2026-08-19 看 golden 图发现这页漏了:
    // 没选验证方式时「保存」仍是可点的白色主按钮,点了才报错。
    final String page =
        codeOf('lib/feature/merchant/node_template_edit_page.dart');
    expect(page.contains('String? get _blocker => _current.validate();'), isTrue,
        reason: '按钮的可点状态必须与提交校验用**同一份**判据,否则两者会漂');
    expect(page.contains('onPressed: (_saving || _blocker != null) ? null : _save'),
        isTrue,
        reason: '还差东西时按钮该是禁用的');
    expect(page.contains('if (_blocker != null)'), isTrue,
        reason: '禁用了还得说出是哪一条 —— 灰按钮不说话等于让用户猜');
  });
}
