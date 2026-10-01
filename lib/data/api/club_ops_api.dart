import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/club_ops.dart';
import 'club_api.dart' show ClubApiException;

/// 版本冲突(HTTP/业务码 409):编辑中的系列/角色已被他人更新。
/// 页面据此「刷新后再改」,不把它当普通失败 toast 掉。
class ClubOpsConflictException extends ClubApiException {
  ClubOpsConflictException([String? message]) : super(message ?? '内容已被更新');
}

/// 后端明确拒绝(业务码 400–499):重试同一 requestId 也不会变好,
/// 调用方应丢弃幂等意图重开一条(小程序 isExplicitClientFailure 同判据)。
class ClubOpsRejectedException extends ClubApiException {
  ClubOpsRejectedException(super.message, {super.data});
}

/// 俱乐部运营四页接口层,对齐小程序 `pages/club/{event-ops,governance,notify,roles}`
/// 消费的 24 个端点。全部 `POST` + JSON body(后端 @RequestBody;裸 FormData 会 415)。
///
/// ★ 所有「读取形状」方法对坏回执返回 null / 抛异常,**不兜底**:
///   小程序把「算不出来」和「是零」分得很清(见 EventSeries.tryFromJson),
///   这一层照搬同一条纪律。
/// 业务码归一 —— `club_ops_api` 与 `club_topic_ops_api` 两份接口层共用一份判据,
/// 不让「409 是刷新后再改、4xx 是明确拒绝」这条语义在两处各写一遍并各自漂移。
///
/// 409 → [ClubOpsConflictException];400–499 → [ClubOpsRejectedException];
/// 其余非 200 → [ClubApiException]。文案都带后端原文。
void ensureClubOpsOk(Map<String, dynamic> body) {
  final int code = (body['code'] as num?)?.toInt() ?? 0;
  if (code == 200) return;
  if (code == 409) {
    throw ClubOpsConflictException('${body['msg'] ?? ''}'.isEmpty
        ? null
        : '${body['msg']}');
  }
  if (code >= 400 && code < 500) {
    throw ClubOpsRejectedException(
      (body['msg'] as String?) ?? '请求被拒绝',
      data: body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : null,
    );
  }
  throw ClubApiException(
    (body['msg'] as String?) ?? '请求失败',
    data: body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : null,
  );
}

class ClubOpsApi {
  ClubOpsApi(this._client);
  final DioClient _client;

  static final math.Random _random = math.Random();

  /// 幂等键(小程序 requestId(prefix) 同构)。
  static String newRequestId(String prefix) {
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    final String tail = _random
        .nextInt(1 << 32)
        .toRadixString(36)
        .padLeft(6, '0');
    return '$prefix-$stamp-$tail';
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Response<Map<String, dynamic>> resp = await _client.dio
        .post<Map<String, dynamic>>(
          path,
          data: body,
          options: Options(contentType: Headers.jsonContentType),
        );
    return resp.data ?? <String, dynamic>{};
  }

  void _ensureOk(Map<String, dynamic> body) => ensureClubOpsOk(body);

  Object? _data(Map<String, dynamic> body) => body['data'];

