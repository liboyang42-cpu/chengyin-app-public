/// 商家的章节承接申请。
/// 对齐后端 `MerchantChapterApplication`(/api/merchant/chapter-application/*)。
class ChapterApplication {
  const ChapterApplication({
    required this.id,
    this.topicId,
    this.chapterId,
    this.topicName,
    this.chapterName,
    this.status = 0,
    this.source = 0,
    this.message,
    this.auditRemark,
    this.offerActive = false,
    this.offerId,
    this.circleThemeCode,
    this.circleSupplyCheckedAt,
  });

  final int id;
  final int? topicId;
  final int? chapterId;
  final String? topicName;
  final String? chapterName;

  /// 0 待审核 / 1 已通过 / 2 已拒绝。
  final int status;

  /// 0 商家申请 / 1 主办方邀请。
  ///
  /// ★ 后端注释:「邀请不另建链路 —— 它就是**预先批准的申请**(建出来即 status=已通过)。
  ///   这一列还决定**点位要不要再审**:邀请来的免审,人是主办方主动邀的。」
  final int source;

  final String? message;

  /// 审核备注。★ 被拒时必须显示 —— 只说「已拒绝」商家不知道怎么改。
  final String? auditRemark;

  /// 我在这一章是否已有**生效**的供给(offer_state == ACTIVE)。
  ///
  /// ★ 只有「我的申请」这条列表回显它,不落库。已生效的供给**不能就地改** ——
  ///   要改得先撤回重来,所以界面对它只说明、不给「填实际供给」按钮。
  final bool offerActive;

  /// 这份生效供给的编号(`merchant_chapter_offer.id`)。
  ///
  /// ★ 圈层供给的两个复核动作(无变化重新确认 / 暂停)**打的是供给,不是申请** ——
  ///   后端读的是 `body.getOfferId()`。拿申请 id 去调,恒回「缺少供给记录」。
  final int? offerId;

  /// 这份供给挂的圈层主题编号(没有 = 不是圈层供给)。
  ///
  /// ★ 30 天供给复核只对圈层供给成立;普通章节供给摆那两个按钮必被后端拒。
  final String? circleThemeCode;

  /// 供给最近一次被确认的时间。界面只取前 10 位(日期)。
  final String? circleSupplyCheckedAt;

  bool get isPending => status == 0;
  bool get isApproved => status == 1;
  bool get isRejected => status == 2;

  /// 是主办方邀请来的(而不是自己申请的)。
  bool get isInvited => source == 1;

  String get statusText {
    if (isRejected) {
      final r = auditRemark?.trim() ?? '';
      return r.isEmpty ? '已拒绝' : '已拒绝:$r';
    }
    if (isApproved) {
      // ★ 邀请与自己申请通过要分开说 —— 前者是"被邀请的",
      //   商家看到「已通过」会以为自己申请过,其实没有。
      return isInvited ? '主办方已邀请你承接' : '已通过';
    }
    return '审核中';
  }

  /// 能不能撤回。★ 只有**自己申请的、还在审核中**的能撤 ——
  ///   已通过/已拒绝的撤不了,主办方邀请的更不该由商家撤。
  bool get canWithdraw => isPending && !isInvited;

  /// 点位是否需要再审。邀请来的免审(后端注释明说)。
  bool get nodeNeedsAudit => !isInvited;

  /// 能不能「供给无变化,重新确认」。
  ///
  /// ★ 真源判据一字不差(`merchantinfo.js:437`):
  ///   `offerActive && !!Number(row.offerId) && !!row.circleThemeCode`。
  ///   三个条件缺一不可 —— 没生效供给时无可确认;圈层码为空时没有圈层可进;
  ///   offerId 拿不到就发不出请求(页面摆出来只会点了没反应)。
  ///
  /// ⚠️ 同一条判据也管着旁边的「暂停供给」两个按钮(wxml:383 是同一个
  ///   `wx:if`)—— 别只给重新确认加闸,那样会出现"暂停一个圈层里
  ///   根本不存在的供给"。
  bool get canReconfirmCircleSupply =>
      offerActive && (offerId ?? 0) > 0 && (circleThemeCode ?? '').isNotEmpty;

  /// 「最近确认」那一小截日期。真源只取前 10 位
  /// (`String(row.circleSupplyCheckedAt).slice(0, 10)` → `YYYY-MM-DD`)——
  /// 原样显示后端 ISO 串会带出 `T00:00:00.000Z`,在卡片上一行放不下。
  String get circleSupplyCheckedDate {
    final String raw = (circleSupplyCheckedAt ?? '').trim();
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  /// 展示标题:主题 · 章节。两截都可能为空。
  String get displayTitle {
    final parts = <String>[
      if ((topicName ?? '').trim().isNotEmpty) topicName!.trim(),
      if ((chapterName ?? '').trim().isNotEmpty) chapterName!.trim(),
    ];
    return parts.isEmpty ? '承接申请' : parts.join(' · ');
  }

  factory ChapterApplication.fromJson(Map<String, dynamic> json) {
    return ChapterApplication(
      id: (json['id'] as num?)?.toInt() ?? 0,
      topicId: (json['topicId'] as num?)?.toInt(),
      chapterId: (json['chapterId'] as num?)?.toInt(),
      topicName: json['topicName'] as String?,
      chapterName: json['chapterName'] as String?,
      status: (json['status'] as num?)?.toInt() ?? 0,
      source: (json['source'] as num?)?.toInt() ?? 0,
      message: json['message'] as String?,
      auditRemark: json['auditRemark'] as String?,
      // 服务端用 case when ... then 1 else 0 算出来,JSON 里可能是 bool 也可能是 0/1。
      offerActive: json['offerActive'] == true || json['offerActive'] == 1,
      offerId: (json['offerId'] as num?)?.toInt(),
      circleThemeCode: json['circleThemeCode'] as String?,
      circleSupplyCheckedAt: json['circleSupplyCheckedAt'] as String?,
    );
  }
}
