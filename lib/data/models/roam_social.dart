/// 漫游社交域模型:附近的局 / 附近正在走的人 / 到店头像堆 / 邮票交换 / 迷雾分页。
///
/// ★ 字段名一律照后端 `RoamHangoutServiceImpl.hangoutItem`、`ApiRoamController`
///   (nearby-runners / shop-visitors)与 `RoamStampListVO` 的原样拼写,
///   别改写成自己觉得顺手的名字 —— 小程序、App、后端三端共用同一套契约。
library;

import 'roam.dart';

/// 局成员简介(详情里那排头像)。
class RoamHangoutMember {
  const RoamHangoutMember({
    required this.memberId,
    required this.nickname,
    this.avatar,
  });

  final int memberId;
  final String nickname;
  final String? avatar;

  factory RoamHangoutMember.fromJson(Map<String, dynamic> json) =>
      RoamHangoutMember(
        memberId: (json['memberId'] as num?)?.toInt() ?? 0,
        nickname: (json['nickname'] ?? '').toString(),
        avatar: json['avatar']?.toString(),
      );
}

/// 附近的局 / 主题 / 活动的一张卡。
///
/// ★ 三类共用一条记录(`kind` 区分),它们的字段并不完全一样 ——
///   局是 `title`,主题与活动是 `name`;局有 `isMember/full/memberCount`,
///   主题有 `productType`(1=城市定向 2=自由探索),活动有 `startDate`。
///   所以这里全部可空,**按 kind 取用**,不硬编成三个类 —— 地图那一行
///   本来就是三类混排的。
class RoamHangoutItem {
  const RoamHangoutItem({
    required this.kind,
    required this.id,
    this.title,
    this.name,
    this.description,
    this.coverUrl,
    this.picUrl,
    this.ownerId,
    this.ownerAvatar,
    this.ownerNickname,
    this.ownerRole,
    this.full = false,
    this.latitude,
    this.longitude,
    this.addressName,
    this.startAt,
    this.startDate,
    this.status,
    this.memberCount = 0,
    this.isMember = false,
    this.isOwner = false,
    this.distance,
    this.conversationId,
    this.productType,
    this.members = const <RoamHangoutMember>[],
    this.reported = false,
  });

  final String kind;
  final int id;
  final String? title;
  final String? name;
  final String? description;
  final String? coverUrl;
  final String? picUrl;
  final int? ownerId;
  final String? ownerAvatar;
  final String? ownerNickname;

  /// player / merchant / club —— 地图上决定头像框形态,详情里决定「商家局 / 公开局」。
  final String? ownerRole;
  final bool full;
  final double? latitude;
  final double? longitude;
  final String? addressName;
  final String? startAt;
  final String? startDate;
  final int? status;
  final int memberCount;
  final bool isMember;
  final bool isOwner;
  final double? distance;
  final int? conversationId;

  /// 主题玩法:1=城市定向(按顺序) 2=自由探索(不限顺序)。
  final int? productType;
  final List<RoamHangoutMember> members;

  /// 本机是否已经举报过这个局(界面上把「举报」换成「已举报」)。
  /// 后端不返回它 —— 这是提交成功后的界面状态,不是服务端字段。
  final bool reported;

  bool get isHangout => kind == 'hangout';
  bool get isTopic => kind == 'topic';
  bool get isActivity => kind == 'activity';

  /// 卡片主标题:局用 title,主题/活动用 name。
  String get label => (title ?? name ?? '').toString();

  /// 发布者是不是商家/俱乐部(按身份字段,不再靠颜色反推)。
  bool get isMerchantOwner => ownerRole == 'merchant' || ownerRole == 'club';

