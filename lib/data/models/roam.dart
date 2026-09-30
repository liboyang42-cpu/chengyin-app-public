/// 漫游结算结果(`/api/roam/finish`)。
///
/// ★ **服务端说了算,客户端一个数都不许自己算**。后端把三件事做死了
/// (ApiRoamController:368-430):
///   ① POI 只认服务端 `/poi/discover` 校验过到点的记录,**不采信客户端传的 poiIds**
///      —— 防伪造 poiId 刷 XP;
///   ② 格子数套今日 200 上限;
///   ③ 用 `status 0→1` 的 CAS 抢结算权,抢不到直接返回「本次漫游已结算」。
/// 所以结束屏上的数字必须**等这个返回**再显示,不能本地先算一个漂亮的。
class RoamFinishResult {
  const RoamFinishResult({
    this.tileXp = 0,
    this.poiXp = 0,
    this.totalXp = 0,
    this.newTiles = 0,
    this.newPois = 0,
    this.tilesEver = 0,
    this.medal,
    this.sessionShops = 0,
    this.shopMedal,
  });

  final int tileXp;
  final int poiXp;
  final int totalXp;
  final int newTiles;
  final int newPois;

  /// 累计点亮格子数(跨会话)。
  final int tilesEver;

  /// 本次拿到的里程碑勋章名。★ **没拿到就是 null,不是空字符串** ——
  /// 空串会让界面渲出一个没有名字的勋章位。
  final String? medal;

  final int sessionShops;

  /// 服务端成功落入 player_badge 后返回的权威三店连亮勋章。
  final ShopStreakBadge? shopMedal;

  factory RoamFinishResult.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    final String medal = (json['medal'] ?? '').toString().trim();
    final Object? shopMedal = json['shopMedal'];
    return RoamFinishResult(
      tileXp: i('tileXp'),
      poiXp: i('poiXp'),
      totalXp: i('totalXp'),
      newTiles: i('newTiles'),
      newPois: i('newPois'),
      tilesEver: i('tilesEver'),
      medal: medal.isEmpty ? null : medal,
      sessionShops: i('sessionShops'),
      shopMedal: shopMedal is Map<String, dynamic>
          ? ShopStreakBadge.fromJson(shopMedal)
          : null,
    );
  }
}

/// 「点到店」的结果(`/api/roam/checkin`)。**三态,而且全走 success。**
///
/// ★ 后端把三种结果都用 `AjaxResult.success` 返回,靠 `data` 里的标志分辨
///   (ApiRoamController:457-495):
///     ① `tooFar: true`        —— 离得太远,什么都没发生
///     ② `participating: true` —— 这是**参与据点**,要走扫码核销(带 poiId)
///     ③ `participating: false`—— 非参与点,已直接点亮;`firstVisit` 决定发不发探索值
///
/// ⚠️ 只判 `code == 200` 会把「离得有点远」当成打卡成功 ——
///   用户站在两条街外,App 告诉他已经到店了。
enum RoamCheckinOutcome {
  /// 离得太远,没有点亮。
  tooFar,

  /// 参与据点:需要接着走扫码核销。
  needsScan,

  /// 已点亮(非参与点)。
  lit,
}

class RoamCheckinResult {
  const RoamCheckinResult({
    required this.outcome,
    required this.message,
    this.poiId,
    this.firstVisit = false,
    this.xp = 0,
  });

  final RoamCheckinOutcome outcome;

  /// 后端原话(如「离得有点远,走近点」)—— 一律透传,别自己另编。
  final String message;

  /// 参与据点的 id,用于跳去扫码。★ 只有 [RoamCheckinOutcome.needsScan] 才有。
  final int? poiId;

  /// 是否首次到这个点。★ 决定发不发探索值(每点终身一次)——
  /// 非首次也是成功点亮,别渲成失败。
  final bool firstVisit;

  /// 首亮发的探索值(服务端真值,源 `r.xp`)。★ 只在 [firstVisit] 时有意义。
  final int xp;

