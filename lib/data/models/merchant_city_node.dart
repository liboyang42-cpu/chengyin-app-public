/// 商家城市节点(据点)。对齐后端 `ApiMerchantNodeController`(/api/merchant/city-node)。
class CityNode {
  const CityNode({
    required this.id,
    required this.name,
    this.address,
    this.status,
    this.templateTitle,
    this.tagsText,
    this.validationMethod,
  });

  final int id;
  final String name;
  final String? address;
  final int? status;
  final String? templateTitle;
  final String? tagsText;
  final int? validationMethod;

  factory CityNode.fromJson(Map<String, dynamic> json) {
    return CityNode(
      id: ((json['poiId'] ?? json['id']) as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '未命名据点',
      address: json['address'] as String?,
      status: (json['status'] as num?)?.toInt(),
      templateTitle: json['templateTitle'] as String?,
      tagsText: (json['tagsText'] ?? json['tags']) as String?,
      validationMethod: (json['validationMethod'] as num?)?.toInt(),
    );
  }
}

/// 我提交的认领申请。
class CityNodeApplication {
  const CityNodeApplication({
    required this.id,
    required this.poiName,
    this.status,
    this.rejectReason,
    this.applicationType,
  });

  final int id;
  final String poiName;

  /// 0 待审 / 1 通过 / 2 驳回(与后端审核态一致)。
  final int? status;
  final String? rejectReason;
  final int? applicationType;

  String get displayTitle =>
      '${applicationType == 2 ? '节点认领' : '据点投放'} · $poiName';

  String get statusText {
    switch (status) {
      case 1:
        return '已通过';
      case 2:
        // ★ 驳回必须把原因说出来 —— 只说「已驳回」商家不知道怎么改。
        return (rejectReason?.isNotEmpty ?? false)
            ? '已驳回:$rejectReason'
            : '已驳回';
      default:
        return '审核中';
    }
  }

  factory CityNodeApplication.fromJson(Map<String, dynamic> json) {
    return CityNodeApplication(
      id: (json['id'] as num?)?.toInt() ?? 0,
      poiName:
          (json['poiName'] as String?) ?? (json['name'] as String?) ?? '未命名地点',
      status: ((json['auditStatus'] ?? json['status']) as num?)?.toInt(),
      rejectReason: (json['auditReason'] ?? json['rejectReason']) as String?,
      applicationType: (json['applicationType'] as num?)?.toInt(),
    );
  }
}

/// 据点页整体,含配额。
class CityNodeHome {
  const CityNodeHome({
    this.nodes = const <CityNode>[],
    this.applications = const <CityNodeApplication>[],
    this.used = 0,
    this.max = 0,
  });

  final List<CityNode> nodes;
  final List<CityNodeApplication> applications;

  /// 已用/上限。★ 用满时「认领新据点」必须禁用并说明原因,
  ///   而不是让商家点进去挑完地点再被后端拒。
  final int used;
  final int max;

  bool get quotaExhausted => max > 0 && used >= max;

  /// 配额文案。max 为 0 表示后端没下发上限 —— 那时**不显示配额**,
  /// 不能显示「0/0」让商家以为一个都不能建。
  String? get quotaText => max > 0 ? '$used / $max' : null;

  factory CityNodeHome.fromJson(Map<String, dynamic> json) {
    return CityNodeHome(
      nodes: ((json['nodes'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CityNode.fromJson)
          .toList(),
      applications:
          ((json['applications'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(CityNodeApplication.fromJson)
              .toList(),
      used: (json['used'] as num?)?.toInt() ?? 0,
      max: (json['max'] as num?)?.toInt() ?? 0,
    );
  }
}
