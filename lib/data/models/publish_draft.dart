/// 专业发布编辑器(对齐小程序 pages/publish/fabu)的草稿模型。
///
/// ★ 字段口径与后端 `TopicCreateDTO` / `ChapterDTO` / `NodeDTO` /
///   `ActivityTicketRequest` / `ChapterBlockDTO` 逐一对齐;提交时的字段名映射
///   见 [PublishDraft.toApiMap] 与 [PublishChapter.toPayloadChapter]。
///
/// ⚠️ 「没有值」与「值是 0/空」的分界写在类型上:可空的都保持 nullable,
///   只有后端语义上真有默认值的字段(如 required=1)才给默认。
library;

import 'category.dart';

/// 产品类型:1 城市定向(经典定向) 2 自由探索。对应后端 ProductType。
const int kProductCity = 1;
const int kProductFreeExplore = 2;

/// 主题草稿 —— 编辑器内存中的唯一真源,直接可变,提交时转 API map。
class PublishDraft {
  String name = '';
  String subtitle = '';
  String description = '';

  /// 主题开始/结束日期。用户展示用;提交时经 normalizeDateTime 归一化。
  String startDate = '';
  String endDate = '';

  /// 招商截止日期(自由探索后端硬必填:缺了 create/update 直接抛异常)。
  String? recruitDeadline;

  /// 竖版封面(单张)与横图(逗号分隔多张)。
  String imgUrl = '';
  String imgArr = '';

  /// 已选类别 ID / 名称(提交时 categoryIds 用逗号 join)。
  List<int> categoryIds = <int>[];
  List<String> categoryNames = <String>[];

  /// 产品类型,见 [kProductCity] / [kProductFreeExplore]。
  int productType = kProductCity;

  List<PublishChapter> chapters = <PublishChapter>[];
  List<PublishTicket> tickets = <PublishTicket>[];

  /// M2 自玩票(仅城市定向生效)。
  bool selfPlay = false;
  String selfPlayPrice = '';
  String selfPlayQuota = '';

  String finishMedalName = '';
  String finishMedalImg = '';
  int completeRewardCouponId = 0;

  /// 发布到创意广场。真源 `pages/publish/fabu/index.js:128` 新建编辑器
  /// data 默认 **true**(默认同步广场);编辑载入时才压成 false
  /// (见 publish_pro_page._loadEditDetail,「编辑不重复往创意广场发帖」)。
  bool publishToCreative = true;

  /// 归属俱乐部;经典定向且有多个俱乐部时必选。
  int? clubId;
  String clubName = '';

  /// 合作者 ID 列表(含 owner 自己)。
  List<int> collaboratorIds = <int>[];

  /// 开放给商家市场(商家池)。仅俱乐部主理人可见可开。
  bool openMerchantPool = false;

  /// 主题音频(编辑器不采集,保留字段口径)。
  String audioUrl = '';
  int audioDuration = 0;

  /// 编辑器模式标记:pro / ai_simple。
  String publishMode = 'pro';

  /// 服务端版本戳(topic.updateTime)。本地草稿恢复时用它判
  /// 「服务端草稿已更新」冲突 —— 真源 fabu baseRevision 同款。
  String baseRevision = '';

  PublishDraft copy() {
    final d = PublishDraft()
      ..name = name
      ..subtitle = subtitle
      ..description = description
      ..startDate = startDate
      ..endDate = endDate
      ..recruitDeadline = recruitDeadline
      ..imgUrl = imgUrl
      ..imgArr = imgArr
      ..categoryIds = List<int>.of(categoryIds)
      ..categoryNames = List<String>.of(categoryNames)
      ..productType = productType
      ..chapters = chapters.map((c) => c.copy()).toList()
      ..tickets = tickets.map((t) => t.copy()).toList()
      ..selfPlay = selfPlay
      ..selfPlayPrice = selfPlayPrice
      ..selfPlayQuota = selfPlayQuota
      ..finishMedalName = finishMedalName
      ..finishMedalImg = finishMedalImg
      ..completeRewardCouponId = completeRewardCouponId
      ..publishToCreative = publishToCreative
      ..clubId = clubId
      ..clubName = clubName
      ..collaboratorIds = List<int>.of(collaboratorIds)
      ..openMerchantPool = openMerchantPool
      ..audioUrl = audioUrl
      ..audioDuration = audioDuration
      ..publishMode = publishMode
      ..baseRevision = baseRevision;
    return d;
  }

