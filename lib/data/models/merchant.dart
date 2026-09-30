/// 商家。对齐后端 `MmsMerchant`(`/api/merchant/list` 公开搜索返回,脱敏字段已被后端抹除)。
class Merchant {
  Merchant({
    required this.id,
    this.memberId,
    this.name,
    this.logo,
    this.coverImage,
    this.description,
    this.address,
    this.slogan,
    this.cityRole,
    this.tags,
  });

  final int id;

  /// 商家主体的会员 ID。小程序商家结果拼主页地址用的是 memberId 而非本行 id。
  final int? memberId;
  final String? name;
  final String? logo;
  final String? coverImage;
  final String? description;
  final String? address;
  final String? slogan;
  final String? cityRole;
  final String? tags;

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
    id: (json['id'] as num?)?.toInt() ?? 0,
    memberId: (json['memberId'] as num?)?.toInt(),
    name: json['name'] as String?,
    logo: json['logo'] as String?,
    coverImage: json['coverImage'] as String?,
    description: json['description'] as String?,
    address: json['address'] as String?,
    slogan: json['slogan'] as String?,
    cityRole: json['cityRole'] as String?,
    tags: json['tags'] as String?,
  );
}