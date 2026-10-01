import 'dart:math' show asin, cos, sin, sqrt;

import '../../core/util/json_parse.dart' show asBool, asInt, asStr;
import 'topic.dart' show TopicChapter, TopicNode, TopicTemplate;

/// 俱乐部 · 主题运营(4-B)的模型。
/// 逐条对齐小程序真源 `pages/club/{topic-detail,topic-story}`(@90e66d70)。
///
/// ⚠️ 形状纪律与 `club_ops.dart` 同一条:坏回执返回 null,不拿 0/空串兜底 ——
///   「这个数没下发」和「这个数是零」在稿上读法不同(小程序 director.js 的
///   「待确认」与广播预览的「不写成 0 人」都是同一条纪律)。

/// 主题的六个状态(小程序 topic-detail/index.js 的 `STATES`)。
///
/// 每个状态同时带:胶囊文案 / 底部主键文案 / 主键是否禁用 / 出不出核销区 /
/// 出不出未通过原因 / 出不出场次列表。放在枚举里而不是散在页面里,
/// 是因为这六件事在稿上永远一起变(H1–H6 逐稿核对过)。
enum ClubTopicStatus {
  reviewing(
    text: '审核中',
    primaryText: '等待审核中',
    primaryDisabled: true,
    showsVerify: false,
    showsRejectReason: false,
    showsSessions: false,
  ),
  rejected(
    text: '未通过',
    primaryText: '修改并重新提交',
    primaryDisabled: false,
    showsVerify: false,
    showsRejectReason: true,
    showsSessions: true,
  ),
  confirmed(
    text: '已确认',
    primaryText: '开始准备',
    primaryDisabled: false,
    showsVerify: false,
    showsRejectReason: false,
    showsSessions: true,
  ),
  preparing(
    text: '准备中',
    primaryText: '开始活动',
    primaryDisabled: false,
    showsVerify: false,
    showsRejectReason: false,
    showsSessions: true,
  ),
  running(
    text: '进行中',
    primaryText: '结束活动',
    primaryDisabled: false,
    showsVerify: true,
    showsRejectReason: false,
    showsSessions: true,
  ),

  /// 自玩(无人带队)的进行中。文案与 [running] 一致:
  /// 小程序 2026-09-11 把「去核销」改掉的理由是**写动作不许挂在读文案下面**,
  /// 这里照抄结论。
  selfRun(
    text: '进行中',
    primaryText: '结束活动',
    primaryDisabled: false,
    showsVerify: true,
    showsRejectReason: false,
    showsSessions: true,
  ),
  ended(
    text: '已结束',
    primaryText: '查看结算报告',
    primaryDisabled: false,
    // ★ ended 也出核销区:已经下架的主题照样可能有已付款未核销的票要退
    //   (小程序 STATES.ended.verify = true,别照「结束了就不用核销」想当然改掉)。
    showsVerify: true,
    showsRejectReason: false,
    showsSessions: true,
  );

  const ClubTopicStatus({
    required this.text,
    required this.primaryText,
    required this.primaryDisabled,
    required this.showsVerify,
    required this.showsRejectReason,
    required this.showsSessions,
  });

  final String text;
  final String primaryText;
  final bool primaryDisabled;
  final bool showsVerify;
  final bool showsRejectReason;
  final bool showsSessions;

  /// 小程序 `resolveStateKey(raw)` 的原样移植。
  ///
  /// ⚠️ 这套推断是**临时口径**(小程序自己也标了 TODO(接口):等后端给俱乐部端
  /// 主题状态字段后换直读)。实现时别顺手「优化」判断顺序 ——
  /// 「有 rejectReason 但没有 auditStatus」必须也落未通过,否则被拒的主题会
  /// 显示成已确认、主键变成「开始准备」。
  static ClubTopicStatus resolve(Map<String, dynamic> raw) {
    final int auditStatus = asInt(raw['auditStatus'], defaultValue: -1);
    final String rejectReason = asStr(raw['rejectReason']);
    if (auditStatus == 2 || rejectReason.isNotEmpty) {
      return ClubTopicStatus.rejected;
    }
    if (auditStatus == 0 || auditStatus == 1) return ClubTopicStatus.reviewing;
    if (asStr(raw['endedAt']).isNotEmpty || asStr(raw['status']) == 'ended') {
      return ClubTopicStatus.ended;
    }
    if (asStr(raw['startedAt']).isNotEmpty ||
        asStr(raw['status']) == 'running') {
      return asBool(raw['selfPublished'])
          ? ClubTopicStatus.selfRun
          : ClubTopicStatus.running;
    }
    if (asStr(raw['preparingAt']).isNotEmpty ||
        asStr(raw['status']) == 'preparing') {
      return ClubTopicStatus.preparing;
    }
    return ClubTopicStatus.confirmed;
  }
}

