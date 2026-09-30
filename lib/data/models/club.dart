/// 俱乐部(社群)。对齐后端 `Club` / `/api/club`。
class Club {
  Club({
    required this.id,
    required this.name,
    this.logo,
    this.cover,
    this.description,
    this.clubTypes,
    this.address,
    this.categoryId,
    this.memberCount = 0,
    this.isJoined = false,
    this.isOwner = false,
    this.viewerIsAdmin = false,
    this.clubType,
    this.activityPrefs = const <String>[],
    this.city,
    this.keywords,
    this.style,
    this.level = 0,
    this.joinPolicy = 0,
    this.joinPolicySupported = false,
    this.prioritySignupEnabled = false,
    this.memberReservedQuota = 0,
    this.nonOwnerMemberCount = 0,
    this.leaderName,
    this.pendingJoinRequestCount = 0,
    this.myJoinStatus,
    this.publicVisible = true,
    this.memberPostAllowed = true,
    this.merchantUndertakeOpen = true,
  });

  final int id;
  final String name;
  final String? logo;
  final String? cover;
  final String? description;
  final String? clubTypes;
  final String? address;
  final int? categoryId;
  final int memberCount;
  final bool isJoined;
  final bool isOwner;

  /// 当前查看者是不是这个俱乐部的**管理员**（后端 `/api/club/detail` 下发的
  /// `viewerIsAdmin`）。小程序 2026-08-26 起用它当 legacyCanGovern 的第二判据
  /// （`canGovern = isOwner || viewerIsAdmin`），不再从成员行 role==1 推导。
  final bool viewerIsAdmin;

  /// 俱乐部大类(校园社团/旅行组织/兴趣社群/商业活动组织方/内容创作团队/其他)。
  /// 与创建/编辑表单的 typeOptions 一一对应。
  final String? clubType;

  /// 路线方向偏好(多选,逗号拼接成串)。创建/编辑表单同源。
  final List<String> activityPrefs;

  /// 所在城市(地理强相关,创建必填)。
  final String? city;

  /// 自定义关键词(逗号分隔文本)。
  final String? keywords;

  /// 风格一句话(作为详情页 tagline 候补)。
  final String? style;

  /// 主理人定级 L1-L5;0 = 未定级(不对外显示)。
  final int level;

  /// 加入策略:0 公开直接加入,1 需主理人审批。
  final int joinPolicy;

  /// 后端是否支持 joinPolicy 字段(不支持时后端会忽略提交值)。
  final bool joinPolicySupported;

  /// 是否开启成员优先报名(创建/编辑页的开关)。
  final bool prioritySignupEnabled;

  /// 成员保留名额(prioritySignupEnabled 开启时生效)。
  final int memberReservedQuota;

  /// 非创建者成员数(解散确认「成员后果」一档用的判据)。
  final int nonOwnerMemberCount;

  /// 主理人姓名(详情页 tagline 候补)。
  final String? leaderName;

  /// 待审批入会申请数(管理 tab「入会申请」角标)。
  final int pendingJoinRequestCount;

  /// 当前账号的入会申请状态。小程序约定:0 待审批 / 1 已加入 / 2 已拒绝。
  /// 缧失时不能猜成待审批，否则公开俱乐部会被错误锁死。
  final int? myJoinStatus;

  /// 「开放设置」三开关,只在创建者(isOwner)自己看时才有意义。
  /// 写入走 `/api/club/open-settings/*`(一开关一端点),每次写完**回读**服务端给的值。
  ///
  /// ★ 缺字段按小程序口径算**开**:小程序写的是 `club.publicVisible != 0`,
  ///   JS 里 `undefined != 0` 为真 —— 这里照抄,不自作主张翻成关。
  final bool publicVisible;
  final bool memberPostAllowed;
  final bool merchantUndertakeOpen;

  bool get joinPending => myJoinStatus == 0;

  /// 需审批。
  bool get needsApproval => joinPolicy == 1;

  /// 小程序 `canGovern`：主理人本人或旧式管理员（detail.viewerIsAdmin）。
  /// 管理入口的 legacy 判据，与 access/me 下发的细粒度权限位并列。
  bool get canGovern => isOwner || viewerIsAdmin;

