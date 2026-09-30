/// 活动列表项。对齐后端 CmsActivity / `/api/activity/list`。
/// 我对活动的态度。后端 `isLiked`:0 未操作 / 1 已点赞 / 2 已踩。
enum ActivityLikeState {
  none,
  liked,
  disliked;

  static ActivityLikeState fromWire(Object? v) =>
      switch (v is num ? v.toInt() : null) {
        1 => ActivityLikeState.liked,
        2 => ActivityLikeState.disliked,
        // 认不出来按「没操作过」——不猜成已赞。
        _ => ActivityLikeState.none,
      };
}

class Activity {
  Activity({
    required this.id,
    required this.name,
    this.productType,
    this.description,
    this.imgUrl,
    this.addressName,
    this.address,
    this.status,
    this.publishStatus,
    this.minAmount,
    this.viewCount = 0,
    this.rating = 0,
    this.startDate,
    this.endDate,
    this.latitude,
    this.longitude,
    this.topicId,
    this.distance,
    this.likeState = ActivityLikeState.none,
  });

  final int id;
  final String name;

  /// 我对这个活动的态度。
  ///
  /// ★★ 后端 `CmsActivity.isLiked` 注释原话:
  ///   「自己是否点赞 **0未操作 1已点赞 2已踩**」—— **三态不是两态**,
  ///   写成 bool 会把「踩过」混成「没点过」。
  ///
  /// ⚠️ 未登录时后端一律置 0(ApiActivityController:267/388
  ///   `member_id > 0 ? ... : 0`)—— 也就是说「没登录」和「没点过」
  ///   在这个字段上**分不开**。判「要不要弹登录」不能靠它,要看登录态本身。
  final ActivityLikeState likeState;

  bool get liked => likeState == ActivityLikeState.liked;

  /// 所属主题的产品类型:1 经典定向 / 2 自由探索(探店日)。
  /// 后端按 topic_id 关联 cms_topic 取回(cms_activity 本身无此列),
  /// 无关联主题的自建活动为 null。
  final int? productType;

  /// ③ 探店日(自由探索的商业名)。
  bool get isFreeExplore => productType == 2;

  /// **明确**是 ① 经典定向。
  bool get isClassicOriented => productType == 1;

  /// 是否在 App 里展示。
  ///
  /// ⚠️⚠️ 2026-08-20:**这里原来会滤掉 ① 经典定向**,理由写的是「App 只做 ③」。
  ///   那是 2026-08-18 的范围裁决,而用户在 **08-19 已经推翻**它:
  ///   「我需要的是全部一致」「全部做 没有不做的」。滤器是残留。
  ///
  ///   ★ 后果不是「少一个入口」而是**玩家付了钱在票夹里看不到自己的票**。
  ///     同一个文件下面那条 NULL 的断言早就写着这句话
  ///     (「玩家买了票却在票夹里找不到」),只是当时范围说别管 ①。
  ///
  ///   ★ 而且藏的是**跑得动的**东西:App 的游玩页是
  ///     `activityId → /api/play/nodes → 扫码打卡`,后端那个端点
  ///     不按 productType 分支,两种模式共用 —— ① 的核心循环本来就实现了。
  ///
  ///   现在恒为 true。保留这个 getter 而不是删掉调用点,是为了让
  ///   「App 要不要按产品类型筛」这件事仍有一个可搜的落点 ——
  ///   下次真要筛时改这一处,而不是又在三个页面里各写一遍。
  bool get shouldShowInApp => true;

  final String? description;
  final String? imgUrl;
  final String? addressName;
  final String? address;

  /// 审核状态：0待审核 1通过 2失败。
  final int? status;

  /// 发布状态：0下架 1已上架。
  final int? publishStatus;

  /// 最低票价(后端 minAmout，可能为 null)。
  final double? minAmount;
  final int viewCount;
  final double rating;

  /// 活动开始时间。**生产一直在下发**(`/api/activity/list` 的 startDate),
  /// 此前没解析,于是列表 meta 只能退而用「地点 + 价格」——
  /// 我早先在 activity_list_page 里把这写成「列表 VO 没有时间字段」,那句是错的。
  final String? startDate;

  /// 活动结束时间。与 startDate 同批下发,同样一直没解析 ——
  /// 「进行中 / 已结束」的分档要靠它(列表响应里没有 status)。
  final String? endDate;

  /// 搜索地图只为服务端明确下发的坐标生成 marker。
  /// null /非法坐标仍保留在结果列表，不伪造默认点。
  final double? latitude;
  final double? longitude;

  /// 活动真实关联的主题；只有正数时才显示关联主题入口。
  final int? topicId;

  /// 距查询点的直线距离(米)。仅当 `/api/activity/list` 带经纬度按距离排序
  /// (sort_type=1)时下发;真源完赛推荐卡 pickCandidate 拿它写 meta。
  /// null = 没下发 —— 不猜 0,推荐卡按「没有距离」渲染。
  final double? distance;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: (json['name'] ?? '') as String,
    productType: asIntOrNull(json['productType']),
    description: json['description'] as String?,
    imgUrl: json['imgUrl'] as String?,
    addressName: json['addressName'] as String?,
    address: json['address'] as String?,
    status: (json['status'] as num?)?.toInt(),
    publishStatus: (json['publishStatus'] as num?)?.toInt(),
    // 后端字段名为 minAmout(拼写如此)。
    minAmount: (json['minAmout'] as num?)?.toDouble(),
    viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
    startDate: json['startDate'] as String?,
    endDate: json['endDate'] as String?,
    latitude: asDoubleOrNull(json['latitude']),
    longitude: asDoubleOrNull(json['longitude']),
    topicId: asIntOrNull(json['topicId']),
    distance: asDoubleOrNull(json['distance']),
    rating: (json['rating'] as num?)?.toDouble() ?? 0,
    likeState: ActivityLikeState.fromWire(json['isLiked']),
  );
}

