/// 专业广场帖文草稿。最终由 [SquareApi] 完成公约确认、媒体登记、
/// 草稿保存与发布送审。
class SquareDraft {
  const SquareDraft({
    this.workflowId = '',
    this.id,
    this.expectedVersion = 0,
    this.sourceLifecycle = 'DRAFT',
    this.contents = '',
    this.pics = const <String>[],
    this.picByteSizes = const <int>[],
    this.picMimeTypes = const <String>[],
    this.picUploadReceipts = const <String>[],
    this.picUploadRequestIds = const <String>[],
    this.existingMediaIds = const <int>[],
    this.existingPicCount = 0,
    this.address,
    this.cityCode,
    this.longitude,
    this.latitude,
    this.dataId,
    this.dataType = 0,
    this.referenceType,
    this.referenceId,
    this.communityId,
    this.audience = 'PUBLIC',
    this.commentPolicy = 'EVERYONE',
    this.replyApprovalEnabled = false,
    this.slowModeSeconds = 0,
    this.disclosureType = 'NONE',
    this.mentionedMemberIds = const <int>[],
    this.safetyLabels = const <String>[],
  });

  /// 一次发帖工作流的稳定命令号。网络超时后重试仍复用它，避免重复建帖。
  final String workflowId;

  /// 有 id 是编辑,没有是新增。
  ///
  /// ⚠️ 编辑时后端会校验 `existing.memberId == 当前用户`,
  ///   不是自己的帖返回「无权编辑该内容」—— 那是权限态,不是故障。
  final int? id;
  final int expectedVersion;
  final String sourceLifecycle;

  /// 正文。后端要求 1-5000 字；图片可选。
  final String contents;

  /// 图片 URL 列表。提交时用**英文分号**连接(后端约定)。
  final List<String> pics;

  /// 与 [pics] 同下标的上传证明。缺任何一项都要求重新选择图片，
  /// 防止客户端伪造对象地址或 MIME。
  final List<int> picByteSizes;
  final List<String> picMimeTypes;
  final List<String> picUploadReceipts;
  final List<String> picUploadRequestIds;
  final List<int> existingMediaIds;
  final int existingPicCount;

  /// Preserve legacy registration keys when a failed image is removed or retried.
  SquareDraft withStableMediaRequests() {
    if (picUploadRequestIds.isNotEmpty || pics.length <= existingPicCount) {
      return this;
    }
    return copyWith(
      picUploadRequestIds: List.generate(
        pics.length - existingPicCount,
        (index) => 'media-$index-$workflowId',
      ),
    );
  }

  final String? address;
  final String? cityCode;
  final String? longitude;
  final String? latitude;

  /// 关联的活动/主题 id。
  final int? dataId;

  /// 0 直接发布 / 1 活动发布 / 2 主题发布。
  final int dataType;
  final String? referenceType;
  final int? referenceId;
  final int? communityId;
  final String audience;
  final String commentPolicy;
  final bool replyApprovalEnabled;
  final int slowModeSeconds;
  final String disclosureType;
  final List<int> mentionedMemberIds;
  final List<String> safetyLabels;

  bool get canSubmit =>
      contents.trim().isNotEmpty &&
      (commentPolicy != 'MENTIONED' || mentionedMemberIds.isNotEmpty);

  /// 草稿允许未完成：有任一可恢复内容即可保存，发布仍走 [canSubmit]。
  bool get canSave =>
      contents.trim().isNotEmpty ||
      pics.isNotEmpty ||
      existingMediaIds.isNotEmpty ||
      (address ?? '').trim().isNotEmpty ||
      referenceId != null ||
      dataId != null ||
      communityId != null ||
      audience != 'PUBLIC' ||
      commentPolicy != 'EVERYONE' ||
      replyApprovalEnabled ||
      slowModeSeconds > 0 ||
      disclosureType != 'NONE' ||
      mentionedMemberIds.isNotEmpty ||
      safetyLabels.isNotEmpty;

  /// 不能提交时说出缺什么。
  String? get blocker {
    if (contents.trim().isEmpty) return '写点什么再发吧';
    if (commentPolicy == 'MENTIONED' && mentionedMemberIds.isEmpty) {
      return '请先选择可以回复的人';
    }
    return null;
  }

  /// 关联态是否自洽。★ dataType 说了要关联,却没有 dataId,
  ///   后端会存下一条指向空的记录 —— 前端先拦住。
  bool get linkConsistent {
    final hasTypedReference =
        (referenceType ?? '').isNotEmpty || referenceId != null;
    if (hasTypedReference) {
      return const <String>{
            'ACTIVITY',
            'TOPIC',
            'ROUTE',
            'CLUB',
            'POI',
          }.contains(referenceType) &&
          referenceId != null &&
          referenceId! > 0;
    }
    return dataType == 0 ? true : (dataId != null && dataId! > 0);
  }

