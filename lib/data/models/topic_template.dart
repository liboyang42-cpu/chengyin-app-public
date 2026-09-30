import 'package:flutter/foundation.dart';

/// 主题模板。对齐后端 `cms_topic`(is_template=1)与 `/api/template/topic-template/*`。
///
/// ★ 与 [PlayTemplate] 是**两套实体**,不能合并(计划文档第 543 行写明):
///   主题 = 一条路线(章节 / 节点 / 总时长),游戏 = 一个地点上的一次互动
///   (人数 / 时长)。字段没有交集,用一个模型兼容两种资源只会两边的字段都半空。
///
/// ★ 字段来源 = 小程序 `pages/template/index.js:355-372` 的 `decorateTopic()` ——
///   它是这条接口唯一的消费方(全仓其它地方零命中)。逐字照搬它读的键名:
///   `name` / `subtitle` / `chapterCount` / `locationCount` / `totalTime` /
///   `categoryIds` / `previewOnly` / `templateStatus` / `imgUrl`(+ `id`)。
///   ⚠️ 后端回包形状**本机未实测**(快照里只有调用点,没有响应样本);
///   多出来的键会被忽略,少一个键则退到空值 —— 但这不等于契约已核对。
@immutable
class TopicTemplate {
  const TopicTemplate({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.chapterCount = 0,
    this.locationCount = 0,
    this.totalTime,
    this.categoryIds = '',
    this.previewOnly = false,
    this.templateStatus,
    this.imgUrl,
  });

  factory TopicTemplate.fromJson(Map<String, dynamic> json) => TopicTemplate(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: (json['name'] ?? '').toString(),
    subtitle: (json['subtitle'] ?? '').toString(),
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    locationCount: (json['locationCount'] as num?)?.toInt() ?? 0,
    totalTime: json['totalTime'],
    categoryIds: json['categoryIds'] == null
        ? ''
        : json['categoryIds'].toString(),
    previewOnly: json['previewOnly'] == true,
    templateStatus: json['templateStatus']?.toString(),
    imgUrl: json['imgUrl']?.toString(),
  );

  final int id;
  final String name;
  final String subtitle;
  final int chapterCount;
  final int locationCount;

  /// 总时长。**原样留着**:后端历史数据同时存在数字(分钟)与已带「分钟」的
  /// 字符串两种形态,单位只应在展示层补一次 —— 见 [formatDurationMinutes]。
  final Object? totalTime;

  /// 逗号分隔的多值分类。装饰层不解析,匹配时才按逗号切。
  final String categoryIds;

  /// 预览模板:数据还没落库,复制/配置都会被后端拒。卡片上直说,别等用户点完才报错。
  final bool previewOnly;

  /// `VERIFIED` 才算已验证。**其余一律当未验证**(含字段没下发)——
  /// 快照注释:状态缺失时不得冒充已验证(`topic-template-shelf-contract`)。
  final String? templateStatus;

  final String? imgUrl;

  /// 副标题:没有就不占位。
  String get displaySubtitle => subtitle.trim();

  /// 「N 章 · N 个点 · X分钟」——照 `decorateTopic` 的拼接顺序,
  /// 缺哪段跳哪段(全缺时是空串,卡片不渲染这一行)。
  String get metaText {
    final List<String> parts = <String>[];
    if (chapterCount > 0) parts.add('$chapterCount 章');
    if (locationCount > 0) parts.add('$locationCount 个点');
    final String duration = formatDurationMinutes(totalTime);
    if (duration.isNotEmpty) parts.add(duration);
    return parts.join(' · ');
  }

  /// 状态标。`previewOnly` 的措辞与已验证分开 —— 两者都不是「正常可复制」。
  String get statusText => previewOnly
      ? '实验预览'
      : (templateStatus == 'VERIFIED' ? '' : '实验模板');

  /// 品类命中(照 `hitCategory`,index.js:395):逗号分隔多值里逐段比。
  /// ★ 后端按 `FIND_IN_SET(categoryIds)` 过滤,前端置顶排序照抄同一个字段 ——
  ///   不要拿别的列判,两者并不同步。
  bool matchesCategory(int? categoryId) {
    if (categoryId == null) return true;
    if (categoryIds.trim().isEmpty) return false;
    return categoryIds
        .split(',')
        .any((String token) => token.trim() == '$categoryId');
  }
}

/// 时长归一化,对齐小程序 `utils/template-display.js`。
///
/// 后端历史数据同时存在 `30` 与 `"30分钟"`,展示层只补一次单位;
/// 补第二次会渲染成「30分钟分钟」。
String formatDurationMinutes(Object? value) {
  if (value == null) return '';
  final String text = value.toString().trim();
  if (text.isEmpty) return '';
  final String stripped = text.replaceFirst(
    RegExp(r'\s*(分钟|min(?:ute)?s?)$', caseSensitive: false),
    '',
  );
  return stripped.isEmpty ? '' : '$stripped分钟';
}
