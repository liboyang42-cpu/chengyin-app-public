/// 附近商家(线索)。对齐后端 `NearbyMerchantVO`(/api/merchant/nearby)。
///
/// ★ 隐私由**服务端**决定,前端只诚实反映:
///   后端在不可拨打时会把 phone 字段**直接置 null**(而不是发个真号让前端藏起来),
///   注释原话:「防『商家侧 canCall=false 但 phone 仍在返回 JSON 被抓包拿到真号』」。
///   所以这里**不做任何前端脱敏** —— 有号就是可拨,没号就是不可拨。
class NearbyMerchant {
  const NearbyMerchant({
    required this.id,
    required this.name,
    this.memberId,
    this.phone,
    this.address,
    this.distance,
    this.category,
    this.tags,
    this.canInvite = false,
    this.canCall = false,
  });

  final int id;
  final String name;

  /// 绑定的会员 id。★ 没有它就**发不出邀约**(邀约要 toId=memberId)。
  final int? memberId;

  /// 手机号。不可拨打时后端下发 null。
  final String? phone;
  final String? address;

  /// 距离(米)。
  final double? distance;
  final String? category;
  final String? tags;

  /// 能不能发线上邀约(已绑定账号且开放协作)。
  final bool canInvite;

  /// 能不能打电话(有权 + 有号 + 开放电话联系),后端算好。
  final bool canCall;

  /// 距离文案。★ 后端没给距离时**整行不显示**,不写「0m」——
  ///   那会让人以为商家就在脚下。
  String? get distanceText {
    final d = distance;
    if (d == null || d < 0) return null;
    if (d < 1000) return '${d.round()}m';
    return '${(d / 1000).toStringAsFixed(1)}km';
  }

  /// 真正能拨的号。★ 判据是 canCall **且** 号码非空 ——
  ///   两者任一不满足都不给拨号入口,不摆一个点了没反应的按钮。
  String? get dialablePhone {
    if (!canCall) return null;
    final p = phone?.trim() ?? '';
    return p.isEmpty ? null : p;
  }

  /// 标签切成列表。后端是逗号/顿号分隔的字符串。
  List<String> get tagList => (tags ?? '')
      .split(RegExp(r'[,,、\s]+'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  factory NearbyMerchant.fromJson(Map<String, dynamic> json) {
    return NearbyMerchant(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: ((json['name'] as String?) ?? '').trim().isEmpty
          ? '未命名商家'
          : (json['name'] as String).trim(),
      memberId: (json['memberId'] as num?)?.toInt(),
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      distance: (json['distance'] as num?)?.toDouble(),
      category: json['category'] as String?,
      tags: json['tags'] as String?,
      canInvite: json['canInvite'] == true,
      canCall: json['canCall'] == true,
    );
  }
}
