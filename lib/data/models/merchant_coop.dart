/// 开放承接的路线(主题)。对齐后端 `MerchantAggregateReadServiceImpl.recruiting()`
/// 下发的 items(/api/merchant/marketing-home → data.recruiting.items)。
class RecruitingRoute {
  const RecruitingRoute({
    required this.id,
    required this.name,
    this.imgUrl,
    this.productType,
    this.signUpEndDate,
  });

  final int id;
  final String name;
  final String? imgUrl;

  /// 产品类型。用于区分 ①经典定向 / ②漫游 / ③探店日。
  final String? productType;

  /// 商家报名截止日。
  final String? signUpEndDate;

  /// 截止提示。★ 后端没下发就**不显示这一行**,不编一句「长期开放」——
  ///   那是在替运营做承诺,而我们并不知道。
  String? get deadlineText {
    final d = signUpEndDate;
    if (d == null || d.isEmpty) return null;
    return '报名截止 ${d.length > 10 ? d.substring(0, 10) : d}';
  }

  factory RecruitingRoute.fromJson(Map<String, dynamic> json) {
    return RecruitingRoute(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '未命名路线',
      imgUrl: json['imgUrl'] as String?,
      productType: json['productType'] as String?,
      signUpEndDate: json['merchantSignUpEndDate'] as String?,
    );
  }
}

/// 官方活动对商家的承接邀约。对齐 `/api/official/merchant-invites`。
///
/// ★ 真源 `utils/merchant-official-channel.js` 的 decorateInvite:后端给的是
///   **数字 status / auditStatus** 与 shareMode 报酬三件套,不是字符串 state。
///   判据、阶段文案、报酬文案、截止日全部照抄它(错一个字商家就会去点已失效的按钮)。
class MerchantInvite {
  const MerchantInvite({
    required this.id,
    required this.title,
    this.eventTitle,
    this.state,
    this.city,
    this.status,
    this.auditStatus,
    this.shareMode,
    this.shareRate,
    this.fixedFee,
    this.expireTime,
  });

  final int id;
  final String title;
  final String? eventTitle;

  /// 兼容口径:后端部分旧路径给字符串状态。
  final String? state;
  final String? city;

  /// 真源口径的数字状态:0 待你确认 / 1 已接受 / 2 已拒绝 / 5 已过期。
  final int? status;
  final int? auditStatus;

  /// 报酬三件套:0 资源支持 / 1 分成 / 2 固定单价。
  final int? shareMode;
  final num? shareRate;
  final num? fixedFee;
  final String? expireTime;

  /// 还能不能处理。★ 已处理的只显示状态,不摆按钮 ——
  ///   摆了点下去必然失败。数字 status 优先(真源 `Number(status) === 0`)。
  bool get actionable {
    final int? s = status;
    if (s != null) return s == 0;
    return state == null || state == 'PENDING' || state == 'INVITED';
  }

  String get stateText {
    final int? s = status;
    if (s != null) {
      if (s == 2) return '已拒绝';
      if (s == 5) return '已过期';
      if (s == 0) return '待你确认';
      if (s == 1) {
        if (auditStatus == 1) return '已中标承接';
        if (auditStatus == 2) return '本轮未中标';
        return '待后台确认';
      }
      return '状态待确认';
    }
    switch (state) {
      case 'ACCEPTED':
        return '已接受';
      case 'DECLINED':
        return '已拒绝';
      case 'EXPIRED':
        return '已过期';
      default:
        return '待处理';
    }
  }

