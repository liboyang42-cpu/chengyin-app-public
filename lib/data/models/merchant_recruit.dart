import '../../core/util/json_parse.dart';
import 'validation_method_labels.dart';

/// 章节招商与承接链路的模型。对齐小程序 `pages/topic/merchantinfo` 那一整条:
/// 可承接章节 → 申请承接 → 提交点位 → 填实际供给 → 看即将到店的场次。
///
/// ★ 本文件的标签一律遵守「能区分就必须区分」:
///   拿不到的字段说「不知道」,真的是 0 才说 0。
///   把"没拿到"渲染成"没有",是这个项目最高频的一类缺陷。

/// 条款档。`TermsMode`(TRAFFIC 引流 / PERK 权益 / REVSHARE 计酬)。
///
/// ★ 空串和无效值都返回 null —— 档位读不出来时**不能默认成 PERK**,
///   那会让「填实际供给」按权益表单收数据,提交必被服务端的
///   「本章节是「X」,不能按「Y」入驻」拒掉。
String? termsModeLabel(String? mode) {
  switch (mode) {
    case 'PERK':
      return '权益承接';
    case 'REVSHARE':
      return '计酬承接';
    case 'TRAFFIC':
      return '引流承接';
    default:
      return null;
  }
}

/// 一个开放招商的章节(`/api/topic/merchant-recruitment-chapters` 的一行)。
///
/// ⚠️ 这条只返回 `recruitStatus.isOpen == true` 的章节 —— 也就是
///   已开招商、已上架、自由探索、配了品类、未锁价且还有名额的那些。
///   ⇒ 界面不必自己再判一遍"能不能申请",但**要把公示项摆出来**:
///     玩法边界与权益门槛是招商时就公示的,商家申请前看得到才叫公示。
class RecruitChapter {
  const RecruitChapter({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.required_,
    this.termsMode,
    this.perkMinValue,
    this.allowedValidationMethods,
    this.maxNodeXp,
    this.maxMerchant,
    this.remainingMerchantCount,
    this.state,
  });

  final int id;
  final String name;
  final String? description;
  final String? category;

  /// 是否必选章:1 是 / 0 否。**缺席保持 null**。
  final int? required_;

  final String? termsMode;
  final double? perkMinValue;
  final String? allowedValidationMethods;
  final int? maxNodeXp;
  final int? maxMerchant;

  /// 剩余名额。★ **null = 不限**,0 = 真的满了 —— 两者不是一回事。
  final int? remainingMerchantCount;

  /// OPEN 招募中 / FULL 已满 / LOCKED 已锁价。
  final String? state;

  String get categoryLabel =>
      (category ?? '').trim().isEmpty ? '未配置招募品类' : category!.trim();

  /// ★ required 缺席时说「章节类型未标注」,不默认成「必选章节」——
  ///   把"没拿到"说成一个确定结论,商家会照着它排优先级。
  String get requiredLabel {
    if (required_ == null) return '章节类型未标注';
    return required_ == 0 ? '可选章节' : '必选章节';
  }

  /// 条款档标签。读不出来时说实话。
  String get termsLabel => termsModeLabel(termsMode) ?? '承接档位未标注';

  /// 玩法边界(公示项)。两条都没有就返回空串,由调用方决定不渲染这一行。
  /// ★ 核验方式文案取自全 App 唯一码表:码 1 是「文字作答」,认不出的码回落
  ///   「其他」;空段/非数字段照旧丢弃,不拼出空名字。
  String get boundaryLabel {
    final List<String> parts = <String>[];
    final String raw = (allowedValidationMethods ?? '').trim();
    if (raw.isNotEmpty) {
      final List<String> names = raw
          .split(',')
          .map((String v) => validationMethodLabel(int.tryParse(v.trim())))
          .whereType<String>()
          .toList();
      if (names.isNotEmpty) parts.add('玩法限 ${names.join('/')}');
    }
    if (maxNodeXp != null && maxNodeXp! > 0) parts.add('探索值上限 ${maxNodeXp!}');
    return parts.join(' · ');
  }

  /// 权益门槛。只有权益档才有;没配门槛就返回空串。
  String get perkMinValueLabel {
    if (termsMode != 'PERK') return '';
    final double? v = perkMinValue;
    if (v == null || v <= 0) return '';
    final String amount = v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(2);
    return '权益零售价不少于 ¥$amount';
  }