  static double? _dec(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  factory RoamHangoutItem.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawMembers = json['members'] as List<dynamic>? ??
        const <dynamic>[];
    return RoamHangoutItem(
      kind: (json['kind'] ?? 'hangout').toString(),
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      picUrl: json['picUrl']?.toString(),
      ownerId: (json['ownerId'] as num?)?.toInt(),
      ownerAvatar: json['ownerAvatar']?.toString(),
      ownerNickname: json['ownerNickname']?.toString(),
      ownerRole: json['ownerRole']?.toString(),
      full: json['full'] == true,
      // 主题/活动是 latitude/longitude;部分接口也会下发 lat/lng 简写。
      latitude: _dec(json['latitude'] ?? json['lat']),
      longitude: _dec(json['longitude'] ?? json['lng']),
      addressName: json['addressName']?.toString(),
      startAt: json['startAt']?.toString(),
      startDate: json['startDate']?.toString(),
      status: (json['status'] as num?)?.toInt(),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      isMember: json['isMember'] == true,
      isOwner: json['isOwner'] == true,
      distance: _dec(json['distance']),
      conversationId: (json['conversationId'] as num?)?.toInt(),
      productType: (json['productType'] as num?)?.toInt(),
      members: rawMembers
          .whereType<Map<String, dynamic>>()
          .map(RoamHangoutMember.fromJson)
          .toList(),
    );
  }
}

/// `GET /api/roam/hangout/nearby` 的整包:
/// items 是三类混排;冷启动时后端额外给 suggestedRadius/suggestedCount(拉远提示)。
class RoamHangoutNearby {
  const RoamHangoutNearby({
    required this.items,
    this.radius,
    this.suggestedRadius,
    this.suggestedCount,
  });

  final List<RoamHangoutItem> items;
  final int? radius;
  final int? suggestedRadius;
  final int? suggestedCount;

  factory RoamHangoutNearby.fromJson(Map<String, dynamic> json) =>
      RoamHangoutNearby(
        items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(RoamHangoutItem.fromJson)
            .toList(),
        radius: (json['radius'] as num?)?.toInt(),
        suggestedRadius: (json['suggestedRadius'] as num?)?.toInt(),
        suggestedCount: (json['suggestedCount'] as num?)?.toInt(),
      );
}

/// 建局回执。conversationId 就是那个群 —— 加入 = 进群,开局也直接进群。
class RoamHangoutCreated {
  const RoamHangoutCreated({required this.id, required this.conversationId});

  final int id;
  final int conversationId;

  factory RoamHangoutCreated.fromJson(Map<String, dynamic> json) =>
      RoamHangoutCreated(
        id: (json['id'] as num?)?.toInt() ?? 0,
        conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      );
}

/// 附近正在走的人(`POST /api/roam/nearby-runners`)。
///
/// ★ 隐私口径(后端 ApiRoamController 写死的三条,前端不许放宽):
///   坐标已在服务端截到 3 位小数(≈100m);只有昵称/头像/地盘%/探店数/
///   在走时长/点亮的店这几样 —— 没有真名、没有精确坐标。停止上报即消失,
///   不给「一直在线」的开关。
class RoamRunner {
  const RoamRunner({
    required this.memberId,
    required this.nickname,
    this.avatar,
    required this.lat,
    required this.lng,
    this.explorePct = 0,
    this.shops = 0,
    this.elapsedSec = 0,
    this.shopPhotos = const <RoamRunnerShopPhoto>[],
  });

  final int memberId;
  final String nickname;
  final String? avatar;
  final double lat;
  final double lng;
  final int explorePct;
  final int shops;
  final int elapsedSec;
  final List<RoamRunnerShopPhoto> shopPhotos;

