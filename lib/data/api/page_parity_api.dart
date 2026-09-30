import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/marketing_consent.dart';

/// 小程序新增二/三级页的窄接口。
///
/// 这些接口都返回变化快的工作流数据，页面只读小程序同名字段；
/// 服务端明确返回非 200 时统一失败，不在 UI 里伪造成功。
class PageParityApi {
  PageParityApi(this._client);

  final DioClient _client;

  Future<Map<String, dynamic>> teamInfo({int? teamId, String? inviteCode}) =>
      _post('/api/team/info', <String, dynamic>{
        'teamId': ?teamId,
        'inviteCode': ?inviteCode,
      });

  Future<Map<String, dynamic>> teamJoin(String code) =>
      _post('/api/team/join', <String, dynamic>{'inviteCode': code});

  Future<int> createActivityTeam({
    required int activityId,
    required int maxMembers,
  }) async {
    final data = await _post('/api/team/create', <String, dynamic>{
      'ownerType': 2,
      'ownerId': activityId,
      'maxMembers': maxMembers,
    });
    final int? teamId = (data['teamId'] as num?)?.toInt();
    if (teamId == null || teamId <= 0) {
      throw const PageParityApiException('创建队伍回执不完整');
    }
    return teamId;
  }

  Future<void> teamAction(String action, Map<String, dynamic> body) async {
    final String path = switch (action) {
      'quit' => '/api/team/quit',
      'kick' => '/api/team/kick',
      'disband' => '/api/team/disband',
      _ => throw const PageParityApiException('队伍操作不受支持'),
    };
    await _post(path, body);
  }

  Future<List<Map<String, dynamic>>> circleOffers(int topicId) =>
      _getList('/api/circle-theme/instance/$topicId/offers');

  /// 主办方「确认本实例供给已复核」:`POST /api/circle-theme/instance/review`
  /// (JSON `{topicId, scope}`)→ 服务端重新校验 3—4 家当前供给。
  ///
  /// 快照 `pages/topic/merchantinfo/merchantinfo.js:1841`。★ 失败里
  /// 「少于 3 家 / 资料过期 / 商家重复时不会刷新」是**复核规则的正常回话**,
  /// 不是可以重试的故障 —— 原文透传,别改写成「网络异常请重试」。
  Future<void> reviewCircleInstance({required int topicId, String? scope}) =>
      _post('/api/circle-theme/instance/review', <String, dynamic>{
        'topicId': topicId,
        'scope': scope ?? '',
      });

  Future<Map<String, dynamic>> createCircleSession(int topicId) =>
      _post('/api/circle-theme/session', <String, dynamic>{'topicId': topicId});

  Future<Map<String, dynamic>> joinCircleSession(String inviteCode) => _post(
    '/api/circle-theme/session/join',
    <String, dynamic>{'inviteCode': inviteCode},
  );

  Future<Map<String, dynamic>> circleCard(Object sessionId) =>
      _get('/api/circle-theme/session/$sessionId/card');

  Future<Map<String, dynamic>> recordCircle(Map<String, dynamic> body) =>
      _post('/api/circle-theme/session/record', body);

  Future<Map<String, dynamic>> answerCircle(Map<String, dynamic> body) =>
      _post('/api/circle-theme/session/answer', body);

  Future<Map<String, dynamic>> merchantAccess() async {
    final Map<String, dynamic> raw = await _post(
      '/api/merchant/access/me',
      const <String, dynamic>{},
    );
    return _normalizeMerchantAccess(raw);
  }

  Map<String, dynamic> _normalizeMerchantAccess(Map<String, dynamic> raw) {
    const Map<String, String> roles = <String, String>{
      'MERCHANT_OWNER': '店主',
      'MERCHANT_MANAGER': '店长',
      'MERCHANT_CHECKIN': '核销员',
      'MERCHANT_MARKETING': '运营',
      'MERCHANT_FINANCE': '财务',
    };
    final Object? merchant = raw['merchant'];
    final Object? merchantId = merchant is Map ? merchant['id'] : null;
    final int? id = merchantId is num
        ? merchantId.toInt()
        : int.tryParse('$merchantId');
    final String roleCode = '${raw['roleCode'] ?? ''}';
    final bool active = raw['active'] == true && id != null && id > 0;
    final bool trusted = active && roles.containsKey(roleCode);
    final Set<String> permissions = trusted && raw['permissions'] is List
        ? (raw['permissions'] as List<dynamic>).whereType<String>().toSet()
        : const <String>{};
    bool has(String permission) => trusted && permissions.contains(permission);

    return <String, dynamic>{
      ...raw,
      'active': trusted,
      'merchant': trusted ? merchant : null,
      'roleCode': trusted ? roleCode : '',
      'roleName': trusted ? roles[roleCode] : '',
      'permissions': permissions.toList(growable: false),
      'canReadBasic': has('merchant:basic:read'),
      'canWriteProfile': has('merchant:profile:write'),
      'canManageProjects': has('merchant:project:manage'),
      'canVerify': has('merchant:verify'),
      'canReadVerifyRecords': has('merchant:verify:record:read'),
      'canReadOrders': has('merchant:order:read'),
      'canReadCrm': has('merchant:crm:read'),
      'canReadCrmSensitive': has('merchant:crm:sensitive:read'),
      'canSegmentCrm': has('merchant:crm:segment'),
      'canExportCrm': has('merchant:crm:export'),
      'canReadFinance': has('merchant:finance:read'),
      'canReadAftercare': has('merchant:aftercare:read'),
      'canRespondAftercare': has('merchant:aftercare:respond'),
      'canReadMarketing': has('merchant:marketing:read'),
      'canWriteMarketing': has('merchant:marketing:write'),
      'canManageCoupons': has('merchant:coupon:manage'),
      'canManageCoop': has('merchant:coop:manage'),
      'canManageOperators': has('merchant:operator:manage'),
    };
  }