  /// 本地草稿信封用的完整编辑器态序列化 —— **不是提交载荷**(提交载荷见
  /// buildTopicPayload)。与 toJson 的区别:这里无损,丢了恢复回来就是缺内容。
  Map<String, dynamic> toDraftState() => <String, dynamic>{
    'name': name,
    'subtitle': subtitle,
    'description': description,
    'startDate': startDate,
    'endDate': endDate,
    'recruitDeadline': recruitDeadline,
    'imgUrl': imgUrl,
    'imgArr': imgArr,
    'categoryIds': categoryIds,
    'categoryNames': categoryNames,
    'productType': productType,
    'chapters': chapters.map(_chapterState).toList(),
    'tickets': tickets.map(_ticketState).toList(),
    'selfPlay': selfPlay,
    'selfPlayPrice': selfPlayPrice,
    'selfPlayQuota': selfPlayQuota,
    'finishMedalName': finishMedalName,
    'finishMedalImg': finishMedalImg,
    'completeRewardCouponId': completeRewardCouponId,
    'publishToCreative': publishToCreative,
    'clubId': clubId,
    'clubName': clubName,
    'collaboratorIds': collaboratorIds,
    'openMerchantPool': openMerchantPool,
    'audioUrl': audioUrl,
    'audioDuration': audioDuration,
    'publishMode': publishMode,
  };

  static Map<String, dynamic> _chapterState(PublishChapter c) =>
      <String, dynamic>{
        'name': c.name,
        'description': c.description,
        'imgArr': c.imgArr,
        'nodes': c.nodes.map(_nodeState).toList(),
        'blocks': c.blocks
            ?.map(
              (b) => <String, dynamic>{
                'key': b.key,
                'type': b.type,
                'content': b.content,
                'nodeKey': b.nodeKey,
                'url': b.url,
              },
            )
            .toList(),
        'schemaVersion': c.schemaVersion,
        'required': c.required,
        'audioUrl': c.audioUrl,
        'atmospherePreset': c.atmospherePreset,
        'category': c.category,
        'categoryId': c.categoryId,
        'recruitEnabled': c.recruitEnabled,
        'perkMinValue': c.perkMinValue,
        'maxMerchant': c.maxMerchant,
        'termsMode': c.termsMode,
        'allowedValidationMethods': c.allowedValidationMethods,
        'maxNodeXp': c.maxNodeXp,
        'calculatedDistance': c.calculatedDistance,
        'localId': c.localId,
      };

  static Map<String, dynamic> _nodeState(PublishNode n) => <String, dynamic>{
    'name': n.name,
    'description': n.description,
    'address': n.address,
    'longitude': n.longitude,
    'latitude': n.latitude,
    'imgUrl': n.imgUrl,
    'nodeTime': n.nodeTime,
    'templateId': n.templateId,
    'templateInfo': n.templateInfo,
    'templateName': n.templateName,
    'businessTime': n.businessTime,
    'sortID': n.sortID,
    'hookText': n.hookText,
    'cardHookLong': n.cardHookLong,
    'fragmentText': n.fragmentText,
    'localId': n.localId,
  };

  static Map<String, dynamic> _ticketState(PublishTicket t) =>
      <String, dynamic>{
        'name': t.name,
        'price': t.price,
        'totalStock': t.totalStock,
        'mode': t.mode,
        'meetingPoint': t.meetingPoint,
        'meetingPointAddress': t.meetingPointAddress,
        'meetingPointLongitude': t.meetingPointLongitude,
        'meetingPointLatitude': t.meetingPointLatitude,
        'teamSize': t.teamSize,
        'startTime': t.startTime,
        'endTime': t.endTime,
        'saleStartTime': t.saleStartTime,
        'saleEndTime': t.saleEndTime,
        'description': t.description,
        'refundSupported': t.refundSupported,
        'syncWithTheme': t.syncWithTheme,
      };

