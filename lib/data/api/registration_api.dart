import '../../core/network/request_session_scope.dart';
import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/balance_detail.dart';
import '../models/role_info.dart';
import '../models/points_statistics.dart';
import '../models/profile_detail.dart';
import '../models/scan_result.dart';
import '../models/profile_edit.dart';
import '../models/invitation.dart';

/// 个人中心相关接口。对齐后端:
/// - `ApiUmsMemberController`(/api/user)的 `/info`(完整资料卡)。
/// - `ApiRegistrationController`(/api/registration)的 `/join_info`、`/scan_qr_code`。
/// 后端形参为表单 String,用 FormData;非 200 抛异常进 error 态(不兜底假数据)。
class RegistrationApi {
  RegistrationApi(this._client);
  final DioClient _client;

  /// 积分统计:`POST /api/user/points/statistics`。
  ///
  /// ★ 积分页此前只有流水,**没有「我在所有人里排第几」**这层。
  Future<PointsStatistics> pointsStatistics() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/points/statistics',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '统计暂不可用');
    }
    return PointsStatistics.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 我邀请过的人:`POST /api/user/invite_list`。
  ///
  /// ★ App 有「填写邀请人」的入口(设置页),却**看不到自己邀请了谁** ——
  ///   邀请这件事只有输入没有输出。
  ///
  /// ⚠️ 后端用 `getDataTable` 包了一层,列表在 **data.rows** 不是 data。
  /// ★ 带分页与 total。total 用来显示「累计邀请 N 人」并判还有没有下一页 ——
  ///   拿 rows.length 当总数会在第二页出现时**从 10 人跳到 20 人**,
  ///   看着像数据在变。
  Future<({List<InvitedMember> rows, num? total})> invitePage({
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/invite_list',
      data: FormData.fromMap(<String, dynamic>{
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List
        ? data
        : ((data as Map<String, dynamic>?)?['rows'] as List<dynamic>?) ??
            <dynamic>[];
    return (
      rows: rows
          .whereType<Map<String, dynamic>>()
          .map(InvitedMember.fromJson)
          .toList(),
      total: data is Map<String, dynamic> ? data['total'] as num? : null,
    );
  }

  /// 会员**公开**资料:`POST /api/user/public-info`(member_id 必传)。
  ///
  /// ★ 与 `/api/user/info` 的差别不是"字段少一点",是**能不能匿名访问**:
  ///   · `/user/info`        —— 后端 `getAppUserId()` 拿不到就 `error("请先登录")`
  ///   · `/user/public-info` —— 白名单字段,**匿名可访问**(后端注释原话:
  ///     「未登录不算错误:这条接口就是给匿名冷启动用的」)
  ///
  ///   他人主页原来走 `/user/info` —— **游客点别人主页会撞「请先登录」**,
  ///   而这一页本来就该是能逛的。
  ///
  /// ⚠️ 后端对查不到的会员统一回 MEMBER_UNAVAILABLE,**不区分禁用/删除/不存在**
  ///   (mapper 强制 status=1 且 del_flag=0)。前端也别去猜是哪一种。
  Future<ProfileDetail> publicUserInfo(int memberId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/public-info',
      data: FormData.fromMap(<String, dynamic>{
        'member_id': memberId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '该用户不可用');
    }
    return ProfileDetail.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 完整资料卡:`POST /api/user/info`(member_id 留空取当前登录用户)。
  /// 后端回填 followNum/fansNum/likeNum/topicNum/activityNum,success(UmsMember)
  /// → 对象在 data。未登录后端返回 error → 抛异常。
  Future<ProfileDetail> userDetail({int? memberId}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/info',
      data: FormData.fromMap(<String, dynamic>{
        if (memberId != null && memberId > 0) 'member_id': memberId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ProfileDetail.fromJson(data);
  }

  /// 核销第一步:`POST /api/registration/scan_qr_code`(参数 type、code)。
  ///
  /// ★ **返回三态,不是成功/失败两态**(见 [ScanResult] 的长注释):
  ///   交集 ≥2 时后端返回 `error("请选择要核销的章节", data)` —— code 是失败码,
  ///   但 data 里带着候选列表,判据是 **`data.needChapterChoice`** 而不是 code。
  ///
  /// ⚠️ 原来这里直接 `_ensureOk` 抛异常 —— 于是「请选择章节」被当成普通失败,
  ///   **候选列表连同 data 一起丢掉**,商家看到一句红字却没有可选的东西。
  ///   后端注释把这个形态叫「核销是个死胡同」(ApiRegistrationController:1064)。
  Future<ScanResult> scanQrCodeDetailed({
    required String type,
    required String code,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/scan_qr_code',
      data: FormData.fromMap(<String, dynamic>{'type': type, 'code': code}),
    );
    return ScanResult.fromBody(resp.data ?? <String, dynamic>{});
  }

  /// 旧签名薄封装:只回一句话。
  ///
  /// ⚠️ **待迁移**。它拿不到候选列表 —— 需要选章/选站时只能抛异常,
  ///   调用方顶多弹一句「请选择要核销的章节」,而**没有可选的东西**。
  ///   新代码一律用 [scanQrCodeDetailed];这里保留只是因为
  ///   `profile_page.dart` 有未提交的在途改动,不能动它的调用点。
  ///   那份工作合并后,把调用点切到 detailed 版并删掉本方法。
  ///
  /// ★ 但**绝不能**把 needsChoice 当成功返回 —— 那会让商家看到「核销成功」
  ///   放人走,而票根本没核销(后端注释:同一张票可反复核销)。所以这里抛。
  Future<String> scanQrCode({
    required String type,
    required String code,
  }) async {
    final ScanResult r = await scanQrCodeDetailed(type: type, code: code);
    if (r.outcome == ScanOutcome.redeemed) return r.message;
    throw Exception(r.needsChoice
        ? '${r.message}(当前入口不支持选择,请到商家核销页扫码)'
        : r.message);
  }

  /// 核销第二步(按章节):`POST /api/registration/scan_qr_code_chapter`。
  /// `chapterId` 取自第一步返回的候选。
  Future<ScanResult> scanChapter({
    required String code,
    required int chapterId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/scan_qr_code_chapter',
      data: FormData.fromMap(<String, dynamic>{
        'code': code,
        'chapterId': chapterId.toString(),
      }),
    );
    return ScanResult.fromBody(resp.data ?? <String, dynamic>{});
  }

  /// 核销第二步(按站点):`POST /api/registration/scan_qr_code_station`。
  /// ⚠️ 传的是**中标记录 ID**(registrationMerchantId),不是站点 id。
  Future<ScanResult> scanStation({
    required String code,
    required int registrationMerchantId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/scan_qr_code_station',
      data: FormData.fromMap(<String, dynamic>{
        'code': code,
        'registrationMerchantId': registrationMerchantId.toString(),
      }),
    );
    return ScanResult.fromBody(resp.data ?? <String, dynamic>{});
  }

  /// 带队场次里核销队员票:`POST /api/registration/scan_group_member_ticket`。
  Future<ScanResult> scanGroupMemberTicket({
    required String code,
    required int activityId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/scan_group_member_ticket',
      data: FormData.fromMap(<String, dynamic>{
        'code': code,
        'activityId': activityId.toString(),
      }),
    );
    return ScanResult.fromBody(resp.data ?? <String, dynamic>{});
  }

  /// 我的进行中报名详情:`POST /api/registration/join_info`(member_id 留空取本人)。
  /// success(CmsRegistration) → 对象在 data;无进行中报名时后端明确返回
  /// error("查询失败")，该业务空态映射为 null；其他错误仍抛出。
  /// 这里只回原始 Map,调用方按需取字段(避免为单处复用建重模型)。
  Future<Map<String, dynamic>?> joinInfo({int? memberId}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/join_info',
      data: FormData.fromMap(<String, dynamic>{
        'member_id': (memberId != null && memberId > 0)
            ? memberId.toString()
            : '',
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200 && body['msg'] == '查询失败') {
      return null;
    }
    _ensureOk(body);
    final Object? data = body['data'];
    if (data is! Map<String, dynamic> ||
        ((data['id'] as num?)?.toInt() ?? 0) <= 0) {
      throw Exception('报名状态数据异常');
    }
    return data;
  }

  /// AjaxResult 非 200 → 抛异常进 error 态(不兜底假数据)。
  void _ensureOk(Map<String, dynamic> body) {
    final code = (body['code'] as num?)?.toInt();
    if (code != 200) {
      throw Exception((body['msg'] as String?) ?? '请求失败');
    }
  }

  /// 更新个人资料:`POST /api/user/update`(JSON body)。
  ///
  /// ⚠️ 后端会跑**微信内容安全审核**(checkText 覆盖昵称/简介/微信号/网址/地址),
  ///   命中违规直接拒 —— 抛 [ProfileUpdateException] 并标出是不是内容问题,
  ///   让页面决定给不给重试。内容被拒时重试没用,得改文字。
  Future<void> updateProfile(ProfileEditForm form) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/update',
      data: form.toJson(),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      final msg = (body['msg'] as String?) ?? '保存失败';
      throw ProfileUpdateException(msg, contentRejected: isContentRejected(msg));
    }
  }

  /// 绑定邀请人:`POST /api/user/setInviter`(表单 inviter_id)。
  ///
  /// ⚠️ 后端 `bindInviterIfAbsent` **只在还没绑定时生效** —— 已绑过再绑返回失败,
  ///   而失败文案是统一的一句,分不出是"码不对"还是"已绑过"。
  ///   所以失败时抛 [InviterBinding.remoteFailureHint],**把两种可能都说出来
  ///   并明确不用重试**,别让用户反复点一个永远不会成功的按钮。
  Future<void> setInviter(String inviterId) => _setInviter(inviterId);

  Future<void> setInviterForSession(String inviterId, RequestSessionScope scope) =>
      _setInviter(inviterId, scope: scope);

  Future<void> _setInviter(String inviterId, {RequestSessionScope? scope}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/setInviter',
      options: scope == null ? null : Options(extra: {RequestSessionScope.extraKey: scope}),
      data: FormData.fromMap(<String, dynamic>{'inviter_id': inviterId.trim()}),
    );
    if (scope != null && !scope.isCurrent()) {
      throw StateError('Session changed during invitation binding');
    }
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception(InviterBinding.remoteFailureHint);
    }
  }

  /// 收益明细:`POST /api/user/balance/list`。
  ///
  /// ⚠️⚠️ 2026-08-20 更正 —— 这个方法原来**两处都错**,因为它零调用方,
  ///   错了三个月没人发现:
  ///   ① 参数发的是 `change_type`(收支方向)。后端
  ///      `ApiUmsMemberController.getBalanceList(String eventType)` 只收
  ///      **eventType**(事由),`change_type` 被整个忽略 ⇒ 筛选静默失效。
  ///      原注释还振振有词地解释「参数名是 change_type 不是 changeType」——
  ///      它抄的是**另一个端点**(`/api/balance/list`,ApiBalanceController),
  ///      那个才收 change_type。同名不同物。
  ///   ② 解析按裸 List。后端走的是 `startPage()` + `getDataTable()`,
  ///      data 是 `{rows,total}` ⇒ `data as List` 恒 null ⇒ **永远返回空列表**。
  ///      原注释写着「data 是裸 List(不是 getDataTable)」,同样是抄错了对象。
  ///
  /// ★ 教训:一个没人调的客户端方法不是「已经写好了」,是**没被验证过的草稿**。
  Future<({List<BalanceDetail> rows, num? total})> incomeDetail({
    IncomeEventFilter filter = IncomeEventFilter.all,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/balance/list',
      data: FormData.fromMap(<String, dynamic>{
        if (filter.wire.isNotEmpty) 'eventType': filter.wire,
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '流水读取失败');
    }
    final Object? data = body['data'];
    final Map<String, dynamic> table =
        data is Map<String, dynamic> ? data : <String, dynamic>{};
    return (
      rows: ((table['rows'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(BalanceDetail.fromJson)
          .toList(),
      total: table['total'] as num?,
    );
  }

  /// 当前会员角色 + 配额 + 用量:`POST /api/role/info`。
  ///
  /// ★★ 后端把它定为**单一事实源**(注释原话:「下发三端能力位全集,
  ///   前端 roleGuard 一律读这里」)。别在客户端自己推能力 ——
  ///   那是第二份判据,必然和后端漂。
  Future<RoleInfo> roleInfo() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/role/info',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '身份读取失败');
    }
    return RoleInfo.fromJson(
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{});
  }

  /// 赚分规则表 + 我各完成过几次:`POST /api/points/result_list`。
  ///
  /// ⚠️ **不是**「我的积分明细」(那是 `/api/user/points/list`)——
  ///   注释原来就是这么写错的,照它接线会接到错的页面。
  ///   后端 ApiPointsController.resultList 取的是 cms_points_setting(type=1)
  ///   规则表,再逐条填该用户的完成次数。
  /// ⚠️ 未登录**有意**返回 error("请登录"),调用方要把它和网络故障分开说。
  Future<List<Map<String, dynamic>>> pointsResultList() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/points/result_list',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '积分明细读取失败');
    }
    final Object? data = body['data'];
    return (data is List ? data : <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 字典项:`POST /api/common/dict`(表单 dictType)。
  ///
  /// ★ 后端先读缓存、缓存没有再查库 —— 两条路都可能返回**空列表**,
  ///   那是"这个字典没有配项",不是错误。别渲染成加载失败。
  Future<List<Map<String, dynamic>>> dict(String dictType) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/dict',
      data: FormData.fromMap(<String, dynamic>{'dictType': dictType}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '字典读取失败');
    }
    final Object? data = body['data'];
    return (data is List ? data : <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 探店日完局面(图鉴 / 通关奖励到账明细 / 回访入口):
  /// `POST /api/registration/explore-completion`(表单 id = **报名 id**)。
  ///
  /// ★★ 这是**纯读**:不发奖、不补发、不写任何表。
  ///   奖励发放的唯一入口在核销侧,别指望调它能"补一下奖励"。
  ///
  /// ★★ 后端对非探索票的订单是 **fail-closed**:返
  ///   「该订单没有探店日完局面」而不是空壳。后端注释说明了为什么:
  ///   「空壳会让 ①② 的订单详情也渲染出一块『图鉴 0/0』的假读面」。
  ///   ⇒ 前端**不要把这个错误吞成空态** —— 吞了就等于把 fail-closed 又打开。
  Future<Map<String, dynamic>> exploreCompletion(int registrationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/explore-completion',
      data: FormData.fromMap(<String, dynamic>{'id': registrationId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '完局面读取失败');
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 关注 / 取关(**切换式**):`POST /api/user/follow/action`
  /// (表单 `follow_member_id`)。
  ///
  /// ★★ 后端**没有"关注"和"取关"两个接口** —— 一个动作,有记录就删、没记录就加。
  ///   ⇒ 客户端**不能自己维护"我现在是不是关注着"**再决定调哪个;
  ///     只能调一次然后**按后端返回的话**更新界面。
  ///
  /// ★★ 结果**只能从 msg 文案区分**(「关注成功」/「取消关注成功」)——
  ///   后端没给布尔。所以这里返回"现在是否已关注",判据就是那句话。
  ///   ⚠️ 文案一旦改,这里会静默判反。所以两种都不匹配时**抛异常**,
  ///     而不是猜一个 —— 猜错的话按钮会显示成反的,用户再点一次就真的反了。
  ///
  /// ⚠️ 参数名是 **`follow_member_id`**(下划线)。
  Future<bool> toggleFollow(int followMemberId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/follow/action',
      data: FormData.fromMap(<String, dynamic>{
        'follow_member_id': followMemberId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    final String msg = (body['msg'] ?? '').toString();
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception(msg.isEmpty ? '操作失败' : msg);
    }
    // 先判"取消",因为「取消关注成功」里也含「关注成功」四个字。
    if (msg.contains('取消关注')) return false;
    if (msg.contains('关注成功')) return true;
    // ⚠️ 文案给用户看,所以说人话;调试信息靠 msg 本身带出来。
    throw Exception('关注状态没确认下来:$msg');
  }

  /// 公开会员列表:`POST /api/user/list`(表单 user_type / keyword)。
  ///
  /// ⚠️ 参数名都是**下划线**式。user_type:0 所有 / 1 普通会员 / 2 商户会员。
  /// ★ 走 getDataTable ⇒ 列表在 **data.rows**。
  Future<List<Map<String, dynamic>>> publicMemberList({
    String userType = '0',
    String? keyword,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/list',
      data: FormData.fromMap(<String, dynamic>{
        'user_type': userType,
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ((data['rows'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 收件地址详情:`POST /api/user/address/info`(表单 id)。
  ///
  /// ★ 后端用 `selectOwnedAddressById(id, 当前登录人)` —— **归属已经在查询里**,
  ///   查别人的地址返回的是"地址不可用"而不是别人的地址。照原文显示即可。
  Future<Map<String, dynamic>> addressInfo(int addressId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/info',
      data: FormData.fromMap(<String, dynamic>{'id': addressId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '地址读取失败');
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }
}

/// 资料更新失败。[contentRejected] 为真表示是**内容审核**拒了,不是故障。
class ProfileUpdateException implements Exception {
  ProfileUpdateException(this.message, {required this.contentRejected});

  final String message;
  final bool contentRejected;

  @override
  String toString() => message;
}
