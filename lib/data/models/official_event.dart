import 'dart:convert';

/// 官方活动。对齐后端 `OfficialEventServiceImpl.baseVo` + `detail` + V2 契约。
///
/// 字段名逐个核过后端 put 的 key,不是照小程序模板猜的。
class OfficialEvent {
  const OfficialEvent({
    required this.id,
    required this.title,
    this.subtitle,
    this.coverImg,
    this.city,
    this.status = 0,
    this.story,
    this.rewardJson,
    this.participants = 0,
    this.myProgress = 0,
    this.signed = false,
    this.roamEnabled = false,
    this.paused = false,
    this.pausedReason,
    this.eligible = false,
    this.contractVersion,
    this.activityStart,
    this.activityEnd,
    this.bannerEnabled = false,
    this.participantAvatars = const <String>[],
    this.missions = const <OfficialMission>[],
    this.collective,
  });

  final int id;
  final String title;
  final String? subtitle;
  final String? coverImg;
  final String? city;
  final int status;
  final String? story;
  final String? rewardJson;
  final int participants;
  final int myProgress;
  final bool signed;

  /// 是否绑定「点亮城市」漫游玩法(后端 `isRoamBound`:content_json.roam 或 play_type=roam)。
  final bool roamEnabled;
  final bool paused;
  final String? pausedReason;
  final bool eligible;
  final int? contractVersion;
  final DateTime? activityStart;
  final DateTime? activityEnd;

  /// 运营的「首页城市事件 banner」开关(真源 `pages/square/list/index.js:684`
  /// 读的就是后端直出的这个字段,不是客户端算的)。
  /// ★ 广场的「即将开始」横滑卡用它当第一道闸 —— 不另造一套推广位判断。
  final bool bannerEnabled;

  /// 参与者头像(可缺省:后端不给就是空数组,不伪造头像堆)。
  /// 真源 `pages/square/list/index.js:697` 同样先判 `Array.isArray` 再逐个过滤。
  final List<String> participantAvatars;
  final List<OfficialMission> missions;
  final CollectiveProgress? collective;

  /// V2 契约:只认服务端验证过的事实,不做「旧进度加一」。
  /// 小程序 `isV2(e)` 的判据是 contractVersion >= 2。
  bool get isV2 => (contractVersion ?? 1) >= 2;

  int get taskDone => missions.where((OfficialMission m) => m.complete).length;
  int get taskTotal => missions.length;

  String get eligibleText => eligible ? '已满足资格' : '完成全部任务后获得资格';

