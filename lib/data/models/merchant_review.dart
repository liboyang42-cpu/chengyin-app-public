enum MerchantReviewStatus {
  visible('VISIBLE', '公开展示中'),
  pendingReview('PENDING_REVIEW', '待平台复核'),
  hidden('HIDDEN', '平台已下架');

  const MerchantReviewStatus(this.wire, this.label);

  final String wire;
  final String label;

  static MerchantReviewStatus parse(Object? value) => values.firstWhere(
    (MerchantReviewStatus status) => status.wire == value,
    orElse: () => throw const MerchantReviewLocalFormatException('评价状态不完整'),
  );
}

enum MerchantReviewMode {
  public('public'),
  manage('manage');

  const MerchantReviewMode(this.wire);

  final String wire;
}

enum MerchantReviewAction { create, reply, report }

class MerchantReviewEligibility {
  const MerchantReviewEligibility({
    required this.canCreate,
    required this.reasonCode,
    required this.registrationId,
  });

  factory MerchantReviewEligibility.fromJson(Map<String, dynamic> json) {
    final bool rawCanCreate = _boolean(json['canCreate'], 'canCreate');
    final String reasonCode = _text(
      json['reasonCode'],
      fallback: 'UNAVAILABLE',
    );
    final int? registrationId = json['registrationId'] == null
        ? null
        : _positiveInt(json['registrationId'], 'registrationId');
    final bool canCreate = rawCanCreate && registrationId != null;
    if (rawCanCreate != canCreate ||
        (canCreate && reasonCode != 'ELIGIBLE') ||
        (!canCreate && reasonCode == 'ELIGIBLE')) {
      throw const MerchantReviewLocalFormatException('评价资格回执不一致');
    }
    return MerchantReviewEligibility(
      canCreate: canCreate,
      reasonCode: reasonCode,
      registrationId: registrationId,
    );
  }

  final bool canCreate;
  final String reasonCode;
  final int? registrationId;

  String get title => switch (reasonCode) {
    'LOGIN_REQUIRED' => '登录后查看评价资格',
    'AMBIGUOUS_LEGACY_MERCHANT_SCOPE' => '该主体有多家门店，暂不可评价',
    'MERCHANT_UNAVAILABLE' => '该门店当前不可评价',
    _ => '当前暂无可评价核销',
  };

  String get subtitle => reasonCode == 'AMBIGUOUS_LEGACY_MERCHANT_SCOPE'
      ? '历史核销尚未保存具体门店，平台不会替你猜测归属。'
      : '只有本人报名且目标门店的 ACTIVE 核销可评价；撤销核销不具备资格。';
}

class MerchantReviewItem {
  const MerchantReviewItem({
    required this.id,
    required this.rating,
    required this.content,
    required this.imageUrls,
    required this.authorNickname,
    required this.authorAvatar,
    required this.verifiedRedemption,
    required this.status,
    required this.merchantReply,
    required this.repliedAt,
    required this.createTime,
    required this.version,
    required this.canReply,
    required this.canReport,
    this.canEditReply = false,
    this.hasAuthorNicknameFallback = false,
  });

