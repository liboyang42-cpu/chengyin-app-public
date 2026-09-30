/// 俱乐部帖文。对齐后端 `ClubPost` 与 `/api/club/post/feed`。
class ClubPost {
  const ClubPost({
    required this.id,
    this.clubId,
    this.authorMemberId,
    this.content,
    this.images = const <String>[],
    this.likeCount = 0,
    this.commentCount = 0,
    this.nickname,
    this.avatar,
    this.createTime,
    this.liked = false,
    this.type = 0,
    this.pinned = false,
    this.version = 0,
    this.edited = false,
    this.viewerCanManage = false,
    this.refType,
    this.refId,
    this.sportName,
    this.sportCover,
    this.sportTopicId,
    this.isTopicTemplate = false,
  });

  final int id;
  final int? clubId;

  /// 作者。★ 后端字段叫 `authorMemberId`(不是 memberId)——
  ///   拿它跳作者主页;为空或 0 时**不给点**,跳 /user/0 会进一个空主页。
  final int? authorMemberId;
  final String? content;

  /// 图片。后端存的是**分号分隔的字符串**,这里切好。
  final List<String> images;

  final int likeCount;
  final int commentCount;
  final String? nickname;
  final String? avatar;
  final String? createTime;
  final bool liked;
  final int type;
  final bool pinned;
  final int version;
  final bool edited;
  final bool viewerCanManage;

  /// 帖子带的游玩引用。后端 `/api/club/post/feed` 由
  /// `ApiClubController.projectPostReferences` 回填:
  /// `refType` 1=活动完赛(成绩卡)、2=主题/模板(模板卡);
  /// `sportTopicId` 两种引用都有(活动取其所属主题、主题即自身);
  /// 被引对象已删/下架时 `sportName` 为空 → 下面的判定自然判假,
  /// 帖子降级成普通图文帖(真源 `pages/club/detail/index.js:367-370` 的口径)。
  final int? refType;
  final int? refId;
  final String? sportName;
  final String? sportCover;
  final int? sportTopicId;
  final bool isTopicTemplate;

  String? get _refName {
    final n = sportName?.trim() ?? '';
    return n.isEmpty ? null : n;
  }

  /// 成绩卡判定。对齐 `utils/feed-play-card.js` `isCompletedShare`:
  /// dataType(=refType)==1 且 completed(俱乐部侧恒真,见
  /// `pages/club/detail/index.js:370`)且有名字。
  bool get isCompletionShare => refType == 1 && _refName != null;

  /// 模板卡判定(`hasFeedPlayCover`):有名有封面,且不是成绩卡。
  bool get hasPlayRefCard =>
      !isCompletionShare &&
      _refName != null &&
      (sportCover ?? '').trim().isNotEmpty;

  /// 卡片可点的前提:拿得到被引主题 id。拿不到就不渲染成死卡。
  bool get refNavigable => (sportTopicId ?? 0) > 0;

  /// 点卡片的落点 —— 「看这条主题」(真源 `onPostReference`)。
  String? get refTopicRoute => refNavigable ? '/topic/$sportTopicId' : null;

  /// 「试玩」的落点 —— 「现在就去玩」(真源 `onPostReferencePlay` →
  /// `/pages/play/index?topicId=`;App 自玩会话走 `/play/0?topicId=`)。
  String? get refPlayRoute =>
      refNavigable ? '/play/0?topicId=$sportTopicId' : null;

  bool get isAnnouncement => type == 2;

  String get authorName =>
      (nickname ?? '').trim().isEmpty ? '城瘾用户' : nickname!.trim();

  /// 正文。★ 帖子**可以只有图没有字** —— 正文为空时返回 null 让界面不渲染
  ///   那一段,而不是显示一个空行把图片顶下去。
  String? get body {
    final c = content?.trim() ?? '';
    return c.isEmpty ? null : c;
  }

