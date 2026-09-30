/// 提现记录。对齐后端 `ApiWithdrawalController`(/api/withdrawal)与 `WithdrawalDTO`。
///
/// ★ R10(2026-09-17):App 不再发起提现(改弹客服微信号、线下结算),
///   模型层只保留历史记录读取;`WithdrawalPreflight` / `WithdrawalForm`
///   随银行卡表单一起删除。
class WithdrawalRecord {
  const WithdrawalRecord({
    required this.id,
    required this.amount,
    this.status = 0,
    this.bankName,
    this.bankAccount,
    this.createTime,
    this.remark,
  });

  final int id;
  final double amount;
  final int status;
  final String? bankName;
  final String? bankAccount;
  final String? createTime;
  final String? remark;

  /// 状态文案。★ 与后端审核状态一一对应,不自己发明中间态。
  String get statusText {
    switch (status) {
      case 1:
        return '审核通过';
      case 2:
        return '已打款';
      case 3:
        return '已驳回';
      default:
        return '待审核';
    }
  }

  /// 尾号显示。银行账号是敏感信息,列表里只给尾四位。
  String get maskedAccount {
    final a = bankAccount ?? '';
    return a.length > 4 ? '**** ${a.substring(a.length - 4)}' : a;
  }

  factory WithdrawalRecord.fromJson(Map<String, dynamic> json) {
    final Object? rawId = json['id'];
    final Object? rawAmount = json['withdrawalAmount'] ?? json['amount'];
    final Object? rawStatus = json['status'];
    if (rawId is! num ||
        !rawId.isFinite ||
        rawId.truncateToDouble() != rawId.toDouble() ||
        rawId.toInt() <= 0 ||
        rawAmount is! num ||
        !rawAmount.isFinite ||
        rawAmount.toDouble() <= 0 ||
        rawStatus is! num ||
        !rawStatus.isFinite ||
        rawStatus.truncateToDouble() != rawStatus.toDouble() ||
        rawStatus.toInt() < 0 ||
        rawStatus.toInt() > 3) {
      throw const FormatException('提现记录回执不完整');
    }
    return WithdrawalRecord(
      id: rawId.toInt(),
      amount: rawAmount.toDouble(),
      status: rawStatus.toInt(),
      bankName: json['bankName'] as String?,
      bankAccount: json['bankAccount'] as String?,
      createTime: json['createTime'] as String?,
      remark: json['remark'] as String?,
    );
  }
}

/// 客诉期内的一笔未到账金额(某天起可提现)。
class ComplaintPeriodStage {
  const ComplaintPeriodStage({
    required this.availableDate,
    required this.amount,
  });

  /// `YYYY-MM-DD`(服务端原样给,非法日期整块判「取不到」)。
  final String availableDate;
  final double amount;

  /// 行文案。快照 `view-model.js` —— `客诉期中 · M月D日可提现`。
  String get label {
    final RegExpMatch? m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(availableDate);
    if (m == null) return '客诉期中';
    final int month = int.parse(m.group(2)!);
    final int day = int.parse(m.group(3)!);
    return '客诉期中 · $month月$day日可提现';
  }
}

/// 余额三段(`POST /api/wallet/stages` 的 data,2026-09-16 晚拍板第 5 条):
/// 待结算(活动未结束)→ 客诉期中(X月X日可提现)→ 可提现,涉诉金额单列。
///
/// ★★ 金额口径全在后端,这里只做**如实**:字段缺失/不是数/负数 ⇒ 整块 null
///   (页面显示「未到账金额暂时取不到」),绝不把缺失渲染成 0 ——
///   那是关于用户资产的错误事实陈述。快照 `buildFundsStages` 同口径。
class MemberFundsStages {
  const MemberFundsStages({
    required this.pendingSettlement,
    required this.disputed,
    required this.withdrawable,
    required this.complaintPeriod,
    required this.amountsKnown,
  });

  final double pendingSettlement;
  final double disputed;
  final double withdrawable;

  /// 只保留 amount > 0 的项(0 元不该占一行)。
  final List<ComplaintPeriodStage> complaintPeriod;

  /// 服务端说「部分金额暂时算不出」时为 false(`amountsKnown === false`)。
  final bool amountsKnown;

  /// 待结算金额文案。不展现的档返回空串(快照 `pending > 0 ? ... : ''`)。
  String get pendingText =>
      pendingSettlement > 0 ? pendingSettlement.toStringAsFixed(2) : '';
  String get disputedText => disputed > 0 ? disputed.toStringAsFixed(2) : '';
  String get withdrawableText => withdrawable.toStringAsFixed(2);

  static double? _amount(Object? value) {
    final num? n = value is num
        ? value
        : (value is String && value.trim().isNotEmpty
              ? num.tryParse(value.trim())
              : null);
    if (n == null || !n.isFinite || n < 0) return null;
    return n.toDouble();
  }

  static MemberFundsStages? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final Object? rawPeriod = value['complaintPeriod'];
    if (rawPeriod is! List) return null;
    final double? pending = _amount(value['pendingSettlement']);
    final double? disputed = _amount(value['disputed']);
    final double? withdrawable = _amount(value['withdrawable']);
    if (pending == null || disputed == null || withdrawable == null) return null;
    final List<ComplaintPeriodStage> period = <ComplaintPeriodStage>[];
    for (final Object? item in rawPeriod) {
      if (item is! Map<String, dynamic>) return null;
      final double? amount = _amount(item['amount']);
      final Object? rawDate = item['availableDate'];
      if (amount == null ||
          rawDate is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate)) {
        return null;
      }
      if (amount > 0) {
        period.add(
          ComplaintPeriodStage(availableDate: rawDate, amount: amount),
        );
      }
    }
    return MemberFundsStages(
      pendingSettlement: pending,
      disputed: disputed,
      withdrawable: withdrawable,
      complaintPeriod: period,
      amountsKnown: value['amountsKnown'] != false,
    );
  }
}