  factory MerchantReviewItem.fromJson(Map<String, dynamic> json) {
    final int id = _positiveInt(json['id'], 'id');
    final int rating = _integer(json['rating'], 'rating');
    if (rating < 1 || rating > 5) {
      throw const MerchantReviewLocalFormatException('评分必须在 1 到 5 之间');
    }
    final Object? rawImages = json['imageUrls'];
    if (rawImages is! List || rawImages.length > 9) {
      throw const MerchantReviewLocalFormatException('评价图片不完整');
    }
    final List<Uri> images = rawImages
        .map<Uri>((Object? value) {
          final Uri? uri = Uri.tryParse(value is String ? value.trim() : '');
          if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
            throw const MerchantReviewLocalFormatException('评价图片地址不安全');
          }
          return uri;
        })
        .toList(growable: false);
    final bool verified = _boolean(
      json['verifiedRedemption'],
      'verifiedRedemption',
    );
    final bool canReply = _boolean(json['canReply'], 'canReply');
    final bool canReport = _boolean(json['canReport'], 'canReport');
    // ★ 缺字段按「不能改」降级(快照 view-model.js:102 同口径):
    //   老后端不返回它,宁可少两个按钮,也不能摆一个必然失败的入口。
    final bool canEditReply = json['canEditReply'] == true;
    final MerchantReviewStatus status = MerchantReviewStatus.parse(
      json['status'],
    );
    final String? reply = _optionalText(json['merchantReply']);
    if (canReply && (status != MerchantReviewStatus.visible || reply != null)) {
      throw const MerchantReviewLocalFormatException('评价回复权限与状态不一致');
    }
    if (canReport && status != MerchantReviewStatus.visible) {
      throw const MerchantReviewLocalFormatException('评价举报权限与状态不一致');
    }
    return MerchantReviewItem(
      id: id,
      rating: rating,
      content: _text(json['content']),
      imageUrls: images,
      authorNickname: _text(json['authorNickname'], fallback: '城瘾玩家'),
      hasAuthorNicknameFallback: (json['authorNickname'] as String?)?.trim().isNotEmpty != true,
      authorAvatar: _optionalText(json['authorAvatar']),
      verifiedRedemption: verified,
      status: status,
      merchantReply: reply,
      repliedAt: _optionalDateTime(json['repliedAt']),
      createTime: _optionalDateTime(json['createTime']),
      version: _nonNegativeInt(json['version'], 'version'),
      canReply: canReply,
      canReport: canReport,
      canEditReply: canEditReply,
    );
  }

  final int id;
  final int rating;
  final String content;
  final List<Uri> imageUrls;
  final String authorNickname;
  final bool hasAuthorNicknameFallback;
  final String? authorAvatar;
  final bool verifiedRedemption;
  final MerchantReviewStatus status;
  final String? merchantReply;
  final DateTime? repliedAt;
  final DateTime? createTime;
  final int version;
  final bool canReply;
  final bool canReport;

  /// 已有公开回复、且当前账号还能改/删它(服务端判)。为假时不给
  /// 「修改回复 / 删除回复」入口。
  final bool canEditReply;
}

class MerchantReviewPage {
  const MerchantReviewPage({
    this.mode = MerchantReviewMode.manage,
    required this.pageNum,
    required this.pageSize,
    required this.total,
    required this.hasMore,
    required this.averageRating,
    this.eligibility,
    required this.items,
  });

  factory MerchantReviewPage.fromJson(
    Map<String, dynamic> json, {
    MerchantReviewMode expectedMode = MerchantReviewMode.manage,
    required int expectedPageNum,
    required int expectedPageSize,
  }) {
    if (json['mode'] != expectedMode.wire) {
      throw const MerchantReviewLocalFormatException('评价列表视角不匹配');
    }
    final int pageNum = _positiveInt(json['pageNum'], 'pageNum');
    final int pageSize = _positiveInt(json['pageSize'], 'pageSize');
    if (pageNum != expectedPageNum || pageSize != expectedPageSize) {
      throw const MerchantReviewLocalFormatException('评价分页回执不匹配');
    }
    final int total = _nonNegativeInt(json['total'], 'total');
    final bool hasMore = _boolean(json['hasMore'], 'hasMore');
    final Object? rawItems = json['items'];
    if (rawItems is! List || rawItems.length > pageSize) {
      throw const MerchantReviewLocalFormatException('评价列表不完整');
    }
    final List<MerchantReviewItem> items = rawItems
        .map<MerchantReviewItem>((Object? value) {
          if (value is! Map<String, dynamic>) {
            throw const MerchantReviewLocalFormatException('评价行不完整');
          }
          return MerchantReviewItem.fromJson(value);
        })
        .toList(growable: false);
    if (expectedMode == MerchantReviewMode.public &&
        items.any(
          (MerchantReviewItem item) =>
              item.status != MerchantReviewStatus.visible,
        )) {
      throw const MerchantReviewLocalFormatException('公开列表包含未公开评价');
    }
    final int loadedThrough = (pageNum - 1) * pageSize + items.length;
    if (loadedThrough > total || hasMore != (loadedThrough < total)) {
      throw const MerchantReviewLocalFormatException('评价分页总数不一致');
    }
    final Object? rawAverage = json['averageRating'];
    final double? average = switch (rawAverage) {
      null => null,
      final num value when value >= 1 && value <= 5 => value.toDouble(),
      _ => throw const MerchantReviewLocalFormatException('评价均分不完整'),
    };
    final MerchantReviewEligibility? eligibility;
    if (expectedMode == MerchantReviewMode.public) {
      final Object? rawEligibility = json['eligibility'];
      if (rawEligibility is! Map<String, dynamic>) {
        throw const MerchantReviewLocalFormatException('评价资格回执不完整');
      }
      eligibility = MerchantReviewEligibility.fromJson(rawEligibility);
    } else {
      if (json['eligibility'] != null) {
        throw const MerchantReviewLocalFormatException('商家管理列表不应包含个人资格');
      }
      eligibility = null;
    }
    return MerchantReviewPage(
      mode: expectedMode,
      pageNum: pageNum,
      pageSize: pageSize,
      total: total,
      hasMore: hasMore,
      averageRating: average,
      eligibility: eligibility,
      items: items,
    );
  }

