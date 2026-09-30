/// 社区举报原因的稳定代码表。
///
/// 标签只用于展示，后端分流只认 [code]。显式映射避免“中文里包含某个词”造成
/// 色情内容落入 OTHER、知识产权问题落入 PRIVACY 之类的错误案件分类。
class CommunityReportReason {
  const CommunityReportReason(
    this.code,
    this.label, {
    this.priority,
    this.firstResponseMinutes,
    this.emergency = false,
  });

  final String code;
  final String label;
  final String? priority;
  final int? firstResponseMinutes;
  final bool emergency;

  factory CommunityReportReason.fromJson(Map<String, dynamic> json) {
    final String code = '${json['code'] ?? ''}'.trim();
    final String label = '${json['label'] ?? ''}'.trim();
    if (code.isEmpty || label.isEmpty) {
      throw const FormatException('举报原因缺少code或label');
    }
    return CommunityReportReason(
      code,
      label,
      priority: '${json['priority'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['priority']}'.trim(),
      firstResponseMinutes: (json['firstResponseMinutes'] as num?)?.toInt(),
      emergency: json['emergency'] == true,
    );
  }

  static const List<CommunityReportReason> values = <CommunityReportReason>[
    CommunityReportReason('DANGEROUS', '现实人身危险或违法行为'),
    CommunityReportReason('MINOR_SAFETY', '未成年人安全'),
    CommunityReportReason('SELF_HARM', '自伤或自杀风险'),
    CommunityReportReason('SEXUAL_CONTENT', '色情低俗内容'),
    CommunityReportReason('HARASSMENT', '人身攻击或骚扰'),
    CommunityReportReason('HATE', '仇恨或歧视'),
    CommunityReportReason('FRAUD', '诈骗'),
    CommunityReportReason('IMPERSONATION', '冒充他人'),
    CommunityReportReason('FALSE_INFORMATION', '虚假信息'),
    CommunityReportReason('SPAM', '垃圾广告或站外导流'),
    CommunityReportReason('PRIVACY', '隐私泄露'),
    CommunityReportReason('INTELLECTUAL_PROPERTY', '知识产权或内容盗用'),
    CommunityReportReason('OTHER', '其他'),
  ];

  static const Map<String, String> _legacyAliases = <String, String>{
    '含有违法违规内容': 'DANGEROUS',
    '色情低俗': 'SEXUAL_CONTENT',
    '虚假信息或欺诈': 'FRAUD',
    '侵犯他人权益': 'PRIVACY',
  };

  static String codeForLabel(String label) {
    final String normalized = label.trim();
    for (final CommunityReportReason reason in values) {
      if (reason.label == normalized) return reason.code;
    }
    final String? alias = _legacyAliases[normalized];
    if (alias != null) return alias;
    throw StateError('未知举报原因，已停止提交以避免错误分流');
  }
}

class CommunityReportPolicySnapshot {
  static const String localPolicyVersion = 'COMMUNITY_REPORT_POLICY_V1';

  const CommunityReportPolicySnapshot({
    required this.policyVersion,
    required this.reasons,
  });

  final String policyVersion;
  final List<CommunityReportReason> reasons;

  factory CommunityReportPolicySnapshot.fromJson(Map<String, dynamic> json) {
    final String version = '${json['policyVersion'] ?? ''}'.trim();
    final List<dynamic> rawReasons =
        json['reasons'] as List<dynamic>? ?? const <dynamic>[];
    if (version.isEmpty || rawReasons.isEmpty) {
      throw const FormatException('举报政策缺少版本或原因列表');
    }
    final List<CommunityReportReason> reasons = rawReasons
        .map(
          (dynamic row) => CommunityReportReason.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
    final Set<String> codes = <String>{};
    final Set<String> labels = <String>{};
    for (final CommunityReportReason reason in reasons) {
      if (!codes.add(reason.code) || !labels.add(reason.label)) {
        throw const FormatException('举报原因code或label重复');
      }
    }
    return CommunityReportPolicySnapshot(
      policyVersion: version,
      reasons: List<CommunityReportReason>.unmodifiable(reasons),
    );
  }
}

/// 用户选择举报原因时的不可分割快照；原因代码与规则版本必须一起提交。
class CommunityReportSelection {
  const CommunityReportSelection({
    required this.policyVersion,
    required this.reason,
    this.evidenceAssetIds = const [],
  });

  final String policyVersion;
  final CommunityReportReason reason;
  final List<int> evidenceAssetIds;
}
