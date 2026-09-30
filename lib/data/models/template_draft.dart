/// 与后端 `CmsTemplatePublishRequest` 一一对应的模板草稿。
/// 四个 `*Enabled` 只是页面模块状态，不进提交 payload。
class TemplateDraft {
  const TemplateDraft({
    this.id,
    this.originalTemplateId,
    this.title = '',
    this.description = '',
    this.imgUrl,
    this.players,
    this.duration,
    this.difficulty,
    this.usageLocation,
    this.requiredMaterials,
    this.ruleInstructions,
    this.categoryId,
    this.activityCategoryids,
    this.isSync = 1,
    this.finishEnabled = true,
    this.validationMethod = 0,
    this.questionName,
    this.questionAnswer,
    this.questionA,
    this.questionB,
    this.questionC,
    this.questionD,
    this.correctAnswer,
    this.questionImg,
    this.questionAudio,
    this.questionOptionMediaJson,
    this.hint1,
    this.hint2,
    this.answerReveal,
    this.photoRequireDesc,
    this.photoReview = 0,
    this.rewardEnabled = true,
    this.feedbackText,
    this.couponId,
    this.medalImg,
    this.medalName,
    this.storyEnabled = false,
    this.storyText,
    this.storyImg,
    this.storyJson,
    this.voiceEnabled = false,
    this.audioUrl,
    this.audioDuration,
    this.advancedConfigJson,
  });

  final int? id,
      originalTemplateId,
      duration,
      categoryId,
      couponId,
      audioDuration;
  final String title, description;
  final String? imgUrl,
      players,
      difficulty,
      usageLocation,
      requiredMaterials,
      ruleInstructions,
      activityCategoryids,
      questionName,
      questionAnswer,
      questionA,
      questionB,
      questionC,
      questionD,
      correctAnswer,
      questionImg,
      questionAudio,
      questionOptionMediaJson,
      hint1,
      hint2,
      answerReveal,
      photoRequireDesc,
      feedbackText,
      medalImg,
      medalName,
      storyText,
      storyImg,
      storyJson,
      audioUrl,
      advancedConfigJson;
  final int isSync, validationMethod, photoReview;
  final bool finishEnabled, rewardEnabled, storyEnabled, voiceEnabled;

  bool get canSaveDraft => title.trim().isNotEmpty;
  String? get draftBlocker => title.trim().isEmpty ? '先给玩法起个名字' : null;

  /// 对齐小程序 `temp::_collectValidationErrors(false)`。
  String? get publishBlocker {
    if (title.trim().isEmpty) return '先给玩法起个名字';
    if (description.trim().isEmpty) return '请填写玩法描述';
    if (description.trim().length > 30) return '玩法描述不超过 30 字';
    if ((players ?? '').trim().isEmpty) return '请选择玩家人数';
    if (duration == null) return '请选择玩法时长';
    if (duration! <= 0) return '时长要大于 0';
    if ((activityCategoryids ?? '').trim().isEmpty && categoryId == null) {
      return '请选择至少一个玩法类别';
    }
    if (!finishEnabled) return '请添加「完成方式」并选择一种玩法';
    if (validationMethod == 1 &&
        ((questionName ?? '').trim().isEmpty ||
            (questionAnswer ?? '').trim().isEmpty)) {
      return '请填写问题和正确答案';
    }
    if (validationMethod == 3) {
      if ((questionName ?? '').trim().isEmpty) return '请填写问题';
      final count = <String?>[
        questionA,
        questionB,
        questionC,
        questionD,
      ].where((v) => (v ?? '').trim().isNotEmpty).length;
      if (count < 2) return '至少需要 2 个选项';
      if ((correctAnswer ?? '').trim().isEmpty) return '请设置正确答案';
    }
    if (rewardEnabled) {
      final coupon = (couponId ?? 0) > 0;
      final text = (feedbackText ?? '').trim().isNotEmpty;
      final medalImage = (medalImg ?? '').trim().isNotEmpty;
      final medalTitle = (medalName ?? '').trim().isNotEmpty;
      if (!coupon && !text && !medalImage && !medalTitle) return '请至少配置一种奖励';
      if (medalImage != medalTitle) return '勋章需同时上传图片和填写名称';
    }
    if (voiceEnabled && (audioUrl ?? '').trim().isEmpty) return '请上传音频文件';
    return null;
  }

