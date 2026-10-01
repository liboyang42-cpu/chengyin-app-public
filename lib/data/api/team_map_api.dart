import '../../core/network/request_session_scope.dart';
import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';

/// 地图组队 P 方案的接口层(漫游「附近的队伍」)。
///
/// ★ 真源 = 小程序只读快照 master@90e66d70,每个方法注释里带调用点出处:
///     subpackageRoam/nearby/index.js          P1–P6 的 7 条调用
///     utils/map-team.js / tests/unit/map-team.test.js   errorCode 分支
///   `/api/team/my` 另有 `subpackageMember/signup/index.js:208` 的落点用法
///   (票夹里那一行「我的队伍 ›」)。
/// ★ 失败带 [TeamMapApiException.errorCode] 上来 —— 页面只按 errorCode 分支,
///   不解析 msg(快照 `utils/map-team.js` 的纪律,契约里专门钉过)。
/// ⚠️ 本层不做 UI 判断:patch / 撤下队伍 / 重拉都留给 `lib/data/models/team_map.dart`。
class TeamMapApiException implements Exception {
  const TeamMapApiException(this.message, {this.errorCode = '', this.localReason});

  final String message;
  final TeamMapLocalFailure? localReason;

  /// 后端 errorCode(TICKET_REQUIRED / TEAM_FULL / APPLY_NOT_PENDING …),
  /// 没有就空串。
  final String errorCode;

  @override
  String toString() => message;
}

/// 接口异常 → [resolveTeamError] 认的 `{errorCode, msg}`。
///
/// 非接口异常(网络层)只带 msg:按纪律它**不触发任何状态改动**,只报失败。
Map<String, dynamic> teamErrorBody(Object error) {
  if (error is TeamMapApiException) {
    return <String, dynamic>{
      'errorCode': error.errorCode,
      'msg': error.message,
      if (error.localReason != null) '_localFailure': error.localReason!.name,
    };
  }
  return <String, dynamic>{'msg': '$error'};
}

class TeamMapApi {
  TeamMapApi(this._client);

  final DioClient _client;