  /// 报酬文案。真源 `rewardText`:分成/固定单价/资源支持,报不出就说待确认,不猜。
  String get rewardText {
    String trim(num? v) {
      if (v == null) return '';
      final String s = v.toString();
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    if (shareMode == 1 && shareRate != null) {
      return '分成 ${trim(shareRate)}%';
    }
    if (shareMode == 2 && fixedFee != null) {
      return '固定 ¥${trim(fixedFee)}/人';
    }
    if (shareMode == 0) return '资源支持';
    return '报酬待官方确认';
  }

  /// 截止文案。真源 `timeText`:解析不出日期就不编,说「待官方确认」。
  String get deadlineText {
    final String raw = (expireTime ?? '').trim();
    if (raw.isEmpty) return '截止时间待官方确认';
    DateTime? d = DateTime.tryParse(raw);
    d ??= DateTime.tryParse(raw.replaceAll('-', '/'));
    if (d == null) return raw;
    return '截止 ${d.month}月${d.day}日';
  }

  factory MerchantInvite.fromJson(Map<String, dynamic> json) {
    return MerchantInvite(
      id: (json['id'] as num?)?.toInt() ??
          (json['partyId'] as num?)?.toInt() ??
          (json['inviteId'] as num?)?.toInt() ??
          0,
      title: (json['title'] as String?) ??
          (json['partyName'] as String?) ??
          '官方活动',
      eventTitle: json['eventTitle'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      status: (json['status'] as num?)?.toInt(),
      auditStatus: (json['auditStatus'] as num?)?.toInt(),
      shareMode: (json['shareMode'] as num?)?.toInt(),
      shareRate: json['shareRate'] as num?,
      fixedFee: json['fixedFee'] as num?,
      expireTime: json['expireTime']?.toString(),
    );
  }
}

/// 协作邀请的处置动作:`POST /api/coop/handle`(body 是 CoopInvite:{id,status,...})。
///
/// ★★ **status 就是目标状态**,不是"动作码":1 接受 / 2 拒绝 / 3 取消。
///   后端 `if (target != 1 && target != 2 && target != 3) return error("操作不合法")`。
///
/// ★★ 谁能做什么,取决于**当前状态 + 你是哪一方**,规则是密的:
///   · 接受/拒绝:**只有受邀方**,且邀约必须仍是待确认(status==0);
///     已处理过的会撞「该邀请已处理」。
///   · 取消(待确认时):**只有发起方**,无代价 —— 「仅发起方可取消待确认邀请」。
///   · 取消(已接受时):双方都行,但**必须填理由**(「取消已接受的合作需填写理由」),
///     且已缴保证金原路退回。锁价后由 service 的 lifecycle 闸拒绝单方取消。
///
///   ⇒ 界面**必须按 (当前状态, 我是哪一方) 决定露哪几个按钮**。
///     三个全摆出来的话,点到的多半是必然报错的那个。
enum CoopHandleAction {
  accept(1, '接受'),
  reject(2, '拒绝'),
  cancel(3, '取消');

  const CoopHandleAction(this.wire, this.label);

  /// 目标状态值,直接放进 body 的 `status`。
  final int wire;
  final String label;

  /// 在给定情形下能不能做。
  ///
  /// ⚠️ 这是**前端的礼貌**,不是权威 —— 权威在后端。
  ///   算错只会多显示一个按钮,不会真的越权。
  bool allowed({required int? inviteStatus, required bool isFrom, required bool isTo}) {
    switch (this) {
      case CoopHandleAction.accept:
      case CoopHandleAction.reject:
        // 只有受邀方,且必须仍在待确认。
        return inviteStatus == 0 && isTo;
      case CoopHandleAction.cancel:
        if (inviteStatus == 0) return isFrom; // 待确认:只有发起方
        if (inviteStatus == 1) return isFrom || isTo; // 已接受:双方都行
        return false; // 其余状态一律不能取消(「该邀请无法取消」)
    }
  }

  /// 这个动作要不要填理由。
  ///
  /// ★ 只有「取消一个已接受的合作」需要 —— 后端会拒空理由。
  ///   界面别对所有取消都强制填,那会让"撤回一个还没人理的邀请"变得很重。
  static bool needsReason(CoopHandleAction a, int? inviteStatus) =>
      a == CoopHandleAction.cancel && inviteStatus == 1;

  static List<CoopHandleAction> availableFor({
    required int? inviteStatus,
    required bool isFrom,
    required bool isTo,
  }) =>
      CoopHandleAction.values
          .where((CoopHandleAction a) =>
              a.allowed(inviteStatus: inviteStatus, isFrom: isFrom, isTo: isTo))
          .toList();
}