  /// [toDraftState] 的逆向。脏条目按字段默认值收敛,不整包作废。
  static PublishDraft fromDraftState(Map<String, dynamic> m) {
    List<int> ints(Object? v) => (v as List<dynamic>? ?? <dynamic>[])
        .whereType<num>()
        .map((num n) => n.toInt())
        .toList();
    List<String> strs(Object? v) =>
        (v as List<dynamic>? ?? <dynamic>[]).map((Object? e) => '$e').toList();
    final d = PublishDraft()
      ..name = '${m['name'] ?? ''}'
      ..subtitle = '${m['subtitle'] ?? ''}'
      ..description = '${m['description'] ?? ''}'
      ..startDate = '${m['startDate'] ?? ''}'
      ..endDate = '${m['endDate'] ?? ''}'
      ..recruitDeadline = m['recruitDeadline'] as String?
      ..imgUrl = '${m['imgUrl'] ?? ''}'
      ..imgArr = '${m['imgArr'] ?? ''}'
      ..categoryIds = ints(m['categoryIds'])
      ..categoryNames = strs(m['categoryNames'])
      ..productType = (m['productType'] as num?)?.toInt() ?? kProductCity
      ..selfPlay = m['selfPlay'] == true
      ..selfPlayPrice = '${m['selfPlayPrice'] ?? ''}'
      ..selfPlayQuota = '${m['selfPlayQuota'] ?? ''}'
      ..finishMedalName = '${m['finishMedalName'] ?? ''}'
      ..finishMedalImg = '${m['finishMedalImg'] ?? ''}'
      ..completeRewardCouponId =
          (m['completeRewardCouponId'] as num?)?.toInt() ?? 0
      ..publishToCreative = m['publishToCreative'] == true
      ..clubId = (m['clubId'] as num?)?.toInt()
      ..clubName = '${m['clubName'] ?? ''}'
      ..collaboratorIds = ints(m['collaboratorIds'])
      ..openMerchantPool = m['openMerchantPool'] == true
      ..audioUrl = '${m['audioUrl'] ?? ''}'
      ..audioDuration = (m['audioDuration'] as num?)?.toInt() ?? 0
      ..publishMode = '${m['publishMode'] ?? 'pro'}';
    for (final Object? raw
        in (m['chapters'] as List<dynamic>? ?? <dynamic>[])) {
      if (raw is! Map) continue;
      final c = Map<String, dynamic>.from(raw);
      final chapter = PublishChapter()
        ..name = '${c['name'] ?? ''}'
        ..description = '${c['description'] ?? ''}'
        ..imgArr = '${c['imgArr'] ?? ''}'
        ..schemaVersion = (c['schemaVersion'] as num?)?.toInt() ?? 1
        ..required = (c['required'] as num?)?.toInt() ?? 1
        ..audioUrl = '${c['audioUrl'] ?? ''}'
        ..atmospherePreset = normalizeAtmosphere(
          c['atmospherePreset']?.toString(),
        )
        ..category = '${c['category'] ?? ''}'
        ..categoryId = (c['categoryId'] as num?)?.toInt()
        ..recruitEnabled = (c['recruitEnabled'] as num?)?.toInt() ?? 0
        ..perkMinValue = c['perkMinValue'] as String?
        ..maxMerchant = (c['maxMerchant'] as num?)?.toInt()
        ..termsMode = '${c['termsMode'] ?? 'PERK'}'
        ..allowedValidationMethods = '${c['allowedValidationMethods'] ?? ''}'
        ..maxNodeXp = (c['maxNodeXp'] as num?)?.toInt()
        ..calculatedDistance = c['calculatedDistance'] as num?
        ..localId = '${c['localId'] ?? ''}';
      for (final Object? nRaw
          in (c['nodes'] as List<dynamic>? ?? <dynamic>[])) {
        if (nRaw is! Map) continue;
        final n = Map<String, dynamic>.from(nRaw);
        chapter.nodes.add(
          PublishNode()
            ..name = '${n['name'] ?? ''}'
            ..description = '${n['description'] ?? ''}'
            ..address = '${n['address'] ?? ''}'
            ..longitude = '${n['longitude'] ?? ''}'
            ..latitude = '${n['latitude'] ?? ''}'
            ..imgUrl = '${n['imgUrl'] ?? ''}'
            ..nodeTime = (n['nodeTime'] as num?)?.toInt() ?? 30
            ..templateId = (n['templateId'] as num?)?.toInt()
            ..templateInfo = n['templateInfo'] is Map
                ? Map<String, dynamic>.from(n['templateInfo'] as Map)
                : <String, dynamic>{}
            ..templateName = '${n['templateName'] ?? ''}'
            ..businessTime = '${n['businessTime'] ?? ''}'
            ..sortID = (n['sortID'] as num?)?.toInt() ?? 1
            ..hookText = '${n['hookText'] ?? ''}'
            ..cardHookLong = '${n['cardHookLong'] ?? ''}'
            ..fragmentText = '${n['fragmentText'] ?? ''}'
            ..localId = '${n['localId'] ?? ''}',
        );
      }
      final blocks = <StoryBlock>[];
      for (final Object? bRaw
          in (c['blocks'] as List<dynamic>? ?? <dynamic>[])) {
        if (bRaw is! Map) continue;
        final b = Map<String, dynamic>.from(bRaw);
        final key = '${b['key'] ?? ''}';
        blocks.add(switch ('${b['type'] ?? 'text'}') {
          'node' => StoryBlock.node(key, '${b['nodeKey'] ?? ''}'),
          'image' => StoryBlock.image(key, '${b['url'] ?? ''}'),
          'audio' => StoryBlock.audio(key, '${b['url'] ?? ''}'),
          _ => StoryBlock.text(key, '${b['content'] ?? ''}'),
        });
      }
      chapter.blocks = (c['blocks'] as List<dynamic>?) == null
          ? null
          : (blocks.isEmpty ? <StoryBlock>[] : blocks);
      d.chapters.add(chapter);
    }
    for (final Object? tRaw
        in (m['tickets'] as List<dynamic>? ?? <dynamic>[])) {
      if (tRaw is! Map) continue;
      final t = Map<String, dynamic>.from(tRaw);
      d.tickets.add(
        PublishTicket()
          ..name = '${t['name'] ?? ''}'
          ..price = (t['price'] as num?)?.toDouble()
          ..totalStock = (t['totalStock'] as num?)?.toInt() ?? 100
          ..mode = (t['mode'] as num?)?.toInt() ?? kProductCity
          ..meetingPoint = '${t['meetingPoint'] ?? ''}'
          ..meetingPointAddress = '${t['meetingPointAddress'] ?? ''}'
          ..meetingPointLongitude = '${t['meetingPointLongitude'] ?? ''}'
          ..meetingPointLatitude = '${t['meetingPointLatitude'] ?? ''}'
          ..teamSize = (t['teamSize'] as num?)?.toInt() ?? 0
          ..startTime = '${t['startTime'] ?? ''}'
          ..endTime = '${t['endTime'] ?? ''}'
          ..saleStartTime = '${t['saleStartTime'] ?? ''}'
          ..saleEndTime = '${t['saleEndTime'] ?? ''}'
          ..description = '${t['description'] ?? ''}'
          ..refundSupported = t['refundSupported'] != false
          ..syncWithTheme = t['syncWithTheme'] == true,
      );
    }
    return d;
  }
}