/// 接下来的一场(小程序 `buildSessions`)。
class ClubTopicSession {
  const ClubTopicSession({
    required this.id,
    required this.whenText,
    required this.whoText,
    required this.etaText,
    required this.kind,
  });

  final String id;
  final String whenText;
  final String whoText;
  final String etaText;
  final String kind;

  /// `walkin` = 自由到店;其余按俱乐部包团(小程序 buildSessions 同判据)。
  String get kindText => kind == 'walkin' ? '自由到店' : '俱乐部包团';

  static ClubTopicSession? tryFromJson(Map<String, dynamic> raw, int index) {
    final String when = asStr(raw['whenText']);
    final String who = asStr(raw['whoText']);
    final String eta = asStr(raw['etaText']);
    if (when.isEmpty && who.isEmpty && eta.isEmpty) return null;
    final String id = asStr(raw['id']);
    return ClubTopicSession(
      id: id.isEmpty ? 's$index' : id,
      whenText: when,
      whoText: who,
      etaText: eta,
      kind: asStr(raw['kind']),
    );
  }
}

/// 团码可用的场次(小程序 `listGroupCodeActivities` 过滤后的两项)。
class ClubTopicActivity {
  const ClubTopicActivity({
    required this.id,
    required this.name,
    this.startDate = '',
  });

  final int id;
  final String name;

  /// 这一场的集合时刻原样字符串(小程序 `_opsTimeMatch` 的真源:
  /// HO-26 改集合时间先从这里读当前值,改完再回读同一条回执)。
  final String startDate;

  static ClubTopicActivity? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final int id = asInt(raw['id']);
    if (id <= 0) return null;
    final String name = asStr(raw['name']);
    return ClubTopicActivity(
      id: id,
      name: name.isEmpty ? '场次 $id' : name,
      startDate: asStr(raw['startDate']),
    );
  }
}

/// 主题**管理向**统计与三个身份字段:`POST /api/club/crm/topic-manage-stats` 的 data。
///
/// ★ 为什么单独一条接口、而不是从公开投影里猜(小程序拍板1,2026-09-17):
///   `/api/topic/info-to-user` 是**公开投影**,里面没有「你是不是主理人」这类判据,
///   原来的写法拿 `isOwner` 加缺省值猜,结果是给没有权限的人画出必失败的写动作
///   (联席主理人、核销员都中过)。现在三块管理向界面各读各的字段:
///     导演台 = [canDirect] / 场次管理 = [canManageSessions] / 核销区 = [canViewVerify];
///   四项统计(站数/本场人数/待核销/我已核销)同源下发,页面只读不算。
///
/// ★ 身份一律按「只有 true 算 true」读:字段没下发 = 没权限,
///   不是「大概是吧」—— 猜错的方向是给用户一个点了就报错的按钮。
class ClubTopicManageStats {
  const ClubTopicManageStats({
    required this.canDirect,
    required this.canManageSessions,
    required this.canViewVerify,
    required this.nodeCount,
    required this.sessionHeadcount,
    required this.pendingVerifyCount,
    required this.verifiedByMeCount,
  });

  /// 导演台(开始准备/开始活动/结束活动)的身份。
  final bool canDirect;

  /// 场次管理入口的身份(与公开投影的 `canManageEvents` 同义)。
  final bool canManageSessions;

  /// 核销区的身份(主理人 / 管理员 / 核销员)。
  final bool canViewVerify;
  final int nodeCount;
  final int sessionHeadcount;
  final int pendingVerifyCount;
  final int verifiedByMeCount;

  /// 核销区三格。★ 标签与数都只认这一份回执(小程序 `applyVerifyVisibility`):
  /// 核销区本身的出不出另由「主题状态 + [canViewVerify]」判。
  List<({String label, int value})> get verifyMetrics =>
      <({String label, int value})>[
        (label: '待核销', value: pendingVerifyCount),
        (label: '我已核销', value: verifiedByMeCount),
        (label: '本场总人数', value: sessionHeadcount),
      ];

  static ClubTopicManageStats? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return ClubTopicManageStats(
      canDirect: asBool(raw['canDirect']),
      canManageSessions: asBool(raw['canManageSessions']),
      canViewVerify: asBool(raw['canViewVerify']),
      nodeCount: asInt(raw['nodeCount']),
      sessionHeadcount: asInt(raw['sessionHeadcount']),
      pendingVerifyCount: asInt(raw['pendingVerifyCount']),
      verifiedByMeCount: asInt(raw['verifiedByMeCount']),
    );
  }
}

