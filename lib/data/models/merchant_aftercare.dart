enum MerchantAftercareBucket {
  pending('PENDING', '待回应'),
  processing('PROCESSING', '处理中'),
  completed('COMPLETED', '已完成');

  const MerchantAftercareBucket(this.wire, this.label);

  final String wire;
  final String label;

  static MerchantAftercareBucket parse(Object? value) => values.firstWhere(
    (MerchantAftercareBucket item) => item.wire == value,
    orElse: () => throw const FormatException('未知的售后分组'),
  );
}

enum MerchantAftercareProcessing {
  waitingPlatformReview('WAITING_PLATFORM_REVIEW', '平台审核中', '平台尚未完成退款审核'),
  platformRejected('PLATFORM_REJECTED', '平台未通过退款', '平台审核已结束，款项不会因此退回'),
  refundProcessing('REFUND_PROCESSING', '退款处理中', '平台已批准，款项仍在处理'),
  manualRefundPending('MANUAL_REFUND_PENDING', '等待人工退款', '原路退款异常，平台正在人工处理'),
  manualRefundReview('MANUAL_REFUND_REVIEW', '人工退款待复核', '人工处理已登记，仍待平台复核'),
  refunded('REFUNDED', '平台确认已退款', '平台已确认款项退回'),
  unknown('UNKNOWN', '平台状态待确认', '当前状态无法安全判断，请稍后刷新');

  const MerchantAftercareProcessing(this.wire, this.label, this.hint);

  final String wire;
  final String label;
  final String hint;

  static MerchantAftercareProcessing parse(Object? value) => values.firstWhere(
    (MerchantAftercareProcessing item) => item.wire == value,
    orElse: () => throw const FormatException('未知的平台处理状态'),
  );
}

enum MerchantAftercareOpinion {
  pending('PENDING', '等待商家意见', '尚未追加同意或拒绝意见'),
  agree('AGREE', '商家已同意申请', '这是商家意见，不代表款项已退'),
  reject('REJECT', '商家建议驳回', '这是商家意见，最终结果以平台审核为准');

  const MerchantAftercareOpinion(this.wire, this.label, this.hint);

  final String wire;
  final String label;
  final String hint;

  static MerchantAftercareOpinion parse(Object? value) => values.firstWhere(
    (MerchantAftercareOpinion item) => item.wire == value,
    orElse: () => throw const FormatException('未知的商家意见状态'),
  );
}

enum MerchantAftercareDecision {
  agree('AGREE', '同意申请'),
  reject('REJECT', '建议驳回'),
  evidence('EVIDENCE', '补充凭证');

  const MerchantAftercareDecision(this.wire, this.label);

  final String wire;
  final String label;

  static MerchantAftercareDecision parse(Object? value) => values.firstWhere(
    (MerchantAftercareDecision item) => item.wire == value,
    orElse: () => throw const FormatException('未知的售后意见'),
  );
}

class MerchantAftercareResponse {
  const MerchantAftercareResponse({
    required this.id,
    required this.refundId,
    required this.decision,
    required this.content,
    required this.evidenceUrl,
    required this.actorRoleCode,
    required this.createTime,
  });

  factory MerchantAftercareResponse.fromJson(
    Map<String, dynamic> json, {
    required int expectedRefundId,
  }) {
    final int refundId = _positiveInt(json['refundId'], '退款申请 ID');
    if (refundId != expectedRefundId) {
      throw const FormatException('售后记录与退款申请不匹配');
    }
    return MerchantAftercareResponse(
      id: _positiveInt(json['id'], '售后记录 ID'),
      refundId: refundId,
      decision: MerchantAftercareDecision.parse(json['decision']),
      content: _optionalText(json['content']),
      evidenceUrl: _safeHttpsUri(json['evidenceUrl']),
      actorRoleCode: _optionalText(json['actorRoleCode']),
      createTime: _optionalDateTime(json['createTime']),
    );
  }

  final int id;
  final int refundId;
  final MerchantAftercareDecision decision;
  final String? content;
  final Uri? evidenceUrl;
  final String? actorRoleCode;
  final DateTime? createTime;

  String get actorText => switch (actorRoleCode) {
    'MERCHANT_OWNER' => '店主',
    'MERCHANT_MANAGER' => '店长',
    'MERCHANT_CHECKIN' => '核销员',
    'MERCHANT_MARKETING' => '运营',
    'MERCHANT_FINANCE' => '财务',
    _ => '商家成员',
  };
}

