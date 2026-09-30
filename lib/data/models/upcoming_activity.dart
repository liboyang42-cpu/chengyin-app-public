/// 「即将上线」活动项。对齐后端 CmsActivity / `/api/activity/list`(isMy:2)。
/// 在 Activity 列表项基础上补充 startDate(后端 java.util.Date,序列化为字符串)
/// 以驱动倒计时。单独建模以避免改动共享的 Activity 模型。
class UpcomingActivity {
  UpcomingActivity({
    required this.id,
    required this.name,
    this.imgUrl,
    this.addressName,
    this.startDate,
  });

  final int id;
  final String name;
  final String? imgUrl;
  final String? addressName;

  /// 开始时间,解析失败 / 缺失时为 null。
  final DateTime? startDate;

  factory UpcomingActivity.fromJson(Map<String, dynamic> json) {
    return UpcomingActivity(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '') as String,
      imgUrl: json['imgUrl'] as String?,
      addressName: json['addressName'] as String?,
      startDate: _parseDate(json['startDate']),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    // 后端常见格式 "2026-06-23 18:00:00",DateTime.parse 接受 ISO/空格分隔。
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }
}
