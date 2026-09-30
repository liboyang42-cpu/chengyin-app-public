/// 候选池:某个主题下的承接候选。
/// 对齐后端 `ApiCoopController.candidates`(/api/coop/candidates)。
///
/// ⚠️ **只有主题发布者能看**(后端 :708「仅主题发布者可查看候选池」)——
///   非发布者会被拒,那是权限态不是故障。
class CoopCandidates {
  const CoopCandidates({
    this.clubApplies = const <ClubApply>[],
    this.registrations = const <CandidateRegistration>[],
  });

  /// 俱乐部主动申请承接的。
  final List<ClubApply> clubApplies;

  /// 已报名的候选(商家侧)。
  final List<CandidateRegistration> registrations;

  bool get isEmpty => clubApplies.isEmpty && registrations.isEmpty;

  factory CoopCandidates.fromJson(Map<String, dynamic> json) {
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) f) {
      final raw = json[key];
      return (raw is List ? raw : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(f)
          .toList();
    }

    return CoopCandidates(
      clubApplies: parse('clubApplies', ClubApply.fromJson),
      registrations: parse('registrations', CandidateRegistration.fromJson),
    );
  }
}

/// 俱乐部承接申请。
class ClubApply {
  const ClubApply({
    required this.id,
    required this.clubName,
    this.clubLogo,
    this.message,
    this.status,
    this.inviteStatus,
    this.createTime,
  });

  final int id;
  final String clubName;
  final String? clubLogo;

  /// 申请留言。★ 为空时**整行不显示**,不渲染一个空的引号框。
  final String? message;

  /// 申请状态:0 待处理 / 1 已婉拒 / 2 已撤回 / 3 已转邀约。
  final int? status;

  /// 该俱乐部当前的邀约状态(后端另算的一层)。
  final String? inviteStatus;
  final String? createTime;

  String get statusText {
    switch (status) {
      case 1:
        return '已婉拒';
      case 2:
        return '已撤回';
      case 3:
        return '已转为邀约';
      default:
        return '待处理';
    }
  }

  /// 还能不能处理。★ 只有待处理才给按钮 ——
  ///   已转邀约/已婉拒/已撤回都摆按钮的话,点下去后端必拒。
  bool get actionable => status == null || status == 0;

  factory ClubApply.fromJson(Map<String, dynamic> json) {
    return ClubApply(
      id: (json['id'] as num?)?.toInt() ?? 0,
      clubName: ((json['clubName'] as String?) ?? '').trim().isEmpty
          ? '未命名俱乐部'
          : (json['clubName'] as String).trim(),
      clubLogo: json['clubLogo'] as String?,
      message: json['message'] as String?,
      status: (json['status'] as num?)?.toInt(),
      inviteStatus: json['inviteStatus'] as String?,
      createTime: json['createTime']?.toString(),
    );
  }
}

/// 候选报名(商家侧)。
class CandidateRegistration {
  const CandidateRegistration({
    required this.id,
    required this.name,
    this.status,
  });

  final int id;
  final String name;
  final int? status;

  factory CandidateRegistration.fromJson(Map<String, dynamic> json) {
    return CandidateRegistration(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ??
          (json['merchantName'] as String?) ??
          '未命名候选',
      status: (json['status'] as num?)?.toInt(),
    );
  }
}

/// 「收到的承接报名」一行(`/api/coop/candidates/received` 的 `data.rows`)。
///
/// ★ 与 [CandidateRegistration](某主题**内**的候选)**不是同一条数据**:
///   这条是**跨主题聚合**的收件箱口径(商家报名承接我主题的节点),
///   行上带 `topicId`/`topicName` 说明这条报名挂在哪个主题下。
///   真源整形见 `pages/coop/list/index.js:57` 的 `decorateReg`。
class CoopReceivedRegistration {
  const CoopReceivedRegistration({
    required this.id,
    this.topicId = 0,
    this.topicName,
    this.memberId,
    this.merchantName,
    this.merchantLogo,
    this.merchantMeta,
    this.addressName,
    this.address,
    this.auditStatus,
  });

  /// 报名 id —— 占槽 / 婉拒两个动作的键都是它(`registrationId`)。
  final int id;

  final int topicId;
  final String? topicName;

  /// 报名商家(bootstrap:占槽成功后要按它发带条款的邀约)。
  final int? memberId;
  final String? merchantName;
  final String? merchantLogo;
  final String? merchantMeta;

  /// 报名时填的地点(`addressName` 优先,回退 `address`)。
  final String? addressName;
  final String? address;

  /// 调配态:**0 待调配 / 1 已中标 / 2 已落选**
  /// (真源 `REG_AUDIT`,list/index.js:52-56)。
  final int? auditStatus;

  /// 状态文案。★ 未知码不猜 —— 说「状态待确认」,
  ///   别让一条已落选的报名看起来还能处理。
  String get auditText {
    switch (auditStatus) {
      case 0:
        return '待调配';
      case 1:
        return '已中标';
      case 2:
        return '已落选';
      default:
        return '状态待确认';
    }
  }

  /// 还能不能处理。★ 只有**待调配**才给按钮 ——
  ///   已中标/已落选再摆按钮,点下去后端必拒(真源 `item.audit===0`)。
  bool get actionable => auditStatus == 0;

  /// 已落选整行压暗(真源 `decorateReg` 的 `dim`)。
  bool get dim => auditStatus == 2;

  /// 商家名。★ 没有商家档案时按 memberId 说「商家 #12」,不是留空。
  String get name {
    final String v = (merchantName ?? '').trim();
    if (v.isNotEmpty) return v;
    return memberId == null ? '未具名商家' : '商家 #$memberId';
  }

  String get meta {
    final String v = (merchantMeta ?? '').trim();
    return v.isEmpty ? '商家候选' : v;
  }

  String get placeText {
    final String a = (addressName ?? '').trim();
    if (a.isNotEmpty) return a;
    return (address ?? '').trim();
  }

  String get topicTitle {
    final String v = (topicName ?? '').trim();
    return v.isEmpty ? '主题 #$topicId' : v;
  }

  factory CoopReceivedRegistration.fromJson(Map<String, dynamic> json) {
    return CoopReceivedRegistration(
      id: (json['id'] as num?)?.toInt() ?? 0,
      topicId: (json['topicId'] as num?)?.toInt() ?? 0,
      topicName: json['topicName'] as String?,
      memberId: (json['memberId'] as num?)?.toInt(),
      merchantName: json['merchantName'] as String?,
      merchantLogo: json['merchantLogo'] as String?,
      merchantMeta: json['merchantMeta'] as String?,
      addressName: json['addressName'] as String?,
      address: json['address'] as String?,
      auditStatus: (json['auditStatus'] as num?)?.toInt(),
    );
  }
}