  static double? _dec(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  /// 没有 memberId 或没有坐标的一律丢 —— 既画不出 marker,也点不开半屏。
  /// ⚠️ 缺坐标**不能当 0 处理**:0,0 在几内亚湾,会把一个不存在的人
  ///   画到地球另一端(小程序 normalizeRunners 同款判据)。
  static RoamRunner? tryFromJson(Map<String, dynamic> json) {
    final int id = (json['memberId'] as num?)?.toInt() ?? 0;
    final double? lat = _dec(json['lat']);
    final double? lng = _dec(json['lng']);
    if (id <= 0 || lat == null || lng == null) return null;
    return RoamRunner(
      memberId: id,
      nickname: (json['nickname'] ?? '').toString().isEmpty
          ? '漫游者'
          : (json['nickname'] ?? '').toString(),
      avatar: json['avatar']?.toString(),
      lat: lat,
      lng: lng,
      explorePct: ((json['explorePct'] as num?)?.toInt() ?? 0).clamp(0, 99),
      shops: ((json['shops'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
      elapsedSec: (json['elapsedSec'] as num?)?.toInt() ?? 0,
      shopPhotos:
          (json['shopPhotos'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RoamRunnerShopPhoto.fromJson)
              .where((RoamRunnerShopPhoto p) => p.image.isNotEmpty)
              .toList(),
    );
  }

  static List<RoamRunner> normalize(List<dynamic> rows) => rows
      .whereType<Map<String, dynamic>>()
      .map(tryFromJson)
      .whereType<RoamRunner>()
      .toList();
}

/// TA 点亮的店(那一排小图)。
class RoamRunnerShopPhoto {
  const RoamRunnerShopPhoto({required this.name, required this.image});

  final String name;
  final String image;

  factory RoamRunnerShopPhoto.fromJson(Map<String, dynamic> json) =>
      RoamRunnerShopPhoto(
        name: (json['name'] ?? '').toString(),
        image: (json['image'] ?? '').toString(),
      );
}

/// 谁在这儿打过卡(`POST /api/roam/shop/visitors`)。
///
/// ★ 后端**按请求顺序每个来源回一行**,没人打过卡的也回(total=0)——
///   前端才能分清「这家没人来过」和「这家没查到」。
class RoamShopVisitors {
  const RoamShopVisitors({
    required this.sourceId,
    this.avatars = const <String>[],
    this.total = 0,
  });

  final int sourceId;
  final List<String> avatars;
  final int total;

  factory RoamShopVisitors.fromJson(Map<String, dynamic> json) =>
      RoamShopVisitors(
        sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
        avatars: (json['avatars'] as List<dynamic>? ?? const <dynamic>[])
            .map((Object? a) => (a ?? '').toString())
            .where((String a) => a.isNotEmpty)
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
      );
}

/// 投一张换一张的回执(`POST /api/roam/stamp/exchange`)。
///
/// ★ 三态要分开,**不能只看 code**:`exchanged:false` + reason 是正常空态
///   (还没有可换的票 / 上一张被机审下架),不是网络故障;
///   `idempotent:true` 表示这枚回礼之前就换过了(重试命中),不是换了两张。
class RoamStampExchangeResult {
  const RoamStampExchangeResult({
    required this.exchanged,
    this.reason,
    this.stamp,
    this.idempotent = false,
  });

  final bool exchanged;
  final String? reason;
  final RoamStamp? stamp;
  final bool idempotent;

  factory RoamStampExchangeResult.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['stamp'];
    return RoamStampExchangeResult(
      exchanged: json['exchanged'] == true,
      reason: json['reason']?.toString(),
      stamp: raw is Map<String, dynamic> ? RoamStamp.fromJson(raw) : null,
      idempotent: json['idempotent'] == true,
    );
  }
}

/// 迷雾记忆增量页(`GET /api/roam/tiles/page`)。
class RoamTilePage {
  const RoamTilePage({
    required this.tiles,
    required this.nextAfterId,
    required this.hasMore,
  });

  final List<String> tiles;
  final int nextAfterId;
  final bool hasMore;

  factory RoamTilePage.fromJson(Map<String, dynamic> json) => RoamTilePage(
    tiles: (json['tiles'] as List<dynamic>? ?? const <dynamic>[])
        .map((Object? t) => (t ?? '').toString())
        .where((String t) => t.isNotEmpty)
        .toList(),
    nextAfterId: (json['nextAfterId'] as num?)?.toInt() ?? 0,
    hasMore: json['hasMore'] == true,
  );
}