  final MerchantReviewMode mode;
  final int pageNum;
  final int pageSize;
  final int total;
  final bool hasMore;
  final double? averageRating;
  final MerchantReviewEligibility? eligibility;
  final List<MerchantReviewItem> items;

  String get averageRatingText => averageRating?.toStringAsFixed(1) ?? '暂无';
}

class MerchantReviewImageUrlPolicy {
  const MerchantReviewImageUrlPolicy._(this.allowedHosts);

  static const MerchantReviewImageUrlPolicy failClosed =
      MerchantReviewImageUrlPolicy._(<String>{});

  factory MerchantReviewImageUrlPolicy.fromBackendOssConfig({
    required String endpoint,
    required String bucket,
  }) {
    final String normalizedBucket = bucket.trim().toLowerCase();
    if (!RegExp(
      r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$',
    ).hasMatch(normalizedBucket)) {
      throw MerchantReviewLocalArgumentError('OSS bucket 配置不合法');
    }
    final String rawEndpoint = endpoint.trim();
    final Uri? endpointUri = Uri.tryParse(
      rawEndpoint.contains('://') ? rawEndpoint : 'https://$rawEndpoint',
    );
    if (endpointUri == null ||
        (endpointUri.scheme != 'https' && endpointUri.scheme != 'http') ||
        endpointUri.host.isEmpty ||
        endpointUri.userInfo.isNotEmpty ||
        endpointUri.hasPort ||
        (endpointUri.path.isNotEmpty && endpointUri.path != '/') ||
        endpointUri.hasQuery ||
        endpointUri.hasFragment) {
      throw MerchantReviewLocalArgumentError('OSS endpoint 配置不合法');
    }
    final String endpointHost = endpointUri.host.toLowerCase();
    final String expectedHost = endpointHost.startsWith('$normalizedBucket.')
        ? endpointHost
        : '$normalizedBucket.$endpointHost';
    return MerchantReviewImageUrlPolicy._(
      Set<String>.unmodifiable(<String>{expectedHost}),
    );
  }

  MerchantReviewImageUrlPolicy allowingTrustedUploadReceipt(String raw) {
    final String value = raw.trim();
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !_isApprovedReviewUploadUrl(value, <String>{uri.host.toLowerCase()})) {
      throw MerchantReviewLocalArgumentError('上传回执不符合评价图片安全合同');
    }
    return MerchantReviewImageUrlPolicy._(
      Set<String>.unmodifiable(<String>{
        ...allowedHosts,
        uri.host.toLowerCase(),
      }),
    );
  }

  final Set<String> allowedHosts;
}

class MerchantReviewCreateDraft {
  const MerchantReviewCreateDraft({
    required this.merchantRowId,
    required this.registrationId,
    required this.rating,
    required this.content,
    required this.imageUrls,
    this.imageUrlPolicy = MerchantReviewImageUrlPolicy.failClosed,
  });

  final int merchantRowId;
  final int registrationId;
  final int rating;
  final String content;
  final List<String> imageUrls;
  final MerchantReviewImageUrlPolicy imageUrlPolicy;