/// 俱乐部视角的主题详情:`POST /api/topic/info-to-user` 的俱乐部消费面。
///
/// ★ 与玩家侧 `topic.dart` 的 `TopicDetail` 是**同一条回执的两个消费面**:
///   那条要吃票/评论/购买门禁,这条吃审核态/核销数/场次/剧情与玩法完备度。
///   章节树(章节→站点→玩法模板)两边都要,所以这里**复用** `TopicChapter`,
///   不另造一套(小程序 topic-story 与玩家页读的也是同一份 chaptersList)。
class ClubTopicOverview {
  const ClubTopicOverview({
    required this.topicId,
    required this.name,
    required this.status,
    required this.cover,
    required this.merchantLogo,
    required this.startDate,
    required this.endDate,
    required this.verifyModeText,
    required this.playModeText,
    required this.chapterCount,
    required this.nodeCount,
    required this.storyReady,
    required this.gameConfiguredCount,
    required this.rejectReason,
    required this.sessions,
    required this.activities,
    required this.chapters,
  });

  final int topicId;
  final String name;
  final ClubTopicStatus status;
  final String cover;

  /// 承接商家的 logo(稿上压在封面左下角)。没有就不画那一块。
  final String merchantLogo;
  final String startDate;
  final String endDate;

  /// 核验方式的一句话(小程序默认「玩家可到店核销」)。
  final String verifyModeText;

  /// 玩法模式(经典定向/自由定向),用作头部 chip 与结构文案的一段。
  final String playModeText;
  final int chapterCount;
  final int nodeCount;

  /// 剧情写没写(稿上「剧情已写」软胶囊)。
  final bool storyReady;

  /// 已配玩法的站点数(稿上「玩法 3/7」)。
  final int gameConfiguredCount;
  final String rejectReason;
  final List<ClubTopicSession> sessions;
  final List<ClubTopicActivity> activities;
  final List<TopicChapter> chapters;

  /// `9月1日 – 9月30日`。两头各自有就写,没有就不写(不补「待定」)。
  String get dateRangeText {
    String fmt(String raw) {
      if (raw.isEmpty) return '';
      final DateTime? parsed = DateTime.tryParse(raw);
      if (parsed == null) return '';
      return '${parsed.month}月${parsed.day}日';
    }

    final String start = fmt(startDate);
    final String end = fmt(endDate);
    if (start.isNotEmpty && end.isNotEmpty) return '$start – $end';
    return start.isNotEmpty ? start : end;
  }

  /// 头部 chips。★ 本场人数只认管理向统计(`stats.sessionHeadcount`)——
  /// 公开投影里同名的一份已经删掉,两套口径就是两个数(小程序拍板1)。
  List<String> chipsOf(ClubTopicManageStats stats) => <String>[
    if (playModeText.isNotEmpty) playModeText,
    if (stats.sessionHeadcount > 0) '本场 ${stats.sessionHeadcount} 人',
  ];

  /// `2 章 · 7 站 · 经典定向`(站数同 [chipsOf],只认管理向统计)。
  String structureTextOf(ClubTopicManageStats stats) {
    final List<String> parts = <String>[
      if (chapterCount > 0) '$chapterCount 章',
      if (stats.nodeCount > 0) '${stats.nodeCount} 站',
      if (playModeText.isNotEmpty) playModeText,
    ];
    return parts.join(' · ');
  }

  /// 「剧情已写」「玩法 3/7」两枚软胶囊。站点数为 0 时不画玩法进度 ——
  /// 「玩法 0/0」会被读成「一个都没配」。
  List<({String text, bool success})> get statusChips {
    return <({String text, bool success})>[
      if (storyReady) (text: '剧情已写', success: true),
      if (nodeCount > 0)
        (text: '玩法 $gameConfiguredCount/$nodeCount', success: false),
    ];
  }

  /// 有场次可进导演台/团码时,拿第一场的 id(小程序 `maybeEnterDirector`:
  /// 主题下只有一场时,这一场就是运营对象)。
  int? get soleActivityId =>
      activities.length == 1 ? activities.first.id : null;

  static ClubTopicOverview? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final int topicId = asInt(raw['id']);
    final String name = asStr(raw['name']).isEmpty
        ? asStr(raw['title'])
        : asStr(raw['name']);
    if (topicId <= 0 || name.isEmpty) return null;

    final Object? rawChapters = raw['chaptersList'];
    final List<TopicChapter> chapters = rawChapters is List
        ? rawChapters
              .whereType<Map<String, dynamic>>()
              .map(TopicChapter.fromJson)
              .toList(growable: false)
        : const <TopicChapter>[];

    final Object? rawSessions = raw['sessions'];
    final List<ClubTopicSession> sessions = <ClubTopicSession>[];
    if (rawSessions is List) {
      for (int i = 0; i < rawSessions.length; i++) {
        final Object? item = rawSessions[i];
        if (item is! Map<String, dynamic>) continue;
        final ClubTopicSession? row = ClubTopicSession.tryFromJson(item, i);
        if (row != null) sessions.add(row);
      }
    }