  bool get canPublish => publishBlocker == null;
  static const _unset = Object();

  TemplateDraft copyWith({
    Object? id = _unset,
    Object? originalTemplateId = _unset,
    String? title,
    String? description,
    Object? imgUrl = _unset,
    Object? players = _unset,
    Object? duration = _unset,
    Object? difficulty = _unset,
    Object? usageLocation = _unset,
    Object? requiredMaterials = _unset,
    Object? ruleInstructions = _unset,
    Object? categoryId = _unset,
    Object? activityCategoryids = _unset,
    int? isSync,
    bool? finishEnabled,
    int? validationMethod,
    Object? questionName = _unset,
    Object? questionAnswer = _unset,
    Object? questionA = _unset,
    Object? questionB = _unset,
    Object? questionC = _unset,
    Object? questionD = _unset,
    Object? correctAnswer = _unset,
    Object? questionImg = _unset,
    Object? questionAudio = _unset,
    Object? questionOptionMediaJson = _unset,
    Object? hint1 = _unset,
    Object? hint2 = _unset,
    Object? answerReveal = _unset,
    Object? photoRequireDesc = _unset,
    int? photoReview,
    bool? rewardEnabled,
    Object? feedbackText = _unset,
    Object? couponId = _unset,
    Object? medalImg = _unset,
    Object? medalName = _unset,
    bool? storyEnabled,
    Object? storyText = _unset,
    Object? storyImg = _unset,
    Object? storyJson = _unset,
    bool? voiceEnabled,
    Object? audioUrl = _unset,
    Object? audioDuration = _unset,
    Object? advancedConfigJson = _unset,
  }) {
    T? v<T>(Object? next, T? current) =>
        identical(next, _unset) ? current : next as T?;
    return TemplateDraft(
      id: v<int>(id, this.id),
      originalTemplateId: v<int>(originalTemplateId, this.originalTemplateId),
      title: title ?? this.title,
      description: description ?? this.description,
      imgUrl: v<String>(imgUrl, this.imgUrl),
      players: v<String>(players, this.players),
      duration: v<int>(duration, this.duration),
      difficulty: v<String>(difficulty, this.difficulty),
      usageLocation: v<String>(usageLocation, this.usageLocation),
      requiredMaterials: v<String>(requiredMaterials, this.requiredMaterials),
      ruleInstructions: v<String>(ruleInstructions, this.ruleInstructions),
      categoryId: v<int>(categoryId, this.categoryId),
      activityCategoryids: v<String>(
        activityCategoryids,
        this.activityCategoryids,
      ),
      isSync: isSync ?? this.isSync,
      finishEnabled: finishEnabled ?? this.finishEnabled,
      validationMethod: validationMethod ?? this.validationMethod,
      questionName: v<String>(questionName, this.questionName),
      questionAnswer: v<String>(questionAnswer, this.questionAnswer),
      questionA: v<String>(questionA, this.questionA),
      questionB: v<String>(questionB, this.questionB),
      questionC: v<String>(questionC, this.questionC),
      questionD: v<String>(questionD, this.questionD),
      correctAnswer: v<String>(correctAnswer, this.correctAnswer),
      questionImg: v<String>(questionImg, this.questionImg),
      questionAudio: v<String>(questionAudio, this.questionAudio),
      questionOptionMediaJson: v<String>(
        questionOptionMediaJson,
        this.questionOptionMediaJson,
      ),
      hint1: v<String>(hint1, this.hint1),
      hint2: v<String>(hint2, this.hint2),
      answerReveal: v<String>(answerReveal, this.answerReveal),
      photoRequireDesc: v<String>(photoRequireDesc, this.photoRequireDesc),
      photoReview: photoReview ?? this.photoReview,
      rewardEnabled: rewardEnabled ?? this.rewardEnabled,
      feedbackText: v<String>(feedbackText, this.feedbackText),
      couponId: v<int>(couponId, this.couponId),
      medalImg: v<String>(medalImg, this.medalImg),
      medalName: v<String>(medalName, this.medalName),
      storyEnabled: storyEnabled ?? this.storyEnabled,
      storyText: v<String>(storyText, this.storyText),
      storyImg: v<String>(storyImg, this.storyImg),
      storyJson: v<String>(storyJson, this.storyJson),
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      audioUrl: v<String>(audioUrl, this.audioUrl),
      audioDuration: v<int>(audioDuration, this.audioDuration),
      advancedConfigJson: v<String>(
        advancedConfigJson,
        this.advancedConfigJson,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final bool question =
        finishEnabled && (validationMethod == 1 || validationMethod == 3);
    final bool choice = finishEnabled && validationMethod == 3;
    final bool photo = finishEnabled && validationMethod == 2;
    final bool hint =
        finishEnabled && const <int>{1, 3, 5}.contains(validationMethod);
    return <String, dynamic>{
      'id': ?id,
      'originalTemplateId': ?originalTemplateId,
      'categoryId': ?categoryId,
      'title': title.trim(),
      'description': description.trim(),
      'imgUrl': ?imgUrl,
      'players': ?players,
      'usageLocation': ?usageLocation,
      'requiredMaterials': ?requiredMaterials,
      'duration': ?duration,
      'difficulty': ?difficulty,
      'isSync': isSync,
      'ruleInstructions': ?ruleInstructions,
      'activityCategoryids': ?activityCategoryids,
      if (finishEnabled) 'validationMethod': validationMethod,
      if (question) 'questionName': ?questionName,
      if (validationMethod == 1 && finishEnabled)
        'questionAnswer': ?questionAnswer,
      if (question) 'questionImg': ?questionImg,
      if (question) 'questionAudio': ?questionAudio,
      if (choice) 'questionA': ?questionA,
      if (choice) 'questionB': ?questionB,
      if (choice) 'questionC': ?questionC,
      if (choice) 'questionD': ?questionD,
      if (choice) 'correctAnswer': ?correctAnswer,
      if (choice) 'questionOptionMediaJson': ?questionOptionMediaJson,
      if (hint) 'hint1': ?hint1,
      if (hint) 'hint2': ?hint2,
      if (hint) 'answerReveal': ?answerReveal,
      if (photo) 'photoRequireDesc': ?photoRequireDesc,
      if (photo) 'photoReview': photoReview,
      if (rewardEnabled) 'feedbackText': ?feedbackText,
      if (rewardEnabled) 'couponId': ?couponId,
      if (rewardEnabled) 'medalImg': ?medalImg,
      if (rewardEnabled) 'medalName': ?medalName,
      if (storyEnabled) 'storyText': ?storyText,
      if (storyEnabled) 'storyImg': ?storyImg,
      if (storyEnabled) 'storyJson': ?storyJson,
      if (voiceEnabled) 'audioUrl': ?audioUrl,
      if (voiceEnabled) 'audioDuration': ?audioDuration,
      // 高级玩法配置:编辑器写进 `_advanced` map,序列化后原样上送。空串 = 没配。
      if (finishEnabled && (advancedConfigJson ?? '').trim().isNotEmpty)
        'advancedConfigJson': advancedConfigJson,
    };
  }
}

class TemplatePublishException implements Exception {
  TemplatePublishException(this.message);
  final String message;
  bool get isDuplicateName => message.contains('已存在');
  bool get isContentRejected =>
      !message.contains('网络') &&
      !message.contains('稍后重试') &&
      const ['违规', '敏感', '不合规', '含有'].any(message.contains);
  bool get retryable => !isDuplicateName && !isContentRejected;
  @override
  String toString() => message;
}