  String? get validationError {
    if (merchantRowId <= 0 || registrationId <= 0) {
      return '核销资格已失效，请刷新';
    }
    if (rating < 1 || rating > 5) return '请选择 1 到 5 星评分';
    final int length = content.trim().length;
    if (length < 2 || length > 1000) return '评价正文需填写 2 到 1000 字';
    if (imageUrls.length > 9) return '评价图片最多 9 张';
    for (final String raw in imageUrls) {
      if (!_isApprovedReviewUploadUrl(raw, imageUrlPolicy.allowedHosts)) {
        return '评价图片必须来自城瘾安全上传链路';
      }
    }
    return null;
  }

  String get fingerprint =>
      '$merchantRowId|$registrationId|$rating|${content.trim()}|${imageUrls.join(',')}';

  Map<String, dynamic> toJson({required String requestId}) {
    if (validationError != null) throw MerchantReviewLocalArgumentError(validationError);
    _validateRequestId(requestId);
    return <String, dynamic>{
      'merchantRowId': merchantRowId,
      'registrationId': registrationId,
      'rating': rating,
      'content': content.trim(),
      'imageUrls': imageUrls.map((String url) => url.trim()).toList(),
      'requestId': requestId,
    };
  }
}

class MerchantReviewReplyDraft {
  const MerchantReviewReplyDraft({
    required this.reviewId,
    required this.expectedVersion,
    required this.content,
  });

  final int reviewId;
  final int expectedVersion;
  final String content;

  String? get validationError {
    if (reviewId <= 0 || expectedVersion < 0) return '评价状态已失效，请刷新';
    final int length = content.trim().length;
    if (length < 1 || length > 500) return '回复内容需填写 1 到 500 字';
    return null;
  }

  String get fingerprint => '$reviewId|$expectedVersion|${content.trim()}';

  Map<String, dynamic> toJson({required String requestId}) {
    if (validationError != null) throw MerchantReviewLocalArgumentError(validationError);
    _validateRequestId(requestId);
    return <String, dynamic>{
      'reviewId': reviewId,
      'content': content.trim(),
      'expectedVersion': expectedVersion,
      'requestId': requestId,
    };
  }
}

class MerchantReviewReportDraft {
  const MerchantReviewReportDraft({
    required this.reviewId,
    required this.expectedVersion,
    required this.reason,
  });

  final int reviewId;
  final int expectedVersion;
  final String reason;

  String? get validationError {
    if (reviewId <= 0 || expectedVersion < 0) return '评价状态已失效，请刷新';
    final int length = reason.trim().length;
    if (length < 2 || length > 500) return '举报原因需填写 2 到 500 字';
    return null;
  }

  String get fingerprint => '$reviewId|$expectedVersion|${reason.trim()}';

  Map<String, dynamic> toJson({required String requestId}) {
    if (validationError != null) throw MerchantReviewLocalArgumentError(validationError);
    _validateRequestId(requestId);
    return <String, dynamic>{
      'reviewId': reviewId,
      'reason': reason.trim(),
      'expectedVersion': expectedVersion,
      'requestId': requestId,
    };
  }
}

class MerchantReviewReceipt {
  const MerchantReviewReceipt({
    required this.reviewId,
    required this.status,
    required this.version,
    required this.replayed,
    required this.auditTaskId,
  });

