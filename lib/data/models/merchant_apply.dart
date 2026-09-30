/// 商家入驻申请。对齐小程序 `pages/merchant/apply` 与后端 `MerchantRegistrationDTO`。
///
/// ⚠️ 后端的 `@NotBlank(message = "商家名称不能为空")` 是**被注释掉的**
///   (MerchantRegistrationDTO:21),即服务端一个字段都不校验 ——
///   空名字也会被建成一条商家记录。**校验只剩前端这一道**,不能省。
class MerchantApplyForm {
  const MerchantApplyForm({
    this.id,
    this.name = '',
    this.preference = '',
    this.phone = '',
    this.description = '',
    this.address = '',
    this.businessTime = '',
    this.businessLicense = '',
    this.wechat = '',
  });

  /// 驳回后重新提交时带上原 id(小程序:status==2 才带)。
  final int? id;

  final String name;

  /// 品类偏好,如「餐饮、零售、文创」。
  final String preference;
  final String phone;
  final String description;
  final String address;
  final String businessTime;

  /// 营业执照图片 URL。第三步必填。
  final String businessLicense;
  final String wechat;

  MerchantApplyForm copyWith({
    int? id,
    String? name,
    String? preference,
    String? phone,
    String? description,
    String? address,
    String? businessTime,
    String? businessLicense,
    String? wechat,
  }) {
    return MerchantApplyForm(
      id: id ?? this.id,
      name: name ?? this.name,
      preference: preference ?? this.preference,
      phone: phone ?? this.phone,
      description: description ?? this.description,
      address: address ?? this.address,
      businessTime: businessTime ?? this.businessTime,
      businessLicense: businessLicense ?? this.businessLicense,
      wechat: wechat ?? this.wechat,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'name': name.trim(),
        'preference': preference.trim(),
        'phone': phone.trim(),
        'description': description.trim(),
        'address': address.trim(),
        'businessTime': businessTime.trim(),
        'businessLicense': businessLicense,
        'wechat': wechat.trim(),
      };
}

/// 四步向导的标题。与小程序 STEP_TITLES 一致。
const List<String> kApplyStepTitles = <String>[
  '基础信息',
  '经营信息',
  '资质信息',
  '预览确认',
];

/// 某一步能不能进入下一步。step 从 1 起。
///
/// ★ 与小程序 validate() 逐条对齐:
///   1 → 名称 + 手机;2 → 地址 + 营业时间;3 → 营业执照;4 → 恒真(预览页)。
bool applyStepReady(int step, MerchantApplyForm f) {
  switch (step) {
    case 1:
      return f.name.trim().isNotEmpty && f.phone.trim().isNotEmpty;
    case 2:
      return f.address.trim().isNotEmpty && f.businessTime.trim().isNotEmpty;
    case 3:
      return f.businessLicense.isNotEmpty;
    default:
      return true;
  }
}

/// 不能进入下一步时**说出缺什么**,而不是给个灰按钮让用户猜。
String? applyStepBlocker(int step, MerchantApplyForm f) {
  switch (step) {
    case 1:
      if (f.name.trim().isEmpty) return '请填写品牌名称';
      if (f.phone.trim().isEmpty) return '请填写联系手机号';
      return null;
    case 2:
      if (f.address.trim().isEmpty) return '请填写门店地址';
      if (f.businessTime.trim().isEmpty) return '请填写营业时间';
      return null;
    case 3:
      if (f.businessLicense.isEmpty) return '请上传营业执照';
      return null;
    default:
      return null;
  }
}

/// 「我的报名」的状态筛选。
///
/// ⚠️ 值是**字符串数字**,后端 `Convert.toLong(status, 0L)` 解析;
///   传 'all' 之类会被转成 0(=全部),看着像生效了其实是回落。
enum RegistrationListFilter {
  all('0', '全部'),
  ongoing('1', '进行中'),
  reviewing('2', '审核中'),
  rejected('3', '已驳回'),
  finished('4', '已结束');