  List<Map<String, dynamic>> _dataList(Map<String, dynamic> body) {
    final Object? data = body['data'];
    if (data is! List) throw ClubApiException('回执不是列表');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  // ── 访问上下文 ──────────────────────────────────────────────

  /// `POST /api/club/access/me`。四页共用的页内权限判据。
  Future<ClubOpsAccess> access({required int clubId, int? activityId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/access/me',
      <String, dynamic>{
        'clubId': clubId,
        if (activityId != null && activityId > 0) 'activityId': activityId,
      },
    );
    _ensureOk(body);
    final Object? data = _data(body);
    if (data is! Map<String, dynamic>) {
      throw ClubApiException('俱乐部权限回执不完整');
    }
    return ClubOpsAccess.fromJson(data);
  }

  // ── 活动运营(event-ops) ────────────────────────────────────

  /// `POST /api/club/event-ops/topics` → 可开场主题列表。
  Future<List<EventOpsTopic>> eventTopics({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/topics',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    return _dataList(body)
        .where((Map<String, dynamic> row) => (row['id'] as num?) != null)
        .map(EventOpsTopic.fromJson)
        .toList();
  }

  /// `POST /api/club/event-ops/series/list` → 系列清单。
  Future<List<EventSeries>> seriesList({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/series/list',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    final List<EventSeries> rows = <EventSeries>[];
    for (final Map<String, dynamic> row in _dataList(body)) {
      final EventSeries? series = EventSeries.tryFromJson(row, clubId: clubId);
      if (series == null) throw ClubApiException('系列列表数据不完整');
      rows.add(series);
    }
    return rows;
  }

  /// `POST /api/club/event-ops/series/occurrences` → 日期清单(含过场次/已取消)。
  Future<List<SeriesOccurrence>> seriesOccurrences({
    required int clubId,
    required int seriesId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/series/occurrences',
      <String, dynamic>{'clubId': clubId, 'seriesId': seriesId},
    );
    _ensureOk(body);
    return _dataList(body).map(SeriesOccurrence.fromJson).toList();
  }

  /// `POST /api/club/event-ops/series/detail` → 编辑态系列。
  /// 回执里的 id 与请求不一致时抛异常(小程序同判据:详情已变化)。
  Future<EventSeries> seriesDetail({
    required int clubId,
    required int seriesId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/series/detail',
      <String, dynamic>{'clubId': clubId, 'seriesId': seriesId},
    );
    _ensureOk(body);
    final Object? data = _data(body);
    final EventSeries? series = data is Map<String, dynamic>
        ? EventSeries.tryFromJson(data, clubId: clubId)
        : null;
    if (series == null || series.id != seriesId) {
      throw ClubApiException('系列详情已变化，请刷新');
    }
    return series;
  }

  /// `POST /api/club/event-ops/series/create` → 新系列 id。
  Future<int> createSeries(Map<String, dynamic> payload) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/series/create',
      payload,
    );
    _ensureOk(body);
    final Object? data = _data(body);
    final int id = data is Map<String, dynamic> ? (data['id'] as num? ?? 0).toInt() : 0;
    if (id <= 0) throw ClubApiException('系列场次创建没返回系列号');
    return id;
  }

  /// `POST /api/club/event-ops/series/update-future` → 被更新的系列 id。
  /// 版本不符时后端回 409 → [ClubOpsConflictException]。
  Future<int> updateSeriesFuture(Map<String, dynamic> payload) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/series/update-future',
      payload,
    );
    _ensureOk(body);
    final Object? data = _data(body);
    final int id = data is Map<String, dynamic> ? (data['id'] as num? ?? 0).toInt() : 0;
    if (id <= 0) throw ClubApiException('更新没有返回系列号');
    return id;
  }

  /// `POST /api/club/event-ops/occurrence/status` → 取消状态独立回读。
  /// 形状不合法返回 null → 页面进 readback-error,可重试回读。
  Future<OccurrenceStatus?> occurrenceStatus({
    required int clubId,
    required int activityId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/occurrence/status',
      <String, dynamic>{'clubId': clubId, 'activityId': activityId},
    );
    _ensureOk(body);
    final Object? data = _data(body);
    return data is Map<String, dynamic>
        ? OccurrenceStatus.tryFromJson(data, activityId: activityId)
        : null;
  }

  /// `POST /api/club/event-ops/cancel`。回执的 activityId 不是本场 → null。
  Future<CancellationOutcome?> cancelOccurrence({
    required int clubId,
    required int activityId,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/cancel',
      <String, dynamic>{
        'clubId': clubId,
        'activityId': activityId,
        'reason': reason,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
    final Object? data = _data(body);
    if (data is! Map<String, dynamic>) return null;
    final int scopedId = (data['activityId'] as num?)?.toInt() ?? 0;
    if (scopedId != activityId) return null;
    return CancellationOutcome(
      activityId: scopedId,
      refundStatus: '${data['refundStatus'] ?? ''}',
    );
  }

  /// `POST /api/club/event-ops/roster` → 四分桶名册。形状不全 → null。
  Future<ClubRoster?> roster({
    required int clubId,
    required int activityId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/roster',
      <String, dynamic>{'clubId': clubId, 'activityId': activityId},
    );
    _ensureOk(body);
    return ClubRoster.tryFromJson(_data(body));
  }

  /// `POST /api/club/event-ops/attendance/correct` → 是否受理(data.id 正整数)。
  Future<bool> correctAttendance({
    required int clubId,
    required int activityId,
    required int memberId,
    required bool arrived,
    required int expectedVersion,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/attendance/correct',
      <String, dynamic>{
        'clubId': clubId,
        'activityId': activityId,
        'memberId': memberId,
        'arrived': arrived,
        'expectedVersion': expectedVersion,
        'reason': reason,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
    final Object? data = _data(body);
    return data is Map<String, dynamic> && ((data['id'] as num?) ?? 0) > 0;
  }

  // ── 成员治理(governance) ──────────────────────────────────

  /// `POST /api/club/governance/list` → 治理记录。形状不全 → null。
  Future<List<GovernanceBan>?> governanceBans({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/governance/list',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    return GovernanceBan.tryList(_data(body), clubId);
  }

  /// `POST /api/club/governance/cases/mine` → 我的平台工单。形状不全 → null。
  Future<List<GovernanceCase>?> governanceCasesMine({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/governance/cases/mine',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    return GovernanceCase.tryList(_data(body), clubId);
  }

  /// `POST /api/club/governance/ban`。
  Future<void> banMember({
    required int clubId,
    required int targetMemberId,
    required String reason,
    required String expiresAt,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/governance/ban',
      <String, dynamic>{
        'clubId': clubId,
        'targetMemberId': targetMemberId,
        'reason': reason,
        'expiresAt': expiresAt,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
  }

  /// `POST /api/club/governance/unban`。
  Future<void> unbanMember({
    required int clubId,
    required int banId,
    required int version,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/governance/unban',
      <String, dynamic>{
        'clubId': clubId,
        'banId': banId,
        'version': version,
        'reason': reason,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
  }

  /// `POST /api/club/governance/owner/transfer`。
  Future<void> transferOwner({
    required int clubId,
    required int targetMemberId,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/governance/owner/transfer',
      <String, dynamic>{
        'clubId': clubId,
        'targetMemberId': targetMemberId,
        'reason': reason,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
  }

  /// 治理举报 / 封禁申诉。`appeal=true` 走 cases/appeal,否则 cases/report。
  Future<void> submitGovernanceCase({
    required int clubId,
    required bool appeal,
    String? targetType,
    int? targetId,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      appeal
          ? '/api/club/governance/cases/appeal'
          : '/api/club/governance/cases/report',
      <String, dynamic>{
        'clubId': clubId,
        if (!appeal) 'targetType': targetType,
        if (!appeal) 'targetId': targetId,
        if (!appeal) 'evidence': <String, dynamic>{},
        'reason': reason,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
  }

  // ── 角色与权限(roles) ─────────────────────────────────────

  /// `POST /api/club/roles/list` → roles + assignments。形状不全 → null。
  Future<RoleScopeData?> rolesList({
    required int clubId,
    int? activityId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/roles/list',
      <String, dynamic>{
        'clubId': clubId,
        if (activityId != null && activityId > 0) 'activityId': activityId,
      },
    );
    _ensureOk(body);
    return RoleScopeData.tryFromJson(
      _data(body),
      clubId: clubId,
      activityId: activityId,
    );
  }

  /// `POST /api/club/roles/assign`。
  Future<void> assignRole({
    required int clubId,
    int? activityId,
    required int targetMemberId,
    required String roleCode,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/roles/assign',
      <String, dynamic>{
        'clubId': clubId,
        if (activityId != null && activityId > 0) 'activityId': activityId,
        'targetMemberId': targetMemberId,
        'roleCode': roleCode,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
  }

  /// `POST /api/club/roles/revoke`。
  Future<void> revokeRole({
    required int clubId,
    int? activityId,
    required int assignmentId,
    required int version,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/roles/revoke',
      <String, dynamic>{
        'clubId': clubId,
        if (activityId != null && activityId > 0) 'activityId': activityId,
        'assignmentId': assignmentId,
        'version': version,
        'reason': reason,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
  }

  // ── 群发通知(notify) ──────────────────────────────────────

  /// `POST /api/club/event-notification/audience-counts` → 各分组人数。
  Future<AudienceCounts?> audienceCounts({
    required int clubId,
    int? activityId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-notification/audience-counts',
      <String, dynamic>{
        'clubId': clubId,
        'activityId': activityId != null && activityId > 0 ? activityId : null,
      },
    );
    _ensureOk(body);
    return AudienceCounts.tryFromJson(_data(body));
  }

  /// `POST /api/club/event-notification/preview` → 受众预览。非法形状 → null。
  Future<NotificationPreview?> notificationPreview({
    required int clubId,
    int? activityId,
    required String audienceType,
    required String title,
    required String content,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-notification/preview',
      <String, dynamic>{
        'clubId': clubId,
        'activityId': activityId,
        'audienceType': audienceType,
        'channel': 'IN_APP',
        'title': title,
        'content': content,
        'requestId': null,
      },
    );
    _ensureOk(body);
    return NotificationPreview.tryFromJson(_data(body));
  }

  /// `POST /api/club/event-notification/send` → 发送回执。非法形状 → null。
  Future<NotificationCampaign?> notificationSend({
    required int clubId,
    int? activityId,
    required String audienceType,
    required String title,
    required String content,
    required String requestId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-notification/send',
      <String, dynamic>{
        'clubId': clubId,
        'activityId': activityId,
        'audienceType': audienceType,
        'channel': 'IN_APP',
        'title': title,
        'content': content,
        'requestId': requestId,
      },
    );
    _ensureOk(body);
    return NotificationCampaign.tryFromJson(_data(body));
  }

  /// Read asynchronous delivery results without sending or retrying a campaign.
  Future<NotificationCampaign?> notificationStatus({
    required int campaignId,
  }) async {
    final body = await _postJson(
      '/api/club/event-notification/status',
      <String, dynamic>{'campaignId': campaignId},
    );
    _ensureOk(body);
    return NotificationCampaign.tryFromJson(_data(body));
  }

  /// `POST /api/club/event-notification/retry` → 只重试失败项的发送回执。
  Future<NotificationCampaign?> notificationRetry({
    required int campaignId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-notification/retry',
      <String, dynamic>{'campaignId': campaignId},
    );
    _ensureOk(body);
    return NotificationCampaign.tryFromJson(_data(body));
  }

  /// `POST /api/club/event-ops/waitlist/status` → 满员票种的候补真状态。
  ///
  /// ★ 玩家侧接口(小程序 `pages/activity/baoming`):App 的落点是报名流程的
  ///   票种卡,不在俱乐部运营页。本线只把接口层接通并把判据固化在
  ///   [EventWaitlistStatus] 里,页面接线见 PR 说明。
  Future<EventWaitlistStatus?> waitlistStatus({
    required int activityId,
    required int ticketId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/waitlist/status',
      <String, dynamic>{'activityId': activityId, 'ticketId': ticketId},
    );
    _ensureOk(body);
    return EventWaitlistStatus.tryFromJson(_data(body));
  }

  /// `POST /api/club/event-ops/waitlist/join` → 加入候补(回执不解析,
  /// 成功与否看业务码;拿到真状态要回读 [waitlistStatus])。
  ///
  /// ⚠️ 调用前必须自己判满员 —— 没满员时后端会拒绝(小程序先 tips「当前已有名额,
  ///   请直接报名」,不发这次请求)。
  Future<void> waitlistJoin({
    required int activityId,
    required int ticketId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/waitlist/join',
      <String, dynamic>{'activityId': activityId, 'ticketId': ticketId},
    );
    _ensureOk(body);
  }

  /// `POST /api/club/event-ops/waitlist/cancel` → 退出候补。
  ///
  /// ⚠️ OFFERED 状态退出会**真实回补并可能立刻晋级下一位**;
  ///   调用方必须重拉票种库存与候补状态,别拿旧票对象继续算(小程序原话)。
  Future<void> waitlistCancel({
    required int activityId,
    required int ticketId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/event-ops/waitlist/cancel',
      <String, dynamic>{'activityId': activityId, 'ticketId': ticketId},
    );
    _ensureOk(body);
  }
}
