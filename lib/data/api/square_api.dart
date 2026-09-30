import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/square_post.dart';
import '../models/square_draft.dart';
import '../models/community_report_reason.dart';

class SquareApiException implements Exception {
  const SquareApiException(this.code, this.message);

  final int? code;
  final String message;

  bool get isStaleReportPolicy => message.contains('举报规则版本已更新');

  @override
  String toString() => message;
}

/// 广场接口。**两代并存,按端点分,不按页分**:
///
/// - 帖文读取 / 点赞 / 举报 / 删除 与评论五件套走**线上真实契约**
///   `/api/creativesquare/*`、`/api/comment/*` —— 与小程序同源,见
///   `contract/openapi-v1.json`(线上 springdoc 冻的 v1 基线)与后端
///   `ApiCreativeSquareController` / `ApiCommentController`。
/// - 草稿 / 通知 / 治理 / 发布工作流仍是 `/api/v1/community/*`:
///   2026-09-17 实测后端 `github/master@1b3ca1c` 与冻结契约里都**定不到**
///   这些路由,属未落地的新世代 —— 页面按未接通处理,不伪造。
class SquareApi {
  SquareApi(this._client);
  final DioClient _client;

  Future<List<SquarePost>> list({
    int isMy = 0,
    String? keyword,
    int? userId,
    String? cityCode,
    SquareFeedMode feedMode = SquareFeedMode.latest,
    int? cursor,
    int? cursorScore,
    String? topicCode,
    int? communityId,
  }) async => (await listPage(
    isMy: isMy,
    keyword: keyword,
    userId: userId,
    cityCode: cityCode,
    feedMode: feedMode,
    cursor: cursor,
    cursorScore: cursorScore,
    topicCode: topicCode,
    communityId: communityId,
  )).items;

  Future<SquareFeedPage> listPage({
    int isMy = 0,
    String? keyword,
    int? userId,
    String? cityCode,
    SquareFeedMode feedMode = SquareFeedMode.latest,
    int? cursor,
    int? cursorScore,
    String? topicCode,
    int? communityId,
  }) async {
    final query = <String, dynamic>{'limit': 30};
    if (cursor != null && cursor > 0) query['cursor'] = cursor;
    if (cursorScore != null) query['cursorScore'] = cursorScore;
    if (keyword != null && keyword.isNotEmpty) query['keyword'] = keyword;
    if (userId != null && userId > 0) query['authorId'] = userId;
    if (feedMode == SquareFeedMode.nearby) {
      if ((cityCode ?? '').trim().isEmpty) {
        throw StateError('附近动态需要先选择城市');
      }
      query['cityCode'] = cityCode!.trim();
    }
    if (feedMode == SquareFeedMode.featured) {
      query['collectionCode'] = 'CITY_PICK';
    }
    if (feedMode == SquareFeedMode.topic) {
      if ((topicCode ?? '').trim().isEmpty) {
        throw StateError('话题动态需要先选择话题');
      }
      query['topicCode'] = topicCode!.trim();
    }
    if (feedMode == SquareFeedMode.community) {
      if ((communityId ?? 0) <= 0) {
        throw StateError('社群动态需要先选择社群');
      }
      query['communityId'] = communityId;
    }
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/feeds/${feedMode.apiValue}',
      queryParameters: query,
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final rows = (data['items'] as List<dynamic>?) ?? <dynamic>[];
    final items = rows
        .map((dynamic e) => SquarePost.fromJson(e as Map<String, dynamic>))
        .toList();
    return SquareFeedPage(
      items: items,
      hasMore: data['hasMore'] == true,
      nextCursor: (data['nextCursor'] as num?)?.toInt(),
      nextCursorScore: (data['nextCursorScore'] as num?)?.toInt(),
    );
  }

  /// 帖文详情。后端把「已删除 / 审核中 / 数据不存在」直接当 msg 返回,
  /// 由页面原样展示(不编兜底文案)。
  Future<SquarePost> info(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/creativesquare/info',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return SquarePost.fromJson(data);
  }