  /// 互动数文案。★ 两个都为 0 时**整行不显示** ——
  ///   刚发的帖子挂着「0 赞 0 评论」既是噪音也很难看。
  String? get statsText {
    if (likeCount <= 0 && commentCount <= 0) return null;
    return <String>[
      if (likeCount > 0) '$likeCount 赞',
      if (commentCount > 0) '$commentCount 评论',
    ].join(' · ');
  }

  /// 作者主页落点。拿不到 id 时返回 null,调用方据此不给点。
  String? get authorRoute {
    final id = authorMemberId;
    return (id != null && id > 0) ? '/user/$id' : null;
  }

  /// 这条帖子有没有可显示的内容。★ 图与字都没有 = 空帖,不渲染 ——
  ///   但带游玩引用的帖子有卡可看,不是空帖。
  bool get hasSomething =>
      body != null || images.isNotEmpty || isCompletionShare || hasPlayRefCard;

  factory ClubPost.fromJson(Map<String, dynamic> json) {
    final raw = (json['images'] as String?) ?? '';
    final Object? rawPinned = json['isPinned'];
    return ClubPost(
      id: (json['id'] as num?)?.toInt() ?? 0,
      clubId: (json['clubId'] as num?)?.toInt(),
      authorMemberId: (json['authorMemberId'] as num?)?.toInt(),
      content: json['content'] as String?,
      images: raw
          .split(';')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      createTime: json['createTime']?.toString(),
      liked: json['liked'] == true,
      type: (json['type'] as num?)?.toInt() ?? 0,
      pinned: rawPinned == true || (rawPinned is num && rawPinned.toInt() == 1),
      version: (json['version'] as num?)?.toInt() ?? 0,
      edited: json['edited'] == true || json['edited'] == 1,
      viewerCanManage:
          json['viewerCanManage'] == true || json['viewerCanManage'] == 1,
      refType: (json['refType'] as num?)?.toInt(),
      refId: (json['refId'] as num?)?.toInt(),
      sportName: (json['sportName'] as String?)?.trim(),
      sportCover: json['sportCover']?.toString(),
      sportTopicId: (json['sportTopicId'] as num?)?.toInt(),
      isTopicTemplate:
          json['isTopicTemplate'] == true || json['isTopicTemplate'] == 1,
    );
  }
}

/// 公开编辑历史只暴露内容快照，不接收 editorMemberId，避免披露审核主体。
class ClubPostRevision {
  const ClubPostRevision({
    required this.id,
    required this.snapshotVersion,
    this.content,
    this.images = const <String>[],
    this.createTime,
  });

  final int id;
  final int snapshotVersion;
  final String? content;
  final List<String> images;
  final String? createTime;

  factory ClubPostRevision.fromJson(Map<String, dynamic> json) {
    final String raw = (json['images'] as String?) ?? '';
    return ClubPostRevision(
      id: (json['id'] as num?)?.toInt() ?? 0,
      snapshotVersion: (json['snapshotVersion'] as num?)?.toInt() ?? 0,
      content: json['content'] as String?,
      images: raw
          .split(';')
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
      createTime: json['createTime']?.toString(),
    );
  }
}

/// 帖文流。
class ClubFeed {
  const ClubFeed({this.rows = const <ClubPost>[], this.clubCount = 0});

  final List<ClubPost> rows;

  /// 我加入的俱乐部数。★ 为 0 时**页面该说"先加入一个俱乐部"**,
  ///   而不是显示空列表 —— 空列表会让人以为"大家都没发帖"。
  final int clubCount;

  bool get hasNoClub => clubCount <= 0;

  factory ClubFeed.fromJson(Map<String, dynamic> json) {
    return ClubFeed(
      rows: ((json['rows'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ClubPost.fromJson)
          // 空帖(图与字都没有)不进列表。
          .where((ClubPost p) => p.hasSomething)
          .toList(),
      clubCount: (json['clubCount'] as num?)?.toInt() ?? 0,
    );
  }
}