  factory OfficialEvent.fromJson(Map<String, dynamic> json) {
    return OfficialEvent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      subtitle: json['subtitle'] as String?,
      coverImg: json['coverImg'] as String?,
      city: json['city'] as String?,
      status: (json['status'] as num?)?.toInt() ?? 0,
      story: json['story'] as String?,
      rewardJson: json['rewardJson'] as String?,
      participants: (json['participants'] as num?)?.toInt() ?? 0,
      myProgress: (json['myProgress'] as num?)?.toInt() ?? 0,
      signed: json['signed'] == true,
      roamEnabled: json['roamEnabled'] == true,
      paused: json['paused'] == true,
      pausedReason: json['pausedReason'] as String?,
      eligible: json['eligible'] == true,
      contractVersion: (json['contractVersion'] as num?)?.toInt(),
      activityStart: _parseTime(json['activityStart']),
      activityEnd: _parseTime(json['activityEnd']),
      bannerEnabled: _flag(json['bannerEnabled']),
      participantAvatars:
          ((json['participantAvatars'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<String>()
              .where((String url) => url.trim().isNotEmpty)
              .toList(growable: false),
      missions: ((json['missions'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(OfficialMission.fromJson)
          .toList(),
      collective: json['collective'] is Map<String, dynamic>
          ? CollectiveProgress.fromJson(
              json['collective'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// 后端布尔:`1/true/'1'` 都当开。真源判的是 `Number(x) !== 1`,
/// 这里放宽到三种写法 —— 同一个后端在不同端点用过这三种。
bool _flag(Object? raw) => raw == true || raw == 1 || raw == '1';

/// 后端时间可能是字符串也可能是毫秒时间戳,两种都收。
DateTime? _parseTime(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }
  return null;
}

class OfficialMission {
  const OfficialMission({
    required this.missionCode,
    required this.title,
    this.description,
    this.missionType,
    this.complete = false,
    this.canVerifyArrival = false,
  });

  final String missionCode;
  final String title;
  final String? description;
  final String? missionType;
  final bool complete;
  final bool canVerifyArrival;

  /// 右侧动作文案。三态:已验证 / 去验证 / 自动同步。
  String get actionText =>
      complete ? '已验证' : (canVerifyArrival ? '去验证' : '自动同步');

  factory OfficialMission.fromJson(Map<String, dynamic> json) {
    return OfficialMission(
      missionCode: (json['missionCode'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      missionType: json['missionType'] as String?,
      complete: json['complete'] == true,
      canVerifyArrival: json['canVerifyArrival'] == true,
    );
  }
}

class OfficialArrivalResult {
  const OfficialArrivalResult({
    required this.accepted,
    required this.completed,
    this.reason,
  });

  final bool accepted;
  final bool completed;
  final String? reason;

  factory OfficialArrivalResult.fromJson(Map<String, dynamic> json) {
    return OfficialArrivalResult(
      accepted: json['accepted'] == true,
      completed: json['completed'] == true,
      reason: json['reason']?.toString(),
    );
  }
}

/// 集体进度(全城已点亮 X%)。
class CollectiveProgress {
  const CollectiveProgress({
    this.enabled = false,
    this.current = 0,
    this.threshold = 0,
    this.pct = 0,
    this.reached = false,
  });

  final bool enabled;
  final int current;
  final int threshold;
  final int pct;
  final bool reached;

  factory CollectiveProgress.fromJson(Map<String, dynamic> json) {
    return CollectiveProgress(
      enabled: json['enabled'] == true,
      current: (json['current'] as num?)?.toInt() ?? 0,
      threshold: (json['threshold'] as num?)?.toInt() ?? 0,
      pct: (json['pct'] as num?)?.toInt() ?? 0,
      reached: json['reached'] == true,
    );
  }
}

/// 底部主按钮该显示什么、点下去做什么。
enum OfficialCtaType {
  /// 报名。
  signup,

  /// 去漫游/点亮城市。
  roam,

  /// 去探索完成任务(非漫游的旧契约)。
  explore,

  /// 等待中 —— **不可点**。
  wait,

  /// 活动已结束 —— **不可点**。
  ended,
}

class OfficialCta {
  const OfficialCta(this.text, this.type);
  final String text;
  final OfficialCtaType type;

  /// 能不能点。★ 这条独立于文案:`wait` / `ended` 一律不可点,
  ///   否则就是「按钮点下去必报错」——本项目反复出现的那类缺陷。
  bool get enabled =>
      type != OfficialCtaType.wait && type != OfficialCtaType.ended;
}

/// 官方活动底部主按钮的状态机。移植自小程序 `official-detail/index.js:_cta`。
///
/// ★ 分支顺序有意义,不能重排:
///   已结束 > 已暂停 > 已报名(再按 V2/漫游细分) > 未报名。
///   把「已暂停」放到「已报名」后面,暂停中的已报名用户会看到「去点亮」并点出错。
OfficialCta officialEventCta(OfficialEvent e) {
  if (e.status >= 5) return const OfficialCta('活动已结束', OfficialCtaType.ended);
  if (e.paused) return const OfficialCta('活动已暂停', OfficialCtaType.wait);
  if (e.signed) {
    if (e.status == 3 && e.isV2) {
      if (e.missions.any((OfficialMission m) => m.canVerifyArrival)) {
        return const OfficialCta('去漫游 · 验证到达', OfficialCtaType.roam);
      }
      if (e.missions.any(
        (OfficialMission m) => m.missionType == 'THEME_VERIFIED_FINISH',
      )) {
        return const OfficialCta('完成绑定主题后自动同步', OfficialCtaType.wait);
      }
      return const OfficialCta('等待可验证任务', OfficialCtaType.wait);
    }
    if (e.status == 3) {
      return e.roamEnabled
          ? const OfficialCta('去点亮 · 点亮城市', OfficialCtaType.roam)
          : const OfficialCta('去探索 · 完成任务', OfficialCtaType.explore);
    }
    if (e.status == 1) {
      return const OfficialCta('已报名 · 待开始', OfficialCtaType.wait);
    }
    return const OfficialCta('已报名', OfficialCtaType.wait);
  }
  if (e.status == 2 || e.status == 3) {
    return const OfficialCta('立即报名', OfficialCtaType.signup);
  }
  if (e.status == 1) return const OfficialCta('报名即将开放', OfficialCtaType.wait);
  return const OfficialCta('暂不可报名', OfficialCtaType.wait);
}

/// rewardJson 解析。解析失败一律当空(后台填错 JSON 不该让详情页整页挂掉)。
Map<String, dynamic> _rewardMap(OfficialEvent e) {
  Map<String, dynamic> rw = const <String, dynamic>{};
  final raw = e.rewardJson;
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) rw = decoded;
    } catch (_) {
      // 后台填了非法 JSON。吞掉 —— 下面按"没配奖励"处理。
    }
  }
  return rw;
}

/// 奖励标签。
///
/// ★★ **没配就是空**。小程序 F22 的裁决原文:「只展示后端 rewardJson 里真实配置的奖励;
///   没有配置就如实说明,**不摆默认承诺**」。App 原来兜底成「🏅 参与即有惊喜」——
///   主办方一个字都没配,页面却替它许了一个奖,而结算时发不出来。
List<String> officialEventRewards(OfficialEvent e) {
  final rw = _rewardMap(e);
  final out = <String>[];
  if (rw['settleBadge'] != null) out.add('🏅 限定徽章');
  if (rw['settleCouponId'] != null) out.add('🎟 专属券');
  if (rw['settleXp'] != null) out.add('✨ ${rw['settleXp']} 成长值');
  if (rw['collectiveCouponId'] != null) out.add('🎉 集体达标全员奖');
  return out;
}

/// 是否配置了**可用的集体券** —— 决定集体进度区能不能承诺「达标后发放」。
/// 真源 `official-detail/index.js:hasCollectiveReward`(rewardJson.collectiveCouponId 为正整数)。
bool officialEventHasCollectiveReward(OfficialEvent e) {
  final Object? couponId = _rewardMap(e)['collectiveCouponId'];
  if (couponId is num) return couponId > 0;
  if (couponId is String) return (int.tryParse(couponId) ?? 0) > 0;
  return false;
}

/// 倒计时文案。status=1 倒计到开始,status=2/3 倒计到结束,其余无。
/// 传入 now 而不是内部取 —— 否则测不了(本项目栽过时区/当前时间不可控的坑)。
String officialEventCountdown(OfficialEvent e, DateTime now) {
  if (e.status == 1 && e.activityStart != null) {
    final d = e.activityStart!.difference(now);
    return d.isNegative ? '' : '距开始 ${_dur(d)}';
  }
  if ((e.status == 2 || e.status == 3) && e.activityEnd != null) {
    final d = e.activityEnd!.difference(now);
    return d.isNegative ? '' : '距结束 ${_dur(d)}';
  }
  return '';
}

/// 活动状态文案。真源 `activityStatusText` —— 详情页海报角标与「活动范围」副行
/// 用的是同一份,别再各写一套。
String officialEventStatusText(int status) {
  if (status == 1) return '即将开始';
  if (status == 2) return '报名中';
  if (status == 3) return '进行中';
  if (status >= 5) return '已结束';
  return '结算中';
}

/// 活动周期(总时长)。真源 `official-detail/index.js:_durationText`:
/// 不足一天按小时向上取整,满一天按天向上取整;两头缺一个就是「待公布」。
String officialEventDurationText(OfficialEvent e) {
  final DateTime? start = e.activityStart;
  final DateTime? end = e.activityEnd;
  if (start == null || end == null) return '待公布';
  final int ms = end.difference(start).inMilliseconds;
  if (ms <= 0) return '待公布';
  if (ms >= 86400000) return '${_ceilDiv(ms, 86400000)}天';
  return '${_ceilDiv(ms, 3600000)}小时';
}

/// 开放时间。真源 `_dateRange`:`M.D–M.D`;只有一头就写一头,两头都没有
/// 「待公布」(不编一个不存在的日期)。
String officialEventDateRange(OfficialEvent e) {
  final String start = _datePart(e.activityStart);
  final String end = _datePart(e.activityEnd);
  if (start.isNotEmpty && end.isNotEmpty) return '$start–$end';
  if (start.isNotEmpty) return start;
  if (end.isNotEmpty) return end;
  return '待公布';
}

String _datePart(DateTime? value) =>
    value == null ? '' : '${value.month}月${value.day}日';

int _ceilDiv(int value, int unit) {
  final int n = (value / unit).ceil();
  return n < 1 ? 1 : n;
}

String _dur(Duration d) {
  final h = d.inHours;
  if (h >= 24) return '${d.inDays} 天';
  if (h >= 1) return '$h 小时';
  // 不足一分钟也说「1 分钟」,不说「0 分钟」。
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} 分钟';
}

/// 承接方对官方活动邀约的处置动作。
///
/// ★ 值是**路径的一段**(`/v2/parties/{partyId}/{action}`),不是 body 字段;
///   后端 `equalsIgnoreCase` 比对,拼错走进 `"未知邀约动作"`,不是 404。
///
/// ★★ 每个动作都有**前置状态**要求,后端会拒:
///   · ACCEPT / DECLINE:只有 `INVITED` 能做,否则「当前邀约不可接受/拒绝」;
///   · WITHDRAW:只有 `ACCEPTED` 或 `ACTIVE` 能做,否则「当前邀约不可退出」。
///   ⇒ 界面按当前状态**只露可做的那几个按钮**;三个全摆出来的话,
///     用户点到的多半是必然报错的那个。
enum OfficialPartyAction {
  accept('ACCEPT'),
  decline('DECLINE'),
  withdraw('WITHDRAW');

  const OfficialPartyAction(this.wire);
  final String wire;

  /// 该动作在当前状态下是否可做。状态取值见 `OfficialEventParty.STATUS_*`。
  ///
  /// ⚠️ 这是**前端的礼貌**,不是权威 —— 权威在后端。
  ///   前端算错只会多显示一个按钮,不会真的越权。
  bool allowedFrom(String? status) {
    switch (this) {
      case OfficialPartyAction.accept:
      case OfficialPartyAction.decline:
        return status == 'INVITED';
      case OfficialPartyAction.withdraw:
        return status == 'ACCEPTED' || status == 'ACTIVE';
    }
  }

  /// 当前状态下可做的动作。
  static List<OfficialPartyAction> availableFor(String? status) =>
      OfficialPartyAction.values
          .where((OfficialPartyAction a) => a.allowedFrom(status))
          .toList();
}