class MerchantAftercareDetail {
  const MerchantAftercareDetail({
    required this.refundId,
    required this.refundNo,
    required this.sourceType,
    required this.sourceId,
    required this.refundAmount,
    required this.reason,
    required this.processing,
    required this.merchantOpinion,
    required this.canRespond,
    required this.allowedDecisions,
    required this.createTime,
    required this.refundPolicyCode,
    required this.refundPolicyVersion,
    required this.refundDeadline,
    required this.responses,
  });

  factory MerchantAftercareDetail.fromJson(
    Map<String, dynamic> json, {
    required int expectedRefundId,
  }) {
    final int refundId = _positiveInt(json['refundId'], '退款申请 ID');
    final MerchantAftercareProcessing processing =
        MerchantAftercareProcessing.parse(json['processing']);
    final Object? rawAllowed = json['allowedDecisions'];
    final Object? rawResponses = json['responses'];
    if (refundId != expectedRefundId ||
        rawAllowed is! List<dynamic> ||
        rawResponses is! List<dynamic>) {
      throw const FormatException('售后详情回执不完整');
    }
    final List<MerchantAftercareDecision> allowed = rawAllowed
        .map(MerchantAftercareDecision.parse)
        .toList(growable: false);
    final bool canRespond = _requiredBool(json['canRespond'], '可回应状态');
    if (allowed.toSet().length != allowed.length ||
        canRespond != allowed.isNotEmpty) {
      throw const FormatException('售后回应权限回执不一致');
    }
    return MerchantAftercareDetail(
      refundId: refundId,
      refundNo: _optionalText(json['refundNo']),
      sourceType: _optionalText(json['sourceType']),
      sourceId: _optionalPositiveInt(json['sourceId']),
      refundAmount: _optionalMoney(json['refundAmount']),
      reason: _optionalText(json['reason']),
      processing: processing,
      merchantOpinion: MerchantAftercareOpinion.parse(json['merchantOpinion']),
      canRespond: canRespond,
      allowedDecisions: allowed,
      createTime: _optionalDateTime(json['createTime']),
      refundPolicyCode: _optionalText(json['refundPolicyCode']),
      refundPolicyVersion: _optionalPositiveInt(json['refundPolicyVersion']),
      refundDeadline: _optionalDateTime(json['refundDeadline']),
      responses: rawResponses
          .map(
            (Object? value) => MerchantAftercareResponse.fromJson(
              _object(value, '售后记录'),
              expectedRefundId: refundId,
            ),
          )
          .toList(growable: false),
    );
  }

  final int refundId;
  final String? refundNo;
  final String? sourceType;
  final int? sourceId;
  final double? refundAmount;
  final String? reason;
  final MerchantAftercareProcessing processing;
  final MerchantAftercareOpinion merchantOpinion;
  final bool canRespond;
  final List<MerchantAftercareDecision> allowedDecisions;
  final DateTime? createTime;
  final String? refundPolicyCode;
  final int? refundPolicyVersion;
  final DateTime? refundDeadline;
  final List<MerchantAftercareResponse> responses;

  bool get refunded => processing == MerchantAftercareProcessing.refunded;
  String get refundNoText => refundNo ?? '#$refundId';
  String get sourceText =>
      sourceType?.toUpperCase() == 'REGISTRATION' ? '报名退款' : '退款申请';
  String get refundAmountText =>
      refundAmount == null ? '金额待确认' : '¥${refundAmount!.toStringAsFixed(2)}';
  String get refundPolicyText => refundPolicyCode == 'EXPLORE_END_100_0'
      ? '截止前未核销可全额申请'
      : refundPolicyCode == null
      ? '退款政策待确认'
      : '退款规则以订单快照为准';
}

class MerchantAftercareResponseDraft {
  MerchantAftercareResponseDraft({
    required this.decision,
    this.content,
    this.evidenceKey,
  });

  final MerchantAftercareDecision decision;
  final String? content;
  final String? evidenceKey;

  String? get validationError {
    final String normalizedContent = content?.trim() ?? '';
    final String normalizedEvidence = evidenceKey?.trim() ?? '';
    if (normalizedContent.length > 500) return '意见内容不能超过500字';
    if (decision == MerchantAftercareDecision.reject &&
        normalizedContent.isEmpty) {
      return '请填写建议驳回的原因';
    }
    if (normalizedEvidence.isNotEmpty &&
        !MerchantAftercareEvidence.isObjectKey(normalizedEvidence)) {
      return '凭证上传结果无效，请重新上传';
    }
    if (decision == MerchantAftercareDecision.evidence &&
        normalizedEvidence.isEmpty) {
      return '请先上传凭证图片';
    }
    return null;
  }