    final Object? rawActivities = raw['activityList'];
    final List<ClubTopicActivity> activities = rawActivities is List
        ? rawActivities
              .map(ClubTopicActivity.tryFromJson)
              .whereType<ClubTopicActivity>()
              .toList(growable: false)
        : const <ClubTopicActivity>[];

    final String verifyModeText = asStr(raw['verifyModeText']);
    return ClubTopicOverview(
      topicId: topicId,
      name: name,
      status: ClubTopicStatus.resolve(raw),
      cover: asStr(raw['cover']).isEmpty
          ? asStr(raw['coverUrl'])
          : asStr(raw['cover']),
      merchantLogo: asStr(raw['merchantLogo']),
      startDate: asStr(raw['startDate']),
      endDate: asStr(raw['endDate']),
      verifyModeText: verifyModeText.isEmpty ? '玩家可到店核销' : verifyModeText,
      playModeText: asStr(raw['playModeText']),
      chapterCount: asInt(raw['chapterCount']),
      nodeCount: asInt(raw['nodeCount']),
      storyReady: asBool(raw['storyReady']),
      gameConfiguredCount: asInt(raw['gameConfiguredCount']),
      rejectReason: asStr(raw['rejectReason']),
      sessions: sessions,
      activities: activities,
      chapters: chapters,
    );
  }
}

/// 主题 · 俱乐部设置:`POST /api/club/topic-setting/{detail,save}` 的 data。
class TopicSetting {
  const TopicSetting({
    required this.topicName,
    required this.lifecycleText,
    required this.coopOpen,
    required this.pinned,
    required this.memberOnly,
    required this.canManage,
    required this.chapters,
  });

  final String topicName;
  final String lifecycleText;
  final bool coopOpen;
  final bool pinned;
  final bool memberOnly;

  /// 我能不能改这三个开关(`d.canManage`)。false 时开关只读。
  final bool canManage;
  final List<TopicSettingChapter> chapters;

  static TopicSetting? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawChapters = raw['chapters'];
    return TopicSetting(
      topicName: asStr(raw['topicName']),
      lifecycleText: asStr(raw['lifecycleText']),
      coopOpen: asBool(raw['coopOpen']),
      pinned: asBool(raw['pinned']),
      memberOnly: asBool(raw['memberOnly']),
      canManage: asBool(raw['canManage']),
      chapters: rawChapters is List
          ? rawChapters
                .whereType<Map<String, dynamic>>()
                .map(TopicSettingChapter.fromJson)
                .toList(growable: false)
          : const <TopicSettingChapter>[],
    );
  }
}

/// 设置里的一行章节。`recruiting` 为假时**不显示「N 家」** ——
/// 那会让人以为已经招到了(小程序 buildSetting 的原话)。
class TopicSettingChapter {
  const TopicSettingChapter({
    required this.id,
    required this.name,
    required this.recruiting,
    required this.category,
    required this.merchantCount,
    required this.finishTime,
  });

  final int id;
  final String name;
  final bool recruiting;
  final String category;
  final int merchantCount;

  /// 本章结束时间(`/api/topic/chapter/finish` 后的回读)。非空 = 已结束。
  final String finishTime;

  bool get finished => finishTime.isNotEmpty;

  String get recruitingText {
    if (!recruiting) return '未开放';
    final String cat = category.isEmpty ? '不限品类' : category;
    return '$cat · $merchantCount 家';
  }

  factory TopicSettingChapter.fromJson(Map<String, dynamic> json) {
    return TopicSettingChapter(
      id: asInt(json['chapterId']),
      name: asStr(json['name']),
      recruiting: asBool(json['recruiting']),
      category: asStr(json['category']),
      merchantCount: asInt(json['merchantCount']),
      finishTime: asStr(json['finishTime']),
    );
  }
}

/// 结束主题的回执:`POST /api/club/topic-setting/end` 的 data。
///
/// ⚠️ 后端是「先下架、再逐场取消并全额退款」,**一场一个事务**:
///   失败的那几场原样回包,已退掉的不会回滚。所以这里必须把三件事分开说 ——
///   只报「已结束」会让主理人以为钱全退干净了(小程序 endResultText 的理由)。
class TopicEndResult {
  const TopicEndResult({
    required this.refundedOrders,
    required this.manualOrders,
    required this.failedSessions,
  });

  final int refundedOrders;

  /// 含已核销票、退不掉、需要人工处理的整单数。
  final int manualOrders;
  final List<String> failedSessions;

  bool get hasFailures => failedSessions.isNotEmpty;

  /// 一句话回执。含人工单时人工单最要紧(小程序同序)。
  String get summaryText {
    if (manualOrders > 0) return '$manualOrders 笔需人工处理';
    if (refundedOrders > 0) return '已结束，退款 $refundedOrders 笔';
    return '已结束，无可退订单';
  }