  Future<Map<String, dynamic>> aftercareList({
    required String bucket,
    int pageNum = 1,
    int pageSize = 20,
  }) => _post(
    '/api/merchant/aftercare/list',
    const <String, dynamic>{},
    query: <String, dynamic>{
      'bucket': bucket,
      'pageNum': pageNum,
      'pageSize': pageSize,
    },
  );

  Future<Map<String, dynamic>> aftercareDetail(int refundId) => _post(
    '/api/merchant/aftercare/detail',
    const <String, dynamic>{},
    query: <String, dynamic>{'refundId': refundId},
  );

  Future<Map<String, dynamic>> respondAftercare(
    int refundId,
    Map<String, dynamic> body,
  ) => _post(
    '/api/merchant/aftercare/respond',
    body,
    query: <String, dynamic>{'refundId': refundId},
  );

  Future<String> uploadAftercareEvidence(String filePath) async {
    final Response<Map<String, dynamic>> response = await _client.dio
        .post<Map<String, dynamic>>(
          '/api/common/uploadOSS',
          data: FormData.fromMap(<String, dynamic>{
            'file': await MultipartFile.fromFile(filePath),
            'bizType': 'merchant_aftercare_evidence',
          }),
        );
    final Map<String, dynamic> body =
        response.data ?? const <String, dynamic>{};
    _ensureSuccess(body);
    final String key = (body['fileName'] ?? '').toString().trim();
    if (key.isEmpty) throw const PageParityApiException('凭证上传回执不完整');
    return key;
  }

  Future<Map<String, dynamic>> reviews({
    required bool manage,
    int? merchantRowId,
    int pageNum = 1,
  }) => _post(
    manage ? '/api/merchant/reviews/manage' : '/api/merchant/reviews/public',
    const <String, dynamic>{},
    query: <String, dynamic>{
      'merchantRowId': ?merchantRowId,
      'pageNum': pageNum,
      'pageSize': 20,
    },
  );

  Future<Map<String, dynamic>> createReview(Map<String, dynamic> body) async {
    final Map<String, dynamic> receipt = await _post(
      '/api/merchant/reviews/create',
      body,
    );
    final int? reviewId = _positiveId(receipt['reviewId']);
    final int? version = _nonNegativeInt(receipt['version']);
    final String status = '${receipt['status'] ?? ''}';
    final bool replayed = receipt['replayed'] == true;
    if (reviewId == null ||
        version == null ||
        receipt['replayed'] is! bool ||
        _positiveId(receipt['auditTaskId']) == null ||
        !const <String>{
          'PENDING_REVIEW',
          'VISIBLE',
          'HIDDEN',
        }.contains(status) ||
        (!replayed && status != 'PENDING_REVIEW')) {
      throw const PageParityApiException('评价提交回执不完整');
    }
    return receipt;
  }

  Future<Map<String, dynamic>> replyReview(Map<String, dynamic> body) async {
    final Map<String, dynamic> receipt = await _post(
      '/api/merchant/reviews/reply',
      body,
    );
    final int? expectedId = _positiveId(body['reviewId']);
    final int? expectedVersion = _nonNegativeInt(body['expectedVersion']);
    final int? version = _nonNegativeInt(receipt['version']);
    if (expectedId == null ||
        expectedVersion == null ||
        _positiveId(receipt['reviewId']) != expectedId ||
        version == null ||
        version <= expectedVersion ||
        receipt['replayed'] is! bool ||
        !const <String>{
          'PENDING_REVIEW',
          'VISIBLE',
          'HIDDEN',
        }.contains('${receipt['status'] ?? ''}')) {
      throw const PageParityApiException('评价回复回执不完整');
    }
    return receipt;
  }