  String get fingerprint => <String>[
    decision.wire,
    content?.trim() ?? '',
    evidenceKey?.trim() ?? '',
  ].join('\u0000');

  Map<String, dynamic> toJson({required String requestId}) {
    if (validationError != null) {
      throw StateError(validationError!);
    }
    final String normalizedRequestId = requestId.trim();
    if (normalizedRequestId.isEmpty ||
        normalizedRequestId.length > 64 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(normalizedRequestId)) {
      throw ArgumentError.value(requestId, 'requestId', '格式不合法');
    }
    final String? normalizedContent = _optionalText(content);
    final String? normalizedEvidence = _optionalText(evidenceKey);
    return <String, dynamic>{
      'decision': decision.wire,
      'content': normalizedContent,
      if (normalizedEvidence != null)
        'evidenceKeys': <String>[normalizedEvidence],
      'requestId': normalizedRequestId,
    };
  }
}

class MerchantAftercareEvidence {
  const MerchantAftercareEvidence({
    required this.objectKey,
    required this.localPath,
  });

  final String objectKey;
  final String localPath;

  static final RegExp _objectKey = RegExp(
    r'^upload/merchant-aftercare-evidence/[0-9a-f]{32}\.(?:jpe?g|png|gif)$',
  );

  static bool isObjectKey(String value) => _objectKey.hasMatch(value.trim());
}

class MerchantAftercareReceipt {
  const MerchantAftercareReceipt({
    required this.id,
    required this.refundId,
    required this.decision,
    required this.processing,
    required this.merchantOpinion,
    required this.refunded,
  });

  factory MerchantAftercareReceipt.fromJson(
    Map<String, dynamic> json, {
    required int expectedRefundId,
    required MerchantAftercareDecision expectedDecision,
  }) {
    final int refundId = _positiveInt(json['refundId'], '退款申请 ID');
    final MerchantAftercareDecision decision = MerchantAftercareDecision.parse(
      json['decision'],
    );
    final MerchantAftercareProcessing processing =
        MerchantAftercareProcessing.parse(json['processing']);
    final bool refunded = _requiredBool(json['refunded'], '退款结果');
    if (refundId != expectedRefundId ||
        decision != expectedDecision ||
        refunded != (processing == MerchantAftercareProcessing.refunded)) {
      throw const FormatException('售后意见提交回执不一致');
    }
    return MerchantAftercareReceipt(
      id: _positiveInt(json['id'], '售后记录 ID'),
      refundId: refundId,
      decision: decision,
      processing: processing,
      merchantOpinion: MerchantAftercareOpinion.parse(json['merchantOpinion']),
      refunded: refunded,
    );
  }

  final int id;
  final int refundId;
  final MerchantAftercareDecision decision;
  final MerchantAftercareProcessing processing;
  final MerchantAftercareOpinion merchantOpinion;
  final bool refunded;
}

class MerchantAftercareListItem {
  const MerchantAftercareListItem({
    required this.refundId,
    required this.refundNo,
    required this.sourceType,
    required this.sourceId,
    required this.refundAmount,
    required this.reason,
    required this.bucket,
    required this.processing,
    required this.merchantOpinion,
    required this.canRespond,
    required this.refunded,
    required this.createTime,
  });

  factory MerchantAftercareListItem.fromJson(
    Map<String, dynamic> json, {
    required MerchantAftercareBucket expectedBucket,
  }) {
    final int refundId = _positiveInt(json['refundId'], '退款申请 ID');
    final MerchantAftercareBucket bucket = MerchantAftercareBucket.parse(
      json['bucket'],
    );
    final MerchantAftercareProcessing processing =
        MerchantAftercareProcessing.parse(json['processing']);
    final bool refunded = _requiredBool(json['refunded'], '退款结果');
    if (bucket != expectedBucket ||
        refunded != (processing == MerchantAftercareProcessing.refunded)) {
      throw const FormatException('售后列表状态不一致');
    }
    return MerchantAftercareListItem(
      refundId: refundId,
      refundNo: _optionalText(json['refundNo']),
      sourceType: _optionalText(json['sourceType']),
      sourceId: _optionalPositiveInt(json['sourceId']),
      refundAmount: _optionalMoney(json['refundAmount']),
      reason: _optionalText(json['reason']),
      bucket: bucket,
      processing: processing,
      merchantOpinion: MerchantAftercareOpinion.parse(json['merchantOpinion']),
      canRespond: _requiredBool(json['canRespond'], '可回应状态'),
      refunded: refunded,
      createTime: _optionalDateTime(json['createTime']),
    );
  }