  static TopicEndResult? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawFailed = raw['failedSessions'];
    return TopicEndResult(
      refundedOrders: asInt(raw['refundedOrders']),
      manualOrders: asInt(raw['manualOrders']),
      failedSessions: rawFailed is List
          ? rawFailed.map(asStr).where((String s) => s.isNotEmpty).toList()
          : const <String>[],
    );
  }
}

/// 俱乐部「开放设置」三个开关的当前值。
/// 值来自 `/api/club/detail` 的 `publicVisible / memberPostAllowed / merchantUndertakeOpen`
/// (0/1,小程序照 `!= 0` 读)。写入走 `/api/club/open-settings/*`,每写一个开关
/// **回读服务端给的值**再渲染 —— 界面上那个「已开启/已关闭」要么是库里的事实,
/// 要么是一条明说没保存成的错误,不作第三种。
class ClubOpenSettings {
  const ClubOpenSettings({
    required this.publicVisible,
    required this.memberPostAllowed,
    required this.merchantUndertakeOpen,
  });

  final bool publicVisible;
  final bool memberPostAllowed;
  final bool merchantUndertakeOpen;

  ClubOpenSettings copyWith({
    bool? publicVisible,
    bool? memberPostAllowed,
    bool? merchantUndertakeOpen,
  }) {
    return ClubOpenSettings(
      publicVisible: publicVisible ?? this.publicVisible,
      memberPostAllowed: memberPostAllowed ?? this.memberPostAllowed,
      merchantUndertakeOpen:
          merchantUndertakeOpen ?? this.merchantUndertakeOpen,
    );
  }

  /// 三个开关的字段名在后端各不相同(publicVisible / memberPostAllowed /
  /// merchantUndertakeOpen),回读时也只认自己那一个 —— 拿不到就是 null,不兜 false。
  static ClubOpenSettings? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    Object? pick(String key) => raw.containsKey(key) ? raw[key] : null;
    final Object? pub = pick('publicVisible');
    final Object? post = pick('memberPostAllowed');
    final Object? coop = pick('merchantUndertakeOpen');
    if (pub == null || post == null || coop == null) return null;
    return ClubOpenSettings(
      publicVisible: asInt(pub) != 0,
      memberPostAllowed: asInt(post) != 0,
      merchantUndertakeOpen: asInt(coop) != 0,
    );
  }

  static ClubOpenSettings fromClubJson(Map<String, dynamic> json) {
    return ClubOpenSettings(
      publicVisible: asInt(json['publicVisible']) != 0,
      memberPostAllowed: asInt(json['memberPostAllowed']) != 0,
      merchantUndertakeOpen: asInt(json['merchantUndertakeOpen']) != 0,
    );
  }
}

/// 单个开关的回读:`/api/club/open-settings/*` 各自只回自己那一个字段。
class ClubOpenSettingValue {
  const ClubOpenSettingValue({required this.key, required this.enabled});

  final String key;
  final bool enabled;

  static ClubOpenSettingValue? tryFromJson(String key, Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    if (!raw.containsKey(key)) return null;
    return ClubOpenSettingValue(key: key, enabled: asInt(raw[key]) != 0);
  }
}

/// 招商台一行(`POST /api/club/recruit/overview` 的 `nodes`)。
class RecruitOverviewNode {
  const RecruitOverviewNode({
    required this.nodeId,
    required this.merchantName,
    required this.stationName,
    required this.phone,
    required this.state,
  });

  final int nodeId;
  final String merchantName;
  final String stationName;

  /// ⚠️ 未确认的商家**回包里压根没有 phone 这个键**,不是前端藏起来。
  final String phone;

  /// `OPEN` 的站点是「还在招商」,不进已承接名单(小程序 buildMerchantRows 过滤)。
  final String state;

  bool get confirmed => phone.isNotEmpty;

  /// 屏幕上只露头尾;真号只在「商家已确认」时才下发。
  String get maskedPhone {
    final String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return '';
    return '${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
  }

  /// 没电话时说的是「还没确认」,**不是**「这家没留电话」(空串会被那样读)。
  String get contactText => phone.isEmpty ? '未确认，暂无联系方式' : maskedPhone;

  static RecruitOverviewNode? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final int nodeId = asInt(raw['nodeId']);
    if (nodeId <= 0) return null;
    return RecruitOverviewNode(
      nodeId: nodeId,
      merchantName: asStr(raw['merchantName']),
      stationName: asStr(raw['name']),
      phone: raw['phone'] is String ? (raw['phone'] as String).trim() : '',
      state: asStr(raw['state']),
    );
  }
}

/// `POST /api/club/recruit/overview` 的 data。
class RecruitOverview {
  const RecruitOverview({required this.nodes});

  final List<RecruitOverviewNode> nodes;

  /// 已承接(非 OPEN)的站点,按站点名稳定排序前的原始顺序保留。
  List<RecruitOverviewNode> get undertaken => nodes
      .where((RecruitOverviewNode n) => n.state != 'OPEN')
      .toList(growable: false);

