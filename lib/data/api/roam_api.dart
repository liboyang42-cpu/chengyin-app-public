import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/city_node_detail.dart';
import '../models/roam.dart';
import '../models/roam_merchant_info.dart';
import '../models/roam_social.dart';

/// 玩家侧据点(漫游域)接口。对齐后端 `ApiCityNodeController`(/api/city)
/// 与 `ApiVerifyController`(/api/verify)。
class RoamApi {
  RoamApi(this._client);
  final DioClient _client;

  /// 商家公开信息(匿名可访问,脱敏):`POST /api/merchant/public-detail`(JSON body)。
  /// 返回商家 + 招牌主推(featured 是顶层兄弟键,不在 data 里)。
  /// ⚠️ 放在 RoamApi 而不是 MerchantApi:唯一调用方是据点详情页;
  ///   merchant_api.dart 是商家工作台域共享文件,避免并发编辑冲突。
  Future<(RoamMerchantInfo, RoamFeatured?)> publicMerchantDetail(
    int merchantId,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/public-detail',
      data: <String, dynamic>{'id': merchantId},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '这次没有读到商家信息,请稍后重试');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if ((data['id'] as num?)?.toInt() == null) {
      throw RoamApiException('这次没有读到商家信息,请稍后重试');
    }
    final Map<String, dynamic>? featuredRaw =
        body['featured'] is Map<String, dynamic>
        ? body['featured'] as Map<String, dynamic>
        : null;
    return (
      RoamMerchantInfo.fromJson(data),
      featuredRaw == null ? null : RoamFeatured.fromJson(featuredRaw),
    );
  }

  /// 据点详情:`GET /api/city/nodes/{id}` → CityNodeDetail。
  /// ⚠️ 「节点不存在」是后端业务空态:抛 [RoamApiException] 并保留原话,
  ///   页面据此显示「据点不存在」而不是可重试的故障。
  Future<CityNodeDetail> nodeDetail(int poiId) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/city/nodes/$poiId',
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '据点不存在');
    }
    return CityNodeDetail.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 收藏/取消收藏(切换):`POST /api/city/nodes/{id}/favorite`。
  /// 返回切换后的收藏态。
  Future<bool> toggleFavorite(int poiId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/city/nodes/$poiId/favorite',
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '操作失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return data['favorited'] == true;
  }

  /// 完成据点互动:`POST /api/city/nodes/{id}/complete`(表单)。
  /// lat/lng 必带 —— 后端有半径二次校验,客户端先取定位再提交。
  Future<CityNodeCompleteResult> completeNode(
    int poiId, {
    required double lat,
    required double lng,
    String answer = '',
    String photoUrl = '',
    String code = '',
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/city/nodes/$poiId/complete',
      data: FormData.fromMap(<String, dynamic>{
        'lat': lat,
        'lng': lng,
        'answer': answer,
        'photoUrl': photoUrl,
        'code': code,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '完成失败');
    }
    return CityNodeCompleteResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 签发我的据点核销码(玩家出码,商家扫码发券):
  /// `POST /api/verify/citynode/issue`(表单 poiId)。
  /// 历史点亮的迷雾格:`GET /api/roam/tiles`(limit 可空)。
  ///
  /// ★ **「恢复版图」** —— 没有它,用户重装 App 或换设备后
  ///   之前点亮的迷雾**全没了**,地图退回一片全黑。
  ///   上一批接了 reveal(写),这条是它的读端,成对。
  Future<List<RoamTile>> tiles({int? limit}) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/tiles',
      queryParameters: <String, dynamic>{
        if (limit != null) 'limit': limit.toString(),
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '版图读取失败');
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List ? data : <dynamic>[];
    return rows
        .map(RoamTile.fromJson)
        .where((RoamTile t) => t.key.isNotEmpty)
        .toList();
  }

  /// 点到店:`POST /api/roam/checkin`。
  ///
  /// ★ **三态,而且全走 success** —— 判据在 data 不在 code
  ///   (见 [RoamCheckinResult]):太远 / 参与据点(要扫码) / 已点亮。
  ///   只判 `code == 200` 会把「离得有点远」当成打卡成功,
  ///   用户站在两条街外,App 告诉他已经到店了。
  Future<RoamCheckinResult> checkin({
    required String name,
    required double poiLat,
    required double poiLng,
    required double curLat,
    required double curLng,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/checkin',
      data: FormData.fromMap(<String, dynamic>{
        'name': name,
        'poiLat': poiLat.toString(),
        'poiLng': poiLng.toString(),
        'curLat': curLat.toString(),
        'curLng': curLng.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '打卡失败');
    }
    return RoamCheckinResult.fromBody(body);
  }

  /// 批量点亮格子:`POST /api/roam/reveal`(sessionId + tiles 逗号分隔)。
  ///
  /// ★ **幂等**(后端 INSERT IGNORE),返回 `newlyRevealed` = 真正新插入的行数。
  ///   所以网络抖动时重发是安全的,而且「这次点亮了几格」必须以返回值为准 ——
  ///   本地按发出去的条数算会把重复的也算上。
  Future<RoamRevealResult> revealTiles({
    required String sessionId,
    required List<String> tiles,
  }) async {
    if (tiles.isEmpty) {
      return RoamRevealResult(sessionId: sessionId, newlyRevealed: 0);
    }
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/reveal',
      data: FormData.fromMap(<String, dynamic>{
        'sessionId': sessionId,
        // 后端读的是逗号分隔的字符串,不是数组
        'tiles': tiles.join(','),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '点亮失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String resolvedSessionId = (data['sessionId'] ?? sessionId)
        .toString();
    if (int.tryParse(resolvedSessionId) == null ||
        int.parse(resolvedSessionId) <= 0) {
      throw RoamApiException('漫游会话创建失败');
    }
    return RoamRevealResult(
      sessionId: resolvedSessionId,
      newlyRevealed: (data['newlyRevealed'] as num?)?.toInt() ?? 0,
    );
  }

  /// 漫游结算:`POST /api/roam/finish`(sessionId + poiIds + distanceM)。
  ///
  /// ★ 这是**唯一**会真正发探索值与勋章的地方。App 此前从没调过它 ——
  ///   漫游全程只存在手机本地,走再多也不涨探索值、拿不到勋章。
  ///
  /// ⚠️ 后端只认服务端校验过的 POI(不采信这里传的 poiIds),并用 CAS 防重复结算;
  ///   已结算再调会返回「本次漫游已结算」。**这不是错误,是正常的重试保护** ——
  ///   调用方应把它当成「已经结过了」而不是弹一个失败提示。
  Future<RoamFinishResult> finishSession({
    required String sessionId,
    required List<int> poiIds,
    required int distanceM,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/finish',
      data: FormData.fromMap(<String, dynamic>{
        'sessionId': sessionId,
        'poiIds': poiIds.join(','),
        'distanceM': distanceM.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '结算失败');
    }
    return RoamFinishResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 漫游会话事实:`GET /api/roam/session`(clientSessionKey 或 sessionId 二选一)。
  ///
  /// 快照 `pages/roam/index.js:1459`(recoverRoam):杀进程/断线之后回来,
  /// 先拿这条核对服务端这一刻的事实 —— **已结束的把 `result` 直接补上**,
  /// 进行中的接着走,没记录的说「没有」。App 目前只在结算重试
  /// (「本次漫游已结算」)那条路上用它把结算结果读回来。
  Future<RoamSessionFact> sessionFact({
    String? clientSessionKey,
    int? sessionId,
  }) async {
    final bool hasKey = clientSessionKey != null && clientSessionKey.isNotEmpty;
    final bool hasId = sessionId != null && sessionId > 0;
    if (!hasKey && !hasId) {
      throw RoamApiException('缺少会话标识,没法核对漫游状态');
    }
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/session',
      queryParameters: <String, dynamic>{
        if (hasKey) 'clientSessionKey': clientSessionKey,
        if (hasId) 'sessionId': sessionId.toString(),
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '漫游状态没能核对,请稍后重试');
    }
    return RoamSessionFact.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 核销据点码(**商家侧**):`POST /api/verify/citynode/redeem`。
  ///
  /// ★ 此前 App 只接了 `issue`(玩家出码),`redeem` 一条没接 ——
  ///   **玩家能出示码、商家扫不了**,整条据点核销链路是断的。
  ///
  /// ⚠️ 后端把三件事做死了,失败文案都很具体,**必须原样透传**:
  ///   · 越权:「您不是商家,无法核销」「无权核销该据点」
  ///     (归属比对的是 roam_poi.merchant_id vs 当前登录 member 解析出的商家 id)
  ///   · 幂等:玩家须已到店打卡(status 0→1 条件更新只成功一次),
  ///     没打卡或已核销都回「玩家未到店打卡,或该券已核销」——
  ///     **那是保护不是故障**,别提示成"网络错误请重试"
  ///   · 库存耗尽会触发整体事务回滚,允许补货后重扫
  ///
  /// 笼统换成「核销失败」会让商家完全不知道下一步该做什么。
  Future<String> redeemCityNodeCode(String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/verify/citynode/redeem',
      data: FormData.fromMap(<String, dynamic>{'code': code}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '核销失败');
    }
    return (body['msg'] as String?) ?? '核销成功';
  }

  Future<CityNodeVoucher> issueCityNodeCode(int poiId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/verify/citynode/issue',
      data: FormData.fromMap(<String, dynamic>{'poiId': poiId}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '暂时无法生成核销码,请稍后重试');
    }
    return CityNodeVoucher.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 附近据点:`GET /api/roam/pois?lat&lng&radius`。
  ///
  /// ⚠️ 这是 **GET + query**,不是 POST 表单 —— 发 POST 会 405。
  /// ⚠️ radius 后端夹在 (0, 20000] 米,默认 3000;传更大不会更远。
  Future<List<RoamPoi>> pois({
    required double lat,
    required double lng,
    int? radiusM,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/pois',
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'radius': ?radiusM,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '据点读取失败');
    }
    return ((body['data'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RoamPoi.fromJson)
        .toList();
  }

  /// 发现据点:`POST /api/roam/poi/discover`(表单 sessionId/poiId/lat/lng)。
  ///
  /// ★ 服务端会用 haversine 复核你**真的到了**(半径 + 30m 容差),
  ///   还会跟上一次到点做瞬移速度校验。被拒时是 `error` 且**不记录**,
  ///   也就意味着 finish 时不会发这个点的 XP —— 所以失败必须让用户看见,
  ///   不能吞掉当作"稍后重试"。
  Future<RoamPoiDiscovered> discoverPoi({
    required int sessionId,
    required int poiId,
    required double lat,
    required double lng,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/poi/discover',
      data: FormData.fromMap(<String, dynamic>{
        'sessionId': sessionId.toString(),
        'poiId': poiId.toString(),
        'lat': lat.toString(),
        'lng': lng.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '发现失败');
    }
    return RoamPoiDiscovered.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      message: (body['msg'] ?? '').toString(),
    );
  }

  /// 到店打卡:`POST /api/roam/shop/visit`。
  ///
  /// ⚠️ `sourceType` 只有两个合法值,别自己发明第三个:
  ///   1 = roam_poi 据点,2 = 报名商家(且**必须是中标的**,后端会拒未中标)。
  /// ★ 店名与坐标一律由后端从来源表读,前端**传了也不采信** —— 别在界面上
  ///   让用户"改一下店名",那只是个不会生效的输入框。
  Future<RoamShopVisit> shopVisit({
    required int sessionId,
    required int sourceType,
    required int sourceId,
    required double lat,
    required double lng,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/shop/visit',
      data: FormData.fromMap(<String, dynamic>{
        'sessionId': sessionId.toString(),
        'sourceType': sourceType.toString(),
        'sourceId': sourceId.toString(),
        'lat': lat.toString(),
        'lng': lng.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '打卡失败');
    }
    return RoamShopVisit.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 附近可参加的自由探索活动:`GET /api/roam/nearby-exploreday?lat&lng`。
  ///
  /// ★ 没有合适的时后端返回 `success(null)` —— 那是**正常态**(附近没活动),
  ///   不是错误,所以返回可空而不抛。
  Future<Map<String, dynamic>?> nearbyExploreDay({
    required double lat,
    required double lng,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/nearby-exploreday',
      queryParameters: <String, dynamic>{'lat': lat, 'lng': lng},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '读取失败');
    }
    return body['data'] as Map<String, dynamic>?;
  }

  /// 连续到店勋章配置:`GET /api/roam/badge/shop-streak`。
  /// 勋章停用时后端给 `success(null)` → 这里返回 null,前端不弹卡。
  Future<ShopStreakBadge?> shopStreakBadge() async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/badge/shop-streak',
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '读取失败');
    }
    final Object? data = body['data'];
    if (data is! Map<String, dynamic>) return null;
    return ShopStreakBadge.fromJson(data);
  }

  /// 集邮入册:`POST /api/roam/stamp/create`(表单 picUrl/caption/idempotencyKey)。
  ///
  /// ★ **必须传 idempotencyKey**。不传的话,网络抖动重试会真的入册第二枚 ——
  ///   而"重拍一张"正是用户在以为没存上时最会做的事。
  Future<RoamStampCreated> createStamp({
    required String picUrl,
    String? caption,
    required String idempotencyKey,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/stamp/create',
      data: FormData.fromMap(<String, dynamic>{
        'picUrl': picUrl,
        if (caption != null && caption.isNotEmpty) 'caption': caption,
        'idempotencyKey': idempotencyKey,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '入册失败');
    }
    return RoamStampCreated.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 我的集邮册:`POST /api/roam/stamp/list`(表单 pageNum/pageSize)。
  Future<RoamStampPage> stampList({int pageNum = 1, int pageSize = 20}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/stamp/list',
      data: FormData.fromMap(<String, dynamic>{
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '集邮册读取失败');
    }
    return RoamStampPage.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  // ══ 漫游社交(附近的局 / 附近的人 / 到店头像堆 / 邮票交换 / 迷雾分页)══
  // 参考后端 `ApiRoamHangoutController`、`ApiRoamController`、`ApiRoamStampController`。

  /// 附近的局 + 有坐标的活动/主题(只读叠加):`GET /api/roam/hangout/nearby`。
  ///
  /// ★ 一屏三类混排(局 kind=hangout / 活动 kind=activity / 主题 kind=topic),
  ///   局之外的两类是只读的,点开走各自整页。
  /// ★ 一个局都没有时后端会给 `suggestedRadius/suggestedCount` ——
  ///   那是引导「拉远一点」的信号,不是错误。
  Future<RoamHangoutNearby> hangoutNearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/hangout/nearby',
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'radius': radiusM,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '附近的局没能打开');
    }
    return RoamHangoutNearby.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 开一个局(免费,加入 = 进群):`POST /api/roam/hangout/create`(表单)。
  ///
  /// ⚠️ 后端闸全在 service,原话必须透传:「标题 2–30 字」「同时最多开 3 个局」
  ///   「账号已被限制,不能开局」「标题或说明含违规内容:…」。
  ///   自己编一句「开局失败」会让用户不知道改哪里。
  Future<RoamHangoutCreated> hangoutCreate({
    required String title,
    String description = '',
    String coverUrl = '',
    required double latitude,
    required double longitude,
    required String addressName,
    String startAt = '',
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/hangout/create',
      data: FormData.fromMap(<String, dynamic>{
        'title': title.trim(),
        'description': description.trim(),
        'coverUrl': coverUrl,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'addressName': addressName,
        // 后端用 DateUtils.parseDate 解析「yyyy-MM-dd HH:mm:ss」;空串=常驻局。
        'startAt': startAt.isEmpty ? '' : '${startAt.trim()}:00',
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '开局失败');
    }
    return RoamHangoutCreated.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 局详情(含头像堆与我的关系):`GET /api/roam/hangout/detail?id=`。
  ///
  /// ⚠️ 「局不存在」「这个局已经关了」都是后端业务空态(404),文案要原样带出去。
  Future<RoamHangoutItem> hangoutDetail(int id) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/hangout/detail',
      queryParameters: <String, dynamic>{'id': id},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '这个局看不了');
    }
    return RoamHangoutItem.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 加入 = 进群(幂等):`POST /api/roam/hangout/join`。
  /// 返回 conversationId,调用方据此进群聊 —— 加入的「回执」就是拿到这个群。
  Future<int> hangoutJoin(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/hangout/join',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200 ||
        (data['conversationId'] as num?)?.toInt() == null) {
      throw RoamApiException((body['msg'] as String?) ?? '进群失败');
    }
    return (data['conversationId'] as num).toInt();
  }

  /// 退出局:`POST /api/roam/hangout/leave`。
  /// ⚠️ 局主不能退,后端回「局主不能退出,只能关局」—— 原话透传。
  Future<void> hangoutLeave(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/hangout/leave',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '退出失败');
    }
  }

  /// 关局(仅局主):`POST /api/roam/hangout/close`。关局后群聊一起关闭。
  Future<void> hangoutClose(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/hangout/close',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '关局失败');
    }
  }

  /// 举报局(进现有审核工作台):`POST /api/roam/hangout/report`。
  /// 返回审核任务 id。成功不弹 toast —— 卡片上的「已举报」就是回执。
  Future<int> hangoutReport({required int id, required String reason}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/hangout/report',
      data: FormData.fromMap(<String, dynamic>{
        'id': id.toString(),
        'reason': reason,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '举报失败');
    }
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return (data['taskId'] as num?)?.toInt() ?? 0;
  }

  /// 上报我此刻的位置(漫游心跳):`POST /api/roam/presence`。
  ///
  /// ★ 这是「附近的人」的**唯一开关**:停止上报,服务端 5 分钟后就把你
  ///   从别人的地图上摘掉。后端坐标截位与 30s 节奏都由服务端定义 ——
  ///   客户端只负责按漫游位移发送,不发精确坐标的额外副本。
  Future<void> reportPresence({
    required String sessionId,
    required double lat,
    required double lng,
    required int explorePct,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/presence',
      data: FormData.fromMap(<String, dynamic>{
        'sessionId': sessionId,
        'lat': lat.toString(),
        'lng': lng.toString(),
        'explorePct': explorePct.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '位置上报失败');
    }
  }

  /// 附近还在走的人:`POST /api/roam/nearby-runners`。
  ///
  /// ★ 返回的是**服务端截位后**的位置(≈100m),只用于「看得出有人在走」;
  ///   拉不到保持上一批,不清空(调用方自己决定)。
  Future<List<RoamRunner>> nearbyRunners({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/nearby-runners',
      data: FormData.fromMap(<String, dynamic>{
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radiusM.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '附近的人读取失败');
    }
    return RoamRunner.normalize(
      (body['data'] as List<dynamic>?) ?? const <dynamic>[],
    );
  }

  /// 谁在这儿打过卡(`sourceType` 1=roam_poi 据点,2=报名商家):
  /// `POST /api/roam/shop/visitors`,一次最多 20 个来源,按请求顺序每个来源回一行。
  Future<List<RoamShopVisitors>> shopVisitors({
    required int sourceType,
    required List<int> sourceIds,
  }) async {
    if (sourceIds.isEmpty) return const <RoamShopVisitors>[];
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/shop/visitors',
      data: FormData.fromMap(<String, dynamic>{
        'sourceType': sourceType.toString(),
        'sourceIds': sourceIds.join(','),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '读过客失败');
    }
    return ((body['data'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RoamShopVisitors.fromJson)
        .toList();
  }

  /// 投一张换一张:`POST /api/roam/stamp/exchange`(表单 givenStampId)。
  ///
  /// ★ `exchanged:false` 是**正常空态**(还没有可以换的票 / 上一张被下架),
  ///   不是故障;失败提示请用后端 `reason` 原话。
  Future<RoamStampExchangeResult> stampExchange(int givenStampId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/roam/stamp/exchange',
      data: FormData.fromMap(<String, dynamic>{
        'givenStampId': givenStampId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '换票失败');
    }
    return RoamStampExchangeResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 迷雾记忆增量页:`GET /api/roam/tiles/page?afterId&limit`。
  ///
  /// ★ 带游标的完整读端。一次最多 2000 格,`hasMore` 为真时拿 `nextAfterId`
  ///   继续翻 —— 小程序换设备/清缓存后就是靠它把版图恢复回来的。
  Future<RoamTilePage> tilesPage({int afterId = 0, int limit = 1000}) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/roam/tiles/page',
      queryParameters: <String, dynamic>{
        'afterId': afterId.toString(),
        'limit': limit.toString(),
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw RoamApiException((body['msg'] as String?) ?? '迷雾记忆读取失败');
    }
    return RoamTilePage.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }
}

/// `GET /api/roam/session` 的三态(快照 `pages/roam/index.js:1462` 的判据)。
enum RoamSessionState { active, finished, notFound }

/// 漫游会话事实。
///
/// ★ **认不出的 state 直接抛,不按 NOT_FOUND 兜** —— 快照同段对白名单外的
///   新值就是按失败处理(`['ACTIVE','FINISHED','NOT_FOUND'].includes(...)` 不成立
///   即 `_recoveryFailure`);兜成「没有记录」会把一次真实会话谎报成从没走过。
class RoamSessionFact {
  const RoamSessionFact({
    required this.state,
    this.sessionId = '',
    this.clientSessionKey = '',
    this.result,
    this.resultComplete = false,
  });

  final RoamSessionState state;
  final String sessionId;
  final String clientSessionKey;

  /// 已结束时服务端带回来的结算事实;进行中 / 没记录时为 null。
  final RoamFinishResult? result;

  /// 结算事实是否已完整落库(快照 `fact.resultComplete`)。
  final bool resultComplete;

  factory RoamSessionFact.fromJson(Map<String, dynamic> json) {
    final RoamSessionState state = switch ('${json['state']}') {
      'ACTIVE' => RoamSessionState.active,
      'FINISHED' => RoamSessionState.finished,
      'NOT_FOUND' => RoamSessionState.notFound,
      _ => throw RoamApiException('漫游状态没能核对,请稍后重试'),
    };
    final Object? result = json['result'];
    return RoamSessionFact(
      state: state,
      sessionId: '${json['sessionId'] ?? ''}',
      clientSessionKey: '${json['clientSessionKey'] ?? ''}',
      result:
          state == RoamSessionState.finished && result is Map<String, dynamic>
          ? RoamFinishResult.fromJson(result)
          : null,
      resultComplete: json['resultComplete'] == true,
    );
  }
}

/// 据点域异常:后端业务空态(据点不存在/未上线)与网络故障都走这里,
/// 由页面按文案分流。
class RoamApiException implements Exception {
  RoamApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