  final int refundId;
  final String? refundNo;
  final String? sourceType;
  final int? sourceId;
  final double? refundAmount;
  final String? reason;
  final MerchantAftercareBucket bucket;
  final MerchantAftercareProcessing processing;
  final MerchantAftercareOpinion merchantOpinion;
  final bool canRespond;
  final bool refunded;
  final DateTime? createTime;

  String get refundNoText => refundNo ?? '#$refundId';
  String get sourceText =>
      sourceType?.toUpperCase() == 'REGISTRATION' ? '报名退款' : '退款申请';
  String get refundAmountText =>
      refundAmount == null ? '金额待确认' : '¥${refundAmount!.toStringAsFixed(2)}';
  String get processingText => processing.label;
  String get merchantOpinionText => merchantOpinion.label;
}

class MerchantAftercarePage {
  const MerchantAftercarePage({
    required this.bucket,
    required this.pageNum,
    required this.pageSize,
    required this.total,
    required this.hasMore,
    required this.items,
  });

  factory MerchantAftercarePage.fromJson(
    Map<String, dynamic> json, {
    required MerchantAftercareBucket expectedBucket,
    required int expectedPageNum,
  }) {
    final MerchantAftercareBucket bucket = MerchantAftercareBucket.parse(
      json['bucket'],
    );
    final int pageNum = _positiveInt(json['pageNum'], '页码');
    final int pageSize = _positiveInt(json['pageSize'], '每页数量');
    final int total = _nonNegativeInt(json['total'], '总数');
    final bool hasMore = _requiredBool(json['hasMore'], '分页状态');
    final Object? rawItems = json['items'];
    if (bucket != expectedBucket ||
        pageNum != expectedPageNum ||
        pageSize > 50 ||
        rawItems is! List<dynamic>) {
      throw const FormatException('售后列表回执不完整');
    }
    final List<MerchantAftercareListItem> items = rawItems
        .map(
          (Object? value) => MerchantAftercareListItem.fromJson(
            _object(value, '售后列表项'),
            expectedBucket: expectedBucket,
          ),
        )
        .toList(growable: false);
    final int returnedThrough = (pageNum - 1) * pageSize + items.length;
    if (items.length > pageSize ||
        returnedThrough > total ||
        hasMore != (returnedThrough < total) ||
        (hasMore && items.isEmpty)) {
      throw const FormatException('售后列表分页回执不一致');
    }
    return MerchantAftercarePage(
      bucket: bucket,
      pageNum: pageNum,
      pageSize: pageSize,
      total: total,
      hasMore: hasMore,
      items: items,
    );
  }

  final MerchantAftercareBucket bucket;
  final int pageNum;
  final int pageSize;
  final int total;
  final bool hasMore;
  final List<MerchantAftercareListItem> items;
}

Map<String, dynamic> _object(Object? value, String label) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$label不完整');
}

int _positiveInt(Object? value, String label) {
  final int? parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed <= 0 || value is num && parsed != value) {
    throw FormatException('$label不合法');
  }
  return parsed;
}

int _nonNegativeInt(Object? value, String label) {
  final int? parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < 0 || value is num && parsed != value) {
    throw FormatException('$label不合法');
  }
  return parsed;
}

int? _optionalPositiveInt(Object? value) {
  if (value == null || value == '') return null;
  return _positiveInt(value, 'ID');
}

bool _requiredBool(Object? value, String label) {
  if (value is bool) return value;
  throw FormatException('$label不完整');
}

String? _optionalText(Object? value) {
  if (value is! String) return null;
  final String text = value.trim();
  return text.isEmpty ? null : text;
}

double? _optionalMoney(Object? value) {
  if (value == null || value == '') return null;
  final double? amount = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (amount == null || !amount.isFinite || amount < 0) {
    throw const FormatException('退款金额不合法');
  }
  return amount;
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null || value == '') return null;
  final String text = value.toString().trim().replaceFirst(' ', 'T');
  return DateTime.tryParse(text);
}

Uri? _safeHttpsUri(Object? value) {
  if (value is! String) return null;
  final String text = value.trim();
  if (text.isEmpty || RegExp(r'[\s\\]').hasMatch(text)) return null;
  final Uri? uri = Uri.tryParse(text);
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    return null;
  }
  return uri;
}
