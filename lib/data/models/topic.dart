import 'package:chengyin_app/core/util/json_parse.dart';

/// 主题(= 路线)列表项。对齐后端 CmsTopic / `/api/topic/list`。
class Topic {
  Topic({
    required this.id,
    required this.name,
    this.picUrl,
    this.introduction,
    this.minAmount,
    this.startDate,
    this.addressName,
    this.isRecommend = 0,
    this.betaFlag = 0,
    this.isLike = 0,
    this.likeNum = 0,
  });

  final int id;
  final String name;
  final String? picUrl;
  final String? introduction;

  /// 最低票价(后端 `minAmout`,拼写如此)。null = 没拿到,不是 0。
  final double? minAmount;

  /// 开始时间。首页底部流「时间」行用它(小程序 index.js 的 formattedDateTime 同源)。
  final String? startDate;

  /// 地点(`addressName`)。null/空 = 没配。
  final String? addressName;
  final int isRecommend;
  /// Source home recommendation marker: exactly betaFlag == 1.
  final int betaFlag;
  final int isLike;
  final int likeNum;

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
    id: asInt(json['id']),
    name: (json['name'] ?? '') as String,
    // 后端 CmsTopic:imgUrl / description(非 picUrl/introduction)
    picUrl: (json['imgUrl'] ?? json['picUrl']) as String?,
    introduction:
        (json['description'] ?? json['subtitle'] ?? json['introduction'])
            as String?,
    minAmount: (json['minAmout'] as num?)?.toDouble(),
    startDate: (json['startDate'] ?? json['start_date'])?.toString(),
    addressName: json['addressName']?.toString(),
    isRecommend: asInt(json['isRecommend']),
    betaFlag: asInt(json['betaFlag']),
    isLike: asInt(json['isLike']),
    likeNum: asInt(json['likeNum']),
  );
}

/// 路线节点。对齐 TopicNodeVO。
class TopicNode {
  TopicNode({
    required this.id,
    required this.name,
    this.description,
    this.address,
    this.latitude,
    this.longitude,
    this.businessTime,
    this.images = const <String>[],
    this.template,
    this.merchants = const <TopicMerchant>[],
  });

  final int id;
  final String name;
  final String? description;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? businessTime;
  final List<String> images;
  final TopicTemplate? template;
  final List<TopicMerchant> merchants;