  static RecruitOverview? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawNodes = raw['nodes'];
    if (rawNodes is! List) return null;
    return RecruitOverview(
      nodes: rawNodes
          .map(RecruitOverviewNode.tryFromJson)
          .whereType<RecruitOverviewNode>()
          .toList(growable: false),
    );
  }
}

/// 主题内成员名单的一行(`/api/club/crm/topic-customers` 的 sessions[].rows[])。
class TopicCustomerRow {
  const TopicCustomerRow({
    required this.key,
    this.nameMissing = false,
    this.timeMissing = false,
    required this.displayName,
    required this.timeText,
    required this.phoneText,
    required this.statusCode,
    required this.statusText,
  });

  final String key;
  final bool nameMissing;
  final bool timeMissing;
  final String displayName;

  /// 这一行属于哪一场(后端按场次分组,稿上是平铺 —— 时间落到每一行)。
  final String timeText;

  /// 由后端按权限决定给号码还是给替代说明,前端原样显示,不自己拼。
  final String phoneText;
  final String statusCode;
  final String statusText;

  String get initial => displayName.isEmpty ? '' : displayName.substring(0, 1);

  static TopicCustomerRow? tryFromJson(Object? raw, String fallbackKey) {
    if (raw is! Map<String, dynamic>) return null;
    final String name = asStr(raw['displayName']);
    final String key = asStr(raw['key']);
    return TopicCustomerRow(
      key: key.isEmpty ? fallbackKey : key,
      nameMissing: name.isEmpty,
      displayName: name.isEmpty ? '这位成员' : name,
      timeText: asStr(raw['timeText']),
      phoneText: asStr(raw['phoneText']),
      statusCode: asStr(raw['statusCode']),
      statusText: asStr(raw['statusText']),
    );
  }
}

/// 主题内成员名单:`POST /api/club/crm/topic-customers` 的 data。
class TopicCustomers {
  const TopicCustomers({
    required this.soldCount,
    required this.pendingCount,
    required this.verifiedCount,
    required this.rows,
  });

  /// 三个数是**全量口径**,不随筛选 chip 变(服务端在过滤前先数完)。
  final int soldCount;
  final int pendingCount;
  final int verifiedCount;
  final List<TopicCustomerRow> rows;

  List<({String text, String tone})> get stats =>
      <({String text, String tone})>[
        (text: '已售 $soldCount', tone: 'default'),
        (text: '待核销 $pendingCount', tone: 'warning'),
        (text: '已核销 $verifiedCount', tone: 'success'),
      ];

  static TopicCustomers? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawSessions = raw['sessions'];
    final List<TopicCustomerRow> rows = <TopicCustomerRow>[];
    if (rawSessions is List) {
      for (int s = 0; s < rawSessions.length; s++) {
        final Object? session = rawSessions[s];
        if (session is! Map<String, dynamic>) continue;
        final String timeText = asStr(session['timeText']);
        final Object? rawRows = session['rows'];
        if (rawRows is! List) continue;
        for (int r = 0; r < rawRows.length; r++) {
          final TopicCustomerRow? row = TopicCustomerRow.tryFromJson(
            rawRows[r],
            's$s-r$r',
          );
          if (row == null) continue;
          rows.add(
            TopicCustomerRow(
              key: row.key,
              nameMissing: row.nameMissing,
              timeMissing: row.timeText.isEmpty && timeText.isEmpty,
              displayName: row.displayName,
              timeText: row.timeText.isEmpty
                  ? (timeText.isEmpty ? '时间待定' : timeText)
                  : row.timeText,
              phoneText: row.phoneText,
              statusCode: row.statusCode,
              statusText: row.statusText,
            ),
          );
        }
      }
    }
    return TopicCustomers(
      soldCount: asInt(raw['soldCount']),
      pendingCount: asInt(raw['pendingCount']),
      verifiedCount: asInt(raw['verifiedCount']),
      rows: rows,
    );
  }
}

/// 主理人看答案:`POST /api/club/topic-node-answer` 的 data。
///
/// ★ 这条是治理专用端点(服务端 canGovernClub 校验),**不是**玩家侧
///   `/api/play/nodes` —— 那条揭示要 member_spoiler_reveal 且揭示即 0 分,
///   语义和权限都不是「主理人看答案」(小程序 topic-story 顶部注释)。
class TopicNodeAnswer {
  const TopicNodeAnswer({
    required this.question,
    required this.answerReveal,
    required this.hints,
    required this.feedbackText,
  });

  final String question;
  final String answerReveal;
  final List<String> hints;
  final String feedbackText;

