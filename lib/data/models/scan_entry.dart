/// 门口游戏码解析回包:`POST /api/play/scan-entry` 的 data。
///
/// 真源 ApiPlayProgressController.java:1299-1315 —— 只透出
/// action/topicId/nodeId,activityId 仅已报名场次时存在;本接口不写打卡进度。
/// `action == 'play'` 进游玩,其余(未报名/待购)去主题购买页。
class ScanEntryResult {
  const ScanEntryResult({
    required this.action,
    this.topicId,
    this.nodeId,
    this.activityId,
  });

  factory ScanEntryResult.fromJson(Map<String, dynamic> json) =>
      ScanEntryResult(
        action: '${json['action'] ?? ''}'.trim(),
        topicId: _intOf(json['topicId']),
        nodeId: _intOf(json['nodeId']),
        activityId: _intOf(json['activityId']),
      );

  /// 后端把 id 发成 num 或数字字符串都收;解析不出按缺失处理(与小程序
  /// `== null || === ''` 的空判口径一致)。
  static int? _intOf(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String && raw.trim().isNotEmpty) return int.tryParse(raw.trim());
    return null;
  }

  final String action;
  final int? topicId;
  final int? nodeId;
  final int? activityId;
}