/// 故事流块(城市定向)。key 是本地标识；提交时文字上送
/// `{type, content}`，节点上送 `{type, nodeIndex}`，媒体上送
/// `{type, url}`。
class StoryBlock {
  StoryBlock.text(this.key, this.content)
    : type = 'text',
      nodeKey = '',
      url = '';

  StoryBlock.node(this.key, this.nodeKey)
    : type = 'node',
      content = '',
      url = '';

  StoryBlock.image(this.key, this.url)
    : type = 'image',
      content = '',
      nodeKey = '';

  StoryBlock.audio(this.key, this.url)
    : type = 'audio',
      content = '',
      nodeKey = '';

  final String key;
  final String type;
  String content;
  final String nodeKey;
  final String url;

  StoryBlock copy() => switch (type) {
    'node' => StoryBlock.node(key, nodeKey),
    'image' => StoryBlock.image(key, url),
    'audio' => StoryBlock.audio(key, url),
    _ => StoryBlock.text(key, content),
  };
}

/// 章节。
/// 章节配色五档(2026-09-06 用户拍板:黑/蓝/红/黄/白,**纯色无渐变**)。
/// ⚠️ 这张表与小程序 `utils/chapter-atmosphere.js`、后端 `ChapterAtmospherePreset`
///   是**同一份口径**,改一处必须改三处 —— 不一致会让同一条数据在两端显示成两个颜色。
/// 色值与文案跟小程序 `utils/chapter-atmosphere.js` 同源,改一边就要改另一边,
/// 否则同一条章节在两端显示成两个颜色。白档是唯一浅色,卡内文字要翻黑。
const List<({String value, String label, String note, int color})>
kChapterAtmospheres = <({String value, String label, String note, int color})>[
  (value: 'DEFAULT', label: '黑', note: '沉浸深色', color: 0xFF0A0A0A),
  (value: 'BLUE', label: '蓝', note: '靛蓝夜路', color: 0xFF14294F),
  (value: 'RED', label: '红', note: '警示暗红', color: 0xFF4E1C24),
  (value: 'YELLOW', label: '黄', note: '旧纸暖黄', color: 0xFF4E4114),
  (value: 'WHITE', label: '白', note: '明亮浅色', color: 0xFFF5F6F8),
];

