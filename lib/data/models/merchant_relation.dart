/// 商家关系(合作过的商家 / 俱乐部)。对齐小程序 `pages/merchant/relation`。
class MerchantRelation {
  const MerchantRelation({
    required this.id,
    required this.memberId,
    required this.name,
    this.address,
    this.categoryName,
    this.city,
    this.type = 'merchant',
  });

  final int id;
  final int memberId;
  final String name;
  final String? address;
  final String? categoryName;
  final String? city;

  /// merchant / club。
  final String type;

  String get typeName => type == 'club' ? '俱乐部' : '商家';

  /// 副标题:地址 → 品类 → 城市,三选一;都没有时给一句可点的提示。
  String get displayDescription {
    for (final String? v in <String?>[address, categoryName, city]) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '查看$typeName资料';
  }

  /// 解析一行。
  ///
  /// ★ **没名字的整条丢掉**(小程序 relation/index.js:15 `if (displayName === '—') return null`)——
  ///   渲染一张只有「—」的卡片,用户点进去也不知道是谁。返回 null 由调用方过滤。
  static MerchantRelation? tryFromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return MerchantRelation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      memberId: (json['memberId'] as num?)?.toInt() ?? 0,
      name: name,
      address: json['address'] as String?,
      categoryName: json['categoryName'] as String?,
      city: json['city'] as String?,
      type: (json['type'] as String?) ?? 'merchant',
    );
  }
}

/// 关系页统计。
class MerchantRelationStats {
  const MerchantRelationStats({
    this.merchantCount = 0,
    this.clubCount = 0,
    this.pendingCoopCount = 0,
  });

  final int merchantCount;
  final int clubCount;

  /// 待处理的合作邀约数。★ 这一项是**待办**,为 0 时不该显示。
  final int pendingCoopCount;

  factory MerchantRelationStats.fromJson(Map<String, dynamic> json) {
    int n(String k) => (json[k] as num?)?.toInt() ?? 0;
    return MerchantRelationStats(
      merchantCount: n('merchantCount'),
      clubCount: n('clubCount'),
      pendingCoopCount: n('pendingCoopCount'),
    );
  }
}

/// 关系页整体。
class MerchantRelationHome {
  const MerchantRelationHome({
    this.relations = const <MerchantRelation>[],
    this.discoveryMerchants = const <MerchantRelation>[],
    this.stats = const MerchantRelationStats(),
  });

  final List<MerchantRelation> relations;
  final List<MerchantRelation> discoveryMerchants;
  final MerchantRelationStats stats;

  factory MerchantRelationHome.fromJson(Map<String, dynamic> json) {
    List<MerchantRelation> parse(Object? raw) {
      final list = raw is List ? raw : const <dynamic>[];
      return list
          .whereType<Map<String, dynamic>>()
          .map(MerchantRelation.tryFromJson)
          .whereType<MerchantRelation>() // 丢掉没名字的
          .toList();
    }

    final discovery = json['discovery'];
    return MerchantRelationHome(
      relations: parse(json['relations']),
      discoveryMerchants: discovery is Map<String, dynamic>
          ? parse(discovery['merchants'])
          : const <MerchantRelation>[],
      stats: json['stats'] is Map<String, dynamic>
          ? MerchantRelationStats.fromJson(json['stats'] as Map<String, dynamic>)
          : const MerchantRelationStats(),
    );
  }
}