  static TopicNodeAnswer? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawHints = raw['hints'];
    return TopicNodeAnswer(
      question: asStr(raw['question']),
      answerReveal: asStr(raw['answerReveal']),
      hints: rawHints is List
          ? rawHints
                .map(asStr)
                .map((String h) => h.trim())
                .where((String h) => h.isNotEmpty)
                .toList()
          : const <String>[],
      feedbackText: asStr(raw['feedbackText']),
    );
  }
}

/// 核验方式码表(小程序 `utils/validation-method-labels.js` 的唯一真源)。
/// 码 1 =「文字作答」是 2026-09-06 用户裁决的名字,别改回「文字暗号」。
const Map<int, String> kValidationMethodLabels = <int, String>{
  0: '无需验证',
  1: '文字作答',
  2: '拍照打卡',
  3: '选项问答',
  4: '到店扫码',
  5: 'GPS 到达',
  6: '偏好题组',
  7: '传感器挑战',
};

/// 没给码(null/空串)不是「无需验证」,是「还没配」—— 走 [fallback]。
String validationMethodLabel(Object? code, {String fallback = ''}) {
  if (code == null || code == '') return fallback;
  final int? parsed = int.tryParse('$code');
  if (parsed == null) return fallback;
  return kValidationMethodLabels[parsed] ?? fallback;
}

/// 只有这两类玩法才存在「答案」这回事(与后端
/// PuzzlePlayServiceImpl.selectPuzzleTemplate 同一判据);其余玩法卡退化成
/// 「看看模板」单键,徽标多挂一个「· 无答案」。
const List<int> kAnswerableValidationMethods = <int>[1, 3];

// ── 剧情与玩法的陈列行(小程序 `pages/club/topic-story` 的 buildChapters)──
//
// ★ 这里只做**陈列形状**:章节/站点/模板本身仍然是 `topic.dart` 的
//   `TopicChapter / TopicNode / TopicTemplate`(同一份公开投影),本层不重解析一遍 JSON。
//   分开的理由与小程序一致:陈列要的是「第几站」「走多久」「有没有答案」,
//   这几个数是页面算出来的,不是回执里的字段。

/// 步行速度 80m/min(≈4.8km/h)。接口没有逐段步行时长,只有站点经纬度,
/// 所以这里是直线距离估算 —— 拿不到坐标就整行不画(不编一个数字充数)。
const double kWalkMetersPerMinute = 80;

const List<String> _cnNumbers = <String>[
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '七',
  '八',
  '九',
  '十',
];

/// 章节标题:已经是「第X章…」就原样用,否则补一个中文序号。
String topicChapterTitle(String name, int index) {
  final String raw = name.trim();
  if (RegExp(r'^第.{1,3}章').hasMatch(raw)) return raw;
  final String ordinal = index < _cnNumbers.length
      ? _cnNumbers[index]
      : '${index + 1}';
  return raw.isEmpty ? '第$ordinal章' : '第$ordinal章 · $raw';
}

/// 时长文案:`3h 20min` / `3h` / `20min`;算不出来(<=0 / 非数)返回空串。
String topicDurationText(Object? minutes) {
  final num? value = minutes is num
      ? minutes
      : num.tryParse('${minutes ?? ''}');
  if (value == null || !value.isFinite || value <= 0) return '';
  final int n = value.toInt();
  final int h = n ~/ 60;
  final int m = n % 60;
  if (h > 0 && m > 0) return '${h}h ${m}min';
  if (h > 0) return '${h}h';
  return '${m}min';
}

/// 两站之间的步行估算。缺坐标 / 距离算不出来 → 空串(整行不画)。
String topicWalkText(Object? previous, Object? node) {
  double? number(Object? raw) =>
      raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
  if (previous is! Map<String, dynamic> || node is! Map<String, dynamic>) {
    return '';
  }
  final double? la1 = number(previous['latitude']);
  final double? lo1 = number(previous['longitude']);
  final double? la2 = number(node['latitude']);
  final double? lo2 = number(node['longitude']);
  if (la1 == null || lo1 == null || la2 == null || lo2 == null) return '';
  if (la1 == 0 || lo1 == 0 || la2 == 0 || lo2 == 0) return '';
  final double meters = _haversineMeters(la1, lo1, la2, lo2);
  if (!meters.isFinite || meters <= 0) return '';
  final int minutes = (meters / kWalkMetersPerMinute).round();
  return '${minutes < 1 ? 1 : minutes}min 步行';
}

double _haversineMeters(double la1, double lo1, double la2, double lo2) {
  const double r = 6371000;
  double rad(double x) => x * 3.1415926535897932 / 180;
  final double dLa = rad(la2 - la1);
  final double dLo = rad(lo2 - lo1);
  final double a =
      (sin(dLa / 2) * sin(dLa / 2)) +
      cos(rad(la1)) * cos(rad(la2)) * (sin(dLo / 2) * sin(dLo / 2));
  return 2 * r * asin(sqrt(a));
}