  SquareDraft copyWith({
    String? workflowId,
    int? id,
    int? expectedVersion,
    String? sourceLifecycle,
    String? contents,
    List<String>? pics,
    List<int>? picByteSizes,
    List<String>? picMimeTypes,
    List<String>? picUploadReceipts,
    List<String>? picUploadRequestIds,
    List<int>? existingMediaIds,
    int? existingPicCount,
    String? address,
    String? cityCode,
    String? longitude,
    String? latitude,
    int? dataId,
    int? dataType,
    String? referenceType,
    int? referenceId,
    int? communityId,
    String? audience,
    String? commentPolicy,
    bool? replyApprovalEnabled,
    int? slowModeSeconds,
    String? disclosureType,
    List<int>? mentionedMemberIds,
    List<String>? safetyLabels,
  }) {
    return SquareDraft(
      workflowId: workflowId ?? this.workflowId,
      id: id ?? this.id,
      expectedVersion: expectedVersion ?? this.expectedVersion,
      sourceLifecycle: sourceLifecycle ?? this.sourceLifecycle,
      contents: contents ?? this.contents,
      pics: pics ?? this.pics,
      picByteSizes: picByteSizes ?? this.picByteSizes,
      picMimeTypes: picMimeTypes ?? this.picMimeTypes,
      picUploadReceipts: picUploadReceipts ?? this.picUploadReceipts,
      picUploadRequestIds: picUploadRequestIds ?? this.picUploadRequestIds,
      existingMediaIds: existingMediaIds ?? this.existingMediaIds,
      existingPicCount: existingPicCount ?? this.existingPicCount,
      address: address ?? this.address,
      cityCode: cityCode ?? this.cityCode,
      longitude: longitude ?? this.longitude,
      latitude: latitude ?? this.latitude,
      dataId: dataId ?? this.dataId,
      dataType: dataType ?? this.dataType,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      communityId: communityId ?? this.communityId,
      audience: audience ?? this.audience,
      commentPolicy: commentPolicy ?? this.commentPolicy,
      replyApprovalEnabled: replyApprovalEnabled ?? this.replyApprovalEnabled,
      slowModeSeconds: slowModeSeconds ?? this.slowModeSeconds,
      disclosureType: disclosureType ?? this.disclosureType,
      mentionedMemberIds: mentionedMemberIds ?? this.mentionedMemberIds,
      safetyLabels: safetyLabels ?? this.safetyLabels,
    );
  }

  /// 取消关联。★ 必须**同时**清掉 dataId 和 dataType ——
  ///   只清一个会留下自相矛盾的状态。copyWith 做不到(它把 null 当"不改")。
  SquareDraft withoutLink() => SquareDraft(
    workflowId: workflowId,
    id: id,
    expectedVersion: expectedVersion,
    sourceLifecycle: sourceLifecycle,
    contents: contents,
    pics: pics,
    picByteSizes: picByteSizes,
    picMimeTypes: picMimeTypes,
    picUploadReceipts: picUploadReceipts,
    picUploadRequestIds: picUploadRequestIds,
    existingMediaIds: existingMediaIds,
    existingPicCount: existingPicCount,
    address: address,
    cityCode: cityCode,
    longitude: longitude,
    latitude: latitude,
    dataId: null,
    dataType: 0,
    referenceType: null,
    referenceId: null,
    communityId: null,
    audience: audience == 'COMMUNITY' ? 'PUBLIC' : audience,
    commentPolicy: commentPolicy == 'MEMBERS' ? 'EVERYONE' : commentPolicy,
    replyApprovalEnabled: replyApprovalEnabled,
    slowModeSeconds: slowModeSeconds,
    disclosureType: disclosureType,
    mentionedMemberIds: mentionedMemberIds,
    safetyLabels: safetyLabels,
  );

  Map<String, dynamic> toForm() => <String, dynamic>{
    if (id != null) 'id': id.toString(),
    'contents': contents.trim(),
    // 空图片列表**不传空串** —— 后端 isNotEmpty 判空,传 '' 与不传等价,
    // 但显式传空串会让日志里多出无意义的字段。
    if (pics.isNotEmpty) 'pics': pics.join(';'),
    if ((address ?? '').isNotEmpty) 'address': address,
    if ((longitude ?? '').isNotEmpty) 'longitude': longitude,
    if ((latitude ?? '').isNotEmpty) 'latitude': latitude,
    if (dataId != null && dataId! > 0) 'data_id': dataId.toString(),
    'data_type': dataType.toString(),
  };
}