  factory Club.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return Club(
      id: asInt(json['id']),
      name: (json['name'] ?? '') as String,
      logo: json['logo'] as String?,
      cover: json['cover'] as String?,
      description: json['description'] as String?,
      clubTypes: json['clubTypes'] as String?,
      address: json['address'] as String?,
      categoryId: (json['categoryId'] as num?)?.toInt(),
      memberCount: asInt(json['memberCount']),
      isJoined: (json['isJoined'] as bool?) ?? false,
      isOwner: (json['isOwner'] as bool?) ?? false,
      viewerIsAdmin: json['viewerIsAdmin'] == true,
      clubType: json['clubType'] as String?,
      activityPrefs: ((json['activityPrefs'] as String?) ?? '')
          .split(',')
          .where((String s) => s.trim().isNotEmpty)
          .toList(),
      city: json['city'] as String?,
      keywords: json['keywords'] as String?,
      style: json['style'] as String?,
      level: asInt(json['level']),
      joinPolicy: asInt(json['joinPolicy']) == 1 ? 1 : 0,
      joinPolicySupported: (json['joinPolicySupported'] as bool?) ?? false,
      prioritySignupEnabled: asInt(json['prioritySignupEnabled']) == 1,
      memberReservedQuota: asInt(json['memberReservedQuota']),
      nonOwnerMemberCount: asInt(json['nonOwnerMemberCount']),
      leaderName: json['leaderName'] as String?,
      pendingJoinRequestCount: asInt(json['pendingJoinRequestCount']),
      myJoinStatus: json['myJoinStatus'] is num
          ? (json['myJoinStatus'] as num).toInt()
          : null,
      publicVisible: json['publicVisible'] == null
          ? true
          : asInt(json['publicVisible']) != 0,
      memberPostAllowed: json['memberPostAllowed'] == null
          ? true
          : asInt(json['memberPostAllowed']) != 0,
      merchantUndertakeOpen: json['merchantUndertakeOpen'] == null
          ? true
          : asInt(json['merchantUndertakeOpen']) != 0,
    );
  }
}

/// 俱乐部成员。对齐后端 `ClubMember`(连表带出 nickname/avatar)。
class ClubMember {
  ClubMember({
    required this.memberId,
    this.nickname,
    this.avatar,
    this.role = 0,
    this.isOwner = false,
  });

  final int memberId;
  final String? nickname;
  final String? avatar;

  /// 0 普通成员,1 创建者/管理。
  final int role;

  /// 这个成员**是不是俱乐部创建者**(后端 `cm.isOwner = club.memberId == cm.memberId`)。
  ///
  /// ⚠️ 别和 `Club.isOwner` 混:那个说的是「**我**是不是创建者」,
  ///   这个说的是「**这一行的人**是不是创建者」。管理成员时两个都要用:
  ///   前者决定给不给管理入口,后者决定这一行能不能被移除
  ///   (后端会拒:「不能移除俱乐部创建者」)。
  final bool isOwner;

  /// 是不是管理员(role==1)。⚠️ 管理员**不能**管理成员 ——
  /// 后端只放行创建者(ApiClubController:577-579)。
  bool get isAdmin => role == 1;

  /// 展示用昵称。拿不到就用 id 兜底,不留空行。
  String get displayName {
    final String n = (nickname ?? '').trim();
    return n.isEmpty ? '用户$memberId' : n;
  }

  factory ClubMember.fromJson(Map<String, dynamic> json) => ClubMember(
    memberId: (json['memberId'] as num?)?.toInt() ?? 0,
    nickname: json['nickname'] as String?,
    avatar: json['avatar'] as String?,
    role: (json['role'] as num?)?.toInt() ?? 0,
    isOwner: json['isOwner'] == true,
  );
}

/// 俱乐部首页四段:`POST /api/club/home`。
///
/// ★ App 原来的俱乐部页只有一个扁平的 `/api/club/list`,
///   小程序那边是**分段**的:我创建的 / 我加入的 / 附近发现 / 俱乐部活动。
///   扁平列表看起来"有数据",但**我自己的俱乐部混在陌生俱乐部里**,
///   而且完全没有"俱乐部活动"这一段 —— 那是入口不是装饰。
class ClubHome {
  const ClubHome({
    required this.owned,
    required this.joined,
    required this.nearby,
    required this.events,
  });