  /// 名额。★ 三档各不相同:不限 / 还剩几家 / 已满。
  String get merchantLimitLabel {
    final int? left = remainingMerchantCount;
    if (left == null) return '名额不限';
    if (left <= 0) return '名额已满';
    final int? cap = maxMerchant;
    if (cap == null || cap <= 0) return '剩余 $left 家可承接';
    return '剩余 $left / $cap 家可承接';
  }

  factory RecruitChapter.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> r =
        (json['recruitStatus'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return RecruitChapter(
      id: asInt(json['id']),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '未命名章节',
      description: json['description'] as String?,
      category: json['category'] as String?,
      required_: json['required'] == null ? null : asInt(json['required']),
      termsMode: r['termsMode'] as String?,
      perkMinValue: asDouble(r['perkMinValue']),
      allowedValidationMethods: r['allowedValidationMethods'] as String?,
      maxNodeXp: r['maxNodeXp'] == null ? null : asInt(r['maxNodeXp']),
      maxMerchant: r['maxMerchant'] == null ? null : asInt(r['maxMerchant']),
      remainingMerchantCount: r['remainingMerchantCount'] == null
          ? null
          : asInt(r['remainingMerchantCount']),
      state: r['state'] as String?,
    );
  }
}

/// 我在某章节下的点位(`/api/merchant/chapter-node/mine` 的一行)。
class MyChapterNode {
  const MyChapterNode({
    required this.id,
    required this.name,
    this.address,
    this.chapterId,
    this.topicId,
    this.nodeAuditStatus,
    this.nodeAuditReason,
  });

  final int id;
  final String name;
  final String? address;
  final int? chapterId;
  final int? topicId;

  /// 0 待审核 / 1 已通过 / 2 已驳回。**缺席保持 null**。
  final int? nodeAuditStatus;
  final String? nodeAuditReason;

  bool get isApproved => nodeAuditStatus == 1;
  bool get isRejected => nodeAuditStatus == 2;

  /// ★ null 不兜成「待审核」:那是一个真实状态,把"没拿到"说成它,
  ///   商家会以为自己在队列里排着,其实我们根本不知道。
  String get auditLabel {
    switch (nodeAuditStatus) {
      case 0:
        return '待审核';
      case 1:
        return '已通过';
      case 2:
        return '已驳回';
      default:
        return '审核状态未知';
    }
  }

  /// 地址。★ 空不等于「没有地址」也不等于 0,照实说没填。
  String get addressLabel =>
      (address ?? '').trim().isEmpty ? '未填地址' : address!.trim();

  factory MyChapterNode.fromJson(Map<String, dynamic> json) => MyChapterNode(
    id: asInt(json['id']),
    name: (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : '未命名点位',
    address: json['address'] as String?,
    chapterId: json['chapterId'] == null ? null : asInt(json['chapterId']),
    topicId: json['topicId'] == null ? null : asInt(json['topicId']),
    nodeAuditStatus: json['nodeAuditStatus'] == null
        ? null
        : asInt(json['nodeAuditStatus']),
    nodeAuditReason: json['nodeAuditReason'] as String?,
  );
}

/// 即将到店的场次(`/api/merchant/upcoming-runs` 的一行)。
class UpcomingRun {
  const UpcomingRun({
    this.ticketId,
    this.startTime,
    this.clubName,
    this.paidCount,
    this.teamStatus,
    this.nodeOrder,
    this.nodeTotal,
    this.arrivalStart,
    this.arrivalEnd,
  });

  final int? ticketId;
  final String? startTime;
  final String? clubName;

  /// 已付款人数。★ **null ≠ 0**:没查到人数和"一个人都没买"是两回事。
  final int? paidCount;

  final String? teamStatus;
  final int? nodeOrder;
  final int? nodeTotal;
  final String? arrivalStart;
  final String? arrivalEnd;

  /// 场次来源。俱乐部包团显示俱乐部名,否则是自由报名场。
  String get sourceLabel =>
      (clubName ?? '').trim().isEmpty ? '自由报名场' : clubName!.trim();