/// 路线时间轴上的一站。
class TopicStoryStop {
  const TopicStoryStop({
    required this.id,
    required this.seq,
    required this.time,
    required this.name,
    required this.address,
    required this.cover,
    required this.walkText,
  });

  final String id;
  final int seq;
  final String time;
  final String name;
  final String address;
  final String cover;
  final String walkText;
}

/// 玩法卡。
class TopicStoryPlay {
  const TopicStoryPlay({
    required this.nodeId,
    required this.templateId,
    required this.title,
    required this.badge,
    required this.cover,
    required this.hasAnswer,
    required this.meta,
  });

  final int nodeId;
  final int templateId;
  final String title;

  /// 核验方式标签;不可作答的玩法多挂一个「· 无答案」(稿 J1-B 卡2)。
  final String badge;
  final String cover;
  final bool hasAnswer;

  /// `第 3 站 古城墙 · 2 人 · 20 分钟 · 难度轻松`。
  final String meta;
}

class TopicStoryChapter {
  const TopicStoryChapter({
    required this.id,
    required this.title,
    required this.meta,
    required this.story,
    required this.stops,
    required this.plays,
  });

  final int id;
  final String title;

  /// `3h 20min · 5 站`;没有站点时是「未开放 · 待招商」。
  final String meta;
  final String story;
  final List<TopicStoryStop> stops;
  final List<TopicStoryPlay> plays;
}

String _joinMeta(List<String> parts) => parts
    .map((String p) => p.trim())
    .where((String p) => p.isNotEmpty)
    .join(' · ');

/// 把公开投影的章节树摊成两页要的陈列行(序号跨章节连续,与小程序 buildChapters 同)。
List<TopicStoryChapter> buildTopicStoryChapters(List<TopicChapter> chapters) {
  final List<TopicStoryChapter> out = <TopicStoryChapter>[];
  int seq = 0;
  for (
    int chapterIndex = 0;
    chapterIndex < chapters.length;
    chapterIndex += 1
  ) {
    final TopicChapter chapter = chapters[chapterIndex];
    final List<TopicStoryStop> stops = <TopicStoryStop>[];
    final List<TopicStoryPlay> plays = <TopicStoryPlay>[];
    for (int nodeIndex = 0; nodeIndex < chapter.nodes.length; nodeIndex += 1) {
      final TopicNode node = chapter.nodes[nodeIndex];
      seq += 1;
      final String cover = node.images.isNotEmpty ? node.images.first : '';
      stops.add(
        TopicStoryStop(
          id: '${node.id}',
          seq: seq,
          time: (node.businessTime ?? '').trim(),
          name: node.name.trim(),
          address: (node.address ?? '').trim(),
          cover: cover,
          // 只有章内第 2 站起才画步行段:第 1 站没有「上一站」。
          walkText: nodeIndex == 0
              ? ''
              : topicWalkText(
                  <String, dynamic>{
                    'latitude': chapter.nodes[nodeIndex - 1].latitude,
                    'longitude': chapter.nodes[nodeIndex - 1].longitude,
                  },
                  <String, dynamic>{
                    'latitude': node.latitude,
                    'longitude': node.longitude,
                  },
                ),
        ),
      );

      final TopicTemplate? tpl = node.template;
      if (tpl == null) continue;
      final int? method = tpl.validationMethod;
      final bool hasAnswer =
          method != null && kAnswerableValidationMethods.contains(method);
      final String label = validationMethodLabel(
        method,
        fallback: (tpl.validationMethodStr ?? '').trim(),
      );
      final String resolved = label.isEmpty ? '玩法' : label;
      plays.add(
        TopicStoryPlay(
          nodeId: node.id,
          templateId: tpl.id,
          title: tpl.title.trim().isEmpty ? node.name.trim() : tpl.title.trim(),
          badge: hasAnswer ? resolved : '$resolved · 无答案',
          cover: (tpl.imgUrl ?? '').trim().isEmpty
              ? cover
              : (tpl.imgUrl ?? '').trim(),
          hasAnswer: hasAnswer,
          meta: _joinMeta(<String>[
            '第 $seq 站 ${node.name.trim()}',
            (tpl.players ?? '').trim(),
            tpl.duration == null ? '' : '${tpl.duration} 分钟',
            (tpl.difficulty ?? '').trim().isEmpty
                ? ''
                : '难度${(tpl.difficulty ?? '').trim()}',
          ]),
        ),
      );
    }
    final String duration = topicDurationText(chapter.totalTime);
    out.add(
      TopicStoryChapter(
        id: chapter.id,
        title: topicChapterTitle(chapter.title, chapterIndex),
        meta: stops.isEmpty
            ? '未开放 · 待招商'
            : _joinMeta(<String>[duration, '${stops.length} 站']),
        story: (chapter.description ?? '').trim(),
        stops: stops,
        plays: plays,
      ),
    );
  }
  return out;
}
