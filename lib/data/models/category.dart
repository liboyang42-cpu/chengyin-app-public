/// 分类。对齐后端 SysCategory / `/api/category/list`。
/// 后端字段:id / categoryName / type / icon(camelCase 序列化)。
class Category {
  Category({
    required this.id,
    required this.name,
    this.type,
    this.icon,
  });

  final int id;
  final String name;

  /// 类型 1主题 2活动 3创意广场 4模版 5其它。
  final int? type;
  final String? icon;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: (json['categoryName'] ?? json['name'] ?? '') as String,
    type: (json['type'] as num?)?.toInt(),
    icon: json['icon'] as String?,
  );
}