/// 活动票种。对齐 OmsTicket(id/name/price)。
class ActivityTicket {
  ActivityTicket({
    required this.id,
    required this.name,
    this.price,
    this.remainingInventory,
    this.startTime,
    this.endTime,
    this.description,
    this.registrants = const <ActivityRegistrant>[],
  });

  final int id;
  final String name;

  /// 票价。★ **可空,且不许兜成 0** —— 后端 `OmsTicket.price` 是 BigDecimal,
  /// 拿不到时兜 0 会让页面渲成「**免费**」(activity_detail_page 的判据是
  /// `price > 0 ? 金额 : '免费'`)。告诉用户不要钱、结果要钱,是最坏的一种错。
  final double? price;

  /// 后端公开票种的真实剩余库存。null 表示未知，不能猜成售罄。
  final int? remainingInventory;
  final String? startTime;
  final String? endTime;
  final String? description;
  final List<ActivityRegistrant> registrants;

  bool get isSoldOut => remainingInventory != null && remainingInventory! <= 0;

  /// 确定不要钱(price 明确是 0)。★ 与 `price == null`(不知道)是两回事。
  bool get isFree => price != null && price! <= 0;

  /// 展示文案:免费 / 金额 / 价格待确认。三态各说各的。
  String get priceText {
    final double? p = price;
    if (p == null) return '价格待确认';
    return p > 0 ? '¥${p.toStringAsFixed(2)}' : '免费';
  }

  factory ActivityTicket.fromJson(Map<String, dynamic> json) => ActivityTicket(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: (json['name'] ?? '') as String,
    price: (json['price'] as num?)?.toDouble(),
    remainingInventory: (json['remainingInventory'] as num?)?.toInt(),
    startTime: json['startTime']?.toString(),
    endTime: json['endTime']?.toString(),
    description: json['description']?.toString(),
    registrants: _activityMapList(
      json['cmsRegistrationList'],
    ).map(ActivityRegistrant.fromJson).toList(growable: false),
  );
}

class ActivityPerson {
  const ActivityPerson({required this.memberId, this.name, this.avatar});

  final int? memberId;
  final String? name;
  final String? avatar;

  factory ActivityPerson.fromJson(Map<String, dynamic> json) => ActivityPerson(
    memberId: asIntOrNull(json['memberId']),
    name: (json['memberRealName'] ?? json['nickname'])?.toString(),
    avatar: (json['memberAvatar'] ?? json['avatar'])?.toString(),
  );
}

class ActivityRegistrant {
  const ActivityRegistrant({
    required this.memberId,
    this.nickname,
    this.avatar,
  });

  final int? memberId;
  final String? nickname;
  final String? avatar;

  factory ActivityRegistrant.fromJson(Map<String, dynamic> json) =>
      ActivityRegistrant(
        memberId: asIntOrNull(json['memberId']),
        nickname: json['nickname']?.toString(),
        avatar: json['avatar']?.toString(),
      );
}

class ActivityNodeSummary {
  const ActivityNodeSummary({
    required this.id,
    this.title,
    this.imgUrl,
    this.players,
    this.duration,
  });

  final int? id;
  final String? title;
  final String? imgUrl;
  final String? players;
  final double? duration;

  factory ActivityNodeSummary.fromJson(Map<String, dynamic> json) =>
      ActivityNodeSummary(
        id: asIntOrNull(json['id']),
        title: json['title']?.toString(),
        imgUrl: json['imgUrl']?.toString(),
        players: json['players']?.toString(),
        duration: asDoubleOrNull(json['duration']),
      );
}

class ActivityComment {
  const ActivityComment({
    this.memberNickname,
    this.createTime,
    this.rating = 0,
    this.contents,
  });

  final String? memberNickname;
  final String? createTime;
  final int rating;
  final String? contents;

  factory ActivityComment.fromJson(Map<String, dynamic> json) =>
      ActivityComment(
        memberNickname: json['memberNickname']?.toString(),
        createTime: json['createTime']?.toString(),
        rating: asIntOrNull(json['rating']) ?? 0,
        contents: json['contents']?.toString(),
      );
}