  factory MerchantReviewReceipt.fromJson(
    Map<String, dynamic> json, {
    required int expectedReviewId,
    required MerchantReviewAction expectedAction,
  }) {
    final int reviewId = _positiveInt(json['reviewId'], 'reviewId');
    if (reviewId != expectedReviewId) {
      throw const MerchantReviewLocalFormatException('评价操作回执串单');
    }
    final String status = _text(json['status']);
    final int? version = json['version'] == null
        ? null
        : _nonNegativeInt(json['version'], 'version');
    final int? auditTaskId = json['auditTaskId'] == null
        ? null
        : _positiveInt(json['auditTaskId'], 'auditTaskId');
    switch (expectedAction) {
      case MerchantReviewAction.create:
        const Set<String> knownStatuses = <String>{
          'PENDING_REVIEW',
          'VISIBLE',
          'HIDDEN',
        };
        final bool replayed = _boolean(json['replayed'], 'replayed');
        if (!knownStatuses.contains(status) ||
            version == null ||
            (replayed
                ? auditTaskId != null
                : status != 'PENDING_REVIEW' || auditTaskId == null)) {
          throw const MerchantReviewLocalFormatException('评价提交回执不完整');
        }
      case MerchantReviewAction.reply:
        if (status != 'VISIBLE' || version == null) {
          throw const MerchantReviewLocalFormatException('公开回复回执不完整');
        }
      case MerchantReviewAction.report:
        if (status != 'PENDING_PLATFORM_REVIEW' || auditTaskId == null) {
          throw const MerchantReviewLocalFormatException('举报复核回执不完整');
        }
    }
    return MerchantReviewReceipt(
      reviewId: reviewId,
      status: status,
      version: version,
      replayed: _boolean(json['replayed'], 'replayed'),
      auditTaskId: auditTaskId,
    );
  }

  final int reviewId;
  final String status;
  final int? version;
  final bool replayed;
  final int? auditTaskId;
}

int _integer(Object? value, String field) {
  if (value is int) return value;
  throw MerchantReviewLocalFormatException('$field 不完整', field: field);
}

int _positiveInt(Object? value, String field) {
  final int parsed = _integer(value, field);
  if (parsed <= 0) throw MerchantReviewLocalFormatException('$field 不完整', field: field);
  return parsed;
}

int _nonNegativeInt(Object? value, String field) {
  final int parsed = _integer(value, field);
  if (parsed < 0) throw MerchantReviewLocalFormatException('$field 不完整', field: field);
  return parsed;
}

bool _boolean(Object? value, String field) {
  if (value is bool) return value;
  throw MerchantReviewLocalFormatException('$field 不完整', field: field);
}

String _text(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is! String) throw const MerchantReviewLocalFormatException('文本回执不完整');
  return value.trim().isEmpty ? fallback : value.trim();
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const MerchantReviewLocalFormatException('文本回执不完整');
  final String normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null || value == '') return null;
  if (value is! String) throw const MerchantReviewLocalFormatException('时间回执不完整');
  final DateTime? parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (parsed == null) throw const MerchantReviewLocalFormatException('时间回执不完整');
  return parsed;
}

void _validateRequestId(String requestId) {
  if (requestId.isEmpty ||
      requestId.length > 64 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(requestId)) {
    throw MerchantReviewLocalArgumentError('请求标识不合法');
  }
}

bool _isApprovedReviewUploadUrl(String raw, Set<String> allowedHosts) {
  final String value = raw.trim();
  if (value.isEmpty || value.length > 500) return false;
  final Uri? uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      !allowedHosts.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment ||
      !RegExp(
        r'^/upload/[0-9a-f]{32}\.(?:jpg|jpeg|png|gif)$',
      ).hasMatch(uri.path) ||
      value.split('?').first.contains('%')) {
    return false;
  }
  bool hasNonEmpty(String key) =>
      uri.queryParametersAll[key]?.any((String item) => item.isNotEmpty) ??
      false;
  final bool v1 =
      hasNonEmpty('OSSAccessKeyId') &&
      hasNonEmpty('Expires') &&
      hasNonEmpty('Signature');
  final bool v4 =
      hasNonEmpty('x-oss-signature-version') &&
      hasNonEmpty('x-oss-credential') &&
      hasNonEmpty('x-oss-date') &&
      hasNonEmpty('x-oss-expires') &&
      hasNonEmpty('x-oss-signature');
  return v1 || v4;
}

/// Explicit provenance for app-authored schema failures, retaining FormatException compatibility.
class MerchantReviewLocalFormatException extends FormatException {
  const MerchantReviewLocalFormatException(String message, {this.field}) : super(message);
  final String? field;
}

/// App-authored draft/configuration errors; never wraps backend message text.
class MerchantReviewLocalArgumentError extends ArgumentError {
  MerchantReviewLocalArgumentError(String? message) : localMessage = message ?? '', super(message);
  final String localMessage;
}