  /// 附近的队伍:`GET /api/team/nearby?lat&lng&radius`。
  ///
  /// 快照 `subpackageRoam/nearby/index.js:121`;`radius` 档位见
  /// `utils/map-team.js` RADII(1000/3000/5000/10000/20000)。
  /// 出参行字段见 `tests/unit/map-team-page-contract.test.js` 的 `team()` 工厂。
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) {
    return _list(
      () => _client.dio.get<Map<String, dynamic>>(
        '/api/team/nearby',
        queryParameters: <String, dynamic>{
          'lat': lat,
          'lng': lng,
          'radius': radiusM,
        },
      ),
      TeamMapLocalFailure.nearby,
    );
  }

  /// 申请加入:`POST /api/team/apply {teamId}`。快照 `index.js:390`。
  ///
  /// 成功回执 `{code:200,msg:'已申请，等待队长同意'}`,`data.applyExpireTime`
  /// 是真实失效时刻(min(申请+24h, 场次开始))——**原样返回给页面回填卡片**,
  /// 服务端没带就返回 null(卡片退回通用规则句,不许断言固定小时数);
  /// 失败按 errorCode 分支
  /// (TICKET_REQUIRED / APPLY_REJECTED / APPLY_PENDING / ALREADY_JOINED /
  /// TEAM_FULL / ACTIVITY_STARTED / TEAM_UNDER_REVIEW / TEAM_NOT_PUBLIC /
  /// APPLY_BLOCKED)。
  Future<Object?> apply(int teamId) async {
    final Map<String, dynamic> body = await _send(
      () => _client.dio.post<Map<String, dynamic>>(
        '/api/team/apply',
        data: <String, dynamic>{'teamId': teamId},
      ),
      TeamMapLocalFailure.apply,
    );
    final Object? data = body['data'];
    return data is Map ? data['applyExpireTime'] : null;
  }

  /// 撤回申请:`POST /api/team/withdraw {teamId}`。快照 `index.js:401`。
  Future<void> withdraw(int teamId) =>
      _post('/api/team/withdraw', <String, dynamic>{'teamId': teamId}, TeamMapLocalFailure.withdraw);

  /// 队长读申请列表:`POST /api/team/applications {teamId}` → `[{memberId, memberName}]`。
  /// 快照 `index.js:415`(页面用 POST;`utils/map-team.js` 注释写的是 GET/POST 都可)。
  Future<List<Map<String, dynamic>>> applications(int teamId) => _list(
    () => _client.dio.post<Map<String, dynamic>>(
      '/api/team/applications',
      data: <String, dynamic>{'teamId': teamId},
    ),
    TeamMapLocalFailure.applications,
  );

  /// 队长处理申请:`POST /api/team/handle {teamId, memberId, approved}`。快照 `index.js:434`。
  Future<void> handle({
    required int teamId,
    required int memberId,
    required bool approved,
  }) => _post('/api/team/handle', <String, dynamic>{
    'teamId': teamId,
    'memberId': memberId,
    'approved': approved,
  }, TeamMapLocalFailure.handle);

  /// 我加入的队伍:`POST /api/team/my {}`
  /// → `[{id, title, joinedCount, maxMembers, status, ownerType, ownerId}]`。
  /// 快照 `index.js:464` 与 `subpackageMember/signup/index.js:208`(静默、空体)。
  /// ⚠️ `ownerType`/`ownerId` 是票夹那行「我的队伍 ›」的落点依据
  ///    (快照 `signup/index.js:219` 按 `ownerType:ownerId` 建索引),别当私有字段丢掉。
  Future<List<Map<String, dynamic>>> myTeams() => _list(
    () => _client.dio.post<Map<String, dynamic>>('/api/team/my'),
    TeamMapLocalFailure.mine,
  );

  /// 我的申请(待审 / 被拒):`POST /api/team/my-applications {}`
  /// → `[{teamId, title, leaderName, applyStatus}]`。快照 `index.js:469`。
  Future<List<Map<String, dynamic>>> myApplications() => _list(
    () => _client.dio.post<Map<String, dynamic>>('/api/team/my-applications'),
    TeamMapLocalFailure.mine,
  );

  /// 建活动队伍:`POST /api/team/create`(JSON)。真源 `utils/team-up.js`。
  ///
  /// 请求体 `{ownerType:2, ownerId, maxMembers}`;joinMode **只在「仅邀请」时**
  /// 传 1 —— 不传由后端默认 2(公开申请制)。回执必须拿到 `data.teamId`
  /// 才算成功(team-up.js 对此是硬校验,拿不到 id 的 200 不能当建成)。
  /// 失败文案分两路:业务失败用后端 msg(兜底「创建队伍失败，请稍后重试」),
  /// 网络失败「网络异常，请稍后重试」且不带 errorCode。
  Future<int> createActivityTeam({
    required int ownerId,
    required int maxMembers,
    bool inviteOnly = false,
  }) async {
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/team/create',
        data: <String, dynamic>{
          'ownerType': 2,
          'ownerId': ownerId,
          'maxMembers': maxMembers,
          if (inviteOnly) 'joinMode': 1,
        },
      );
    } on DioException {
      throw const TeamMapApiException('网络异常，请稍后重试', localReason: TeamMapLocalFailure.network);
    }
    final Map<String, dynamic> body = resp.data ?? const <String, dynamic>{};
    final String errorCode = '${body['errorCode'] ?? ''}'.trim();
    if ((body['code'] as num?)?.toInt() != 200) {
      final String msg = '${body['msg'] ?? ''}'.trim();
      throw TeamMapApiException(
        msg.isEmpty ? '创建队伍失败，请稍后重试' : msg,
        errorCode: errorCode,
        localReason: msg.isEmpty ? TeamMapLocalFailure.create : null,
      );
    }
    final Object? data = body['data'];
    final Object? rawTeamId = data is Map ? data['teamId'] : null;
    final int teamId = rawTeamId is num
        ? rawTeamId.toInt()
        : int.tryParse('${rawTeamId ?? ''}') ?? 0;
    if (teamId <= 0) {
      throw TeamMapApiException('创建队伍失败，请稍后重试', errorCode: errorCode, localReason: TeamMapLocalFailure.create);
    }
    return teamId;
  }

  /// 队长切换加入方式:`POST /api/team/join-mode`。
  ///
  /// ⚠️ **快照无前端调用点** —— 快照里唯一提到它的是
  /// `components/cy/scene-member-order-detail/index.wxml:107-110` 的注释:
  /// 「后端有 POST /api/team/join-mode(队长可随时切),但全仓没有任何前端调用点
  ///  —— 队伍详情页还没接这个控件」。建队那刻的公开/仅邀请走的是
  /// `utils/team-up.js` 里 create 请求体的 `joinMode` 字段(1=仅邀请, 2=公开申请制)。
  /// 所以本方法只把接口接通,请求体形态按 create 的 `joinMode` 推定;
  /// **接 UI 之前需要后端确认 `/api/team/info` 是否下发当前 joinMode**
  /// (拿不到当前值就没法画出开关的初始态,盲切会把「改回公开」也做成「改成仅邀请」)。
  Future<void> setJoinMode({required int teamId, required bool inviteOnly}) =>
      _post('/api/team/join-mode', <String, dynamic>{
        'teamId': teamId,
        'joinMode': inviteOnly ? 1 : 2,
      }, TeamMapLocalFailure.joinMode);

  Future<void> _post(
    String path,
    Map<String, dynamic> body,
    TeamMapLocalFailure fallback,
  ) async {
    await _send(
      () => _client.dio.post<Map<String, dynamic>>(path, data: body, options: RequestSessionScope.options()),
      fallback,
    );
  }

  Future<List<Map<String, dynamic>>> _list(
    Future<Response<Map<String, dynamic>>> Function() request,
    TeamMapLocalFailure fallback,
  ) async {
    final Map<String, dynamic> body = await _send(request, fallback);
    final Object? data = body['data'];
    if (data is! List) throw TeamMapApiException(fallback.message, localReason: fallback);
    return data.whereType<Map<String, dynamic>>().toList();
  }

  /// code==200 才算成功;非 200 把后端 `msg` + `errorCode` 原样抛上来。
  Future<Map<String, dynamic>> _send(
    Future<Response<Map<String, dynamic>>> Function() request,
    TeamMapLocalFailure fallback,
  ) async {
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await request();
    } on DioException {
      // 网络层失败没有 errorCode ⇒ 页面按「只报失败、不改状态」处理。
      throw TeamMapApiException(fallback.message, localReason: fallback);
    }
    final Map<String, dynamic> body = resp.data ?? const <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      final String msg = '${body['msg'] ?? ''}'.trim();
      final String code = '${body['errorCode'] ?? ''}'.trim();
      throw TeamMapApiException(msg.isEmpty ? fallback.message : msg, errorCode: code,
        localReason: msg.isEmpty ? fallback : null);
    }
    return body;
  }
}

/// Authored fallback identity, never inferred from a server message.
enum TeamMapLocalFailure {
  nearby('附近的队伍没能读到'),
  apply('申请没发出去'),
  withdraw('撤回没成功'),
  applications('申请列表没读到'),
  handle('处理没成功'),
  mine('我的队伍没读到'),
  joinMode('加入方式没改成功'),
  create('创建队伍失败，请稍后重试'),
  network('网络异常，请稍后重试');
  const TeamMapLocalFailure(this.message);
  final String message;
}
