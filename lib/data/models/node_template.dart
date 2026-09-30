/// 节点玩法模板(`cms_member_template`)。
///
/// 对齐小程序 `pages/publish/temp` 的表单 + 后端
/// `ApiMerchantNodeController.validationMethodError` 的校验。
library;

import 'validation_method_labels.dart';

/// 验证方式:玩家到了这个点之后**怎么算完成**。
///
/// ★★ 不同方式要的字段完全不同,而**配不全的后果不是报错,是玩家怎么做都不对**。
///   后端注释原话:「vm=3 比 correctAnswer,且正确项得真有内容 ——
///   缺了后端拿 null 去比,玩家怎么答都错」。
///   所以这道闸在服务端(才算数),但表单也要拦,否则商家要提交完才知道缺什么。
///
/// ★ 这里只放**可创作**的 1–5;码 0/6/7 有码表没表单,别顺手加进来。
enum NodeValidationMethod {
  /// 文字作答:玩家输入一串字,和 questionAnswer 比。
  secretWord(1, '玩家到店后输入你给的暗号'),

  /// 拍照:靠现场照片判,不需要答案。
  photo(2, '玩家拍一张现场照片'),

  /// 选项问答:题目 + 至少两个选项 + 正确项。
  quiz(3, '玩家从选项里选一个'),

  /// 张贴码:扫店里贴的码,不需要答案。
  posterCode(4, '玩家扫你店里贴的那张码'),

  /// GPS:走到附近就算,不需要答案。
  gps(5, '玩家走进范围内自动完成');

  const NodeValidationMethod(this.wire, this.hint);

  final int wire;
  final String hint;

  /// 展示名。★ 与全 App 共用一份 0–7 码表,不在这里另起一套。
  String get label => validationMethodLabel(wire)!;

  /// 这种方式要不要填答案类字段。
  bool get needsAnswer =>
      this == NodeValidationMethod.secretWord || this == NodeValidationMethod.quiz;

  static NodeValidationMethod? fromWire(int? v) {
    for (final NodeValidationMethod m in NodeValidationMethod.values) {
      if (m.wire == v) return m;
    }
    return null;
  }
}

/// 模板草稿(编辑中的状态)。
class NodeTemplateDraft {
  const NodeTemplateDraft({
    this.id,
    this.title = '',
    this.description = '',
    this.imgUrl,
    this.method,
    this.questionAnswer = '',
    this.questionName = '',
    this.optionA = '',
    this.optionB = '',
    this.optionC = '',
    this.optionD = '',
    this.correctAnswer = '',
    this.feedbackText = '',
    this.couponId,
  });

  final int? id;
  final String title;
  final String description;
  final String? imgUrl;

  /// null = 还没选。**不预设一个** —— 预设成"拍照"的话,
  /// 商家可能一路点到提交都没意识到自己选过验证方式。
  final NodeValidationMethod? method;

  /// vm=1 用。
  final String questionAnswer;

  /// vm=3 用。
  final String questionName;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;

  /// vm=3 用,取值 A/B/C/D。
  final String correctAnswer;

  final String feedbackText;
  final int? couponId;

  List<String> get options => <String>[optionA, optionB, optionC, optionD];

  /// 与后端 `validationMethodError` **同口径**的校验。
  ///
  /// 返回 null = 可以提交;否则是该显示给商家的那句话。
  ///
  /// ⚠️ 这是**前端的礼貌**,不是权威 —— 权威在服务端。
  ///   前端拦一道只是为了让商家在填的时候就知道缺什么,
  ///   而不是提交完才被打回。
  String? validate() {
    if (title.trim().isEmpty) return '请填写标题';
    final NodeValidationMethod? m = method;
    // 后端:vm == null 时「不传按老默认走,不在这道闸上收紧」。
    // 但表单不该让人不选就提交 —— 那会落一条谁也说不清怎么完成的玩法。
    if (m == null) return '请选择玩家怎么算完成';

    if (m == NodeValidationMethod.secretWord &&
        questionAnswer.trim().isEmpty) {
      return '文字作答要填答案';
    }

    if (m == NodeValidationMethod.quiz) {
      if (questionName.trim().isEmpty) return '选项问答要填题目';
      final int filled =
          options.where((String o) => o.trim().isNotEmpty).length;
      if (filled < 2) return '选项问答至少要两个选项';
      final String key = correctAnswer.trim().toUpperCase();
      final int idx = 'ABCD'.indexOf(key);
      // ★ 正确项必须是 A-D 之一,**且那一项真有内容** ——
      //   指向空选项等于没答案,玩家怎么选都不对。
      if (key.length != 1 || idx < 0 || options[idx].trim().isEmpty) {
        return '请把正确答案指到一个填了内容的选项上';
      }
    }
    return null;
  }

  /// 提交体。只发后端认的键。
  ///
  /// ★ 不发的字段**不出现在 body 里**(而不是发空串)——
  ///   编辑已有模板时,发空串会把原来填过的内容清掉。
  Map<String, dynamic> toJson() {
    String? nz(String s) => s.trim().isEmpty ? null : s.trim();
    return <String, dynamic>{
      'id': ?id,
      'title': title.trim(),
      'description': ?nz(description),
      'imgUrl': ?imgUrl,
      'validationMethod': ?method?.wire,
      'questionAnswer': ?nz(questionAnswer),
      'questionName': ?nz(questionName),
      'questionA': ?nz(optionA),
      'questionB': ?nz(optionB),
      'questionC': ?nz(optionC),
      'questionD': ?nz(optionD),
      'correctAnswer': ?nz(correctAnswer),
      'feedbackText': ?nz(feedbackText),
      'couponId': ?couponId,
    };
  }

  NodeTemplateDraft copyWith({
    int? id,
    String? title,
    String? description,
    String? imgUrl,
    NodeValidationMethod? method,
    String? questionAnswer,
    String? questionName,
    String? optionA,
    String? optionB,
    String? optionC,
    String? optionD,
    String? correctAnswer,
    String? feedbackText,
    int? couponId,
  }) =>
      NodeTemplateDraft(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        imgUrl: imgUrl ?? this.imgUrl,
        method: method ?? this.method,
        questionAnswer: questionAnswer ?? this.questionAnswer,
        questionName: questionName ?? this.questionName,
        optionA: optionA ?? this.optionA,
        optionB: optionB ?? this.optionB,
        optionC: optionC ?? this.optionC,
        optionD: optionD ?? this.optionD,
        correctAnswer: correctAnswer ?? this.correctAnswer,
        feedbackText: feedbackText ?? this.feedbackText,
        couponId: couponId ?? this.couponId,
      );

  factory NodeTemplateDraft.fromJson(Map<String, dynamic> j) {
    String s(Object? v) => v?.toString() ?? '';
    return NodeTemplateDraft(
      id: j['id'] is num ? (j['id'] as num).toInt() : null,
      title: s(j['title']),
      description: s(j['description']),
      imgUrl: j['imgUrl']?.toString(),
      method: NodeValidationMethod.fromWire(
          j['validationMethod'] is num
              ? (j['validationMethod'] as num).toInt()
              : null),
      questionAnswer: s(j['questionAnswer']),
      questionName: s(j['questionName']),
      optionA: s(j['questionA']),
      optionB: s(j['questionB']),
      optionC: s(j['questionC']),
      optionD: s(j['questionD']),
      correctAnswer: s(j['correctAnswer']),
      feedbackText: s(j['feedbackText']),
      couponId: j['couponId'] is num ? (j['couponId'] as num).toInt() : null,
    );
  }
}