  factory RoamCheckinResult.fromBody(Map<String, dynamic> body) {
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String msg = (body['msg'] as String?) ?? '';

    if (data['tooFar'] == true) {
      return RoamCheckinResult(
        outcome: RoamCheckinOutcome.tooFar,
        message: msg.isEmpty ? '离得有点远,走近点' : msg,
      );
    }
    if (data['participating'] == true) {
      return RoamCheckinResult(
        outcome: RoamCheckinOutcome.needsScan,
        message: msg.isEmpty ? '这是参与据点,去扫码核销' : msg,
        poiId: (data['poiId'] as num?)?.toInt(),
      );
    }
    final bool firstVisit = data['firstVisit'] == true;
    return RoamCheckinResult(
      outcome: RoamCheckinOutcome.lit,
      message: msg.isEmpty ? (firstVisit ? '已点亮' : '已点亮过') : msg,
      firstVisit: firstVisit,
      xp: (data['xp'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一个已点亮的迷雾格。
class RoamTile {
  const RoamTile({required this.key});

  /// 后端下发的格子标识(字符串形态)。
  final String key;

  factory RoamTile.fromJson(Object? raw) {
    if (raw is Map) {
      final Object? k = raw['tileKey'] ?? raw['key'] ?? raw['tile'];
      return RoamTile(key: (k ?? '').toString());
    }
    return RoamTile(key: (raw ?? '').toString());
  }
}

/// 迷雾揭示回执。`sessionId` 是首次 reveal 由服务端懒创建的真实会话号，
/// 后续发现、到店和结算必须沿用它。
class RoamRevealResult {
  const RoamRevealResult({
    required this.sessionId,
    required this.newlyRevealed,
  });

  final String sessionId;
  final int newlyRevealed;
}

/// 漫游据点(`roam_poi`):`GET /api/roam/pois?lat&lng&radius`。
///
/// ★ 后端按**外接矩形**粗筛(dLat/dLng 换算),不是真圆 ——
///   返回的点里会有略超出 radius 的,需要展示距离时自己算,别当成"都在半径内"。
class RoamPoi {
  const RoamPoi({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.type = 1,
    this.radiusM,
    this.address,
    this.description,
    this.xp,
    this.couponTemplateId,
  });

  final int id;
  final String name;
  final double lat;
  final double lng;

  /// 1=城市地点，2=商户据点（商户走 shop/visit，不走 poi/discover）。
  final int type;

  /// 到点判定半径(米)。后端:自带优先,否则默认 120,另有 30m GPS 容差。
  final int? radiusM;

  final String? address;
  final String? description;

  /// 发现该点可得的经验。
  final int? xp;

  /// 该点绑定的券模板;非空才有"到点发券"。
  final int? couponTemplateId;

  static double? _dec(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  factory RoamPoi.fromJson(Map<String, dynamic> json) => RoamPoi(
    id: json['id'] is num ? (json['id'] as num).toInt() : 0,
    name: (json['name'] ?? '').toString(),
    // BigDecimal 有可能以字符串下发,只认 num 会静默变 0 → 所有点堆到几内亚湾。
    lat: _dec(json['lat']) ?? 0,
    lng: _dec(json['lng']) ?? 0,
    type: json['type'] is num ? (json['type'] as num).toInt() : 1,
    radiusM: json['radiusM'] is num ? (json['radiusM'] as num).toInt() : null,
    address: json['address']?.toString(),
    description: json['description']?.toString(),
    xp: json['xp'] is num ? (json['xp'] as num).toInt() : null,
    couponTemplateId: json['couponTemplateId'] is num
        ? (json['couponTemplateId'] as num).toInt()
        : null,
  );
}

/// 集邮票(`roam_stamp`):`POST /api/roam/stamp/list`。
///
/// ★ `checkState` 是**机审状态**,不是"通没通过"的布尔:
///   0=未送检(机审关闭或送检失败时的诚实值,图确实逃过了机审)
///   1=通过  2=违规(后端会自动移出册子)
///   把 0 当成"没过审"而隐藏,会让机审关闭时整本册子空掉。
class RoamStamp {
  const RoamStamp({
    required this.id,
    required this.picUrl,
    this.caption,
    required this.checkState,
    this.createTime,
  });

  final int id;
  final String picUrl;
  final String? caption;
  final int checkState;
  final String? createTime;

  /// 该不该显示在册子里。**未送检(0)照显示** —— 见类注释。
  bool get visible => checkState != 2;

  factory RoamStamp.fromJson(Map<String, dynamic> json) => RoamStamp(
    id: json['id'] is num ? (json['id'] as num).toInt() : 0,
    picUrl: (json['picUrl'] ?? '').toString(),
    caption: json['caption']?.toString(),
    checkState: json['checkState'] is num
        ? (json['checkState'] as num).toInt()
        : 0,
    createTime: json['createTime']?.toString(),
  );
}

/// 集邮册一页。
class RoamStampPage {
  const RoamStampPage({
    required this.list,
    required this.total,
    required this.pageNum,
    required this.pageSize,
  });

  final List<RoamStamp> list;
  final int total;
  final int pageNum;
  final int pageSize;

  bool get hasMore => pageNum * pageSize < total;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  factory RoamStampPage.fromJson(Map<String, dynamic> json) => RoamStampPage(
    list: (json['list'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RoamStamp.fromJson)
        .toList(),
    total: _int(json['total']),
    pageNum: _int(json['pageNum']),
    pageSize: _int(json['pageSize']),
  );
}

/// 集邮入册结果。
class RoamStampCreated {
  const RoamStampCreated({required this.id, required this.idempotent});

  final int id;

  /// true = **同键重放命中了原来那枚票**,没有新入册第二枚。
  ///
  /// ★ 提示必须区分:说"已入册"是对的,说"又收藏了一枚"是错的 ——
  ///   用户会以为册子里多了一张,回去数发现没有。
  final bool idempotent;

  factory RoamStampCreated.fromJson(Map<String, dynamic> json) =>
      RoamStampCreated(
        id: json['id'] is num ? (json['id'] as num).toInt() : 0,
        idempotent: json['idempotent'] == true,
      );
}

/// 连续到店勋章的配置:`GET /api/roam/badge/shop-streak`。
///
/// ★ 后端在勋章**停用**时返回 `success(null)` —— 不是错误。
///   这时前端也不该弹卡。所以这里用可空返回而不是抛异常。
class ShopStreakBadge {
  const ShopStreakBadge({
    required this.code,
    required this.name,
    this.statement,
    this.iconUrl,
    this.threshold,
  });

  final String code;
  final String name;
  final String? statement;
  final String? iconUrl;

  /// 解锁门槛(连续到店次数)。
  final int? threshold;

  factory ShopStreakBadge.fromJson(Map<String, dynamic> json) =>
      ShopStreakBadge(
        code: (json['code'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        statement: json['statement']?.toString(),
        iconUrl: json['iconUrl']?.toString(),
        threshold: json['threshold'] is num
            ? (json['threshold'] as num).toInt()
            : null,
      );
}

/// 发现据点的结果:`POST /api/roam/poi/discover`。
///
/// ★ `discovered` 区分「首次发现」与「以前就发现过」——
///   后端 msg 分别是「发现新地点」/「已发现过」。
///   两者都是 success,只判 code 会把重复到点也庆祝一遍。
class RoamPoiDiscovered {
  const RoamPoiDiscovered({
    required this.discovered,
    required this.poiId,
    required this.xp,
    this.drop,
    this.meaning,
    required this.message,
  });

  /// true = 这次是**首次**发现(库里真插进去了一行)。
  /// false = 之前就发现过,**不再发 XP**。
  final bool discovered;

  final int poiId;

  /// 该点的经验值。⚠️ 这是**该点的面值**,不是"本次到手的" ——
  /// `discovered == false` 时并没有真发。别直接拿它做「+20 经验」的飘字。
  final int xp;

  /// 掉落(仅首次发现商户据点时可能有)。
  final Map<String, dynamic>? drop;

  /// 地点意义文案。内容层故障时后端会静默省略它,发现结果照常 —— 所以可空。
  final String? meaning;

  /// 后端原话:「发现新地点」/「已发现过」。
  final String message;

  factory RoamPoiDiscovered.fromJson(
    Map<String, dynamic> json, {
    required String message,
  }) => RoamPoiDiscovered(
    discovered: json['discovered'] == true,
    poiId: json['poiId'] is num ? (json['poiId'] as num).toInt() : 0,
    xp: json['xp'] is num ? (json['xp'] as num).toInt() : 0,
    drop: json['drop'] as Map<String, dynamic>?,
    meaning: json['meaning']?.toString(),
    message: message,
  );
}

/// 到店打卡的结果:`POST /api/roam/shop/visit`。
class RoamShopVisit {
  const RoamShopVisit({required this.recorded, required this.shops});

  /// true = 这次真记上了;false = 这家店本次会话已经打过。
  final bool recorded;

  /// 本次会话已打卡的**不同店铺**数(后端 count distinct)。
  /// 三店连亮的进度就看它。
  final int shops;

  factory RoamShopVisit.fromJson(Map<String, dynamic> json) => RoamShopVisit(
    recorded: json['recorded'] == true,
    shops: json['shops'] is num ? (json['shops'] as num).toInt() : 0,
  );
}