  factory TopicNode.fromJson(Map<String, dynamic> json) => TopicNode(
    id: asInt(json['id']),
    name: (json['name'] ?? json['nodeName'] ?? '') as String,
    description: json['description']?.toString(),
    address: json['address']?.toString(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    businessTime: json['businessTime']?.toString(),
    images: _splitImages(json['imgUrl']),
    template: json['cmsMemberTemplate'] is Map<String, dynamic>
        ? TopicTemplate.fromJson(
            json['cmsMemberTemplate'] as Map<String, dynamic>,
          )
        : null,
    merchants:
        (json['registrationMerchantList'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(TopicMerchant.fromJson)
            .toList(),
  );
}

List<String> _splitImages(Object? raw) => (raw ?? '')
    .toString()
    .split(RegExp('[,;]'))
    .map((String value) => value.trim())
    .where((String value) => value.isNotEmpty)
    .toList(growable: false);

class TopicTemplate {
  const TopicTemplate({
    required this.id,
    required this.title,
    this.imgUrl,
    this.players,
    this.duration,
    this.difficulty,
    this.validationMethod,
    this.validationMethodStr,
  });

  final int id;
  final String title;
  final String? imgUrl;
  final String? players;
  final int? duration;

  /// 难度标签(展示用文案,如「轻松」)。小程序 topic-story 的玩法卡 meta 用。
  final String? difficulty;

  /// 核验方式码(1 文字作答 / 3 选项问答 …)。★ 只有 1、3 两类存在「答案」。
  /// 传原值而不是 `Number(null)=0`:没有码时走 [validationMethodStr],
  /// 不能被读成「无需验证」(小程序 validationMethodLabel 的原注释)。
  final int? validationMethod;

  /// 没配码时后端给的字面量。
  final String? validationMethodStr;

  factory TopicTemplate.fromJson(Map<String, dynamic> json) => TopicTemplate(
    id: asInt(json['id']),
    title: (json['title'] ?? '').toString(),
    imgUrl: json['imgUrl']?.toString(),
    players: json['players']?.toString(),
    duration: json['duration'] is num
        ? (json['duration'] as num).toInt()
        : null,
    difficulty: json['difficulty']?.toString(),
    validationMethod: json['validationMethod'] == null
        ? null
        : asInt(json['validationMethod']),
    validationMethodStr: json['validationMethodStr']?.toString(),
  );
}

class TopicMerchant {
  const TopicMerchant({
    required this.memberId,
    required this.name,
    this.businessTime,
    this.picUrl,
  });

  final int memberId;
  final String name;
  final String? businessTime;
  final String? picUrl;

  factory TopicMerchant.fromJson(Map<String, dynamic> json) {
    final merchant = json['mmsMerchant'] is Map<String, dynamic>
        ? json['mmsMerchant'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return TopicMerchant(
      memberId: asInt(json['memberId']),
      name: (merchant['name'] ?? json['name'] ?? '').toString(),
      businessTime: (merchant['businessTime'] ?? json['businessTime'])
          ?.toString(),
      picUrl: _splitImages(json['picUrl']).firstOrNull,
    );
  }
}

/// 章节(含有序节点)。对齐 TopicChapterVO(`nodes` + `routeGeometry`)。
class TopicChapter {
  TopicChapter({
    required this.id,
    required this.title,
    required this.nodes,
    this.description,
    this.totalTime,
  });

  final int id;
  final String title;
  final List<TopicNode> nodes;
  final String? description;

  /// 本章预计时长(分钟)。小程序 `pages/club/topic-story` 用 `chapter.totalTime`
  /// 渲染「3h 20min · 5 站」;没下发就不画时长那一段(不兜 0)。
  final int? totalTime;

  factory TopicChapter.fromJson(Map<String, dynamic> json) {
    final rawNodes = (json['nodes'] as List<dynamic>?) ?? <dynamic>[];
    return TopicChapter(
      id: asInt(json['id']),
      title: (json['title'] ?? json['name'] ?? '') as String,
      description: json['description']?.toString(),
      totalTime: json['totalTime'] is num
          ? (json['totalTime'] as num).toInt()
          : int.tryParse('${json['totalTime'] ?? ''}'),
      nodes: rawNodes
          .map((dynamic e) => TopicNode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 路线详情。对齐 TopicInfoVO(主题 → `chaptersList` → `nodes`)。
class TopicDetail {
  TopicDetail({
    required this.id,
    required this.name,
    this.introduction,
    this.picUrl,
    this.lifecycle,
    this.selfPlay,
    this.selfPlayPrice,
    this.merchantCount,
    required this.chapters,
    this.isOwner = false,
    this.betaFlag = 0,
    this.merchantClosed = false,
    this.subtitle,
    this.images = const <String>[],
    this.categoryNames = const <String>[],
    this.initiatorName,
    this.initiatorAvatar,
    this.clubName,
    this.averageRating,
    this.totalTimeSeconds,
    this.startDate,
    this.endDate,
    this.totalMileage,
    this.audioUrl,
    this.audioDuration,
    this.locationCount = 0,
    this.templateCount = 0,
    this.productType = 0,
    this.perkSellableCapacity,
    this.tickets = const <TopicTicket>[],
    this.comments = const <TopicComment>[],
    this.storyLocked = false,
    this.totalChapterCount = 0,
    this.unlockedChapterCount,
    this.isSignUp = false,
  });

  final int id;
  final String name;
  final String? introduction;
  final String? picUrl;
  final String? subtitle;
  final List<String> images;
  final List<String> categoryNames;
  final String? initiatorName;
  final String? initiatorAvatar;
  final String? clubName;
  final double? averageRating;
  final int? totalTimeSeconds;
  final String? startDate;
  final String? endDate;
  final double? totalMileage;
  final String? audioUrl;
  final int? audioDuration;
  final int locationCount;
  final int templateCount;
  final int productType;
  final int? perkSellableCapacity;
  final List<TopicTicket> tickets;
  final List<TopicComment> comments;

  /// 招募生命周期。**空 = 普通主题,照常售票**;非空表示走招募流程:
  /// 1 招募中 / 2 定价中 —— 这两态**未到售票态,不可购买**(小程序 F2-3 售票门禁)。
  /// 后端 `TopicInfoVO:57`。
  final int? lifecycle;

  /// 是否开放「自玩通行证」(1 开放)。后端 `TopicInfoVO:48`。
  /// ⚠️ 判据是这个开关,**不是 selfPlayPrice 有没有值** —— 小程序
  /// `pages/topic/index/index.wxml:335` 用的就是 `info.selfPlay==1`。
  final int? selfPlay;

  /// 自玩通行证价格。后端 `TopicInfoVO:49`。
  final double? selfPlayPrice;

  final List<TopicChapter> chapters;

  /// 我是不是这个主题的**创建者**(后端 `isOwner = memberId == 我 ? 1 : 0`,
  /// ApiTopicController:996)。
  ///
  /// ⚠️ 后端下发的是 **0/1 的数字**,不是布尔 —— 用 `as bool?` 解析会抛。
  /// ★ 拿不到时按**不是**处理:移交主题会把原主题下架,
  ///   宁可让真创建者少一个入口(他还能从我的发布进),也不能让判不准的人看到它。
  final bool isOwner;

  /// 是否还在 Beta 试玩期(1 = 是)。快照 `pages/topic/index/index.wxml:74`:
  /// `betaFlag==1` 才挂「Beta 试玩」标识,作者本人才看得到转正入口。
  /// 缺失按 0(不是 Beta)处理。
  final int betaFlag;

  /// 发布者(承接商家)是否已打烊。后端 `TopicInfoVO.merchantClosed`
  /// (ApiTopicController「拍板 2026-09-16 #10」):闭店时购票入口先说清原因。
  final bool merchantClosed;

  /// 已承接这条路线的商家数(后端 `TopicInfoVO:105 registrationMerchantCount`)。
  ///
  /// ★★ 可空,**拿不到时不显示这一栏**,不兜 0 ——
  ///   「还没有商家承接」和「这个数没算出来」是两回事,
  ///   而对一条正在招商的路线来说,写死 0 会劝退本来想报名的商家。
  final int? merchantCount;

  /// 故事付费墙总开关。后端 `TopicInfoVO:101 storyLocked`
  /// (ApiTopicController:1361 `unlockedChapterCount < totalChapterCount`)。
  final bool storyLocked;

  /// 章节总数。后端 `TopicInfoVO:97`。
  final int totalChapterCount;

  /// 已解锁章节数。后端 `TopicInfoVO:99`;null = 没下发,
  /// 真源此时退化成按 chaptersList.length 计(index.js:1636-1641)。
  final int? unlockedChapterCount;

  /// 我是否已购/已报名(`TopicInfoVO:113 isSignUp`,ownerType=1 & 已支付回填)。
  /// ★ 已购态不能只信 URL 参数 is_join —— 从首页/搜索进来的已购用户
  ///   URL 上永远没有它(P0 2026-09-05 审核,index.js:1665-1668)。
  final bool isSignUp;

  /// 被锁住的章节数 = 总数 − 已解锁(没下发按已渲染章节数兜底),下限 0。
  int get lockedChapterCount {
    final unlocked = unlockedChapterCount ?? chapters.length;
    final locked = totalChapterCount - unlocked;
    return locked > 0 ? locked : 0;
  }

  /// 是否显示故事付费墙卡。真源 index.wxml:462
  /// `info.storyLocked && info.lockedChapterCount > 0`。
  bool get showStoryPaywall => storyLocked && lockedChapterCount > 0;

  List<TopicMerchant> get merchants => chapters
      .expand((TopicChapter chapter) => chapter.nodes)
      .expand((TopicNode node) => node.merchants)
      .toList(growable: false);

  String get totalHoursText {
    final seconds = totalTimeSeconds;
    if (seconds == null || seconds < 0) return '0';
    final hours = seconds / 3600;
    return hours == hours.roundToDouble()
        ? hours.toInt().toString()
        : hours.toStringAsFixed(1);
  }

  String get openPeriodText {
    String part(String? raw) {
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      return parsed == null ? '' : '${parsed.month}.${parsed.day}';
    }

    final start = part(startDate);
    final end = part(endDate);
    if (start.isEmpty) return end;
    if (end.isEmpty) return start;
    return '$start-$end';
  }

  String get totalTimeText {
    final seconds = totalTimeSeconds;
    if (seconds == null || seconds <= 0) return '时长待定';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
  }

  String get perkCapacityText {
    final capacity = perkSellableCapacity;
    if (capacity == null || capacity >= 2147483647) return '';
    return '本期可售 ${capacity < 0 ? 0 : capacity} 张';
  }

  factory TopicDetail.fromJson(Map<String, dynamic> json) {
    final rawChapters = (json['chaptersList'] as List<dynamic>?) ?? <dynamic>[];
    return TopicDetail(
      id: asInt(json['id']),
      name: (json['name'] ?? '') as String,
      // 后端发 0/1;将来若改布尔也接得住。缺失 = 判不准 = false。
      merchantCount: json['registrationMerchantCount'] is num
          ? (json['registrationMerchantCount'] as num).toInt()
          : null,
      betaFlag: asInt(json['betaFlag']),
      merchantClosed: json['merchantClosed'] == true,
      isOwner: switch (json['isOwner']) {
        final num n => n.toInt() == 1,
        final bool b => b,
        _ => false,
      },
      introduction:
          (json['description'] ?? json['subtitle'] ?? json['introduction'])
              as String?,
      subtitle: json['subtitle']?.toString(),
      picUrl: (json['imgUrl'] ?? json['picUrl']) as String?,
      images: _splitImages(json['imgArr']),
      categoryNames: (json['sysCategoryList'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((row) => (row['categoryName'] ?? '').toString())
          .where((name) => name.isNotEmpty)
          .toList(),
      initiatorName:
          (json['collaboratorsList'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .firstOrNull?['memberRealName']
              ?.toString(),
      initiatorAvatar:
          (json['collaboratorsList'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .firstOrNull?['memberAvatar']
              ?.toString(),
      clubName: json['clubName']?.toString(),
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      totalTimeSeconds: json['totalTime'] is num
          ? (json['totalTime'] as num).toInt()
          : null,
      startDate: (json['startDate'] ?? json['start_date'])?.toString(),
      endDate: json['endDate']?.toString(),
      totalMileage: (json['totalMileage'] as num?)?.toDouble(),
      audioUrl: json['audioUrl']?.toString(),
      audioDuration: json['audioDuration'] is num
          ? (json['audioDuration'] as num).toInt()
          : null,
      locationCount: asInt(json['locationCount']),
      templateCount: asInt(json['templateCount']),
      productType: asInt(json['productType']),
      perkSellableCapacity: json['perkSellableCapacity'] is num
          ? (json['perkSellableCapacity'] as num).toInt()
          : null,
      tickets: (json['omsTicketList'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TopicTicket.fromJson)
          .toList(),
      comments: (json['commentList'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TopicComment.fromJson)
          .toList(),
      lifecycle: (json['lifecycle'] as num?)?.toInt(),
      selfPlay: (json['selfPlay'] as num?)?.toInt(),
      selfPlayPrice: (json['selfPlayPrice'] as num?)?.toDouble(),
      storyLocked: json['storyLocked'] == true || json['storyLocked'] == 1,
      totalChapterCount: asInt(json['totalChapterCount']),
      unlockedChapterCount: json['unlockedChapterCount'] is num
          ? (json['unlockedChapterCount'] as num).toInt()
          : null,
      isSignUp: json['isSignUp'] == 1 || json['isSignUp'] == true,
      chapters: rawChapters
          .map((dynamic e) => TopicChapter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TopicRegistrant {
  const TopicRegistrant({
    required this.memberId,
    required this.nickname,
    this.avatar,
  });

  final int memberId;
  final String nickname;
  final String? avatar;

  factory TopicRegistrant.fromJson(Map<String, dynamic> json) =>
      TopicRegistrant(
        memberId: asInt(json['memberId']),
        nickname: (json['nickname'] ?? '城瘾玩家').toString(),
        avatar: json['avatar']?.toString(),
      );
}

class TopicTicket {
  const TopicTicket({
    required this.id,
    required this.name,
    this.startTime,
    this.endTime,
    this.meetingPoint,
    this.refundRule,
    this.price,
    this.remaining,
    this.totalInventory = 0,
    this.registrants = const <TopicRegistrant>[],
  });

  final int id;
  final String name;
  final String? startTime;
  final String? endTime;
  final String? meetingPoint;
  final String? refundRule;
  final double? price;
  final int? remaining;
  final int totalInventory;
  final List<TopicRegistrant> registrants;

  static String _shortTime(String? raw) {
    if (raw == null || raw.length < 16) return '';
    return '${raw.substring(5, 10)} ${raw.substring(11, 16)}';
  }

  String get sessionTimeText {
    final start = _shortTime(startTime);
    final end = _shortTime(endTime);
    if (start.isEmpty) return '';
    if (end.isEmpty) return start;
    return start.substring(0, 5) == end.substring(0, 5)
        ? '$start–${end.substring(6)}'
        : '$start ~ $end';
  }

  factory TopicTicket.fromJson(Map<String, dynamic> json) => TopicTicket(
    id: asInt(json['id']),
    name: (json['name'] ?? '').toString(),
    startTime: json['startTime']?.toString(),
    endTime: json['endTime']?.toString(),
    meetingPoint: json['meetingPoint']?.toString(),
    refundRule: json['refundRule']?.toString(),
    price: (json['price'] as num?)?.toDouble(),
    remaining: json['remainingInventory'] is num
        ? (json['remainingInventory'] as num).toInt().clamp(0, 2147483647)
        : null,
    totalInventory: asInt(json['totalInventory']),
    registrants: (json['cmsRegistrationList'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(TopicRegistrant.fromJson)
        .toList(),
  );
}

class TopicComment {
  const TopicComment({
    required this.memberNickname,
    required this.createTime,
    required this.rating,
    required this.contents,
  });

  final String memberNickname;
  final String createTime;
  final int rating;
  final String contents;

  factory TopicComment.fromJson(Map<String, dynamic> json) => TopicComment(
    memberNickname: (json['memberNickname'] ?? '城瘾玩家').toString(),
    createTime: (json['createTime'] ?? '').toString(),
    rating: asInt(json['rating']),
    contents: (json['contents'] ?? '').toString(),
  );
}