/// 存量别名 → 新档。库里还存着 NIGHT/ARCHIVE/MOSS/NEON,读出来要能显示;
/// 再保存时会被写成新的规范值。苔野没有对应色,落回默认黑。
const Map<String, String> kChapterAtmosphereAliases = <String, String>{
  'NIGHT': 'BLUE',
  'ARCHIVE': 'YELLOW',
  'NEON': 'RED',
  'MOSS': 'DEFAULT',
};

/// 读侧归一:未知值一律落回 DEFAULT,不把脏值原样透传到界面。
String normalizeAtmosphere(String? raw) {
  final String v = (raw ?? '').trim().toUpperCase();
  if (kChapterAtmospheres.any((a) => a.value == v)) return v;
  return kChapterAtmosphereAliases[v] ?? 'DEFAULT';
}

class PublishChapter {
  String name = '';
  String description = '';

  /// 章节图(逗号分隔)。编辑器暂不采集,保留口径。
  String imgArr = '';

  List<PublishNode> nodes = <PublishNode>[];

  /// 城市定向的故事流块;自由探索不使用。打开故事流编辑器时才物化。
  List<StoryBlock>? blocks;

  int schemaVersion = 1;
  int required = 1;

  /// 本章背景旁白(进本章自动播放,一章最多一段)。后端列 cms_topic_chapter.audio_url,
  /// 2026-09-05 的 migration_x10 加的;小程序侧同期上线,App 这边补齐。
  String audioUrl = '';

  /// 章节配色。2026-09-06 用户拍板换成黑/蓝/红/黄/白五档**纯色**,取值域见
  /// [kChapterAtmospheres];旧值(NIGHT/ARCHIVE/MOSS/NEON)由后端 requireValid 收敛,
  /// 读侧也在 normalizeAtmosphere 里做同样的别名映射,两边必须一致。
  String atmospherePreset = 'DEFAULT';

  /// 商家承接配置。开关/品类/条款/门槛/名额在章节弹窗里配(只对俱乐部主理人露出)。
  ///
  /// ⚠️ 后端更新章节是「整章删掉重建 + copyProperties」,载荷少一个字段那一列就写成 NULL。
  ///   所以**读回来的都必须原样送回去**,哪怕这一端没有界面去改它 —— 见
  ///   `publish_draft_logic._chapterCarryOver`。
  String category = '';
  int? categoryId;
  int recruitEnabled = 0;
  String? perkMinValue;
  int? maxMerchant;
  String termsMode = 'PERK';

  /// 玩法边界:允许的核验方式,1-5 的逗号串;空 = 不限。
  /// App 没有编辑界面(在小程序里配),但**必须原样往返** —— 它是承接合同的一部分,
  /// 被清空后商家侧 assertWithinTerms 拿它比对会恒不命中,商家怎么配都被拒。
  String allowedValidationMethods = '';

  /// 单节点探索值上限。同样只读不写,不带上去就被清成 NULL。
  int? maxNodeXp;

  /// 章节里程(后端算好的展示值)。App 不重算,原样带回去。
  num? calculatedDistance;

