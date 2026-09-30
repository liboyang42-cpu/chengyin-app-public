/// 商家客户名册一行。对齐小程序 `pages/merchant/customer` 的 shapeRow。
class MerchantCustomer {
  const MerchantCustomer({
    this.customerMemberId,
    this.name = '',
    this.phone = '',
    this.avatar,
    this.tier,
    this.lastAction,
    this.lastTime,
    this.contactHint,
  });

  /// 客户详情路由与 CRM 写操作使用的会员 ID。
  /// 列表接口当前字段名为 `memberId`，详情回包使用 `customerMemberId`。
  final int? customerMemberId;
  final String name;
  final String phone;
  final String? avatar;

  /// 分层:new / active / loyal …
  final String? tier;
  final String? lastAction;
  final String? lastTime;
  final String? contactHint;

  /// 列表主标题。没留姓名时兜底。
  String get displayName => name.trim().isEmpty ? '未留姓名' : name.trim();

  /// 头像取首字用的名字。
  ///
  /// ★ **兜底文案不能进头像** —— 用 displayName 会渲成一个「未」字当姓氏。
  ///   没名字就返回空串,让头像走图片或纯色占位。
  String get avatarName => name.trim();

  String get tierText {
    switch (tier) {
      case 'loyal':
        return '常客';
      case 'active':
        return '活跃';
      default:
        return '新客';
    }
  }

  /// 「核销了『夜跑咖啡路线』· 3 天前」。
  ///
  /// ★ 两截都可能为空 —— 直接拼会得到孤零零的「· 」。用 where 过滤后再 join。
  String actionText(DateTime now) {
    final parts = <String>[
      (lastAction ?? '').trim(),
      relativeTime(lastTime, now),
    ].where((String s) => s.isNotEmpty).toList();
    return parts.join(' · ');
  }

  factory MerchantCustomer.fromJson(Map<String, dynamic> json) {
    final Object? rawMemberId = json['memberId'] ?? json['customerMemberId'];
    final int? parsedMemberId = rawMemberId is num
        ? rawMemberId.toInt()
        : int.tryParse(rawMemberId?.toString() ?? '');
    return MerchantCustomer(
      customerMemberId: parsedMemberId != null && parsedMemberId > 0
          ? parsedMemberId
          : null,
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      avatar: json['avatar'] as String?,
      tier: json['tier'] as String?,
      lastAction: json['lastAction'] as String?,
      lastTime: json['lastTime'] as String?,
      contactHint: json['contactHint'] as String?,
    );
  }
}

/// 客户名册分页回包。`null` 表示服务端未下发，不能用 0 伪造。
class MerchantCustomerPageData {
  const MerchantCustomerPageData({
    required this.rows,
    required this.total,
    required this.segmentCounts,
    required this.pageNum,
    required this.pageSize,
    required this.hasMore,
  });

  final List<MerchantCustomer> rows;
  final int? total;
  final Map<String, int?> segmentCounts;
  final int pageNum;
  final int pageSize;
  final bool hasMore;

  static const List<String> segmentKeys = <String>[
    'all',
    'pending',
    'repeat',
    'dormant',
    'abnormal',
  ];

  factory MerchantCustomerPageData.fromJson(
    Map<String, dynamic> json, {
    required int requestedPageNum,
    required int requestedPageSize,
  }) {
    int? countOf(dynamic value) {
      final int? parsed = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '');
      return parsed != null && parsed >= 0 ? parsed : null;
    }

    final List<MerchantCustomer> rows =
        ((json['rows'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MerchantCustomer.fromJson)
            .toList(growable: false);
    final int pageNum = countOf(json['pageNum']) ?? requestedPageNum;
    final int pageSize = countOf(json['pageSize']) ?? requestedPageSize;
    final int? total = countOf(json['total']);
    final dynamic rawCounts = json['segmentCounts'];
    final Map<String, dynamic> counts = rawCounts is Map<String, dynamic>
        ? rawCounts
        : const <String, dynamic>{};
    final dynamic explicitHasMore = json['hasMore'];
    final bool hasMore = explicitHasMore is bool
        ? explicitHasMore
        : total != null
        ? pageNum * pageSize < total
        : rows.length >= pageSize && pageSize > 0;
    return MerchantCustomerPageData(
      rows: rows,
      total: total,
      segmentCounts: <String, int?>{
        for (final String key in segmentKeys) key: countOf(counts[key]),
      },
      pageNum: pageNum,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }
}

/// 相对时间。
///
/// ★ **必须在前端按用户本机时区算** —— 服务端算「3 天前」会按服务器时区,
///   跨时区必错;而且 CI 恒 UTC,这类 bug 结构性抓不到(小程序侧原注释)。
/// ★ now 由调用方传入,否则测不了。
String relativeTime(String? value, DateTime now) {
  if (value == null || value.isEmpty) return '';
  final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (parsed == null) return '';
  final days = now.difference(parsed).inDays;
  if (days < 0) return ''; // 未来时间不显示「-1 天前」
  if (days == 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 30) return '$days 天前';
  if (days < 365) return '${days ~/ 30} 个月前';
  return '${days ~/ 365} 年前';
}