List<Map<String, dynamic>> _activityMapList(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const <Map<String, dynamic>>[];

/// 活动详情。对齐后端 ActivityInfoVO(继承 CmsActivity + omsTicketList 等)。
class ActivityDetail {
  ActivityDetail({
    required this.id,
    required this.name,
    this.productType,
    this.description,
    this.imgUrl,
    this.addressName,
    this.address,
    this.status,
    this.publishStatus,
    this.commentCount = 0,
    this.rating = 0,
    this.registrationCount = 0,
    this.viewCount = 0,
    this.startDate,
    this.endDate,
    this.latitude,
    this.longitude,
    this.hostMemberId,
    this.cancelTime,
    this.cancelReason,
    this.categoryNames = const <String>[],
    this.collaborators = const <ActivityPerson>[],
    this.registrants = const <ActivityRegistrant>[],
    this.nodes = const <ActivityNodeSummary>[],
    this.comments = const <ActivityComment>[],
    this.teamMode,
    this.teamMaxMembers,
    this.likeState = ActivityLikeState.none,
    required this.tickets,
    this.isGate = false,
    this.gateClubId = 0,
    this.gateMessage = '',
  });

  final int id;
  final String name;

  /// 所属主题的产品类型:1 经典定向 / 2 自由探索(探店日)。
  final int? productType;

  bool get isFreeExplore => productType == 2;

  /// 活动开始时间。后端 `ActivityInfoVO:33` 有 startDate,此前没解析 ——
  /// hero 上要压日期,不解析就只能空着。
  final String? startDate;
  final String? endDate;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  final String? description;
  final String? imgUrl;
  final String? addressName;
  final String? address;
  final int? status;
  final int? publishStatus;
  final int commentCount;
  final double rating;
  final int registrationCount;
  final int viewCount;
  final List<ActivityTicket> tickets;

  /// M1-3 门卡:俱乐部活动对非成员不下发详情,后端只回 `{gate:true, clubId, message}`。
  /// 这不是加载失败(重试无意义),而是一条真实可达的「加入俱乐部才能报名」终态。
  final bool isGate;
  final int gateClubId;
  final String gateMessage;

  /// 我对这个活动的态度。三态见 [ActivityLikeState] —— 「已踩」不是「没点过」。
  final ActivityLikeState likeState;

  bool get liked => likeState == ActivityLikeState.liked;

  /// 主办方的 member id(后端 `CmsActivity.memberId`,注释「用户ID」)。
  ///
  /// ⚠️ **不要和 `ownerId` 混**:本仓库里 `ownerId` 指的是**活动 ID**
  ///   (票/报名的 owner 是活动),不是主办人。CmsActivity 压根没有 ownerId 字段。
  ///
  /// ★ 判「我是不是主办方」只能用它。拿不到时(null)一律按**不是**处理 ——
  ///   主办方专属动作里有「取消活动并全额退款」,宁可让真主办方少一个入口,
  ///   也不能让判不准的人看到它。
  final int? hostMemberId;
  final String? cancelTime;
  final String? cancelReason;
  final List<String> categoryNames;
  final List<ActivityPerson> collaborators;
  final List<ActivityRegistrant> registrants;
  final List<ActivityNodeSummary> nodes;
  final List<ActivityComment> comments;

  /// 2 = 报名/支付成功后进入邀请制组队。
  final int? teamMode;
  final int? teamMaxMembers;

  factory ActivityDetail.fromJson(Map<String, dynamic> json) {
    // 门禁是终态:后端此时不下发详情字段,真源清空 info/tickets 只留 gate 三件
    // (scene-play-activity-detail/index.js:182-190)。先判它,别让半空详情
    // 伪装成可报名的正常页。
    if (json['gate'] == true) {
      final Object? rawClub = json['clubId'];
      final int clubId = rawClub is num
          ? rawClub.toInt()
          : int.tryParse(rawClub?.toString() ?? '') ?? 0;
      return ActivityDetail(
        id: 0,
        name: '',
        tickets: const <ActivityTicket>[],
        isGate: true,
        gateClubId: clubId > 0 ? clubId : 0,
        gateMessage: (json['message'] ?? '来自俱乐部的活动，加入后查看').toString(),
      );
    }
    final rawTickets = (json['omsTicketList'] as List<dynamic>?) ?? <dynamic>[];
    return ActivityDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '') as String,
      productType: asIntOrNull(json['productType']),
      description: json['description'] as String?,
      imgUrl: json['imgUrl'] as String?,
      addressName: json['addressName'] as String?,
      address: json['address'] as String?,
      status: (json['status'] as num?)?.toInt(),
      publishStatus: (json['publishStatus'] as num?)?.toInt(),
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      rating:
          ((json['averageRating'] ?? json['rating']) as num?)?.toDouble() ?? 0,
      registrationCount: (json['registrationCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      latitude: asDoubleOrNull(json['latitude']),
      longitude: asDoubleOrNull(json['longitude']),
      hostMemberId: (json['memberId'] as num?)?.toInt(),
      cancelTime: json['cancelTime']?.toString(),
      cancelReason: json['cancelReason']?.toString(),
      categoryNames: _activityMapList(json['sysCategoryList'])
          .map(
            (Map<String, dynamic> item) =>
                item['categoryName']?.toString() ?? '',
          )
          .where((String name) => name.trim().isNotEmpty)
          .toList(growable: false),
      collaborators: _activityMapList(
        json['collaboratorsList'],
      ).map(ActivityPerson.fromJson).toList(growable: false),
      registrants: _activityMapList(
        json['registrationList'],
      ).map(ActivityRegistrant.fromJson).toList(growable: false),
      nodes: _activityMapList(
        json['memberTemplateList'],
      ).map(ActivityNodeSummary.fromJson).toList(growable: false),
      comments: _activityMapList(
        json['commentList'],
      ).map(ActivityComment.fromJson).toList(growable: false),
      teamMode: asIntOrNull(json['teamMode']),
      teamMaxMembers: asIntOrNull(json['teamMaxMembers']),
      likeState: ActivityLikeState.fromWire(json['isLiked']),
      tickets: rawTickets
          .map(
            (dynamic e) => ActivityTicket.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      isGate: json['gate'] == true,
      gateClubId: (json['clubId'] as num?)?.toInt() ?? 0,
      gateMessage: (json['message'] ?? '') as String,
    );
  }
}

/// 我报名的一条记录。对齐 `/api/registration/my-joined` 返回的 CmsRegistration
/// (内嵌 cmsActivity / cmsTopic;此处仅取活动场景所需字段)。
class MyRegistration {
  MyRegistration({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    this.activityId,
    this.topicId,
    this.registrationNo,
    this.registrationStatus,
    this.verificationStatus,
    this.title,
    this.imgUrl,
    this.participateDate,
    this.productType,
    this.payableAmount,
    this.startDate,
    this.endDate,
    this.addressName,
    this.refundable,
    this.refundPayoutStatus,
  });

  final int id;

  /// 1主题 2活动。
  final int ownerType;
  final int ownerId;
  final int? activityId;
  final int? topicId;
  final String? registrationNo;

  /// 报名状态：1待支付 2已支付/进行中 3已取消。
  final int? registrationStatus;

  /// 核销状态：0待核销 1已核销。
  final int? verificationStatus;

  /// 关联标题(取 cmsActivity.name / cmsTopic.name)。
  final String? title;
  final String? imgUrl;
  final String? participateDate;

  /// 所属主题的产品类型:1 经典定向 / 2 自由探索(探店日)。
  /// 取自后端 cmsActivity.productType —— 那是按 topic_id 关联 cms_topic
  /// 取回的瞬态值,cms_activity 本身没有这一列。
  ///
  /// ⚠️ 生产存在 product_type 为 NULL 的存量主题(探店日开工计划第 0 批 0-5
  ///    待回填),这类票的 productType 会是 null。
  final int? productType;

  /// 应付金额(折扣/积分抵扣之后)。后端 `CmsRegistration` 一直有下发,
  /// 只是此前没解析 —— 订单页因此整页不显示金额,而「付了多少钱」正是
  /// 用户打开订单最先要找的东西。
  final double? payableAmount;

  /// 列表行卡所需的原始活动时段与地点。它们直接来自
  /// `/api/registration/list` 内嵌的 `cmsActivity/cmsTopic`，不可由创建时间猜测。
  final String? startDate;
  final String? endDate;
  final String? addressName;

  /// 列表状态归一所需的退款事实。`refundPayoutStatus == null` 表示后端未下发申请，
  /// 与 payoutStatus=0（已受理、退款中）完全不同。
  final bool? refundable;
  final int? refundPayoutStatus;

  /// 小程序行卡用关联对象而非当前时间决定玩法文案：活动是「经典定向」，
  /// 主题是「自由定向」。未知 ownerType 不给伪玩法文案。
  OrderListMode? get orderMode => switch (ownerType) {
    2 => OrderListMode.classicOriented,
    1 => OrderListMode.freeExplore,
    _ => null,
  };

  /// ③ 探店日判据。App 当前范围只做 ③,①② 不露出。
  bool get isFreeExplore => productType == 2;

  /// 票券状态。★判定顺序与小程序 wxs 一致,不可重排:
  /// 已核验 → 已取消/已过期(3/4 同归 void)→ 待使用 → 待支付。
  TicketState get ticketState {
    if (verificationStatus == 1) return TicketState.done;
    if (registrationStatus == 3 || registrationStatus == 4) {
      return TicketState.voided;
    }
    if (registrationStatus == 2) return TicketState.ready;
    return TicketState.pending;
  }

  /// wxs `label()` 对 void 态再分一刀:4 写「已过期」,其余写「已取消」。
  /// 枚举只留一档(色带/点击分流两态同路),措辞差异在票根这一层还原。
  String get ticketStatusLabel =>
      registrationStatus == 4 && ticketState == TicketState.voided
      ? '已过期'
      : ticketState.label;

  /// **明确**是 ① 经典定向。注意 null 不算 —— 见 [shouldShowInApp]。
  bool get isClassicOriented => productType == 1;

  /// 票夹是否展示。**恒为 true**。
  ///
  /// ⚠️⚠️ 2026-08-20:原来是 `!isClassicOriented`,即滤掉 ① 经典定向。
  ///   依据是 08-18 的「App 只做 ③」,而用户 **08-19 已推翻**:
  ///   「我需要的是全部一致」「全部做 没有不做的」。
  ///
  ///   ★ 讽刺的是,这段注释自己就写着判断的标准:
  ///     「玩家买了票却找不到,比多显示一张票严重得多」。
  ///     这句话对 NULL 成立,对 ① 同样成立 —— 当时只是范围说别管 ①。
  ///
  ///   ★ 而且 ① 的玩法 App 跑得动:游玩页走
  ///     `activityId → /api/play/nodes → 扫码打卡`,后端那个端点
  ///     不按 productType 分支,两种模式共用。
  bool get shouldShowInApp => true;

  factory MyRegistration.fromJson(Map<String, dynamic> json) {
    final activity = json['cmsActivity'] as Map<String, dynamic>?;
    final topic = json['cmsTopic'] as Map<String, dynamic>?;
    final owner = activity ?? topic;
    return MyRegistration(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerType: (json['ownerType'] as num?)?.toInt() ?? 0,
      ownerId: (json['ownerId'] as num?)?.toInt() ?? 0,
      activityId: asIntOrNull(json['activityId']),
      topicId: asIntOrNull(json['topicId']),
      registrationNo: json['registrationNo'] as String?,
      registrationStatus: (json['registrationStatus'] as num?)?.toInt(),
      verificationStatus: (json['verificationStatus'] as num?)?.toInt(),
      title: owner?['name'] as String?,
      imgUrl: _firstOrderImage(owner?['imgUrl'] ?? owner?['imgArr']),
      participateDate: json['participateDate'] as String?,
      productType: asIntOrNull(owner?['productType']),
      payableAmount: (json['payableAmount'] as num?)?.toDouble(),
      startDate: owner?['startDate']?.toString(),
      endDate: owner?['endDate']?.toString(),
      addressName: owner?['addressName']?.toString(),
      refundable: json['refundInfo'] is Map<String, dynamic>
          ? (json['refundInfo'] as Map<String, dynamic>)['refundable'] as bool?
          : null,
      refundPayoutStatus: json['refundApplication'] is Map<String, dynamic>
          ? asIntOrNull(
              (json['refundApplication']
                  as Map<String, dynamic>)['payoutStatus'],
            )
          : null,
    );
  }
}

/// 小程序订单卡的玩法摘要。未知来源必须返回 null，而不是挪用任一玩法文案。
enum OrderListMode { classicOriented, freeExplore }

extension OrderListModeDisplay on OrderListMode {
  String get label => switch (this) {
    OrderListMode.classicOriented => '城市定向',
    OrderListMode.freeExplore => '自由探索',
  };

  String get summary => switch (this) {
    OrderListMode.classicOriented => '按路线完成现场节点互动',
    OrderListMode.freeExplore => '打开票夹后开始探索',
  };
}

/// 主题的 `imgArr` 在不同历史接口里可能是逗号串或数组；列表只消费首图，
/// 与小程序的 `img.first(item.cmsTopic.imgArr)` 对齐。空值保持 null，不造封面。
String? _firstOrderImage(Object? raw) {
  if (raw is List) {
    for (final Object? value in raw) {
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }
  final String text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final String first = text.split(',').first.trim();
  return first.isEmpty ? null : first;
}

/// 创建报名的结果:`POST /api/registration/create`。
///
/// 后端在 payableAmount>0 且带 payChannel=APP 时会**直接**返回 App 支付六元组,
/// 故不必再调一次 /pay/app —— 少一次往返,也避免同一 outTradeNo 被两种
/// trade_type 重复下单。
class RegistrationCreateResult {
  const RegistrationCreateResult({
    required this.registrationId,
    this.registrationNo,
    this.payParams,
  });

  final int registrationId;
  final String? registrationNo;

  /// App 支付六元组(appId/partnerId/prepayId/packageValue/nonceStr/timeStamp/sign)。
  /// 零元单或后端未下发时为 null —— 此时无需调起支付。
  final Map<String, String>? payParams;

  bool get needsPayment => payParams != null && payParams!.isNotEmpty;

  factory RegistrationCreateResult.fromJson(Map<String, dynamic> json) {
    final raw = json['payParams'];
    Map<String, String>? params;
    if (raw is Map && raw.isNotEmpty) {
      params = raw.map((k, v) => MapEntry('$k', '${v ?? ''}'));
    }
    return RegistrationCreateResult(
      registrationId: (json['registrationId'] as num?)?.toInt() ?? 0,
      registrationNo: json['registrationNo'] as String?,
      payParams: params,
    );
  }
}

/// 票券状态。与小程序 `subpackageMember/signup/index.wxml` 顶部的 wxs
/// `state()` **逐字对齐**,包括判定顺序 —— 已核验优先于已取消,
/// 顺序改了会让「核验完又取消」的票显示成已取消。
enum TicketState {
  /// 待支付
  pending,

  /// 待使用(已报名未核验)
  ready,

  /// 已核验
  done,

  /// 已取消
  voided,
}

extension TicketStateDisplay on TicketState {
  /// 票根直书的状态文字。小程序已删掉票面右下角的彩底状态胶囊,
  /// 理由是「同一状态说两遍」——状态由**左缘色带 + 这行文字**表达,
  /// 不要再加角标。
  String get label => switch (this) {
    TicketState.done => '已核验',
    TicketState.voided => '已取消',
    TicketState.ready => '待使用',
    TicketState.pending => '待支付',
  };

  /// 票根右侧的动作提示。真源 wxs `cta()` 三态逐字:
  /// ready→「进入游玩」、pending→「去支付」、其余**不出 CTA**。
  /// 「查看详情」那条例由已作废 —— 它指的是订单页,票夹→订单的路 2026-09-10
  /// 已由用户关掉,只有待支付(还没付完的单)例外,落点才是订单。
  String get cta => switch (this) {
    TicketState.ready => '进入游玩 ›',
    TicketState.pending => '去支付 ›',
    TicketState.done || TicketState.voided => '',
  };
}

/// 可空的容错整数解析:契约声明数字可能是 int/long/String。
/// 不能复用 core/util/json_parse.dart 的 asInt —— 那个缺省返回 0,
/// 而 productType 的 null(未知)与 0 语义不同,不能被压成同一个值。
int? asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// 票券权益(③ 探店日:每票每必选章一行)。
/// 对齐后端 `RegistrationEntitlement`。玩家侧唯一能看到「这张票还剩什么」的地方 ——
/// `verificationStatus` 对 ③ 只表示「被核销过至少一次」,看不出还欠几章。
class Entitlement {
  const Entitlement({
    required this.id,
    required this.status,
    this.chapterId,
    this.chapterName,
    this.statusLabel,
    this.invalidReason,
    this.redeemedAt,
  });

  final int id;

  /// 0 应得(已售未核销) 1 已得(已核销) 2 失效(退款/取消)。
  final int status;
  final int? chapterId;

  /// 章节名(后端瞬态字段,订单详情已 enrich)。
  final String? chapterName;

  /// 状态文案(后端瞬态):待核销 / 已核销 / 已失效。
  final String? statusLabel;
  final String? invalidReason;
  final String? redeemedAt;

  bool get isPending => status == 0;
  bool get isRedeemed => status == 1;
  bool get isInvalid => status == 2;

  /// 后端 statusLabel 缺失时的兜底文案(不猜业务,只做三态直译)。
  String get label =>
      statusLabel ??
      const <int, String>{0: '待核销', 1: '已核销', 2: '已失效'}[status] ??
      '未知';

  factory Entitlement.fromJson(Map<String, dynamic> json) {
    return Entitlement(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as num?)?.toInt() ?? 0,
      chapterId: (json['chapterId'] as num?)?.toInt(),
      chapterName: json['chapterName'] as String?,
      statusLabel: json['statusLabel'] as String?,
      invalidReason: json['invalidReason'] as String?,
      redeemedAt: json['redeemedAt'] as String?,
    );
  }
}

/// 票卡详情:`POST /api/registration/info`。
/// entitlements 仅 ③ 探索票(purchaseKind=EXPLORE_PASS)返回,其余为空。
class RegistrationDetail {
  const RegistrationDetail({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.entitlements,
    this.registrationNo,
    this.registrationStatus,
    this.verificationStatus,
    this.title,
    this.imgUrl,
    this.participateDate,
    this.realName,
    this.phone,
    this.purchaseKind,
    this.description,
    this.eventStartDate,
    this.paymentStatus,
    this.ticketName,
    this.ticketPrice,
    this.orderNum,
    this.payableAmount,
    this.pointUsed,
    this.pointPaymentAmount,
    this.wechatPaymentAmount,
    this.paymentTime,
    this.paymentTypeLabel,
    this.transactionId,
    this.expiresAt,
    this.verificationTime,
    this.refundDeadlineDisplay,
    this.organizerName,
    this.omsTicket,
    this.refundable,
    this.refundPayoutStatus,
    this.statusText,
    this.orderHint,
    this.typeLabel,
    this.primaryActionText,
    this.secondaryActionText,
    // ── 订单进度时间线 / 组队卡 / 营销同意行(gap-spec-player #3)——
    // 真源 = /api/registration/info 回包的整个 CmsRegistration 实体
    // (ApiRegistrationController:382-505 原样序列化返回),字段名逐字取自
    // components/cy/scene-member-order-detail 的消费点。
    this.createTime,
    this.payExpireTime,
    this.manualRefundCaseStatus,
    this.ownerMemberId,
    this.teamMode,
    this.teamMaxMembers,
    this.ownerStartDate,
    this.ownerStartTime,
    this.ownerEndDate,
    this.ownerEndTime,
    this.hasRefundApplication = false,
    this.refundApplicationStatus,
    this.refundAmount,
    this.refundPayoutTime,
    this.refundUpdateTime,
    this.refundInfoReason,
    this.refundInfoDeadline,
  });

  final int id;
  final int ownerType;
  final int ownerId;
  final List<Entitlement> entitlements;
  final String? registrationNo;
  final int? registrationStatus;
  final int? verificationStatus;
  final String? title;
  final String? imgUrl;
  final String? participateDate;
  final String? realName;

  /// 后端已脱敏(RegistrationDetailDisplay.enrich)。
  final String? phone;
  final String? purchaseKind;
  final String? description;
  final String? eventStartDate;
  final int? paymentStatus;
  final String? ticketName;
  final double? ticketPrice;
  final int? orderNum;
  final double? payableAmount;
  final int? pointUsed;
  final double? pointPaymentAmount;
  final double? wechatPaymentAmount;
  final String? paymentTime;
  final String? paymentTypeLabel;
  final String? transactionId;
  final String? expiresAt;
  final String? verificationTime;
  final String? refundDeadlineDisplay;
  final String? organizerName;
  final OrderTicketSnapshot? omsTicket;
  final bool? refundable;
  final int? refundPayoutStatus;
  final String? statusText;
  final String? orderHint;
  final String? typeLabel;
  final String? primaryActionText;
  final String? secondaryActionText;

  /// 建单时间(BaseEntity.createTime)—— 时间线第一行。
  final String? createTime;

  /// 待支付单的支付时限(scene-member-order-detail:844 的 orderHint 依据)。
  final String? payExpireTime;

  /// 人工售后工单态(NO_REFUND / PENDING_ASSESSMENT / MANUAL_REFUND_REQUIRED /
  /// MANUAL_REFUND_EVIDENCE_VERIFIED…)。非空即整单按「人工售后」判。
  final String? manualRefundCaseStatus;

  /// 主办(cmsActivity/cmsTopic)的 memberId —— 营销同意行查商家行用。
  final int? ownerMemberId;

  /// 1=不允许组队 / 2=允许(scene-member-order-detail 组队卡判据)。
  final int? teamMode;
  final int? teamMaxMembers;

  /// owner 的起止时间:summarizeOrderState 用它推 未开始/进行中/已结束。
  final String? ownerStartDate;
  final String? ownerStartTime;
  final String? ownerEndDate;
  final String? ownerEndTime;

  /// 后端是否下发了 refundApplication(建单即有 payoutStatus=5,
  /// 零元单/无申请单时是 null —— 判据的「有没有」必须显式记)。
  final bool hasRefundApplication;

  /// refundApplication.status(0 待审核 / 1 批准 / 2 驳回)。
  final int? refundApplicationStatus;
  final double? refundAmount;
  final String? refundPayoutTime;
  final String? refundUpdateTime;

  /// refundInfo(RefundPolicy 判决)的 reason/deadline。
  final String? refundInfoReason;
  final String? refundInfoDeadline;

  /// ③ 探索票判据:按后端 purchaseKind,不按 entitlements 是否为空
  /// (空也可能是尚未建行)。
  bool get isExplorePass => purchaseKind == 'EXPLORE_PASS';

  TicketState get ticketState {
    if (verificationStatus == 1) return TicketState.done;
    if (registrationStatus == 3 || registrationStatus == 4) {
      return TicketState.voided;
    }
    if (registrationStatus == 2) return TicketState.ready;
    return TicketState.pending;
  }

  /// 与小程序 `utils/order-status.js` 同源：退款终态只取
  /// `refundApplication.payoutStatus`，不能由报名取消态猜测。
  String get orderStatusLabel {
    if ((statusText ?? '').trim().isNotEmpty) return statusText!.trim();
    if (refundPayoutStatus != null) {
      return switch (refundPayoutStatus) {
        1 || 4 => '已退款',
        2 || 3 => '退款处理中',
        _ => '退款中',
      };
    }
    return ticketState.label;
  }

  String get orderStatusHint {
    if ((orderHint ?? '').trim().isNotEmpty) return orderHint!.trim();
    if (refundPayoutStatus != null) {
      return switch (refundPayoutStatus) {
        1 || 4 => '退款已原路退回',
        2 => '原路退款异常，平台正在人工处理',
        3 => '人工退款已处理，等待复核确认',
        _ => '退款已受理，预计 1-3 个工作日原路退回',
      };
    }
    if (registrationStatus == 1) return '请完成支付后使用票夹';
    if (ticketState == TicketState.done) return '已核销订单不可退款';
    if (ticketState == TicketState.voided) return '订单已关闭，如有疑问请联系客服';
    if ((refundDeadlineDisplay ?? '').isNotEmpty) {
      return refundDeadlineDisplay!;
    }
    return '可在退款截止前申请原路退款';
  }

  /// 还欠几章。仅对 ③ 有意义。
  int get pendingCount => entitlements.where((e) => e.isPending).length;

  factory RegistrationDetail.fromJson(Map<String, dynamic> json) {
    final activity = json['cmsActivity'] as Map<String, dynamic>?;
    final topic = json['cmsTopic'] as Map<String, dynamic>?;
    final owner = activity ?? topic;
    final ents = (json['entitlements'] as List<dynamic>?) ?? <dynamic>[];
    return RegistrationDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerType: (json['ownerType'] as num?)?.toInt() ?? 0,
      ownerId: (json['ownerId'] as num?)?.toInt() ?? 0,
      entitlements: ents
          .map((dynamic e) => Entitlement.fromJson(e as Map<String, dynamic>))
          .toList(),
      registrationNo: json['registrationNo'] as String?,
      registrationStatus: (json['registrationStatus'] as num?)?.toInt(),
      verificationStatus: (json['verificationStatus'] as num?)?.toInt(),
      title: owner?['name'] as String?,
      imgUrl: owner?['imgUrl'] as String?,
      participateDate: json['participateDate'] as String?,
      realName: json['realName'] as String?,
      phone: json['phone'] as String?,
      purchaseKind: switch (json['purchaseKind']) {
        3 => 'EXPLORE_PASS',
        2 => 'SELF_PASS',
        1 => 'GUIDED_TICKET',
        final String value => value,
        _ => null,
      },
      description: owner?['description'] as String?,
      eventStartDate: owner?['startDate']?.toString(),
      paymentStatus: (json['paymentStatus'] as num?)?.toInt(),
      ticketName: json['ticketName'] as String?,
      ticketPrice: (json['ticketPrice'] as num?)?.toDouble(),
      orderNum: (json['orderNum'] as num?)?.toInt(),
      payableAmount: (json['payableAmount'] as num?)?.toDouble(),
      pointUsed: (json['pointUsed'] as num?)?.toInt(),
      pointPaymentAmount: (json['pointPaymentAmount'] as num?)?.toDouble(),
      wechatPaymentAmount: (json['wechatPaymentAmount'] as num?)?.toDouble(),
      paymentTime: json['paymentTime']?.toString(),
      paymentTypeLabel: json['paymentTypeLabel'] as String?,
      transactionId: json['transactionId'] as String?,
      expiresAt: json['expiresAt']?.toString(),
      verificationTime: json['verificationTime']?.toString(),
      refundDeadlineDisplay: json['refundDeadlineDisplay'] as String?,
      organizerName: json['organizerName'] as String?,
      omsTicket: json['omsTicket'] is Map<String, dynamic>
          ? OrderTicketSnapshot.fromJson(
              json['omsTicket'] as Map<String, dynamic>,
            )
          : null,
      refundable: json['refundInfo'] is Map<String, dynamic>
          ? (json['refundInfo'] as Map<String, dynamic>)['refundable'] as bool?
          : null,
      refundPayoutStatus: json['refundApplication'] is Map<String, dynamic>
          ? asIntOrNull(
              (json['refundApplication']
                  as Map<String, dynamic>)['payoutStatus'],
            )
          : null,
      statusText: json['statusText']?.toString(),
      orderHint: json['orderHint']?.toString(),
      typeLabel: json['typeLabel']?.toString(),
      primaryActionText: json['primaryActionText']?.toString(),
      secondaryActionText: json['secondaryActionText']?.toString(),
      createTime: json['createTime']?.toString(),
      payExpireTime: json['payExpireTime']?.toString(),
      manualRefundCaseStatus: json['manualRefundCaseStatus'] is String
          ? json['manualRefundCaseStatus'] as String
          : null,
      ownerMemberId: asIntOrNull(owner?['memberId']),
      teamMode: asIntOrNull(owner?['teamMode']),
      teamMaxMembers: asIntOrNull(owner?['teamMaxMembers']),
      ownerStartDate: owner?['startDate']?.toString(),
      ownerStartTime: owner?['startTime']?.toString(),
      ownerEndDate: owner?['endDate']?.toString(),
      ownerEndTime: owner?['endTime']?.toString(),
      hasRefundApplication: json['refundApplication'] is Map,
      refundApplicationStatus: json['refundApplication'] is Map
          ? asIntOrNull((json['refundApplication'] as Map)['status'])
          : null,
      refundAmount: json['refundApplication'] is Map
          ? (json['refundApplication'] as Map)['refundAmount'] is num
                ? ((json['refundApplication'] as Map)['refundAmount'] as num)
                      .toDouble()
                : null
          : null,
      refundPayoutTime: json['refundApplication'] is Map
          ? (json['refundApplication'] as Map)['payoutTime']?.toString()
          : null,
      refundUpdateTime: json['refundApplication'] is Map
          ? (json['refundApplication'] as Map)['updateTime']?.toString()
          : null,
      refundInfoReason: json['refundInfo'] is Map
          ? (json['refundInfo'] as Map)['reason']?.toString()
          : null,
      refundInfoDeadline: json['refundInfo'] is Map
          ? (json['refundInfo'] as Map)['deadline']?.toString()
          : null,
    );
  }
}

class OrderTicketSnapshot {
  const OrderTicketSnapshot({
    this.startTime,
    this.endTime,
    this.meetingPoint,
    this.gatherLat,
    this.gatherLng,
  });

  final String? startTime;
  final String? endTime;
  final String? meetingPoint;
  final double? gatherLat;
  final double? gatherLng;

  bool get hasCoordinates => gatherLat != null && gatherLng != null;

  factory OrderTicketSnapshot.fromJson(Map<String, dynamic> json) {
    return OrderTicketSnapshot(
      startTime: json['startTime']?.toString(),
      endTime: json['endTime']?.toString(),
      meetingPoint: json['meetingPoint'] as String?,
      gatherLat: (json['gatherLat'] as num?)?.toDouble(),
      gatherLng: (json['gatherLng'] as num?)?.toDouble(),
    );
  }
}

/// 动态核销码:`POST /api/verify/dyncode/issue`。TTL 由后端下发(当前 5 分钟)。
class DynCode {
  const DynCode({
    required this.code,
    required this.expiresAt,
    this.qrcodeUrl,
    this.ttlMs,
    this.type,
  });

  final String code;

  /// 后端下发的绝对过期时间戳(ms)。倒计时以它为准,不本地推算。
  final int expiresAt;

  /// 服务端渲染的二维码图;出图失败时为 null,前端回落展示 code 文本。
  final String? qrcodeUrl;
  final int? ttlMs;
  final String? type;

  Duration remaining() {
    final ms = expiresAt - DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: ms > 0 ? ms : 0);
  }

  bool get isExpired => remaining() == Duration.zero;

  factory DynCode.fromJson(Map<String, dynamic> json) {
    return DynCode(
      code: (json['code'] as String?) ?? '',
      expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
      qrcodeUrl: json['qrcodeUrl'] as String?,
      ttlMs: (json['ttlMs'] as num?)?.toInt(),
      type: json['type'] as String?,
    );
  }
}