  Future<Map<String, dynamic>> reportReview(
    Map<String, dynamic> body, {
    required bool manage,
  }) async {
    final Map<String, dynamic> receipt = await _post(
      manage
          ? '/api/merchant/reviews/manage/report'
          : '/api/merchant/reviews/report',
      body,
    );
    final int? expectedId = _positiveId(body['reviewId']);
    if (expectedId == null ||
        _positiveId(receipt['reviewId']) != expectedId ||
        receipt['status'] != 'PENDING_PLATFORM_REVIEW' ||
        receipt['replayed'] is! bool ||
        _positiveId(receipt['auditTaskId']) == null) {
      throw const PageParityApiException('评价举报回执不完整');
    }
    return receipt;
  }

  Future<Map<String, dynamic>> customerDetail(int customerMemberId) => _post(
    '/api/merchant/crm/customers/$customerMemberId/detail',
    const <String, dynamic>{},
  );

  Future<Map<String, dynamic>> addCustomerNote(
    int customerMemberId,
    Map<String, dynamic> body,
  ) => _post('/api/merchant/crm/customers/$customerMemberId/notes', body);

  Future<Map<String, dynamic>> hideCustomerNote(
    int customerMemberId,
    Map<String, dynamic> body,
  ) => _post('/api/merchant/crm/customers/$customerMemberId/notes/hide', body);

  Future<Map<String, dynamic>> addCustomerTag(
    int customerMemberId,
    Map<String, dynamic> body,
  ) => _post('/api/merchant/crm/customers/$customerMemberId/tags', body);

  Future<Map<String, dynamic>> removeCustomerTag(
    int customerMemberId,
    Map<String, dynamic> body,
  ) => _post('/api/merchant/crm/customers/$customerMemberId/tags/remove', body);

  Future<List<MarketingConsent>> marketingConsents() async {
    final List<Map<String, dynamic>> rows = await _getList(
      '/api/merchant/crm/marketing-consents',
    );
    try {
      return rows.map(MarketingConsent.fromJson).toList(growable: false);
    } on FormatException catch (error) {
      throw PageParityApiException(error.message);
    }
  }

  /// 写入后重新读取服务端状态；POST 接收成功不等于同意已落库。
  Future<List<MarketingConsent>> setMarketingConsent({
    required int merchantRowId,
    required int merchantOwnerMemberId,
    required String channel,
    required bool optedIn,
    required String requestId,
  }) async {
    if (merchantRowId <= 0 ||
        merchantOwnerMemberId <= 0 ||
        !const <String>{'IN_APP', 'COUPON'}.contains(channel) ||
        requestId.trim().isEmpty) {
      throw ArgumentError('营销同意参数不完整');
    }
    await _post('/api/merchant/crm/marketing-consents', <String, dynamic>{
      'merchantRowId': merchantRowId,
      'merchantOwnerMemberId': merchantOwnerMemberId,
      'channel': channel,
      'optedIn': optedIn,
      'requestId': requestId,
    });
    final List<MarketingConsent> rows = await marketingConsents();
    final bool confirmed = rows.any(
      (MarketingConsent row) =>
          row.merchantRowId == merchantRowId &&
          row.merchantOwnerMemberId == merchantOwnerMemberId &&
          row.valueFor(channel) == optedIn,
    );
    if (!confirmed) {
      throw const PageParityApiException('营销同意状态未确认，请重试');
    }
    return rows;
  }

  /// 导出脱敏客户资料(创建任务):`POST /api/merchant/crm/exports`。
  ///
  /// body 是 **JSON**`{query, requestId}`(小程序 `pages/merchant/customer/index.js:1084`),
  /// query 与客户名册同一套筛选词汇(pageNum / pageSize / keyword)。
  ///
  /// ★ [requestId] 由调用方生成并**在重试时重用同一个值**:后端按它幂等,
  ///   换新 id 重试 = 一次全新的导出任务(小程序同款 `crm-export-*`)。
  ///
  /// ★★ 下载凭证只在**创建**响应里出现一次(customer/index.js:1092),
  ///   轮询拿不到 —— 调用方必须把 downloadToken 跟任务一起存。
  /// ★ [query] 就是**名册那份筛选**(快照 `_customerQuery(1)`,index.js:1084/1195):
  ///   分群 / 标签 / 来源 / 时间窗与关键词全在里面。只传关键词 = 用户在
  ///   「回头客 + 主题 + 日期窗」下点导出,拿到的却是全量名单。
  Future<Map<String, dynamic>> createCrmExport({
    required String requestId,
    required Map<String, dynamic> query,
  }) => _post('/api/merchant/crm/exports', <String, dynamic>{
    'query': query,
    'requestId': requestId,
  });

