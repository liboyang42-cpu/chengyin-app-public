import 'dart:convert';

/// 广场真实数据源。`latest` 对所有人开放；`following` 需要登录。
enum SquareFeedMode {
  latest('LATEST', '最新'),
  following('FOLLOWING', '关注'),
  nearby('NEARBY', '附近'),
  topic('TOPIC', '话题'),
  community('COMMUNITY', '社群'),
  featured('FEATURED', '精选'),
  trending('TRENDING', '热门'),
  forYou('FOR_YOU', '推荐');

  const SquareFeedMode(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// 创意广场动态 + 评论模型。对齐后端 `ViewCreativeSquare` / `ViewComment`。
/// 注意:pics 字段在后端是「英文分号/逗号分隔 或 JSON 数组」字符串,解析需容错。

/// 把 pics 字段解析成图片 URL 列表。
/// 容错:null/空 → []; JSON 数组 → 取其元素; 否则按逗号/分号切分。
List<String> parsePics(dynamic raw) {
  if (raw == null) return const <String>[];
  if (raw is List) {
    return raw
        .map((dynamic e) => e?.toString().trim() ?? '')
        .where((String s) => s.isNotEmpty)
        .toList();
  }
  final str = raw.toString().trim();
  if (str.isEmpty) return const <String>[];
  // 可能是 JSON 数组字符串
  if (str.startsWith('[')) {
    try {
      final decoded = jsonDecode(str);
      if (decoded is List) {
        return decoded
            .map((dynamic e) => e?.toString().trim() ?? '')
            .where((String s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // 落到分隔符解析
    }
  }
  return str
      .split(RegExp(r'[;,，；]'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
}

/// 广场动态。
class SquarePost {
  const SquarePost({
    required this.id,
    required this.memberId,
    this.contents,
    this.pics = const <String>[],
    this.mediaIds = const <int>[],
    this.address,
    this.cityCode,
    this.likeNum = 0,
    this.nolikeNum = 0,
    this.commentCount = 0,
    this.isLiked = 0,
    this.memberNickname,
    this.memberAvatar,
    this.rz = false,
    this.memberLevelId = 0,
    this.authorBadge,
    this.noticeBadge,
    this.clubId,
    this.clubName,
    this.routePreviewImg,
    this.sportName,
    this.sportCover,
    this.sportTopicId,
    this.referenceType,
    this.referenceId,
    this.dataId,
    this.dataType = 0,
    this.isTopicTemplate = false,
    this.nodeTotal = 0,
    this.nodeDoneCount = 0,
    this.completed = false,
    this.isFollowTheUser = 0,
    this.createTime,
    this.version = 0,
    this.bookmarked = false,
    this.shareCount = 0,
    this.lifecycle = 'PUBLISHED',
    this.audience = 'PUBLIC',
    this.commentPolicy = 'EVERYONE',
    this.postType = 'MOMENT',
    this.reasonCode,
    this.disclosureType = 'NONE',
    this.communityId,
    this.replyApprovalEnabled = false,
    this.slowModeSeconds = 0,
    this.mentionedMemberIds = const <int>[],
    this.viewerCanComment = false,
    this.safetyLabels = const <String>[],
  });

  final int id;
  final int memberId;
  final String? contents;
  final List<String> pics;
  final List<int> mediaIds;
  final String? address;
  final String? cityCode;
  final int likeNum;
  final int nolikeNum;
  final int commentCount;

  /// 0 未操作 / 1 已点赞 / 2 已踩。
  final int isLiked;
  final String? memberNickname;
  final String? memberAvatar;

  /// 实名认证徽章(真源 `components/cy/post-card/index.wxml:22` 的 `post.rz`)。
  final bool rz;

  /// 会员等级,`> 0` 才显示 `Lv.N`(真源同文件 `:23`)。0 与缺省同义。
  final int memberLevelId;

  /// 作者身份徽章,后端下发原文(真源 `:24`)。
  final String? authorBadge;

  /// 通知类徽章,后端下发原文;与 [authorBadge] 分开,视觉上一轻一重(真源 `:25`)。
  final String? noticeBadge;

  /// 所属俱乐部(真源 `:29` 的 `post.clubName`),点它进俱乐部。
  final int? clubId;
  final String? clubName;

  final String? routePreviewImg;
  final String? sportName;
  final String? sportCover;

  /// 关联的真实主题 id。活动帖取其 topicId，主题帖即自身 id。
  final int? sportTopicId;
  final String? referenceType;
  final int? referenceId;

  /// 关联对象 id 与类型(1 活动 / 2 主题 / 3 自由漫游成绩)。
  ///
  /// 读模型直接下发这一对(小程序 `pages/square/{list,detail}` 也是读它俩,
  /// 再原样塞进发帖面板的编辑态);发帖/改帖要把它们发回
  /// `/api/creativesquare/action` 的 `data_id`/`data_type` —— 后端对关联是
  /// 「无值即清 0」,编辑不重发就等于把旧关联删了。
  final int? dataId;
  final int dataType;

  /// 只有后端明确标记的主题模板才允许复制改编。
  final bool isTopicTemplate;
  final int nodeTotal;
  final int nodeDoneCount;
  final bool completed;
  final int isFollowTheUser;
  final String? createTime;
  final int version;
  final bool bookmarked;
  final int shareCount;
  final String lifecycle;
  final String audience;
  final String commentPolicy;
  final String postType;
  final String? reasonCode;
  final String disclosureType;
  final int? communityId;
  final bool replyApprovalEnabled;
  final int slowModeSeconds;
  final List<int> mentionedMemberIds;
  final bool viewerCanComment;
  final List<String> safetyLabels;

  bool get liked => isLiked == 1;
  bool get canRemixTopicTemplate => isTopicTemplate && (sportTopicId ?? 0) > 0;

  /// 本地叠加一层改动(点赞/收藏的乐观更新、失败回滚)。
  /// 只带会被本地改写的字段;其余字段按原值拷贝。
  SquarePost copyWith({
    String? contents,
    List<String>? pics,
    List<int>? mediaIds,
    String? address,
    String? cityCode,
    int? likeNum,
    int? nolikeNum,
    int? commentCount,
    int? isLiked,
    bool? bookmarked,
    int? shareCount,
    int? version,
    String? lifecycle,
    String? audience,
    String? commentPolicy,
    bool? viewerCanComment,
    List<int>? mentionedMemberIds,
    List<String>? safetyLabels,
  }) {
    return SquarePost(
      id: id,
      memberId: memberId,
      contents: contents ?? this.contents,
      pics: pics ?? this.pics,
      mediaIds: mediaIds ?? this.mediaIds,
      address: address ?? this.address,
      cityCode: cityCode ?? this.cityCode,
      likeNum: likeNum ?? this.likeNum,
      nolikeNum: nolikeNum ?? this.nolikeNum,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      memberNickname: memberNickname,
      memberAvatar: memberAvatar,
      rz: rz,
      memberLevelId: memberLevelId,
      authorBadge: authorBadge,
      noticeBadge: noticeBadge,
      clubId: clubId,
      clubName: clubName,
      routePreviewImg: routePreviewImg,
      sportName: sportName,
      sportCover: sportCover,
      sportTopicId: sportTopicId,
      referenceType: referenceType,
      referenceId: referenceId,
      dataId: dataId,
      dataType: dataType,
      isTopicTemplate: isTopicTemplate,
      nodeTotal: nodeTotal,
      nodeDoneCount: nodeDoneCount,
      completed: completed,
      isFollowTheUser: isFollowTheUser,
      createTime: createTime,
      bookmarked: bookmarked ?? this.bookmarked,
      shareCount: shareCount ?? this.shareCount,
      version: version ?? this.version,
      lifecycle: lifecycle ?? this.lifecycle,
      audience: audience ?? this.audience,
      commentPolicy: commentPolicy ?? this.commentPolicy,
      postType: postType,
      reasonCode: reasonCode,
      disclosureType: disclosureType,
      communityId: communityId,
      replyApprovalEnabled: replyApprovalEnabled,
      slowModeSeconds: slowModeSeconds,
      mentionedMemberIds: mentionedMemberIds ?? this.mentionedMemberIds,
      viewerCanComment: viewerCanComment ?? this.viewerCanComment,
      safetyLabels: safetyLabels ?? this.safetyLabels,
    );
  }

  factory SquarePost.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> post = json['post'] is Map
        ? Map<String, dynamic>.from(json['post'] as Map)
        : json;
    final List<dynamic> media = json['media'] is List
        ? json['media'] as List<dynamic>
        : const <dynamic>[];
    final List<String> mediaUrls = media
        .whereType<Map>()
        .where(
          (Map row) =>
              '${row['media_type'] ?? row['mediaType'] ?? 'IMAGE'}' == 'IMAGE',
        )
        .map(
          (Map row) =>
              '${row['derived_object_key'] ?? row['derivedObjectKey'] ?? ''}'
                  .trim(),
        )
        .where((String value) => value.isNotEmpty)
        .toList();
    final Map<dynamic, dynamic> routeMedia = media
        .whereType<Map>()
        .cast<Map>()
        .firstWhere(
          (Map row) =>
              '${row['media_type'] ?? row['mediaType'] ?? ''}' ==
              'MAP_SNAPSHOT',
          orElse: () => <dynamic, dynamic>{},
        );
    final List<dynamic> references = json['references'] is List
        ? json['references'] as List<dynamic>
        : const <dynamic>[];
    final Map<String, dynamic> reference = references.whereType<Map>().isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(references.whereType<Map>().first);
    final String referenceType =
        '${reference['reference_type'] ?? reference['referenceType'] ?? ''}';
    final int? referenceId =
        (reference['reference_id'] ?? reference['referenceId']) is num
        ? ((reference['reference_id'] ?? reference['referenceId']) as num)
              .toInt()
        : int.tryParse(
            '${reference['reference_id'] ?? reference['referenceId'] ?? ''}',
          );
    final Object? rawSnapshot =
        reference['snapshot_json'] ?? reference['snapshotJson'];
    Map<String, dynamic> referenceSnapshot = <String, dynamic>{};
    if (rawSnapshot is Map) {
      referenceSnapshot = Map<String, dynamic>.from(rawSnapshot);
    } else if (rawSnapshot is String && rawSnapshot.trim().isNotEmpty) {
      try {
        final Object? parsed = jsonDecode(rawSnapshot);
        if (parsed is Map) {
          referenceSnapshot = Map<String, dynamic>.from(parsed);
        }
      } catch (_) {
        referenceSnapshot = <String, dynamic>{};
      }
    }
    final String snapshotTitle =
        '${referenceSnapshot['title'] ?? referenceSnapshot['name'] ?? ''}'
            .trim();
    final String? referenceLabel = referenceType.isEmpty || referenceId == null
        ? null
        : snapshotTitle.isNotEmpty
        ? snapshotTitle
        : '${_referenceTypeLabel(referenceType)} #$referenceId';
    // 关联:读模型直接给 `dataId`/`dataType`;只有老 shape(`references[]`)才折算 ——
    // 折算不出来的(CLUB / POI)当没有,编辑重发要的是**原样**,不是猜一个。
    final int rawDataId = _intOr(post['dataId'] ?? post['data_id']);
    final int rawDataType = _intOr(post['dataType'] ?? post['data_type']);
    final int linkDataId = rawDataId > 0 ? rawDataId : (referenceId ?? 0);
    final int linkDataType = rawDataType > 0
        ? rawDataType
        : _dataTypeOfReference(referenceType);
    final bool hasDataLink = linkDataId > 0 && linkDataType > 0;
    return SquarePost(
      id: (post['id'] as num?)?.toInt() ?? 0,
      memberId: ((post['authorId'] ?? post['memberId']) as num?)?.toInt() ?? 0,
      contents: (post['body'] ?? post['contents']) as String?,
      pics: mediaUrls.isNotEmpty ? mediaUrls : parsePics(post['pics']),
      mediaIds:
          <Map<dynamic, dynamic>>[
                ...media.whereType<Map>().where(
                  (Map row) =>
                      '${row['media_type'] ?? row['mediaType'] ?? 'IMAGE'}' ==
                      'IMAGE',
                ),
                ...media.whereType<Map>().where(
                  (Map row) =>
                      '${row['media_type'] ?? row['mediaType'] ?? 'IMAGE'}' !=
                      'IMAGE',
                ),
              ]
              .map((Map<dynamic, dynamic> row) => row['id'] ?? row['mediaId'])
              .whereType<num>()
              .map((num id) => id.toInt())
              .where((int id) => id > 0)
              .toList(growable: false),
      address: (post['poiName'] ?? post['address']) as String?,
      cityCode: (post['cityCode'] ?? post['city_code']) as String?,
      likeNum: ((post['likeCount'] ?? post['likeNum']) as num?)?.toInt() ?? 0,
      nolikeNum: (post['nolikeNum'] as num?)?.toInt() ?? 0,
      commentCount: (post['commentCount'] as num?)?.toInt() ?? 0,
      isLiked: _truthy(post['viewerLiked'])
          ? 1
          : ((post['isLiked'] as num?)?.toInt() ?? 0),
      memberNickname:
          (post['authorNickname'] ?? post['memberNickname']) as String?,
      memberAvatar: (post['authorAvatar'] ?? post['memberAvatar']) as String?,
      rz: _truthy(post['rz']),
      memberLevelId: _intOr(post['memberLevelId'] ?? post['member_level_id']),
      authorBadge: _nonEmpty(post['authorBadge'] ?? post['author_badge']),
      noticeBadge: _nonEmpty(post['noticeBadge'] ?? post['notice_badge']),
      clubId: _intOrNull(post['clubId']),
      clubName: _nonEmpty(post['clubName']),
      routePreviewImg:
          (routeMedia['derived_object_key'] ??
                  routeMedia['derivedObjectKey'] ??
                  json['routePreviewImg'])
              as String?,
      sportName: (json['sportName'] as String?) ?? referenceLabel,
      sportCover:
          (json['sportCover'] ??
                  referenceSnapshot['cover_url'] ??
                  referenceSnapshot['coverUrl'])
              as String?,
      sportTopicId: json['sportTopicId'] is num
          ? (json['sportTopicId'] as num).toInt()
          : (int.tryParse('${json['sportTopicId'] ?? ''}') ??
                (referenceType == 'TOPIC' ? referenceId : null)),
      referenceType: referenceType.isEmpty ? null : referenceType,
      referenceId: referenceId,
      dataId: hasDataLink ? linkDataId : null,
      dataType: hasDataLink ? linkDataType : 0,
      isTopicTemplate:
          json['isTopicTemplate'] == true ||
          json['isTopicTemplate'] == 1 ||
          json['isTopicTemplate'] == '1',
      nodeTotal: (json['nodeTotal'] as num?)?.toInt() ?? 0,
      nodeDoneCount: (json['nodeDoneCount'] as num?)?.toInt() ?? 0,
      completed:
          json['completed'] == true ||
          json['completed'] == 1 ||
          json['completed'] == '1',
      isFollowTheUser: (json['isFollowTheUser'] as num?)?.toInt() ?? 0,
      createTime: '${post['publishedAt'] ?? post['createTime'] ?? ''}',
      version: (post['version'] as num?)?.toInt() ?? 0,
      bookmarked: _truthy(post['viewerBookmarked']),
      shareCount: (post['shareCount'] as num?)?.toInt() ?? 0,
      lifecycle: '${post['lifecycle'] ?? 'PUBLISHED'}',
      audience: '${post['audience'] ?? 'PUBLIC'}',
      commentPolicy: '${post['commentPolicy'] ?? 'EVERYONE'}',
      postType: '${post['postType'] ?? 'MOMENT'}',
      reasonCode: post['reasonCode'] as String?,
      disclosureType: '${post['disclosureType'] ?? 'NONE'}',
      communityId: (post['communityId'] as num?)?.toInt(),
      replyApprovalEnabled: _truthy(post['replyApprovalEnabled']),
      slowModeSeconds: (post['slowModeSeconds'] as num?)?.toInt() ?? 0,
      // ★ 2026-09-17:真实契约 `/api/creativesquare/info`(ViewCreativeSquare)
      //   **不投影这个字段** —— `viewerCanComment` 只存在于未落地的
      //   `/api/v1/community` 那一代。原来「缺席 ⇒ false」会让详情页的输入框、
      //   回复入口整块消失:小程序里能评论,App 里评论不了。
      //   小程序那边没有这道闸门(输入框常显)⇒ 缺席 = 服务端没说不能 = 能评论,
      //   只有后端**显式**说 false 才关。
      viewerCanComment: json['viewerCanComment'] == null
          ? true
          : _truthy(json['viewerCanComment']),
      safetyLabels: _stringList(
        post['safetyLabelsJson'] ?? post['safety_labels_json'],
      ),
      mentionedMemberIds:
          (json['mentions'] as List<dynamic>? ?? const <dynamic>[])
              .map(
                (dynamic value) => value is num
                    ? value.toInt()
                    : (value is Map
                          ? (value['mentioned_member_id'] ?? value['memberId'])
                          : null),
              )
              .whereType<num>()
              .map((num value) => value.toInt())
              .where((int value) => value > 0)
              .toList(growable: false),
    );
  }
}

/// `references[].reference_type` → 写接口的 `data_type`(1 活动 / 2 主题 / 3 自由漫游)。
/// 认不出的类型(CLUB / POI / 空)返回 0 —— 没有可回发的关联,总比编一个强。
int _dataTypeOfReference(String type) => switch (type) {
  'ACTIVITY' => 1,
  'TOPIC' => 2,
  'ROUTE' => 3,
  _ => 0,
};

String _referenceTypeLabel(String value) {
  switch (value) {
    case 'ACTIVITY':
      return '活动';
    case 'TOPIC':
      return '主题';
    case 'ROUTE':
      return '路线';
    case 'CLUB':
      return '俱乐部';
    case 'POI':
      return '地点';
    default:
      return '关联内容';
  }
}

bool _truthy(dynamic value) => value == true || value == 1 || value == '1';

/// 宽松取整:后端这几个字段既发过数字也发过字符串,而 `as num` 遇到字符串
/// 会**直接抛**,把整页信息流带下水。取不到就当 0(缺省语义)。
int _intOr(dynamic value) => _intOrNull(value) ?? 0;

int? _intOrNull(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _nonEmpty(dynamic value) {
  final String text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

String squareSafetyLabelText(String value) =>
    const <String, String>{
      'DANGEROUS_ACTIVITY': '危险活动',
      'SENSITIVE_CONTENT': '敏感内容',
      'FLASHING_IMAGES': '闪烁画面',
      'SPOILER': '剧透',
      'TEMPORARY_CLOSURE': '临时关闭',
      'ACCESSIBILITY_LIMIT': '无障碍限制',
      'WEATHER_RISK': '天气风险',
    }[value] ??
    value;

/// 评论。对齐后端 `ViewComment`(owner_type=3 创意广场)。
class Comment {
  Comment({
    required this.id,
    required this.memberId,
    this.contents,
    this.imgArr = const <String>[],
    this.rating = 0,
    this.likeCount = 0,
    this.isLiked = 0,
    this.memberNickname,
    this.memberAvatar,
    this.createTime,
    this.lifecycle = 'PUBLISHED',
    this.approvalState = 'VISIBLE',
    this.version = 0,
    this.rootId,
    this.parentId,
    this.repliedToMemberId,
  });

  final int id;
  final int memberId;
  final String? contents;
  final List<String> imgArr;
  final int rating;
  final int likeCount;

  /// 0 未点赞 / 1 已点赞。
  final int isLiked;
  final String? memberNickname;
  final String? memberAvatar;
  final String? createTime;
  final String lifecycle;
  final String approvalState;
  final int version;
  final int? rootId;
  final int? parentId;
  final int? repliedToMemberId;

  bool get liked => isLiked == 1;

  /// 本地叠加一层改动(评论点赞的乐观更新、失败回滚)。
  Comment copyWith({
    String? contents,
    int? likeCount,
    int? isLiked,
    String? lifecycle,
    String? approvalState,
    int? version,
  }) {
    return Comment(
      id: id,
      memberId: memberId,
      contents: contents ?? this.contents,
      imgArr: imgArr,
      rating: rating,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      memberNickname: memberNickname,
      memberAvatar: memberAvatar,
      createTime: createTime,
      lifecycle: lifecycle ?? this.lifecycle,
      approvalState: approvalState ?? this.approvalState,
      version: version ?? this.version,
      rootId: rootId,
      parentId: parentId,
      repliedToMemberId: repliedToMemberId,
    );
  }

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: (json['id'] as num?)?.toInt() ?? 0,
    memberId:
        ((json['author_id'] ?? json['authorId'] ?? json['memberId']) as num?)
            ?.toInt() ??
        0,
    contents: (json['body'] ?? json['contents']) as String?,
    imgArr: parsePics(json['imgArr']),
    rating: (json['rating'] as num?)?.toInt() ?? 0,
    likeCount:
        ((json['like_count'] ?? json['likeCount']) as num?)?.toInt() ?? 0,
    isLiked: _truthy(json['viewer_liked'] ?? json['viewerLiked'])
        ? 1
        : ((json['isLiked'] as num?)?.toInt() ?? 0),
    memberNickname:
        (json['author_nickname'] ??
                json['authorNickname'] ??
                json['memberNickname'])
            as String?,
    memberAvatar:
        (json['author_avatar'] ?? json['authorAvatar'] ?? json['memberAvatar'])
            as String?,
    createTime: '${json['create_time'] ?? json['createTime'] ?? ''}',
    lifecycle: '${json['lifecycle'] ?? 'PUBLISHED'}',
    approvalState:
        '${json['author_approval_state'] ?? json['approvalState'] ?? 'VISIBLE'}',
    version: (json['version'] as num?)?.toInt() ?? 0,
    rootId: _optionalInt(json['root_id'] ?? json['rootId']),
    // reply_id 是被回复的那条评论(`/api/comment/add` 的入参就是它),
    // 与 parent_id 同义 —— 两代契约各用一个名字。
    parentId: _optionalInt(
      json['parent_id'] ??
          json['parentId'] ??
          json['reply_id'] ??
          json['replyId'],
    ),
    repliedToMemberId: _optionalInt(
      json['replied_to_member_id'] ?? json['repliedToMemberId'],
    ),
  );
}

int? _optionalInt(dynamic value) => value is num ? value.toInt() : null;

List<String> _stringList(dynamic value) {
  dynamic decoded = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      decoded = jsonDecode(value);
    } catch (_) {
      return const <String>[];
    }
  }
  if (decoded is! List) return const <String>[];
  return decoded
      .map((dynamic item) => '$item'.trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
}
