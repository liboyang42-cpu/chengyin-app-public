/// 商家入驻申请行 + 状态投影。对齐小程序 `utils/merchant-identity-policy.js`。
///
/// ★★ 两个状态字段管的不是一件事,合并会同时错两处:
///   · `status`        —— 审核态:0 审核中 / 1 通过 / 2 驳回
///   · `accountStatus` —— 账号态:0 未启用 / 1 已启用 / 2 停用
///   停用(accountStatus==2)**优先级压过一切**,连驳回原因都不能冒充停用原因。
///
/// ⚠️ 后端字段拼写就是 `reson`(少一个 s)—— 那是审核驳回原因;
///   `disableReason` 是平台停用原因(R9-35 明确两者不复用,
///   混用会把历史驳回原因「执照模糊」显示成停用原因)。
class MerchantApplication {
  const MerchantApplication({
    required this.id,
    required this.status,
    required this.accountStatus,
    this.name = '',
    this.preference = '',
    this.phone = '',
    this.address = '',
    this.businessTime = '',
    this.description = '',
    this.businessLicense = '',
    this.derivatives = '',
    this.rejectReason = '',
    this.disableReason = '',
    this.createTime = '',
  });

  /// 申请行主键。重新提交时回传给后端走 update 分支。
  final int id;
  final int status;
  final int accountStatus;

  /// 表单回填用(驳回重提时商家不必从零再填一遍)。
  final String name;
  final String preference;
  final String phone;
  final String address;
  final String businessTime;
  final String description;
  final String businessLicense;
  final String derivatives;

  /// 后端原话 `reson`。
  final String rejectReason;
  final String disableReason;

  /// 提交时间原文(后端 `createTime`)。空串时真源回「已提交」。
  final String createTime;

  bool get isRejected => status == 2;
  bool get isDisabled => accountStatus == 2;

  /// 能否重新提交。★ 停用中的账号即使被驳回也不能重提。
  bool get canReapply => isRejected && !isDisabled;

  /// 状态签(小程序 `statusLabel`)。
  String get statusLabel {
    if (isDisabled) return '账号已停用';
    if (status == 1 && accountStatus == 1) return '已生效';
    if (isRejected) return '已驳回';
    if (status == 1) return '待启用';
    if (status == 0) return '审核中';
    return '状态待确认';
  }

  /// 状态正文(小程序 `statusText`)。原因一句拿后端原话,拿不到说「暂未填写」。
  String get statusText {
    if (isDisabled) {
      final String reason = disableReason.trim();
      return '商家账号已停用，经营功能暂不可用。'
          '${reason.isEmpty ? '平台暂未填写停用原因。' : '停用原因：$reason。'}'
          '请等待平台复核。';
    }
    if (status == 1 && accountStatus == 1) {
      return '商家身份已生效，可以进入商家中心使用经营功能。';
    }
    if (isRejected) {
      final String reason = rejectReason.trim();
      return '本次申请未通过。${reason.isEmpty ? '请完善资料后重新提交。' : reason}';
    }
    if (status == 1) {
      return '资料审核已通过；完成主理人移交等身份条件后，商家账号才会生效。';
    }
    if (status == 0) {
      return '我们正在审核你的资料，预计 1-3 个工作日内完成。';
    }
    return '申请状态暂时无法确认，请稍后重新检查。';
  }

  /// 时间线末节点(小程序 `timelineText`)。
  String get timelineText {
    if (isDisabled) return '账号已停用';
    if (status == 1 && accountStatus == 1) return '已生效';
    if (isRejected) return '未通过';
    if (status == 1) return '待身份条件完成';
    return '等待上一步完成';
  }

  /// 状态签是不是警示色(小程序 badgeVariant danger)。
  bool get isDangerBadge => isDisabled || isRejected;

  /// 状态签配色档(小程序 `badgeVariant`,四档)。
  /// 「待启用」在真源里是 **neutral**:审核过了但身份条件没齐,不是警示。
  String get badgeVariant {
    if (isDisabled || isRejected) return 'danger';
    if (status == 1 && accountStatus == 1) return 'success';
    if (status == 0) return 'warning';
    return 'neutral';
  }

  /// 时间线末节点是不是完成态(小程序 `timelineClass === 'done'`)。
  bool get timelineDone => status == 1 && accountStatus == 1;

  /// 时间线末节点是不是警示态(小程序 `timelineClass === 'rej'`)。
  bool get timelineRejected => isDisabled || isRejected;

  /// `POST /api/merchant/info` → 申请行。
  ///
  /// ★ 判据与小程序 `normalizeApplication` 逐条同:id 必须是正整数,
  ///   两个状态字段必须落在 0..2 —— 任一不满足就当**没有这一行**回落表单,
  ///   而不是拿脏数据渲染一个不存在的状态。
  static MerchantApplication? tryParse(Map<String, dynamic> json) {
    final int? id = _int(json['id']);
    final int? status = _int(json['status']);
    final int? accountStatus = _int(json['accountStatus']);
    if (id == null || id <= 0) return null;
    if (status == null || !_isAllowedState(status)) return null;
    if (accountStatus == null || !_isAllowedState(accountStatus)) return null;
    String text(String key) => (json[key] ?? '').toString().trim();
    return MerchantApplication(
      id: id,
      status: status,
      accountStatus: accountStatus,
      name: text('name'),
      preference: text('preference'),
      phone: text('phone'),
      address: text('address'),
      businessTime: text('businessTime'),
      description: text('description'),
      businessLicense: text('businessLicense'),
      derivatives: text('derivatives'),
      rejectReason: text('reson'),
      disableReason: text('disableReason'),
      createTime: text('createTime'),
    );
  }

  /// `/api/merchant/access/me` 未激活时下发的门店摘要 —— 字段更少
  /// (没有 reson/disableReason),但足以给工作台那张状态卡。
  static MerchantApplication? fromAccessSummary(Map<String, dynamic>? json) {
    if (json == null) return null;
    return tryParse(json);
  }

  /// 后端偶尔把 Long 序列化成字符串,小程序 `numberValue` 两种都收;
  /// 这里同一口径,否则「有申请行」会被读成「没有」。
  static int? _int(Object? v) => switch (v) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value.trim()),
    _ => null,
  };
  static bool _isAllowedState(int v) => v >= 0 && v <= 2;
}

/// 后端在「这个账号名下确实没有申请行」时的答复。
/// (`ApiMerchantOperatorController.accessMe` / `ApiMerchantController.getUserInfo`
///  都是 `data=null` + 顶层 `applicationState:"NONE"` —— 那是**结论不是故障**。)
bool isNoApplication(Map<String, dynamic> body) {
  final Object? data = body['data'];
  final bool empty = data == null || (data is Map && data.isEmpty);
  return empty && body['applicationState'] == 'NONE';
}
