import 'package:chengyin_app/core/util/json_parse.dart';

/// 勋章墙 v2(对齐后端 BadgeWallV2VO / `/api/badge/wall-v2`)。
/// 身份卡目录的真源在库(growth_badge 表),本页消费 identity 层;
/// growth/collection/honor 三层本页不渲染。
class BadgeWallV2 {
  BadgeWallV2({
    required this.identity,
    required this.growth,
    required this.collection,
    required this.honor,
  });

  final List<BadgeWallItem> identity;
  final List<BadgeWallItem> growth;
  final List<BadgeWallItem> collection;
  final List<BadgeWallItem> honor;

  factory BadgeWallV2.fromJson(Map<String, dynamic> json) => BadgeWallV2(
    identity: _items(json['identity']),
    growth: _items(json['growth']),
    collection: _items(json['collection']),
    honor: _items(json['honor']),
  );

  static List<BadgeWallItem> _items(Object? raw) => (raw as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(BadgeWallItem.fromJson)
      .toList();
}

/// 墙上一枚身份卡(对齐 BadgeWallItemVO)。
class BadgeWallItem {
  BadgeWallItem({
    required this.badgeCode,
    required this.badgeName,
    required this.nameEn,
    required this.statement,
    required this.iconUrl,
    required this.assetType,
    required this.category,
    required this.unlockHint,
    required this.unlocked,
    required this.unlockTime,
  });

  final String badgeCode;
  final String badgeName;
  final String nameEn;
  final String statement;
  final String iconUrl;
  final String assetType;
  final String category;
  final String unlockHint;
  final bool unlocked;

  /// 获得时间(后端 Date 序列化为中国时间串);未点亮为 null。
  final String? unlockTime;

  factory BadgeWallItem.fromJson(Map<String, dynamic> json) => BadgeWallItem(
    badgeCode: asStr(json['badgeCode']),
    badgeName: asStr(json['badgeName']),
    nameEn: asStr(json['nameEn']),
    statement: asStr(json['statement']),
    iconUrl: asStr(json['iconUrl']),
    assetType: asStr(json['assetType']),
    category: asStr(json['category']),
    unlockHint: asStr(json['unlockHint']),
    unlocked: asBool(json['unlocked']),
    unlockTime: json['unlockTime'] as String?,
  );
}

/// 我的勋章墙(对齐 `/api/medal/wall` 返回)。
class MedalWall {
  MedalWall({required this.count, required this.medals});

  final int count;
  final List<MedalWallItem> medals;

  factory MedalWall.fromJson(Map<String, dynamic> json) => MedalWall(
    count: asInt(json['count']),
    medals: (json['medals'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(MedalWallItem.fromJson)
        .toList(),
  );
}

/// 一枚纪念章 / 成就徽章(对齐 medal/wall 单行)。
class MedalWallItem {
  MedalWallItem({
    required this.templateId,
    required this.medalImg,
    required this.medalName,
    required this.style,
    required this.topicId,
    required this.getTime,
    required this.condition,
    required this.kind,
    required this.badgeCode,
  });

  final int templateId;
  final String medalImg;
  final String medalName;
  final String style;
  final int topicId;
  final String? getTime;
  final String condition;

  /// 'achievement' = 成就徽章;其他 = 城市纪念章(模板勋章)。
  final String kind;
  final String badgeCode;

  factory MedalWallItem.fromJson(Map<String, dynamic> json) => MedalWallItem(
    templateId: asInt(json['templateId']),
    medalImg: asStr(json['medalImg']),
    medalName: asStr(json['medalName']),
    style: asStr(json['style']),
    topicId: asInt(json['topicId']),
    getTime: json['getTime'] as String?,
    condition: asStr(json['condition']),
    kind: asStr(json['kind']),
    badgeCode: asStr(json['badgeCode']),
  );
}