  /// 帖文点赞。`/api/creativesquare/like` 是**切换式**的(已赞再调一次即取消,
  /// `type` 1 赞 / 2 踩),没有显式态参数 —— 调用方只在状态翻转时发一次,
  /// 一次请求 = 一次翻转。
  Future<void> like(int id, {int type = 1}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/creativesquare/like',
      data: FormData.fromMap(<String, dynamic>{
        'id': id.toString(),
        'type': type.toString(),
      }),
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  /// 发帖 / 改帖 —— 真实契约 `/api/creativesquare/action`,小程序两处发布入口
  /// (`pages/square/list` 的内嵌编辑器、`components/cy/post-compose`)共用的唯一端点。
  ///
  /// 字段与小程序逐一对齐(后端 `ApiCreativeSquareController#creativeSquareActoin`):
  /// - `contents` 必填,空则后端回「请输入发布内容」;
  /// - `pics` 英文分号连接,**只有新建发** —— 编辑态后端按 R10-06「未提交字段不清空」
  ///   保留原图,发了反而会覆盖;
  /// - `data_id`/`data_type` 新建**与编辑都得发**:后端对关联是「无值即清 0」,
  ///   编辑不重发就把旧关联清掉了(小程序为此在编辑态专门重发这一对);
  /// - `request_id` 只服务新建:后端按它做幂等发布(重试复用同键,不重复发帖),
  ///   格式 `[A-Za-z0-9_-]{16,64}`;编辑是幂等 update,不占意图键。
  ///
  /// 失败抛 [SquarePublishException],message 是后端原话(「无权编辑该内容」/
  /// 「内容未通过审核，请修改后重新发布」/「只能关联自己主办或报名过的活动」…);
  /// 网络失败不在这里翻译,原样抛给页面。
  Future<void> publishPost({
    int? id,
    required String contents,
    List<String> pics = const <String>[],
    String? address,
    String? longitude,
    String? latitude,
    int? dataId,
    int? dataType,
    String? requestId,
  }) async {
    final bool editing = (id ?? 0) > 0;
    final Map<String, dynamic> form = <String, dynamic>{'contents': contents};
    if (editing) {
      form['id'] = '$id';
    } else {
      form['pics'] = pics.join(';');
      if ((address ?? '').trim().isNotEmpty) form['address'] = address;
      if ((longitude ?? '').trim().isNotEmpty) form['longitude'] = longitude;
      if ((latitude ?? '').trim().isNotEmpty) form['latitude'] = latitude;
      if ((requestId ?? '').trim().isNotEmpty) form['request_id'] = requestId;
    }
    if ((dataId ?? 0) > 0) {
      form['data_id'] = '$dataId';
      form['data_type'] = '${dataType ?? 1}';
    }
    try {
      final resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/creativesquare/action',
        data: FormData.fromMap(form),
      );
      _ensureOk(resp.data ?? <String, dynamic>{});
    } on SquareApiException catch (error) {
      // 换成发布语义的异常,页面据此区分「重试有用 / 没用」。
      throw SquarePublishException(error.message);
    }
  }

  /// 帖文动作(收藏 / 不感兴趣 …)。⚠️ 仍是 `/api/v1/community` 新世代,
  /// 后端未落地前这些动作发不出去 —— 见文件头注。
  Future<void> setAction(int id, String action, {bool enabled = true}) async {
    final Response<Map<String, dynamic>> resp;
    if (enabled) {
      resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/v1/community/posts/$id/actions',
        data: <String, dynamic>{
          'actionType': action,
          'requestId': _requestId(action.toLowerCase()),
          'source': 'APP_SQUARE',
        },
      );
    } else {
      resp = await _client.dio.delete<Map<String, dynamic>>(
        '/api/v1/community/posts/$id/actions/$action',
        data: <String, dynamic>{
          'requestId': _requestId('un-${action.toLowerCase()}'),
        },
      );
    }
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  /// 复制广场里的主题模板，返回当前用户自己的新草稿 topicId。
  ///
  /// 对齐小程序 `utils/topic-template-remix.js`：表单参数只传 `id`，
  /// 且只有 `code=200` 并读到正数 `data.topicId` 才算成功。
  Future<int> remixTopicTemplate(int topicId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/topic-template/use',
      data: FormData.fromMap(<String, dynamic>{'id': topicId.toString()}),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    final int? code = body['code'] is num
        ? (body['code'] as num).toInt()
        : int.tryParse('${body['code'] ?? ''}');
    if (code != 200) {
      throw SquareTemplateRemixException((body['msg'] as String?) ?? '模板改编失败');
    }
    final Object? rawId = (body['data'] as Map?)?['topicId'];
    final int? copiedTopicId = rawId is num
        ? rawId.toInt()
        : int.tryParse('${rawId ?? ''}');
    if ((copiedTopicId ?? 0) <= 0) {
      throw SquareTemplateRemixException((body['msg'] as String?) ?? '模板改编失败');
    }
    return copiedTopicId!;
  }

