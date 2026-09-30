import '../../core/network/dio_client.dart';
import '../models/official_event.dart';

/// 官方活动接口。对齐后端 `ApiOfficialEventController`(/api/official)。
///
/// ★ 这一整个域 App 之前**一个端点都没接**,而后端有 16 个。
class OfficialApi {
  OfficialApi(this._client);
  final DioClient _client;

  /// 公开活动列表:`GET /api/official/events`。
  Future<List<OfficialEvent>> events({String? city}) async {
    return _list('/api/official/events', query: <String, dynamic>{'city': ?city});
  }

  /// 活动详情:`GET /api/official/events/{id}`。
  /// ⚠️ 后端查不到时返回 `error("活动不存在")`(code≠200),不是 404。
  Future<OfficialEvent> detail(int id) async {
    final data = await _object('/api/official/events/$id');
    return OfficialEvent.fromJson(data);
  }

  /// 一键报名:`POST /api/official/events/{id}/signup`。后端幂等,不占额度。
  Future<void> signup(int id) => _post('/api/official/events/$id/signup');

  /// 完成任务:`POST /api/official/events/{id}/complete`。
  Future<void> complete(int id) => _post('/api/official/events/$id/complete');

  /// V2 活动到达验证。sessionId 必须是当前账号本次实时漫游的服务端会话。
  Future<OfficialArrivalResult> verifyArrival({
    required int eventId,
    required String missionCode,
    required double latitude,
    required double longitude,
    required double accuracyM,
    required int sessionId,
    required String requestId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/official/events/$eventId/arrivals',
      data: <String, dynamic>{
        'missionCode': missionCode,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyM': accuracyM,
        'sessionId': sessionId,
        'requestId': requestId,
      },
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    return OfficialArrivalResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 我报名的活动:`GET /api/official/my-events`。
  Future<List<OfficialEvent>> myEvents() => _list('/api/official/my-events');

  /// 我的承接邀约收件箱:`GET /api/official/v2/party-inbox`。
  Future<List<PartyInviteItem>> partyInbox() async {
    final resp = await _client.dio.get<Map<String, dynamic>>('/api/official/v2/party-inbox');
    final body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    final raw = body['data'];
    final rows = raw is List
        ? raw
        : (raw is Map<String, dynamic> ? (raw['rows'] as List<dynamic>? ?? const <dynamic>[]) : const <dynamic>[]);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PartyInviteItem.fromJson)
        .toList();
  }

  /// 接受 / 拒绝承接邀约:`POST /api/official/v2/organizer-invites/{partyId}/{accept|decline}`。
  Future<void> respondInvite(int partyId, {required bool accept}) =>
      _post('/api/official/v2/organizer-invites/$partyId/${accept ? 'accept' : 'decline'}');

  /// 我发布的活动 + 通知:`GET /api/official/my-published`。
  ///
  /// ⚠️ 无发布权限时后端返回 `error("无官方发布权限")` —— 这是**正常的权限态**,
  ///   不是故障。调用方要把它显示成「你没有官方发布权限」,别渲染成加载失败。
  Future<MyPublished> myPublished() async {
    final data = await _object('/api/official/my-published');
    return MyPublished.fromJson(data);
  }

  // ----------------------------------------------- 白名单发布者侧
  //
  // ★★ 这一组全部受 **同一道闸** 管:后端 `canPublish(memberId)` 读
  //   sys_config 的 `official_publish_whitelist`(逗号分隔 memberId,**空 = 全部拒绝**)。
  //   非白名单调用一律 `error("无官方发布权限")`。
  //   ⇒ 界面**必须先问 [canPublish] 再决定露不露入口**。
  //     直接摆出来的话,绝大多数用户点下去必然撞一句权限错误 ——
  //     那是"点了必失败的按钮",比没有按钮更坏。

  /// 我有没有官方发布权限:`GET /api/official/can-publish` → `data.canPublish`。
  ///
  /// ★ 这条**不要求登录也不报错**(后端 uid()<=0 时 canPublish 直接 false),
  ///   所以游客调用会安静地拿到 false —— 正是想要的行为。
  Future<bool> canPublish() async {
    final Map<String, dynamic> data = await _object('/api/official/can-publish');
    return data['canPublish'] == true;
  }

  /// 轻发布:创建官方活动 `POST /api/official/publish` → data 是**新活动 id**。
  ///
  /// ⚠️ 后端会做**同步**文本内容安全检查(标题/副标题/故事),不过就 error 原文返回;
  ///   而封面图是**异步**送检 —— 也就是说这里成功**不代表封面已过审**,
  ///   提示只能说「已发布」,不能说「封面已生效」。
  Future<int> publishEvent(Map<String, dynamic> event) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/official/publish',
      data: event,
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    final Object? id = body['data'];
    if (id is! num) {
      throw OfficialApiException('发布没返回活动号 —— 别当成功了');
    }
    return id.toInt();
  }