  /// 导出任务状态:`POST /api/merchant/crm/exports/{taskId}/status`。
  ///
  /// 行数/失败原因都只在这条上更新,所以「生成中」时必须轮询它
  /// (小程序 1.5s 一次,customer/index.js:1141)。
  Future<Map<String, dynamic>> crmExportStatus(int taskId) =>
      _post('/api/merchant/crm/exports/$taskId/status', const <String, dynamic>{});

  /// 下载导出好的 Excel:`GET /api/merchant/crm/exports/{taskId}/download`。
  ///
  /// ★★ 两个必须:① 目标路径**不能改**(后端按任务 id 取文件);
  ///   ② `X-CRM-Export-Token` 头必须带 —— 只凭 Authorization 会被拒,
  ///   而拒绝发生在下载流里,外面看起来只是「下载失败,请稍后重试」。
  ///   小程序走 `wx.downloadFile` 带同一个头(customer/index.js:1164)。
  Future<void> downloadCrmExport({
    required int taskId,
    required String downloadToken,
    required String savePath,
  }) async {
    await _client.dio.download(
      '/api/merchant/crm/exports/$taskId/download',
      savePath,
      options: Options(
        headers: <String, dynamic>{'X-CRM-Export-Token': downloadToken},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> operatorRoles() =>
      _postList('/api/merchant/operators/roles', const <String, dynamic>{});

  Future<Map<String, dynamic>> operatorTeam() =>
      _post('/api/merchant/operators/list', const <String, dynamic>{});

  Future<Map<String, dynamic>> operatorMutation(
    String action,
    Map<String, dynamic> body,
  ) {
    final String path = switch (action) {
      'invite' => '/api/merchant/operators/invite',
      'invite/accept' => '/api/merchant/operators/invite/accept',
      'invite/revoke' => '/api/merchant/operators/invite/revoke',
      'remove' => '/api/merchant/operators/remove',
      'role' => '/api/merchant/operators/role',
      _ => throw const PageParityApiException('经营团队操作不受支持'),
    };
    return _post(path, body);
  }

  Future<Map<String, dynamic>> gameSession(int activityId) => _get(
    '/api/game/session/view',
    query: <String, dynamic>{
      'activityId': activityId,
      'perspective': 'MERCHANT',
    },
  );

  Future<List<Map<String, dynamic>>> merchantGameEntries() =>
      _getList('/api/game/session/merchant/entries');

  Future<Map<String, dynamic>> gameCommand(Map<String, dynamic> body) =>
      _post('/api/game/session/command', body);

  Future<Map<String, dynamic>> gameReceipt({
    required int activityId,
    required String requestId,
  }) => _get(
    '/api/game/session/receipt',
    query: <String, dynamic>{'activityId': activityId, 'requestId': requestId},
  );

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.dio
        .get<Map<String, dynamic>>(path, queryParameters: query);
    return _unwrap(response.data);
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final Response<Map<String, dynamic>> response = await _client.dio
        .get<Map<String, dynamic>>(path);
    final dynamic data = _unwrapValue(response.data);
    return _maps(data);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, dynamic>? query,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.dio
        .post<Map<String, dynamic>>(path, data: body, queryParameters: query);
    return _unwrap(response.data);
  }

  Future<List<Map<String, dynamic>>> _postList(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Response<Map<String, dynamic>> response = await _client.dio
        .post<Map<String, dynamic>>(path, data: body);
    return _maps(_unwrapValue(response.data));
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic>? body) {
    final dynamic value = _unwrapValue(body);
    if (value is Map<String, dynamic>) return value;
    if (value is List) return <String, dynamic>{'rows': value};
    return <String, dynamic>{'value': value};
  }

  dynamic _unwrapValue(Map<String, dynamic>? body) {
    final map = body ?? const <String, dynamic>{};
    _ensureSuccess(map);
    return map['data'];
  }

  void _ensureSuccess(Map<String, dynamic> body) {
    final dynamic code = body['code'];
    final bool ok = code is num ? code.toInt() == 200 : '$code' == '200';
    if (!ok) {
      throw PageParityApiException((body['msg'] ?? '请求失败').toString());
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) =>
      (value is List ? value : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

  int? _positiveId(dynamic value) {
    final int? id = value is num ? value.toInt() : int.tryParse('$value');
    return id != null && id > 0 ? id : null;
  }

  int? _nonNegativeInt(dynamic value) {
    final int? number = value is num ? value.toInt() : int.tryParse('$value');
    return number != null && number >= 0 ? number : null;
  }
}

class PageParityApiException implements Exception {
  const PageParityApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