  /// 本地标识:故事流块的 nodeKey 引用它,不随数组顺序变。
  String localId = '';

  PublishChapter copy() => PublishChapter()
    ..name = name
    ..description = description
    ..imgArr = imgArr
    ..nodes = nodes.map((n) => n.copy()).toList()
    ..blocks = blocks?.map((b) => b.copy()).toList()
    ..schemaVersion = schemaVersion
    ..required = required
    ..audioUrl = audioUrl
    ..atmospherePreset = atmospherePreset
    ..category = category
    ..categoryId = categoryId
    ..recruitEnabled = recruitEnabled
    ..perkMinValue = perkMinValue
    ..maxMerchant = maxMerchant
    ..termsMode = termsMode
    ..allowedValidationMethods = allowedValidationMethods
    ..maxNodeXp = maxNodeXp
    ..calculatedDistance = calculatedDistance
    ..localId = localId;

  /// 完整状态序列化(白名单锁字段指纹/测试用),不是提交载荷。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'description': description,
    'imgArr': imgArr,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'blocks': blocks
        ?.map(
          (b) => <String, dynamic>{
            'key': b.key,
            'type': b.type,
            'content': b.content,
            'nodeKey': b.nodeKey,
            if (b.url.isNotEmpty) 'url': b.url,
          },
        )
        .toList(),
    'schemaVersion': schemaVersion,
    'required': required,
    'audioUrl': audioUrl,
    'atmospherePreset': atmospherePreset,
    'category': category,
    'categoryId': categoryId,
    'recruitEnabled': recruitEnabled,
    'perkMinValue': perkMinValue,
    'maxMerchant': maxMerchant,
    'termsMode': termsMode,
    'allowedValidationMethods': allowedValidationMethods,
    'maxNodeXp': maxNodeXp,
    'calculatedDistance': calculatedDistance,
    'localId': localId,
  };
}

/// 节点。
class PublishNode {
  String name = '';
  String description = '';
  String address = '';
  String longitude = '';
  String latitude = '';

  /// 逗号分隔多图串,最多 9 张。
  String imgUrl = '';

  int nodeTime = 30;
  int? templateId;
  Map<String, dynamic> templateInfo = <String, dynamic>{};
  String templateName = '';
  String businessTime = '';
  int sortID = 1;
  String hookText = '';
  String cardHookLong = '';
  String fragmentText = '';

  String localId = '';

  List<String> get imgList => imgUrl
      .split(',')
      .where((s) => s.trim().isNotEmpty)
      .toList(growable: false);

  PublishNode copy() => PublishNode()
    ..name = name
    ..description = description
    ..address = address
    ..longitude = longitude
    ..latitude = latitude
    ..imgUrl = imgUrl
    ..nodeTime = nodeTime
    ..templateId = templateId
    ..templateInfo = Map<String, dynamic>.of(templateInfo)
    ..templateName = templateName
    ..businessTime = businessTime
    ..sortID = sortID
    ..hookText = hookText
    ..cardHookLong = cardHookLong
    ..fragmentText = fragmentText
    ..localId = localId;

  /// 完整状态序列化(白名单锁字段指纹/测试用),不是提交载荷。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'description': description,
    'address': address,
    'longitude': longitude,
    'latitude': latitude,
    'imgUrl': imgUrl,
    'nodeTime': nodeTime,
    'templateId': templateId,
    'templateName': templateName,
    'sortID': sortID,
    'localId': localId,
  };
}

/// 票种。字段与后端 ActivityTicketRequest 对齐;
/// saleStartTime/saleEndTime 为编辑器内售票窗口(小程序同款,后端忽略)。
class PublishTicket {
  String name = '';

  /// 票价。★ null = 还没填(校验拦「请填写票价」),0 = 免费票 —— 两种含义不能合并。
  double? price = 0;
  int totalStock = 100;
  int mode = kProductCity;
  String meetingPoint = '';
  String meetingPointAddress = '';
  String meetingPointLongitude = '';
  String meetingPointLatitude = '';
  int teamSize = 0;
  String startTime = '';
  String endTime = '';
  String saleStartTime = '';
  String saleEndTime = '';
  String description = '';
  bool refundSupported = true;
  bool syncWithTheme = false;