/// 报名报价 —— 后端 `RegistrationQuoteResult`。
///
/// ★ 小程序报名页的费用明细(baoming.wxml:56-90)是五行:
///   票种价 / 订单金额 / 俱乐部会员权益 / 积分抵扣 / 总计。
///   App 此前既不显示明细、也把 `isUsePoint` 写死 0,积分等于永远用不上。
class RegistrationQuote {
  const RegistrationQuote({
    this.payAmount,
    this.pointsUsed = 0,
    this.pointsDeductYuan,
    this.pointsUsable = true,
    this.memberDiscountYuan,
    this.couponDeductYuan,
    this.clubMember = false,
    this.quoteSign = '',
  });

  /// 实付金额(抵扣之后)。
  final double? payAmount;

  /// 本单实际使用的积分数。
  final int pointsUsed;

  /// 积分折算成的金额(元)。
  final double? pointsDeductYuan;

  /// 当前票种是否支持积分抵扣。小程序同名状态为 false 时
  /// 整行隐藏，不展示一个永远无效的开关。
  final bool pointsUsable;

  /// 俱乐部会员权益减免(元)。
  final double? memberDiscountYuan;

  /// 优惠券减免(元)。
  final double? couponDeductYuan;

  /// 当前用户是否俱乐部会员 —— 决定「俱乐部会员权益」这行显不显示。
  final bool clubMember;