  /// 人数 · 成团状态。★ 人数拿不到就说「人数未知」,不写「0 人」。
  String get metaLabel {
    final List<String> parts = <String>[
      paidCount == null ? '人数未知' : '$paidCount 人',
      if (teamStatusLabel.isNotEmpty) teamStatusLabel,
    ];
    return parts.join(' · ');
  }

  String get teamStatusLabel {
    switch (teamStatus) {
      case 'FORMED':
      case 'formed':
        return '已成团';
      case 'PENDING':
      case 'pending':
        return '待成团';
      case 'FAILED':
      case 'failed':
        return '未成团';
      default:
        return '';
    }
  }

  /// 第几站。两个数都齐才说,缺一个就不说 —— 「第 3/0 站」比不说更糟。
  String get stepLabel {
    if (nodeOrder == null || nodeTotal == null || nodeTotal! <= 0) return '';
    return '第 $nodeOrder/$nodeTotal 站';
  }

  /// 预计到店窗口。★ 这是**估算区间**,两端事实不齐时一律不给区间,
  ///   不自己补一个 —— 商家会照着它安排人手。
  String get arrivalLabel {
    final String s = (arrivalStart ?? '').trim();
    final String e = (arrivalEnd ?? '').trim();
    if (s.isEmpty || e.isEmpty) return '';
    return '预计 ${_clock(s)}-${_clock(e)} 到店';
  }

  /// 开场时间。拿不到就说没拿到。
  ///
  /// ★ 只**截**不**解析**:原串是服务端格式化好的 `yyyy-MM-dd HH:mm:ss`,
  ///   里面没有时区;拿去 DateTime.parse 再 format 会按本地时区猜,跨日就错。
  ///   这里只把末尾的秒切掉,不做任何时间运算。
  String get startLabel {
    final String t = (startTime ?? '').trim();
    if (t.isEmpty) return '开场时间未知';
    return RegExp(r'^(.*\d{2}:\d{2}):\d{2}$').firstMatch(t)?.group(1) ?? t;
  }

  /// `2026-08-19 14:30:00` → `14:30`。★ 只截不解析:原串没有时区,
  ///   重新 parse 会按本地时区猜,跨日就错。
  static String _clock(String raw) {
    final int i = raw.indexOf(':');
    if (i < 2) return raw;
    return raw.substring(i - 2, i + 3);
  }

  factory UpcomingRun.fromJson(Map<String, dynamic> json) => UpcomingRun(
    ticketId: json['ticketId'] == null ? null : asInt(json['ticketId']),
    startTime: json['startTime']?.toString(),
    clubName: json['clubName'] as String?,
    paidCount: json['paidCount'] == null ? null : asInt(json['paidCount']),
    teamStatus: json['teamStatus']?.toString(),
    nodeOrder: json['nodeOrder'] == null ? null : asInt(json['nodeOrder']),
    nodeTotal: json['nodeTotal'] == null ? null : asInt(json['nodeTotal']),
    arrivalStart: json['arrivalStart']?.toString(),
    arrivalEnd: json['arrivalEnd']?.toString(),
  );
}

/// 一条报名的完整内容(`/api/registration/merchant/info`)。
///
/// ★★ 这个模型只带**能改的那九个字段** + 只读的身份/状态。
///   服务端 `MerchantRegistrationEditServiceImpl` 的白名单就是这九个:
///   picUrl / address / addressName / longitude / latitude /
///   activityDesc / limitNum / startDate / endDate。
///   topicId、nodeId、templateId 是承接标的,status/auditStatus 是审核结论,
///   sharingRate/sharingAmount 是钱 —— 一律不接受客户端改,
///   所以表单里**也不该出现**,做成可编辑就是在骗人。
class MerchantRegistrationDetail {
  const MerchantRegistrationDetail({
    required this.id,
    this.topicId,
    this.topicName,
    this.nodeName,
    this.chapterName,
    this.status,
    this.auditStatus,
    this.reason,
    this.picUrl,
    this.address,
    this.addressName,
    this.longitude,
    this.latitude,
    this.activityDesc,
    this.limitNum,
    this.startDate,
    this.endDate,
  });

  final int id;
  final int? topicId;
  final String? topicName;
  final String? nodeName;
  final String? chapterName;

  /// 0 待审核 / 1 已通过 / 2 已驳回。**缺席保持 null**。
  final int? status;

