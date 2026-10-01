import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/request_session_scope.dart';
import '../models/registration_cancellation_outcome.dart';
import '../models/club.dart';
import '../models/club_comment.dart';
import '../models/club_post.dart';
import '../models/club_manage.dart';

/// 后端业务错误(AjaxResult.code != 200),携带后端原文 msg。
class ClubApiException implements Exception {
  ClubApiException(this.message, {this.data, this.isLocal = false});
  final bool isLocal;
  final String message;

  /// 后端回的错误明细(如解散阻断的 actionItems)。
  final Map<String, dynamic>? data;

  @override
  String toString() => message;
}

/// 俱乐部(社群)接口。对齐后端 `ApiClubController`(/api/club)。
/// 注意:list/members 的 data 直接是 List(非 data.rows 分页);
/// detail 的 data 直接是对象。join/quit 用 body {id}(Club body)。
/// 管理类接口(create/update/dissolve/join-request 等)要求 JSON body,
/// 后端 @RequestBody,裸对象会走 urlencoded → 415(名册打不开的教训)。
class ClubApi {
  ClubApi(this._client);
  final DioClient _client;

  /// 俱乐部目录(已通过):`POST /api/club/list` → `success(List<Club>)`。
  Future<List<Club>> list() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/club/list',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .map((dynamic e) => Club.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 按名搜索:`POST /api/club/list`(JSON body {name})。
  /// 后端 list 收 `@RequestBody Club`,JSON body 才能绑上 name;空 FormData 绑不上。
  /// 用于搜索结果页的俱乐部分组(与小程序 discover-search 同参)。
  Future<List<Club>> searchByName(String name) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/club/list',
      data: <String, dynamic>{'name': name},
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .map((dynamic e) => Club.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 俱乐部详情:`POST /api/club/detail`(body {id}) → success(Club)。
  Future<Club> detail(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/club/detail',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return Club.fromJson(data);
  }

  /// 俱乐部成员:`POST /api/club/members`(body {clubId}) → `success(List<ClubMember>)`。
  Future<List<ClubMember>> members(int clubId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/club/members',
      data: FormData.fromMap(<String, dynamic>{'clubId': clubId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .map((dynamic e) => ClubMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 加入俱乐部(即时):`POST /api/club/join`(body {id})。
  /// 返 `data.state` —— 真源判据 `state === 'joined'` 才算直进,
  /// 其余(私密团进待审)是另一种回执,两种都要说清,不许把 pending 显示成已入群。
  Future<String?> join(int clubId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/club/join',
      data: FormData.fromMap(<String, dynamic>{'id': clubId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = body['data'];
    return data is Map ? data['state']?.toString() : null;
  }

  /// 退出俱乐部:`POST /api/club/quit`(body {id})。
  Future<void> quit(int clubId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/club/quit',
      data: FormData.fromMap(<String, dynamic>{'id': clubId.toString()}),
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  /// AjaxResult 非 200 → 抛异常进 error 态(不兜底假数据)。
  void _ensureOk(Map<String, dynamic> body) {
    final code = (body['code'] as num?)?.toInt();
    if (code != 200) {
      final data = body['data'];
      throw ClubApiException(
        (body['msg'] as String?) ?? '请求失败',
        isLocal: body['msg'] == null,
        data: data is Map<String, dynamic> ? data : null,
      );
    }
  }

  /// JSON body 的 POST(管理类接口全部要求 @RequestBody JSON)。
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: RequestSessionScope.options(Options(contentType: Headers.jsonContentType)),
    );
    return resp.data ?? <String, dynamic>{};
  }

  /// 我的俱乐部:`POST /api/club/my` → `data.owned` 是 List。
  Future<List<Club>> my() async {
    final body = await _postJson('/api/club/my', <String, dynamic>{});
    _ensureOk(body);
    final raw = body['data'];
    final Map<String, dynamic> data = raw is Map<String, dynamic>
        ? raw
        : const <String, dynamic>{};
    final list = (data['owned'] as List<dynamic>?) ?? <dynamic>[];
    return list.whereType<Map<String, dynamic>>().map(Club.fromJson).toList();
  }

  /// 成为俱乐部主理人(填完即有):`POST /api/club/become-leader`。
  Future<void> becomeLeader(Map<String, dynamic> payload) async {
    final body = await _postJson('/api/club/become-leader', payload);
    _ensureOk(body);
  }

  /// 创建俱乐部:`POST /api/club/create` → data 可能带 clubId/id。
  Future<int> create(Map<String, dynamic> payload) async {
    final body = await _postJson('/api/club/create', payload);
    _ensureOk(body);
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      final id = (data['clubId'] ?? data['id']) as num?;
      return id?.toInt() ?? 0;
    }
    return 0;
  }

  /// 更新我的俱乐部:`POST /api/club/update-mine`(带 id 改指定团)。
  Future<void> updateMine(Map<String, dynamic> payload) async {
    final body = await _postJson('/api/club/update-mine', payload);
    _ensureOk(body);
  }

  /// 解散俱乐部:`POST /api/club/dissolve`。
  /// 需 `dissolveConfirmed: true`;有非创建者成员时还需 `memberConsequencesConfirmed: true`。
  /// 后端有资金阻断时抛 [ClubApiException](data.actionItems 为阻断明细)。
  Future<void> dissolve({
    required int id,
    required bool memberConsequencesConfirmed,
  }) async {
    final body = await _postJson('/api/club/dissolve', <String, dynamic>{
      'id': id,
      'dissolveConfirmed': true,
      'memberConsequencesConfirmed': memberConsequencesConfirmed,
    });
    _ensureOk(body);
  }

  /// 俱乐部办的经典定向团:`POST /api/club/topics`(body {id})。
  Future<List<ClubTopic>> topics(int clubId) async {
    final body = await _postJson('/api/club/topics', <String, dynamic>{
      'id': clubId,
    });
    _ensureOk(body);
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ClubTopic.fromJson)
        .toList();
  }

  /// 入会申请列表:`POST /api/club/join-requests`。
  Future<List<JoinRequest>> joinRequests(int clubId) async {
    final body = await _postJson('/api/club/join-requests', <String, dynamic>{
      'clubId': clubId,
    });
    _ensureOk(body);
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(JoinRequest.fromJson)
        .toList();
  }

  /// 通过/拒绝入会申请:`POST /api/club/join-request/approve|reject`。
  Future<void> reviewJoinRequest({
    required int clubId,
    required int memberId,
    required bool approve,
  }) async {
    final body = await _postJson(
      approve
          ? '/api/club/join-request/approve'
          : '/api/club/join-request/reject',
      <String, dynamic>{'clubId': clubId, 'memberId': memberId},
    );
    _ensureOk(body);
  }

  /// 解散前资金阻断:`POST /api/club/dissolution-blockers`(body {id})。
  Future<DissolutionBlockers> dissolutionBlockers(int clubId) async {
    final body = await _postJson(
      '/api/club/dissolution-blockers',
      <String, dynamic>{'id': clubId},
    );
    _ensureOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return DissolutionBlockers.fromJson(data);
  }

  /// 重试合作保证金原路退款:`POST /api/coop/deposit/refund/retry`。
  ///
  /// 小程序 `coop/list/index.js:900-915` 的回执判据:只有「code 200 +
  /// data.refundState 是字符串 + msg 非空」才算说清了结果,否则是
  /// 「结果暂无法确认」。把这两样原样交给调用方,不在这层编文案。
  Future<({String msg, bool refundStateGiven})> retryDepositRefund(
    int inviteId,
  ) async {
    final body = await _postJson(
      '/api/coop/deposit/refund/retry',
      <String, dynamic>{'inviteId': inviteId},
    );
    _ensureOk(body);
    final data = body['data'];
    return (
      msg: (body['msg'] as String?)?.trim() ?? '',
      refundStateGiven:
          data is Map<String, dynamic> && data['refundState'] is String,
    );
  }

  /// 报名名册(owner/admin 专用):`POST /api/club/topic-registrations`。
  /// ⚠️ 必须 JSON body,裸对象走 urlencoded → 415。
  Future<TeamDetail> topicRegistrations({
    required int clubId,
    required int topicId,
  }) async {
    final body = await _postJson(
      '/api/club/topic-registrations',
      <String, dynamic>{'clubId': clubId, 'topicId': topicId},
    );
    _ensureOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return TeamDetail.fromJson(data);
  }

  /// 主理人清退某条报名并退款:`POST /api/registration/cancel-by-owner`。
  Future<RegistrationCancellationOutcome> cancelRegistrationByOwner(int registrationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/cancel-by-owner',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'id': registrationId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return RegistrationCancellationOutcome.fromResponse(body);
  }

  /// 俱乐部帖文流:`POST /api/club/post/feed`(JSON body)。
  ///
  /// ⚠️ 返回 `{rows, clubCount}`。**clubCount 为 0 表示"我还没加入任何俱乐部"** ——
  ///   那和"加入了但大家没发帖"是两回事,界面必须分开说。
  /// 移除成员:`POST /api/club/remove-member`。
  ///
  /// ★ 此前俱乐部详情的「管理」区只有编辑资料 / 报名名册 / 入会申请 ——
  ///   **主理人加了人之后没法移除**,也没法设管理员。后端两条一直都在。
  ///
  /// ⚠️ 权限:**只有创建者**(club.memberId)能移除,role==1 的管理员**不能**
  ///   (ApiClubController:577-579)。移除创建者本人会被拒(「不能移除俱乐部创建者」)。
  ///   后端还会一并清理 IM 关系,失败整体回滚。
  Future<String> removeMember({
    required int clubId,
    required int memberId,
  }) async {
    final body = await _postJson('/api/club/remove-member', <String, dynamic>{
      'clubId': clubId,
      'memberId': memberId,
    });
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '移除失败');
    }
    return (body['msg'] as String?) ?? '已移除成员';
  }

  /// 设为 / 取消管理员:`POST /api/club/set-member-role`(role: 1 管理员 / 0 普通)。
  ///
  /// ⚠️ 同样**只有创建者**能做;创建者自己不需要设(会回「创建者无需设置角色」)。
  /// ⚠️ **管理员最多 2 个** —— 超了后端回「管理员最多 2 个,请先取消其他管理员」。
  ///   那句话带着可执行信息,别吞成「设置失败」。
  Future<String> setMemberRole({
    required int clubId,
    required int memberId,
    required bool admin,
  }) async {
    final body = await _postJson('/api/club/set-member-role', <String, dynamic>{
      'clubId': clubId,
      'memberId': memberId,
      'role': admin ? 1 : 0,
    });
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '设置失败');
    }
    return (body['msg'] as String?) ?? (admin ? '已设为管理员' : '已取消管理员');
  }