  const RegistrationListFilter(this.wire, this.label);
  final String wire;
  final String label;
}

/// 「我的报名」一行(后端 `ViewRegistrationMerchant` + controller 富化)。
///
/// ★★ **两个状态字段并存,管的不是一件事**,合并会同时错两处:
///   · `status`     —— 审核态:0 待审核 / 1 已审核 / 2 审核失败(驳回)
///   · `auditStatus` —— 中标态:**1 = 已中标**(视图本身没这列,controller 从报名主表补的)
///
///   判据分别是:
///   · **能不能改** 看 status(只有 0/2 且主题未开始才行);
///   · **能不能取消** 看 auditStatus(已中标一律不能取消,闸在 service 里)。
///
///   用一个字段兜两件事的话:已中标的会给出取消按钮(点了必报错),
///   或者被驳回的给不出修改按钮(而那正是加 update 接口要解决的问题 ——
///   后端原注释:「被驳回的商家想补一张现场图,只能取消重报,记录丢失、重新排队」)。
class TopicRegistration {
  const TopicRegistration({
    required this.id,
    required this.topicId,
    this.topicName,
    this.topicImgUrl,
    this.addressName,
    this.mode,
    this.status,
    this.auditStatus,
    this.reason,
    this.startDate,
    this.endDate,
    this.chapterName,
    this.nodeName,
  });

  final int id;
  final int topicId;
  final String? topicName;
  final String? topicImgUrl;
  final String? addressName;
  final int? mode;

  /// 审核态。0 待审核 / 1 已审核 / 2 审核失败。
  final int? status;

  /// 中标态。1 = 已中标。
  final int? auditStatus;

  /// 驳回原因。status==2 时应当有;没有也要能显示。
  final String? reason;

  final String? startDate;
  final String? endDate;
  final String? chapterName;
  final String? nodeName;

  String? get assignmentText {
    final chapter = (chapterName ?? '').trim();
    final node = (nodeName ?? '').trim();
    final date = _displayDate(startDate);
    final parts = <String>[
      if (chapter.isNotEmpty) chapter,
      if (node.isNotEmpty && node != chapter) node,
      if (date.isNotEmpty) date,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get isRejected => status == 2;
  bool get isPending => status == 0;

  /// ★ 已中标 —— 取消闸看它,不看 status。
  bool get isWon => auditStatus == 1;

  /// 能不能改:待审核或已驳回。
  ///
  /// ⚠️ 「主题未开始」这个条件**只有后端知道**(要查主题时间),
  ///   前端算不出来 —— 所以这里只是**减少必然失败的点击**,
  ///   真正的闸在 service。改不了时后端会说清原因,照原文显示。
  bool get canEdit => status == 0 || status == 2;

  /// 能不能取消。
  ///
  /// ★★ 两条各管一半,**都要满足**:
  ///   ① 没中标 —— 中标的后端一律拒绝取消;
  ///   ② **审核状态得知道** —— status 为 null 时我们连它处于哪一档都不清楚,
  ///      摆一个取消按钮等于让用户去试。
  ///      (2026-08-19 看 golden 图发现:一条状态全空的记录显示着「状态未知」,
  ///       底下却摆着「取消报名」。)
  ///
  /// ⚠️ 判据**不能**写成 `auditStatus == 0`:
  ///   列表接口(view_registration_merchant)**根本不下发 auditStatus**,
  ///   只有详情接口才富化它 —— 那样写会让列表里每一行的取消按钮全消失。
  ///   我就这么改过一版,是去查 mapper 才发现的。
  bool get canCancel => !isWon && status != null;

  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

  static String _displayDate(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw.length <= 10 ? raw : raw.substring(0, 10);
    const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${weekdays[date.weekday - 1]} ${date.month}月${date.day}日';
  }

  factory TopicRegistration.fromJson(Map<String, dynamic> json) =>
      TopicRegistration(
        id: _int(json['id']),
        topicId: _int(json['topicId']),
        topicName: json['topicName']?.toString(),
        topicImgUrl: json['topicImgUrl']?.toString(),
        addressName: json['addressName']?.toString(),
        mode: _intOrNull(json['mode']),
        // ⚠️ 缺席保持 null,别兜 0 —— 0 是"待审核"这个**真实状态**,
        //   把"没拿到"说成"待审核"会让界面给出它其实没有的操作。
        status: _intOrNull(json['status']),
        auditStatus: _intOrNull(json['auditStatus']),
        reason: json['reason']?.toString(),
        startDate: json['startDate']?.toString(),
        endDate: json['endDate']?.toString(),
        chapterName: json['chapterName']?.toString(),
        nodeName: json['nodeName']?.toString(),
      );
}