  /// 1 = 已中标。详情接口会富化它(列表接口不下发)。
  final int? auditStatus;
  final String? reason;

  final String? picUrl;
  final String? address;
  final String? addressName;
  final String? longitude;
  final String? latitude;
  final String? activityDesc;
  final int? limitNum;
  final String? startDate;
  final String? endDate;

  bool get isWon => auditStatus == 1;

  /// 能不能改。★ 与服务端闸二同口径:只有「审核中」「已驳回」可改。
  ///
  /// ⚠️ 「主题未开始」那一半**前端算不出来**(要查主题时间),
  ///   所以这里只是减少必然失败的点击,真正的闸在 service ——
  ///   拒绝时把它的原话照显示。
  bool get canEdit => status == 0 || status == 2;

  /// 图片列表。后端存的是逗号分隔串。
  List<String> get pics => (picUrl ?? '')
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  factory MerchantRegistrationDetail.fromJson(Map<String, dynamic> json) =>
      MerchantRegistrationDetail(
        id: asInt(json['id']),
        topicId: json['topicId'] == null ? null : asInt(json['topicId']),
        topicName: json['topicName'] as String?,
        nodeName: json['nodeName'] as String?,
        chapterName: json['chapterName'] as String?,
        status: json['status'] == null ? null : asInt(json['status']),
        auditStatus: json['auditStatus'] == null
            ? null
            : asInt(json['auditStatus']),
        reason: json['reason'] as String?,
        picUrl: json['picUrl'] as String?,
        address: json['address'] as String?,
        addressName: json['addressName'] as String?,
        longitude: json['longitude']?.toString(),
        latitude: json['latitude']?.toString(),
        activityDesc: json['activityDesc'] as String?,
        limitNum: json['limitNum'] == null ? null : asInt(json['limitNum']),
        startDate: json['startDate']?.toString(),
        endDate: json['endDate']?.toString(),
      );
}

/// 我的章节承接申请,叠上「这一章的档位」后的可操作态。
///
/// ★★ `/api/merchant/chapter-application/mine` **不下发 termsMode** ——
///   它得从可承接章节那份里按 chapterId 对出来。对不出来时
///   `canSubmitOffer` 必须是 false:档位不明就摆「填实际供给」,
///   点下去必被「条款档不合法」或「本章节是 X,不能按 Y 入驻」拒掉。
class ChapterApplicationAction {
  const ChapterApplicationAction({
    required this.status,
    required this.source,
    required this.offerActive,
    this.termsMode,
    this.offerId,
    this.circleThemeCode,
  });

  final int status;
  final int source;
  final bool offerActive;
  final String? termsMode;

  /// 生效供给的编号;为空 = 无从定位这份供给。
  final int? offerId;

  /// 供给挂的圈层主题编号;为空 = 不是圈层供给。
  final String? circleThemeCode;

  /// 撤回。只有**自己申请的、还在审核中**的能撤。
  bool get canWithdraw => status == 0 && source != 1;

  /// 填实际供给。★ 三个条件缺一不可:
  ///   ① 申请已通过 —— 服务端 enroll 的授权闸就是「本章申请已通过」;
  ///   ② 还没有生效供给 —— 已生效的要改必须先撤回重来;
  ///   ③ 档位读得出来 —— 见类注释。
  bool get canSubmitOffer =>
      status == 1 && !offerActive && termsModeLabel(termsMode) != null;

  /// 已经有生效供给了。界面要说清「要改先撤回」,而不是给一个必被拒的按钮。
  bool get offerReadOnly => offerActive;

  /// 圈层供给的两个复核动作(「供给无变化,重新确认」/「暂停供给」)。
  ///
  /// ★★ 三个条件与小程序**一字不差**(`pages/topic/merchantinfo/merchantinfo.js`
  ///   `refreshMyChapterApplications`):`offerActive && offerId && circleThemeCode`。
  ///   少一个都会摆出一个点下去必被拒的按钮 —— 后端两条都要 offerId,
  ///   且 30 天复核只对**圈层**供给成立。
  bool get canReconfirmCircleSupply =>
      offerActive &&
      (offerId ?? 0) > 0 &&
      (circleThemeCode ?? '').trim().isNotEmpty;
}