  /// ★ 报价签名。**建单必传**:`RegistrationOrderCreateGateImpl:37` 对活动报名
  ///   (ownerType=2)空签名直接 400「缺少报价签名」,签名对不上 409「价格已更新」。
  ///   App 此前建单根本没传过这个字段 —— 也就是说**活动报名从来没成功过**。
  final String quoteSign;

  /// 是否真的抵扣到了钱 —— 判据看**金额**不看积分数:
  /// 后端可能返回 pointsUsed>0 但折算额为 0(比例不足一分),那时不该显示抵扣行。
  bool get hasDeduction => (pointsDeductYuan ?? 0) > 0;

  factory RegistrationQuote.fromJson(Map<String, dynamic> json) {
    return RegistrationQuote(
      payAmount: (json['payAmount'] as num?)?.toDouble(),
      pointsUsed: (json['pointsUsed'] as num?)?.toInt() ?? 0,
      pointsDeductYuan: (json['pointsDeductYuan'] as num?)?.toDouble(),
      pointsUsable: json['pointsUsable'] != false,
      memberDiscountYuan: (json['memberDiscountYuan'] as num?)?.toDouble(),
      couponDeductYuan: (json['couponDeductYuan'] as num?)?.toDouble(),
      clubMember: json['clubMember'] == true,
      quoteSign: (json['quoteSign'] as String?) ?? '',
    );
  }
}
