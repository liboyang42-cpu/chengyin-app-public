/// 商家 CRM 导出任务(`/api/merchant/crm/exports`)。
///
/// 五态来自小程序 `pages/merchant/customer/index.js:1241` 的 shapeExportTask ——
/// 那是个**白名单**:未知状态一律当没读到,而不是猜一个。
class MerchantCrmExportTask {
  const MerchantCrmExportTask({
    required this.id,
    required this.status,
    this.rowCount,
    this.downloadToken,
    this.errorMessage,
  });

  final int id;

  /// PENDING / RUNNING / SUCCESS / FAILED / EXPIRED。
  final String status;

  /// 行数。SUCCESS 时后端必给(shapeExportTask 里对 SUCCESS 强校验)。
  final int? rowCount;

  /// 下载凭证。★ 只在**创建**响应里给一次,轮询响应不带 ——
  ///   所以要跟任务一起记住,不能每次从状态里现取
  ///   (小程序 `this._exportToken` 就是这个用法,customer/index.js:1092)。
  final String? downloadToken;

  final String? errorMessage;

  /// 还在生成中(这两个态要禁重复发起,并继续轮询)。
  bool get isRunning => status == 'PENDING' || status == 'RUNNING';

  bool get isSuccess => status == 'SUCCESS';
  bool get isExpired => status == 'EXPIRED';
  bool get isFailed => status == 'FAILED';

  /// 状态条文案。逐字对齐小程序 `pages/merchant/customer/index.wxml:89-92`。
  String get statusLabel {
    switch (status) {
      case 'PENDING':
      case 'RUNNING':
        return '正在生成脱敏 Excel,可继续浏览客户';
      case 'SUCCESS':
        return '导出已就绪(${rowCount ?? 0} 行)';
      case 'EXPIRED':
        return '导出已过期,请重新创建';
      case 'FAILED':
        return '导出失败';
      default:
        return '导出状态未知';
    }
  }

  static const List<String> _knownStatuses = <String>[
    'PENDING',
    'RUNNING',
    'SUCCESS',
    'FAILED',
    'EXPIRED',
  ];

  /// 严格解析。★ 回到 null = 这一帧状态不可信(缺 id / 未知状态 /
  /// SUCCESS 却没有行数)—— 调用方应保留上一帧并重新查询,
  /// 而不是把 UI 落到一个编造的态上。判据同 shapeExportTask。
  static MerchantCrmExportTask? tryParse(Map<String, dynamic> json) {
    final int? id = (json['id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    final String status = '${json['status'] ?? ''}';
    if (!_knownStatuses.contains(status)) return null;
    final Object? rawCount = json['rowCount'];
    final int? rowCount = rawCount == null ? null : (rawCount as num?)?.toInt();
    if (status == 'SUCCESS' && (rowCount == null || rowCount < 0)) return null;
    return MerchantCrmExportTask(
      id: id,
      status: status,
      rowCount: rowCount,
      downloadToken: json['downloadToken'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
