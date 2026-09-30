import 'validation_method_labels.dart';

/// 玩法模板。对齐后端 `CmsMemberTemplate` 与 `/api/template/{list,info,homeData,myinfo}`。
class PlayTemplate {
  const PlayTemplate({
    required this.id,
    required this.title,
    this.description,
    this.imgUrl,
    this.players,
    this.duration,
    this.difficulty,
    this.usageLocation,
    this.requiredMaterials,
    this.categoryId,
    this.ruleInstructions,
    this.storyText,
    this.storyImg,
    this.validationMethod,
    this.questionName,
    this.publisher,
    this.status,
    this.publishStatus,
    this.useNum,
    this.packType = 0,
  });

  final int id;
  final String title;
  final String? description;
  final String? imgUrl;

  /// 建议人数,后端是字符串(可能是 "2-6" 这种区间)。
  final String? players;

  /// 时长(分钟)。
  final int? duration;

  final String? difficulty;
  final String? usageLocation;
  final String? requiredMaterials;
  final int? categoryId;

  // ── 详情页才用得到的几块。★ 后端 `CmsMemberTemplate` 一直有这些字段,
  //    App 的模型此前只解析了列表要用的那几个,于是详情页比小程序薄一半:
  //    小程序那页有 13 块,App 只有 3 块。

  /// 规则说明。与 [description](简介)不是一回事 ——
  /// 简介说「这是什么」,规则说「怎么玩」。
  final String? ruleInstructions;

  /// 创作者说。★ 拿不到时退到 [publisher](谁做的)——
  /// 小程序就是 `info.storyText || info.publisher`,不是留空。
  final String? storyText;
  final String? storyImg;

  /// 核验方式(后端 validationMethod)。
  final int? validationMethod;

  /// 问答题面 —— 核验方式是问答时才有内容。
  final String? questionName;

  /// 发布者。
  final String? publisher;
  final int? status;
  final int? publishStatus;
  final int? useNum;

  /// 模板形态:0 单节点玩法 / 1 剧情包 / 2 店铺 IP 包。
  ///
  /// ★ 默认 0 与后端 `PublicTemplateListItemVO` 的服务端归一同口径 ——
  /// 老数据 pack_type 为 null 时后端就回 0,这里的默认值只是 JSON 缺字段时的兜底。
  final int packType;

  /// 形态标签文案。★ **认不出的形态不编一个名字**,返回 null 让 UI 不显示标签 ——
  /// 编一个「其它」出来,用户会以为那是一种真实存在的分类。
  String? get packTypeLabel => switch (packType) {
    0 => '单节点玩法',
    1 => '剧情包',
    2 => '店铺 IP 包',
    _ => null,
  };

  String get managementStatusText => switch (status) {
    1 => '已发布',
    2 => '审核中',
    _ => '未发布',
  };

  /// 「创作者说」显示什么。★ storyText 优先,退到 publisher ——
  /// 与小程序 `info.storyText || info.publisher` 同一条。
  /// 两个都没有就**不显示这一块**,不留一个空标题。
  String? get creatorNote {
    final String t = (storyText ?? '').trim();
    if (t.isNotEmpty) return t;
    final String p = (publisher ?? '').trim();
    return p.isEmpty ? null : p;
  }

  /// 核验方式文案。★ 认不出的码说「其他」而不是编 —— 后端加了新方式时,
  /// 编出来的名字会一直错下去而没人发现。空值仍返回 null(不显示这一块)。
  String? get validationText => validationMethodLabel(validationMethod);

  /// 时长文案。★ 后端没给就**不显示这一项**,不写「0 分钟」——
  ///   那会让人以为这个玩法瞬间就能玩完。
  String? get durationText {
    final d = duration;
    if (d == null || d <= 0) return null;
    if (d < 60) return '$d 分钟';
    final h = d ~/ 60;
    final m = d % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }

  /// 难度文案。后端存的是自由文本,原样透出;为空则不显示。
  String? get difficultyText {
    final v = difficulty?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  /// 人数文案。
  String? get playersText {
    final v = players?.trim() ?? '';
    return v.isEmpty ? null : '$v 人';
  }

  /// 列表卡片下方的一行元信息。★ 各段都可能为空 ——
  ///   用 where 过滤后再 join,否则会拼出「· · 」这种。
  String get metaLine => <String?>[
    playersText,
    durationText,
    difficultyText,
  ].where((String? s) => s != null && s.isNotEmpty).join(' · ');

  factory PlayTemplate.fromJson(Map<String, dynamic> json) {
    return PlayTemplate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: ((json['title'] as String?) ?? '').trim().isEmpty
          ? '未命名玩法'
          : (json['title'] as String).trim(),
      description: json['description'] as String?,
      imgUrl: json['imgUrl'] as String?,
      players: json['players']?.toString(),
      duration: (json['duration'] as num?)?.toInt(),
      difficulty: json['difficulty'] as String?,
      usageLocation: json['usageLocation'] as String?,
      requiredMaterials: json['requiredMaterials'] as String?,
      categoryId: (json['categoryId'] as num?)?.toInt(),
      ruleInstructions: json['ruleInstructions'] as String?,
      storyText: json['storyText'] as String?,
      storyImg: json['storyImg'] as String?,
      validationMethod: (json['validationMethod'] as num?)?.toInt(),
      questionName: json['questionName'] as String?,
      publisher: json['publisher']?.toString(),
      status: (json['status'] as num?)?.toInt(),
      publishStatus: (json['publishStatus'] as num?)?.toInt(),
      useNum: (json['useNum'] as num?)?.toInt(),
      packType: (json['packType'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 模板不可用的原因。
///
/// ★ 后端 `ApiTemplateController.producInfo` 有**四种**拒绝理由,
///   它们对用户意味着完全不同的事,不能都渲染成「加载失败 + 重试」:
///   - 不存在 / 已删除 → 这个模板没有了,重试无用
///   - 审核中           → 还会回来,可以稍后再看
///   - 已下架           → 作者主动下架,重试无用
enum TemplateUnavailable { notFound, deleted, underReview, offline, unknown }

/// 从后端的错误文案判定原因。
TemplateUnavailable templateUnavailableFrom(String message) {
  if (message.contains('审核中')) return TemplateUnavailable.underReview;
  if (message.contains('已下架')) return TemplateUnavailable.offline;
  if (message.contains('已删除')) return TemplateUnavailable.deleted;
  if (message.contains('不存在')) return TemplateUnavailable.notFound;
  return TemplateUnavailable.unknown;
}

extension TemplateUnavailableX on TemplateUnavailable {
  String get title {
    switch (this) {
      case TemplateUnavailable.underReview:
        return '这个玩法正在审核';
      case TemplateUnavailable.offline:
        return '这个玩法已下架';
      case TemplateUnavailable.deleted:
      case TemplateUnavailable.notFound:
        return '找不到这个玩法';
      case TemplateUnavailable.unknown:
        return '玩法暂时打不开';
    }
  }

  String get hint {
    switch (this) {
      case TemplateUnavailable.underReview:
        return '审核通过后就能看到,过一会儿再来';
      case TemplateUnavailable.offline:
        return '作者已把它下架';
      case TemplateUnavailable.deleted:
      case TemplateUnavailable.notFound:
        return '它可能已被删除';
      case TemplateUnavailable.unknown:
        return '稍后再试';
    }
  }

  /// 给不给重试。★ 只有「审核中」和「未知」值得重试 ——
  ///   已删除/已下架重试一万次也不会回来,给按钮是骗人。
  bool get retryable =>
      this == TemplateUnavailable.underReview ||
      this == TemplateUnavailable.unknown;
}