  /// 我创建的(后端已置 isOwner=true)
  final List<Club> owned;

  /// 我加入的(后端已置 isJoined=true)
  final List<Club> joined;

  /// 附近发现:已通过、且排除了 owned/joined,后端截前 10
  final List<Club> nearby;

  /// 我创建的俱乐部名下的经典定向团,后端截前 20。
  /// 后端是手搭的 Map(id/title/cover/clubId),不是 CmsTopic 实体,别按主题模型解析。
  final List<ClubHomeEvent> events;

  bool get isEmpty =>
      owned.isEmpty && joined.isEmpty && nearby.isEmpty && events.isEmpty;

  static List<Club> _clubs(Object? raw) =>
      (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Club.fromJson)
          .toList();

  factory ClubHome.fromJson(Map<String, dynamic> json) => ClubHome(
    owned: _clubs(json['owned']),
    joined: _clubs(json['joined']),
    nearby: _clubs(json['nearby']),
    events: (json['events'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ClubHomeEvent.fromJson)
        .toList(),
  );
}

/// 俱乐部活动条目(后端 `/api/club/home` 里手搭的 Map)。
class ClubHomeEvent {
  const ClubHomeEvent({
    required this.id,
    required this.title,
    this.cover,
    required this.clubId,
  });

  final int id;
  final String title;
  final String? cover;
  final int clubId;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  factory ClubHomeEvent.fromJson(Map<String, dynamic> json) => ClubHomeEvent(
    id: _int(json['id']),
    // 后端键是 title/cover,不是主题实体的 name/imgUrl —— 照实体解析会全空。
    title: (json['title'] ?? '').toString(),
    cover: json['cover']?.toString(),
    clubId: _int(json['clubId']),
  );
}

/// 排行榜一行:`POST /api/club/leaderboard`。
///
/// ★ 两个字段的 **null 有语义,不能兜成 0**:
///   · `pace`(配速 min/km):零里程或零用时时后端显式给 null,
///     兜成 0 = 「0.0 分钟每公里」= 无限快,会**稳居榜首**;
///   · `completionDuration`(完成用时):同理,0 不是「0 分钟完成」,
///     而是单节点/缺有效计时。
///   后端排序用 nullsLast 把它们沉底,前端也必须显示成「—」而不是 0。
class ClubRankRow {
  const ClubRankRow({
    required this.memberId,
    this.nickname,
    this.avatar,
    required this.score,
    required this.clearCount,
    required this.mileage,
    required this.durationMin,
    required this.hostedCount,
    this.pace,
    this.completionDuration,
  });

  final int memberId;
  final String? nickname;
  final String? avatar;

  /// 综合分(后端加权算好下发,前端别自己再算一遍)
  final num score;

  /// 通关团数
  final int clearCount;

  /// 累计里程 km
  final num mileage;

  /// 累计用时(分钟)
  final num durationMin;

  /// 带团次数
  final int hostedCount;

  /// 配速 min/km。**null = 无配速**,别写成 0。
  final num? pace;

  /// 完成用时(分钟)。**null = 无有效计时**,别写成 0。
  final num? completionDuration;

  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static num _num(Object? v) => v is num ? v : 0;

  /// 只在「后端确实给了数」时返回值;缺席/null 一律 null。
  static num? _nullable(Object? v) => v is num ? v : null;

  factory ClubRankRow.fromJson(Map<String, dynamic> json) => ClubRankRow(
    memberId: _int(json['memberId']),
    nickname: json['nickname']?.toString(),
    avatar: json['avatar']?.toString(),
    score: _num(json['score']),
    clearCount: _int(json['clearCount']),
    mileage: _num(json['mileage']),
    durationMin: _num(json['durationMin']),
    hostedCount: _int(json['hostedCount']),
    pace: _nullable(json['pace']),
    completionDuration: _nullable(json['completionDuration']),
  );
}

/// 排行榜的排序维度。后端只认这四个,别的一律回落 composite。
enum ClubRankSort {
  composite('composite', '综合'),
  mileage('mileage', '里程'),
  pace('pace', '配速'),
  duration('duration', '用时');

  const ClubRankSort(this.wire, this.label);
  final String wire;
  final String label;
}