  /// 官方批量邀请商家承接:`POST /api/official/invites`。
  ///
  /// ⚠️ 订阅消息通知是 **best-effort**(后端逐个 try/ignore)——
  ///   接口成功**不代表商家收到了通知**。文案别写「已通知商家」,
  ///   只能写「已发出邀约」。
  Future<List<int>> inviteMerchants(Map<String, dynamic> request) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/official/invites',
      data: request,
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    return ((body['data'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<num>()
        .map((num e) => e.toInt())
        .toList();
  }

  /// 官方邀约跟踪列表:`GET /api/official/invites`(可按 status 筛)。
  Future<List<Map<String, dynamic>>> officialInvites({int? status}) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/official/invites',
      queryParameters: <String, dynamic>{'status': ?status},
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    return ((body['data'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 发官方通知/公告:`POST /api/official/broadcast` → data 是**通知 id**。
  ///
  /// ⚠️ 后端返回的话是「通知已提交」,不是「已送达」。分角色文案在 contentJson 里,
  ///   同样过同步文本安全检查。
  Future<int> broadcast(Map<String, dynamic> bc) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/official/broadcast',
      data: bc,
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    final Object? id = body['data'];
    if (id is! num) {
      throw OfficialApiException('通知没返回编号 —— 别当已发出');
    }
    return id.toInt();
  }

  /// 通知触达/点击复盘:`GET /api/official/broadcast/{id}/stats`。
  ///
  /// ★ 后端做了**归属校验**:白名单内也只能看自己发的那条,
  ///   别人的返回 `error("通知不存在")` —— 那是防互看,不是"这条没了"。
  Future<Map<String, dynamic>> broadcastStats(int id) =>
      _object('/api/official/broadcast/$id/stats');

  /// 官方通知点击回流:`POST /api/official/broadcast/{id}/click?channel=`。
  ///
  /// ★ 这是**埋点**,不是业务动作:后端未登录时直接 `success()` 什么都不做。
  ///   所以它**永远不该把失败抛给用户** —— 点击回流失败了,
  ///   用户要去的那个页面照样得打开。
  Future<void> reportBroadcastClick(int id, {String? channel}) async {
    try {
      await _client.dio.post<Map<String, dynamic>>(
        '/api/official/broadcast/$id/click',
        queryParameters: <String, dynamic>{'channel': ?channel},
      );
    } catch (_) {
      // 埋点失败不影响用户动作,故意吞掉。
    }
  }

  /// 商家/俱乐部对本场活动邀约的处置:
  /// `POST /api/official/v2/parties/{partyId}/{action}`。
  ///
  /// ⚠️ action 是**路径的一段**,不是 body 字段。后端认的值见 [OfficialPartyAction];
  ///   拼错会走进 service 的兜底错误,而不是 404。
  Future<void> respondParty(
    int partyId,
    OfficialPartyAction action, {
    String? reason,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/official/v2/parties/$partyId/${action.wire}',
      data: <String, dynamic>{'reason': ?reason},
    );
    _assertOk(resp.data ?? <String, dynamic>{});
  }

  Future<List<OfficialEvent>> _list(String path, {Map<String, dynamic>? query}) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(path, queryParameters: query);
    final body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    final rows = (body['data'] as List<dynamic>?) ?? const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(OfficialEvent.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> _object(String path) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(path);
    final body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  Future<void> _post(String path) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path);
    _assertOk(resp.data ?? <String, dynamic>{});
  }

  /// 后端一律 HTTP 200 + body.code 表达失败,不看 code 等于没做错误处理。
  void _assertOk(Map<String, dynamic> body) {
    if (body['code'] != 200) {
      throw OfficialApiException((body['msg'] as String?) ?? '请求失败');
    }
  }
}

/// 带上后端原话的异常 —— 「无官方发布权限」这类需要按文案分流。
class OfficialApiException implements Exception {
  OfficialApiException(this.message);
  final String message;

  /// 是不是「没权限」而非「出错了」。两者的界面应当完全不同。
  bool get isNoPermission => message.contains('无官方发布权限');

  @override
  String toString() => message;
}

/// 承接邀约收件箱条目。
class PartyInviteItem {
  const PartyInviteItem({
    required this.partyId,
    required this.title,
    required this.partyType,
    this.eventTitle,
    this.status,
    this.city,
  });

  final int partyId;
  final String title;

  /// ★★ 决定**用哪条接口处置**,不是装饰:
  ///   · `OFFICIAL` → `/v2/organizer-invites/{id}/{accept|decline}`(需白名单)
  ///   · `MERCHANT` / `CLUB` → `/v2/parties/{id}/{ACCEPT|DECLINE|WITHDRAW}`
  ///   后端两条路**互斥**:respondParty 对 OFFICIAL 直接回
  ///   「官方主办关系只能由专用受控命令处理」;
  ///   而 organizer-invites 要白名单,商家调用得到「无官方发布权限」。
  ///   ⇒ 全都走 organizer-invites 的话,**商家点接受必然报权限错误**。
  final String? partyType;

  final String? eventTitle;

  /// ⚠️ 后端字段名是 **status**(SQL 里就是 `p.status`),不是 `state`。
  ///   读错名字不会报错,只会恒为 null —— 于是"还能不能操作"恒真,
  ///   已接受的邀约照样显示「接受/拒绝」两个按钮,点下去撞
  ///   「当前邀约不可接受」。
  ///   取值:INVITED / ACCEPTED / ACTIVE(收件箱只查这三种)。
  final String? status;

  final String? city;

  /// 这条是不是走商家/俱乐部那条路径。
  bool get isPartyRoute => partyType == 'MERCHANT' || partyType == 'CLUB';

  /// 当前状态下**真能做**的动作(仅对 MERCHANT/CLUB 有意义)。
  List<OfficialPartyAction> get actions =>
      isPartyRoute ? OfficialPartyAction.availableFor(status) : const <OfficialPartyAction>[];

  /// 官方主办邀约只有"待接受"时能处置。
  bool get organizerActionable => partyType == 'OFFICIAL' && status == 'INVITED';

  factory PartyInviteItem.fromJson(Map<String, dynamic> json) {
    return PartyInviteItem(
      partyId: (json['partyId'] as num?)?.toInt() ?? (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ??
          (json['partyName'] as String?) ??
          (json['responsibilitySummary'] as String?) ??
          '承接邀约',
      partyType: json['partyType'] as String?,
      eventTitle: json['eventTitle'] as String?,
      status: json['status'] as String?,
      city: json['city'] as String?,
    );
  }
}

/// 我发布的活动 + 通知。
class MyPublished {
  const MyPublished({this.events = const <OfficialEvent>[], this.broadcasts = const <OfficialBroadcast>[]});

  final List<OfficialEvent> events;
  final List<OfficialBroadcast> broadcasts;

  bool get isEmpty => events.isEmpty && broadcasts.isEmpty;

  factory MyPublished.fromJson(Map<String, dynamic> json) {
    return MyPublished(
      events: ((json['events'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(OfficialEvent.fromJson)
          .toList(),
      broadcasts: ((json['broadcasts'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(OfficialBroadcast.fromJson)
          .toList(),
    );
  }
}

class OfficialBroadcast {
  const OfficialBroadcast({required this.id, required this.title, this.content, this.reach = 0});

  final int id;
  final String title;
  final String? content;
  final int reach;

  factory OfficialBroadcast.fromJson(Map<String, dynamic> json) {
    return OfficialBroadcast(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      content: json['content'] as String?,
      reach: (json['reach'] as num?)?.toInt() ?? 0,
    );
  }
}