  Future<Map<String, dynamic>> activeGuideline() async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/guidelines/active',
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
  }

  Future<CommunityReportPolicySnapshot> reportPolicy() async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/capabilities',
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
    return CommunityReportPolicySnapshot.fromJson(
      Map<String, dynamic>.from(
        data['reporting'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }

  /// 只保存草稿，不确认发布公约，也不进入内容安全发布队列。
  Future<SquarePost> saveDraft(
    SquareDraft draft, {
    required int guidelineVersionId,
  }) async {
    _validateDraftWorkflow(draft, guidelineVersionId);
    if (draft.id != null && draft.sourceLifecycle != 'DRAFT') {
      throw SquarePublishException('已发布帖文的修改稿只能保存在本机，提交时会重新审核');
    }
    return _upsertDraft(draft, guidelineVersionId: guidelineVersionId);
  }

  /// 专业发布链路：显式确认当前公约 → 登记媒体 → 保存草稿 → 内容安全送审。
  /// 正文必填；权限或内容拒绝属于不可重试结果。
  Future<SquarePost> publish(
    SquareDraft draft, {
    required int guidelineVersionId,
  }) async {
    _validateDraftWorkflow(draft, guidelineVersionId);
    final ackResp = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/community/guidelines/ack',
      data: <String, dynamic>{
        'guidelineVersionId': guidelineVersionId,
        'requestId': _workflowRequestId(
          draft.workflowId,
          'guideline-$guidelineVersionId',
        ),
        'scene': 'PUBLISH',
      },
    );
    _ensureOk(ackResp.data ?? <String, dynamic>{});

    final post = await _upsertDraft(
      draft,
      guidelineVersionId: guidelineVersionId,
    );
    if (post.lifecycle != 'DRAFT') return post;
    final publishResp = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/community/posts/${post.id}/publish',
      data: <String, dynamic>{
        'expectedVersion': post.version,
        'requestId': _workflowRequestId(draft.workflowId, 'publish'),
      },
    );
    final publishBody = publishResp.data ?? <String, dynamic>{};
    if (publishBody['code'] != 200) {
      throw SquarePublishException((publishBody['msg'] as String?) ?? '发布失败');
    }
    return SquarePost.fromJson(
      publishBody['data'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
  }

  void _validateDraftWorkflow(SquareDraft draft, int guidelineVersionId) {
    if (guidelineVersionId <= 0) {
      throw SquarePublishException('社区规范尚未启用');
    }
    if (draft.workflowId.trim().length < 8) {
      throw SquarePublishException('草稿缺少稳定发布标识，请返回后重新发布');
    }
  }

  Future<SquarePost> _upsertDraft(
    SquareDraft draft, {
    required int guidelineVersionId,
  }) async {
    final mediaIds = <int>[...draft.existingMediaIds];
    final newMediaCount = draft.pics.length - draft.existingPicCount;
    if (newMediaCount < 0 ||
        newMediaCount != draft.picByteSizes.length ||
        newMediaCount != draft.picMimeTypes.length ||
        newMediaCount != draft.picUploadReceipts.length) {
      throw SquarePublishException('媒体上传回执缺失，请重新选择图片');
    }
    for (int index = 0; index < newMediaCount; index++) {
      final String url = draft.pics[draft.existingPicCount + index];
      final int byteSize = draft.picByteSizes[index];
      final mediaResp = await _client.dio.post<Map<String, dynamic>>(
        '/api/v1/community/media/register',
        data: <String, dynamic>{
          'uploadRequestId': _workflowRequestId(
            draft.workflowId,
            'media-$index',
          ),
          'mediaType': 'IMAGE',
          'objectKey': url,
          'uploadReceipt': draft.picUploadReceipts[index],
          'mimeType': draft.picMimeTypes[index],
          'byteSize': byteSize,
        },
      );
      final mediaBody = mediaResp.data ?? <String, dynamic>{};
      _ensureOk(mediaBody);
      final mediaId = ((mediaBody['data'] as Map?)?['id'] as num?)?.toInt();
      if (mediaId == null || mediaId <= 0) {
        throw SquarePublishException('媒体登记失败');
      }
      mediaIds.add(mediaId);
    }
    final createRequestId = _workflowRequestId(draft.workflowId, 'post');
    final references = <Map<String, dynamic>>[];
    final legacyReferenceType = switch (draft.dataType) {
      1 => 'ACTIVITY',
      2 => 'TOPIC',
      3 => 'ROUTE',
      4 => 'CLUB',
      5 => 'POI',
      _ => null,
    };
    final referenceType = draft.referenceType ?? legacyReferenceType;
    final referenceId = draft.referenceId ?? draft.dataId;
    if ((referenceId ?? 0) > 0 && referenceType != null) {
      references.add(<String, dynamic>{
        'referenceType': referenceType,
        'referenceId': referenceId,
        'snapshotJson': '{}',
        'privacySnapshot': 'PUBLIC_SAFE',
      });
    }
    final upsertPayload = <String, dynamic>{
      'clientRequestId': createRequestId,
      if (draft.id != null) 'expectedVersion': draft.expectedVersion,
      'communityId': draft.communityId,
      'postType': referenceType == 'ACTIVITY'
          ? 'ACTIVITY_RECAP'
          : referenceType == 'ROUTE'
          ? 'ROUTE_DISCOVERY'
          : 'MOMENT',
      'body': draft.contents.trim(),
      'audience': draft.audience,
      'commentPolicy': draft.commentPolicy,
      'replyApprovalEnabled': draft.replyApprovalEnabled ? 1 : 0,
      'slowModeSeconds': draft.slowModeSeconds,
      'locationPrecision': (draft.address ?? '').isEmpty ? 'NONE' : 'CITY',
      'cityCode': draft.cityCode,
      // 只保留可公开展示的地点名称，不上传经纬度或内部 geohash。
      'poiName': draft.address,
      'disclosureType': draft.disclosureType,
      'safetyLabels': draft.safetyLabels,
      'guidelineVersionId': guidelineVersionId,
      'mediaIds': mediaIds,
      'topicCodes': referenceType == 'TOPIC' && (referenceId ?? 0) > 0
          ? <String>[referenceId.toString()]
          : <String>[],
      'mentionedMemberIds': draft.mentionedMemberIds,
      'references': references,
    };
    final createResp = draft.id == null
        ? await _client.dio.post<Map<String, dynamic>>(
            '/api/v1/community/posts',
            data: upsertPayload,
          )
        : await _client.dio.patch<Map<String, dynamic>>(
            '/api/v1/community/posts/${draft.id}',
            data: upsertPayload,
          );
    final createBody = createResp.data ?? <String, dynamic>{};
    if (createBody['code'] != 200) {
      throw SquarePublishException((createBody['msg'] as String?) ?? '草稿保存失败');
    }
    final post = SquarePost.fromJson(
      createBody['data'] as Map<String, dynamic>,
    );
    return post;
  }

  /// 删除自己的帖文(软删)。归属校验在服务端；前端是否显示入口只用于交互，
  /// 不是授权依据。
  Future<String> delete(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/creativesquare/delete',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return (body['msg'] as String?) ?? '已删除';
  }

  Future<void> withdrawLocation(int id, {required int version}) async {
    final resp = await _client.dio.delete<Map<String, dynamic>>(
      '/api/v1/community/posts/$id/location',
      data: <String, dynamic>{
        'expectedVersion': version,
        'requestId': _requestId('location-withdraw'),
      },
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  Future<SquareFeedPage> drafts({int? cursor}) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/drafts',
      queryParameters: <String, dynamic>{'limit': 30, 'cursor': ?cursor},
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final items = (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic row) => SquarePost.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
    return SquareFeedPage(
      items: items,
      hasMore: items.length >= 30,
      nextCursor: (data['nextCursor'] as num?)?.toInt(),
    );
  }

  Future<List<Map<String, dynamic>>> revisions(int postId) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/posts/$postId/revisions',
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return (body['data'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> referenceOptions(String type) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/reference-options/$type',
      queryParameters: const <String, dynamic>{'limit': 30},
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return (body['data'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  /// 举报帖文。后端只把内容放进统一审核队列(不立即下架),回执原话转述,
  /// 不把「已提交」误报成「已下架」。
  Future<String> report(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/creativesquare/report',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return (body['msg'] as String?) ?? '举报已提交，内容将进入审核';
  }

  /// 举报评论。同一条统一审核队列,审核台 REJECT 才下架。
  Future<String> reportComment(int commentId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/comment/report',
      data: FormData.fromMap(<String, dynamic>{'id': commentId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return (body['msg'] as String?) ?? '举报已提交，评论将进入审核';
  }

  Future<void> mute(int memberId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/community/members/$memberId/mute',
      data: <String, dynamic>{'requestId': _requestId('mute')},
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  Future<void> recordShare(int postId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/community/posts/$postId/shares',
      data: <String, dynamic>{'requestId': _requestId('share')},
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  /// 当前账号可申诉的处置记录；包含直接账号处置和自己帖文上的内容处置。
  Future<List<Map<String, dynamic>>> myEnforcements({int? cursor}) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/me/enforcements',
      queryParameters: <String, dynamic>{'limit': 30, 'cursor': ?cursor},
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> appealEnforcement(int enforcementId, String reason) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/community/appeals',
      data: <String, dynamic>{
        'enforcementId': enforcementId,
        'reason': reason.trim(),
        'evidenceAssetIds': <int>[],
        'requestId': _requestId('appeal'),
      },
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  Future<List<Map<String, dynamic>>> notifications({int? cursor}) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/notifications',
      queryParameters: <String, dynamic>{'limit': 50, 'cursor': ?cursor},
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> readNotification(int notificationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/community/notifications/$notificationId/read',
      data: <String, dynamic>{'requestId': _requestId('notification-read')},
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> notificationPreferences() async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/community/notification-preferences',
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> updateNotificationPreferences({
    bool? interactionEnabled,
    bool? mentionEnabled,
    bool? socialEnabled,
  }) async {
    final resp = await _client.dio.patch<Map<String, dynamic>>(
      '/api/v1/community/notification-preferences',
      data: <String, dynamic>{
        'interactionEnabled': ?interactionEnabled,
        'mentionEnabled': ?mentionEnabled,
        'socialEnabled': ?socialEnabled,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
  }

  /// 评论列表。`owner_type=3` 是创意广场(1 主题 / 2 活动),分页是
  /// **pageNum/pageSize**,不是游标 —— 返回 `data.{rows,total}`。
  Future<List<Comment>> comments(
    int postId, {
    int page = 1,
    int limit = 50,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/comment/list',
      data: FormData.fromMap(<String, dynamic>{
        'owner_type': '3',
        'owner_id': postId.toString(),
        'pageNum': page.toString(),
        'pageSize': limit.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return (data['rows'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (dynamic row) =>
              Comment.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  /// 发评论 / 回复。回复只传 `reply_id`(被回复的那条评论 id);
  /// 服务端自己做文本机审,命中就返错 —— 这里不预判、也不吞错。
  Future<void> addComment(int postId, String body, {int? replyToId}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/comment/add',
      data: FormData.fromMap(<String, dynamic>{
        'owner_type': '3',
        'owner_id': postId.toString(),
        'rating': '0',
        'contents': body,
        'reply_id': (replyToId ?? 0).toString(),
        'img_arr': '',
      }),
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  /// 评论点赞。`/api/comment/like` 同样是**切换式**的,没有显式态参数 ——
  /// [enabled] 只用于和本地乐观态对齐:调用方每次只在状态翻转时发一次。
  Future<void> setCommentLike(int commentId, {required bool enabled}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/comment/like',
      data: FormData.fromMap(<String, dynamic>{'id': commentId.toString()}),
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  Future<void> approveComment(int postId, int commentId, int version) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/community/posts/$postId/comments/$commentId/approve',
      data: <String, dynamic>{
        'expectedVersion': version,
        'requestId': _requestId('comment-approve'),
      },
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  /// 删自己的评论。归属校验在服务端;入口是否显示只决定交互。
  Future<void> deleteComment(int commentId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/comment/delete',
      data: FormData.fromMap(<String, dynamic>{'id': commentId.toString()}),
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  static int _sequence = 0;
  static String _requestId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  static String _workflowRequestId(String workflowId, String stage) =>
      '$stage-$workflowId';

  /// AjaxResult 非 200 → 抛异常进 error 态(不兜底假数据)。
  void _ensureOk(Map<String, dynamic> body) {
    final Object? rawCode = body['code'];
    final int? code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '');
    if (code != 200) {
      throw SquareApiException(code, (body['msg'] as String?) ?? '请求失败');
    }
  }
}

class SquareFeedPage {
  const SquareFeedPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.nextCursorScore,
  });

  final List<SquarePost> items;
  final bool hasMore;
  final int? nextCursor;
  final int? nextCursorScore;
}

/// 发布失败。带上后端原话,并区分「不该重试」的两类。
class SquarePublishException implements Exception {
  SquarePublishException(this.message);
  final String message;

  /// 不是自己的帖 —— 权限态,重试无用。
  bool get isNotOwner => message.contains('无权编辑');

  /// 内容被审核拒 —— 要改文字,重试无用。
  ///
  /// ⚠️ 先排除明确的故障词,避免把网络问题误判成内容问题
  /// (误判就不给重试了,那是另一个方向的坏)。
  bool get isContentRejected {
    if (message.contains('网络') || message.contains('稍后重试')) return false;
    return const <String>['违规', '敏感', '不合规', '审核', '含有'].any(message.contains);
  }

  /// 值不值得重试。
  bool get retryable => !isNotOwner && !isContentRejected;

  @override
  String toString() => message;
}

class SquareTemplateRemixException implements Exception {
  const SquareTemplateRemixException(this.message);

  final String message;

  @override
  String toString() => message;
}