  PublishTicket copy() => PublishTicket()
    ..name = name
    ..price = price
    ..totalStock = totalStock
    ..mode = mode
    ..meetingPoint = meetingPoint
    ..meetingPointAddress = meetingPointAddress
    ..meetingPointLongitude = meetingPointLongitude
    ..meetingPointLatitude = meetingPointLatitude
    ..teamSize = teamSize
    ..startTime = startTime
    ..endTime = endTime
    ..saleStartTime = saleStartTime
    ..saleEndTime = saleEndTime
    ..description = description
    ..refundSupported = refundSupported
    ..syncWithTheme = syncWithTheme;

  /// 完整状态序列化(白名单锁字段指纹/测试用),不是提交载荷。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'price': price,
    'totalStock': totalStock,
    'mode': mode,
    'meetingPoint': meetingPoint,
    'teamSize': teamSize,
    'startTime': startTime,
    'endTime': endTime,
    'saleStartTime': saleStartTime,
    'saleEndTime': saleEndTime,
    'description': description,
    'refundSupported': refundSupported,
    'syncWithTheme': syncWithTheme,
  };
}

/// 玩法模板(节点配置模板用,来自 /api/template/homeData 或 /api/template/my-list)。
class PublishTemplate {
  PublishTemplate({
    required this.id,
    required this.title,
    required this.imgUrl,
    required this.players,
    required this.duration,
    required this.raw,
  });

  final int id;
  final String title;
  final String imgUrl;

  /// 展示用人数(可能是 '--' 这类占位,不承诺数值)。
  final String players;

  /// 时长(分钟,0 表示无值/不限 —— 区分「没有时长」与「时长 0 分钟」)。
  final int duration;
  final Map<String, dynamic> raw;

  /// 玩法描述/规则(task 真源:ruleInstructions / questionName / description)。
  String get taskText {
    final t = raw;
    final v = t['rule_instructions'] ?? t['question_name'] ?? t['description'];
    return (v ?? '').toString();
  }

  String get hint1 => (raw['hint1'] ?? '').toString();
  String get hint2 => (raw['hint2'] ?? '').toString();

  factory PublishTemplate.fromJson(Map<String, dynamic> json) {
    final d = json['duration'];
    return PublishTemplate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      imgUrl: (json['imgUrl'] ?? '').toString(),
      players: json['players'] == null ? '--' : json['players'].toString(),
      duration: d == null ? 0 : (d as num).toInt(),
      raw: json,
    );
  }
}

/// 模板广场首屏数据。每一段都保留 `/api/template/homeData`
/// 的原始列表语义，不合并、不去重后再冒充多个区块。
class PublishTemplateHomeData {
  const PublishTemplateHomeData({
    required this.total,
    required this.categories,
    required this.banner,
    required this.latest,
    required this.recommended,
    required this.mustPlay,
    required this.hot,
  });

  final int total;
  final List<Category> categories;
  final List<PublishTemplate> banner;
  final List<PublishTemplate> latest;
  final List<PublishTemplate> recommended;
  final List<PublishTemplate> mustPlay;
  final List<PublishTemplate> hot;

  factory PublishTemplateHomeData.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);

    List<PublishTemplate> templates(String key) =>
        rows(key).map(PublishTemplate.fromJson).toList(growable: false);

    return PublishTemplateHomeData(
      total: (json['total'] as num?)?.toInt() ?? 0,
      categories: rows(
        'categoryList',
      ).map(Category.fromJson).toList(growable: false),
      banner: templates('bannerList'),
      latest: templates('latestList'),
      recommended: templates('recommendList'),
      mustPlay: templates('mustPlayList'),
      hot: templates('hotList'),
    );
  }

  /// 只供旧的节点编辑器选择器使用；广场 UI 不得用它代替分段。
  List<PublishTemplate> get merged {
    final Set<int> seen = <int>{};
    return <PublishTemplate>[
          ...banner,
          ...recommended,
          ...mustPlay,
          ...hot,
          ...latest,
        ]
        .where((PublishTemplate item) => seen.add(item.id))
        .toList(growable: false);
  }
}

/// 编辑既有主题时的锁定档:WHITELIST 只许改文案与图。
enum PublishEditScope { full, whitelist }