  /// 某条动态的评论列表:`POST /api/club/post/comment/list`(公开)。
  Future<List<ClubComment>> postComments(
    int postId, {
    int pageNum = 1,
    int pageSize = 50,
  }) async {
    final body = await _postJson(
      '/api/club/post/comment/list',
      <String, dynamic>{
        'postId': postId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final Object? data = body['data'];
    // 后端有时下发 {rows:[...]},有时直接是数组 —— 两种都收。
    final List<dynamic> rows = data is List
        ? data
        : ((data as Map<String, dynamic>?)?['rows'] as List<dynamic>?) ??
              <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ClubComment.fromJson)
        .toList();
  }

  /// 发一条评论。
  Future<void> createComment({
    required int postId,
    required String content,
  }) async {
    final body = await _postJson(
      '/api/club/post/comment/create',
      <String, dynamic>{'postId': postId, 'content': content},
    );
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '发送失败');
    }
  }

  /// 删除一条评论。
  ///
  /// ⚠️ 后端放行的**不止作者本人** —— 俱乐部创建者与 role==1 的管理员也能删
  /// (canModerate:171-179),这是社区代管语义。越权会回「无权删除」。
  Future<String> deleteComment(int commentId) async {
    final body = await _postJson(
      '/api/club/post/comment/delete',
      <String, dynamic>{'id': commentId},
    );
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '删除失败');
    }
    return (body['msg'] as String?) ?? '已删除';
  }

  /// 举报一条评论。⚠️ 只入审核队列,**不立即删** —— 提示别说「已删除」。
  Future<String> reportComment(int commentId) async {
    final body = await _postJson(
      '/api/club/post/comment/report',
      <String, dynamic>{'id': commentId},
    );
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '举报失败');
    }
    return (body['msg'] as String?) ?? '举报已提交,将进入审核';
  }

  /// 单个俱乐部的动态列表(不是聚合流):`POST /api/club/post/list`。
  Future<List<ClubPost>> clubPosts(
    int clubId, {
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final body = await _postJson('/api/club/post/list', <String, dynamic>{
      'clubId': clubId,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List
        ? data
        : ((data as Map<String, dynamic>?)?['rows'] as List<dynamic>?) ??
              <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ClubPost.fromJson)
        .toList();
  }

  /// 点赞 / 取消点赞。★ 后端是**切换式**的:已赞再调一次就是取消
  /// (ApiClubController:1152 —— 查到已有点赞记录就删掉并 -1)。
  /// 所以调用方不要传「想变成什么」,直接调,然后**以服务端返回为准刷新**。
  Future<void> likePost(int postId) async {
    final body = await _postJson('/api/club/post/like', <String, dynamic>{
      'postId': postId,
    });
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
  }

  /// 发一条俱乐部动态。
  ///
  /// ⚠️ 图片后端存的是**分号分隔的字符串**(见 ClubPost.images 的解析),
  ///   传的时候要按同一个约定拼回去 —— 传数组后端不认。
  Future<void> createPost({
    required int clubId,
    required String content,
    List<String> images = const <String>[],
  }) async {
    final body = await _postJson('/api/club/post/create', <String, dynamic>{
      'clubId': clubId,
      'content': content,
      if (images.isNotEmpty) 'images': images.join(';'),
    });
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '发布失败');
    }
  }

  Future<String> updatePost({
    required int postId,
    required String content,
    required List<String> images,
    required int version,
    required String requestId,
  }) async {
    final body = await _postJson('/api/club/post/update', <String, dynamic>{
      'id': postId,
      'content': content,
      'images': images.join(';'),
      'version': version,
      'requestId': requestId,
    });
    _ensureOk(body);
    return (body['msg'] as String?) ?? '已更新';
  }

  Future<String> setPostPinned({
    required int postId,
    required bool pinned,
    required int version,
    required String requestId,
  }) async {
    final body = await _postJson('/api/club/post/pin', <String, dynamic>{
      'id': postId,
      'pinned': pinned,
      'version': version,
      'requestId': requestId,
    });
    _ensureOk(body);
    return (body['msg'] as String?) ?? (pinned ? '已置顶' : '已取消置顶');
  }

  Future<List<ClubPostRevision>> postHistory(int postId) async {
    final body = await _postJson('/api/club/post/history', <String, dynamic>{
      'id': postId,
    });
    _ensureOk(body);
    return ((body['data'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ClubPostRevision.fromJson)
        .toList(growable: false);
  }

  static int _clubPostRequestSequence = 0;
  static String newPostMutationRequestId(String action, int postId) =>
      'club-post-$action-$postId-${DateTime.now().microsecondsSinceEpoch}-${_clubPostRequestSequence++}';

  /// 删除自己发的动态。归属由后端判,前端只决定显示哪个入口。
  Future<String> deletePost(int postId) async {
    final body = await _postJson('/api/club/post/delete', <String, dynamic>{
      'id': postId,
    });
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '删除失败');
    }
    return (body['msg'] as String?) ?? '已删除';
  }

  /// 举报一条俱乐部动态。
  ///
  /// ⚠️ 与广场举报同一条纪律:只入审核队列、**不立即下架**,提示别说「已删除」。
  Future<String> reportPost(int postId) async {
    final body = await _postJson('/api/club/post/report', <String, dynamic>{
      'id': postId,
    });
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '举报失败');
    }
    return (body['msg'] as String?) ?? '举报已提交,将进入审核';
  }

  Future<ClubFeed> postFeed({int pageNum = 1, int pageSize = 20}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/club/post/feed',
      data: <String, dynamic>{'pageNum': pageNum, 'pageSize': pageSize},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    return ClubFeed.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 俱乐部首页四段:`POST /api/club/home`。
  ///
  /// ★ 别用 `list()` 顶替它。`list()` 是**扁平目录**,
  ///   分不出「我创建的 / 我加入的 / 附近」,也完全没有「俱乐部活动」那一段。
  Future<ClubHome> home() async {
    final body = await _postJson('/api/club/home', <String, dynamic>{});
    _ensureOk(body);
    return ClubHome.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 俱乐部贡献榜:`POST /api/club/leaderboard`(body {id, sortBy})。
  ///
  /// ⚠️ body 的键是 **`id`**,不是 clubId —— 后端 `badgeLong(body.get("id"))`。
  ///   传错键会走进 `error("缺少俱乐部ID")`,而不是返回空榜。
  Future<List<ClubRankRow>> leaderboard(
    int clubId, {
    ClubRankSort sort = ClubRankSort.composite,
  }) async {
    final body = await _postJson('/api/club/leaderboard', <String, dynamic>{
      'id': clubId,
      'sortBy': sort.wire,
    });
    _ensureOk(body);
    return ((body['data'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ClubRankRow.fromJson)
        .toList();
  }

  /// 可对接商家目录:`POST /api/club/merchants`。
  /// 后端强制 coopOpen=1 + status=1 + delFlag=0,前端传这三个没意义。
  Future<List<Map<String, dynamic>>> coopMerchants({String? name}) async {
    final body = await _postJson('/api/club/merchants', <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
    });
    _ensureOk(body);
    return ((body['data'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 进入/创建俱乐部群聊:`POST /api/club/chat`(body {id})→ `data.conversationId`。
  ///
  /// ★ 非成员会拿到 `error("加入俱乐部后才能进群聊")` —— 那是**正常业务态**,
  ///   要照原文提示,别渲成「群聊打不开」。
  Future<int> chatConversationId(int clubId) async {
    final body = await _postJson('/api/club/chat', <String, dynamic>{
      'id': clubId,
    });
    _ensureOk(body);
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Object? id = data['conversationId'];
    if (id is! num) {
      throw ClubApiException('群聊没能打开,请稍后重试');
    }
    return id.toInt();
  }
}
