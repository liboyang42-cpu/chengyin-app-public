/// 一条同意记录(`/api/compliance/consents/latest`)。
///
/// ★ **拿不到记录 = 没同意过**,由 API 层返回 null 表示 —— 那是正常态不是错误。
class ConsentRecord {
  const ConsentRecord({
    required this.docType,
    this.docVersion,
    this.scene,
    this.scopeType,
    this.scopeId,
    this.eventType,
    this.occurredAt,
  });

  final String docType;

  /// 同意时的文档版本。★ **由服务端给** —— 客户端不猜:
  /// 猜的版本一旦与服务端不符,后端会判定「未同意」。
  final String? docVersion;

  final String? scene;

  /// 授权范围。只有商家授权这类场景才有 —— 后端在为空时**不下发这两个字段**,
  /// 所以 null 表示「本场景无范围概念」,不是「范围丢了」。
  final String? scopeType;
  final int? scopeId;

  final String? eventType;
  final String? occurredAt;

  factory ConsentRecord.fromJson(Map<String, dynamic> json) {
    String? s(String k) {
      final String t = (json[k] ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return ConsentRecord(
      docType: (json['docType'] ?? '').toString(),
      docVersion: s('docVersion'),
      scene: s('scene'),
      scopeType: s('scopeType'),
      scopeId: (json['scopeId'] as num?)?.toInt(),
      eventType: s('eventType'),
      occurredAt: s('occurredAt'),
    );
  }
}
