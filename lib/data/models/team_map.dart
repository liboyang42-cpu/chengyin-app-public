// 地图组队 P 方案(漫游「附近的队伍」)的卡片状态机 / 文案 / errorCode 分支。
//
// ★ 真源 = 小程序只读快照 master@90e66d70:
//     utils/map-team.js                 纯函数(本文件逐条直译)
//     tests/unit/map-team.test.js        纯函数契约
//     tests/unit/map-team-page-contract.test.js  页面接线契约
//     subpackageRoam/nearby/index.js     页面实现(接口形态)
//   App 侧不发明新规则:按钮文案 / patch / 兜底标题 / 去重顺序都照抄快照,
//   两边对拍时能一眼看出是谁漂了。
//   例外:申请失效时刻(expireLeft / applyExpireTime)与 P5 留言展示是后补的
//   追平项 —— 真源 github/master@a7d179760 `subpackageRoam/utils/map-team.js`
//   (契约 tests/unit/apply-expire-contract.test.js;真实失效 = min(申请+24h,
//   场次开始),文案禁止断言固定小时数)。
//
// ⚠️ 两条纪律(与快照一致):
//   ① 失败**只认 errorCode**,不解析 msg —— msg 只原样当失败原因展示
//      (快照契约专门钉了「文案里写了 TEAM_FULL 不算数」)。
//   ② 队伍私密字段(inviteCode / leaderMemberId / ownerType)一律不进视图:
//      [decorateTeam] / [myTeamRows] 只白名单取字段。

/// 范围档位(米)。快照 `utils/map-team.js` RADII。
const List<int> kTeamRadiusOptions = <int>[1000, 3000, 5000, 10000, 20000];

/// viewerStatus 的合法值。快照 STATUSES。
const List<String> kTeamViewerStatuses = <String>[
  'NONE',
  'PENDING',
  'JOINED',
  'LEADER',
  'REJECTED',
];

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String _text(Object? value) => value?.toString().trim() ?? '';

/// 距离的人话:≥1 km 用一位小数,否则整米。快照 `km()`。
String teamFmtKm(Object? meters) {
  final double n = _double(meters) ?? 0;
  if (n >= 1000) {
    final double value = (n / 100).round() / 10;
    // JS `1.5 + ' km'` / `3 + ' km'` —— 整数不带 `.0`,照抄。
    final String text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    return '$text km';
  }
  return '${n.round()} m';
}

/// viewerStatus,未知值按最保守的 NONE(不误判成队长)。快照 `statusOf()`。
String teamStatusOf(Map<String, dynamic>? team) {
  final String status = _text(team?['viewerStatus']);
  return kTeamViewerStatuses.contains(status) ? status : 'NONE';
}

/// 把服务端下发的时刻解析成 epoch 毫秒;解析不出来返回 null(不猜时刻)。
/// 快照 `datetime.js toTimestamp()` 的收敛口径:正数 / 纯数字串按 epoch 毫秒,
/// 10 位秒统一 ×1000;「yyyy-MM-dd HH:mm:ss」与 [teamAppliedAgo] 同一约定(设备日历)。
int? _teamEpochMs(Object? value) {
  if (value == null) return null;
  if (value is num) {
    if (!value.isFinite || value == 0) return null;
    final int n = value.toInt();
    if (n < 0) return n;
    return n > 0 && '$n'.length == 10 ? n * 1000 : n;
  }
  final String str = '$value'.trim();
  if (str.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(str)) {
    final int? digits = int.tryParse(str);
    if (digits == null || digits == 0) return null;
    if (str.length == 10) return digits * 1000;
    if (str.length == 13) return digits;
    return null;
  }
  final RegExpMatch? m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$',
  ).firstMatch(str);
  if (m != null) {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6) ?? '0'),
    ).millisecondsSinceEpoch;
  }
  return DateTime.tryParse(str)?.millisecondsSinceEpoch;
}

/// 「N 分钟 / N 小时」的剩余时刻人话 —— 快照 `expireLeft()`:真实失效 =
/// min(申请+24h, 场次开始),**由服务端 applyExpireTime 定夺**;
/// 拿不到或已过期 → ''(调用方兜底通用规则句,不许断言固定小时数)。
String teamExpireLeft(Object? applyExpireTime, DateTime now) {
  final int? at = _teamEpochMs(applyExpireTime);
  if (at == null) return '';
  final int diffMs = at - now.millisecondsSinceEpoch;
  if (diffMs <= 0) return '';
  final int min = diffMs ~/ 60000;
  if (min < 1) return '1 分钟';
  if (min < 60) return '$min 分钟';
  return '${min ~/ 60} 小时';
}

/// 队伍名兜底。快照 `teamName()`。
String teamDisplayName(Map<String, dynamic>? team) {
  final String title = _text(team?['title']);
  return title.isEmpty ? '玩家队伍' : title;
}

String teamHeaderText(int count) => '附近的队伍 · $count 支在招募';

String teamRangeText(Object? meters) => '范围 ${teamFmtKm(meters)}';

/// 下一档范围(到顶回卷)。快照 `nextRadius()`。
int teamNextRadius(Object? meters) {
  final int? current = _int(meters);
  final int index = current == null ? -1 : kTeamRadiusOptions.indexOf(current);
  return kTeamRadiusOptions[(index + 1) % kTeamRadiusOptions.length];
}

String teamMyTeamsText(int count) => count > 0 ? '我的队伍 · $count' : '我的队伍';

class TeamCardButton {
  const TeamCardButton({required this.text, required this.action});

  final String text;

  /// buy / apply / enter / withdraw —— 页面对它做接线,不做猜测。
  final String action;
}

class TeamCardNotice {
  const TeamCardNotice({required this.tone, required this.text});

  /// ok / wait / bad / plain —— 状态不只靠颜色(V5):文案本身也带 ✓ ◷ 这类形状。
  final String tone;
  final String text;
}

class TeamCardState {
  const TeamCardState({
    required this.mode,
    this.notice,
    this.primary,
    this.secondary,
    this.foot = '',
  });

  /// leader / joined / pending / rejected / apply / buy。
  final String mode;
  final TeamCardNotice? notice;
  final TeamCardButton? primary;
  final TeamCardButton? secondary;
  final String foot;
}

/// P2/P3/P4/P5/被拒/已加入 → 卡片该出什么。快照 `teamCardState()`,
/// 优先级 **LEADER > JOINED > PENDING > REJECTED > 有票申请 > 去购票**。
TeamCardState teamCardState(Map<String, dynamic>? team, {DateTime? now}) {
  final String status = teamStatusOf(team);
  if (status == 'LEADER') {
    return const TeamCardState(mode: 'leader');
  }
  if (status == 'JOINED') {
    return const TeamCardState(
      mode: 'joined',
      notice: TeamCardNotice(tone: 'ok', text: '✓ 你已在这支队伍里'),
      primary: TeamCardButton(text: '进入队伍', action: 'enter'),
    );
  }
  if (status == 'PENDING') {
    final String left = teamExpireLeft(
      team?['applyExpireTime'],
      now ?? DateTime.now(),
    );
    return TeamCardState(
      mode: 'pending',
      notice: TeamCardNotice(tone: 'wait', text: '◷ 已申请 · 等队长同意'),
      secondary: TeamCardButton(text: '撤回申请', action: 'withdraw'),
      foot: left.isEmpty
          ? '队长没处理或活动开始时,申请自动失效'
          : '队长没处理的话,申请 $left后自动失效',
    );
  }
  if (status == 'REJECTED') {
    // 被拒就是被拒:一个按钮都不出(24h 失效的是 PENDING,不是 REJECTED)。
    return const TeamCardState(
      mode: 'rejected',
      notice: TeamCardNotice(tone: 'bad', text: '不能再申请这支队伍'),
    );
  }
  if (team?['viewerHasTicket'] == true) {
    return const TeamCardState(
      mode: 'apply',
      notice: TeamCardNotice(tone: 'ok', text: '✓ 你已持有这一场的票'),
      primary: TeamCardButton(text: '申请加入', action: 'apply'),
      foot: '队长同意后,你会自动进入这支队伍的群聊',
    );
  }
  return const TeamCardState(
    mode: 'buy',
    notice: TeamCardNotice(tone: 'plain', text: '加入队伍需要先持有这一场的票'),
    primary: TeamCardButton(text: '去买这场的票', action: 'buy'),
    foot: '买完回到地图,这张卡会变成「申请加入」',
  );
}

/// nearby 一行 → 卡片视图。快照 `decorateTeam()`,白名单取字段。 [].
class TeamNearbyCard {
  const TeamNearbyCard({
    required this.teamId,
    required this.activityId,
    required this.topicId,
    required this.name,
    required this.heading,
    required this.sub,
    required this.membersLine,
    required this.faces,
    required this.plate,
    required this.joinedCount,
    required this.maxMembers,
    required this.viewerStatus,
    required this.viewerHasTicket,
    required this.latitude,
    required this.longitude,
    required this.card,
  });

  final int? teamId;
  final int? activityId;
  final int? topicId;
  final String name;

  /// 活动名(有就压过队伍名当大标题)。快照 `heading`。
  final String heading;
  final String sub;
  final String membersLine;

  /// 最多 3 个头像 URL(空白已滤)。快照 `faces`。
  final List<String> faces;
  final String plate;
  final int joinedCount;
  final int maxMembers;
  final String viewerStatus;
  final bool viewerHasTicket;
  final double? latitude;
  final double? longitude;
  final TeamCardState card;
}

TeamNearbyCard decorateTeam(Map<String, dynamic> team, {DateTime? now}) {
  final String status = teamStatusOf(team);
  final int joined = _int(team['joinedCount']) ?? 0;
  final int max = _int(team['maxMembers']) ?? 0;
  final int left = (max - joined) > 0 ? (max - joined) : 0;
  final String name = teamDisplayName(team);
  final bool free = _int(team['productType']) == 2;
  final String address = _text(team['addressName']);
  final String place = address.isEmpty
      ? ''
      : address + (_text(team['coordSource']) == 'GATHER' ? '集合' : '附近');
  final String distance = team['distance'] == null
      ? ''
      : '距你 ${teamFmtKm(team['distance'])}';
  final int pending = _int(team['pendingCount']) ?? 0;

  final String plate = status == 'LEADER'
      ? '我的队伍 · $pending 人申请'
      : status == 'PENDING'
      ? '$name · 申请中'
      : '$name · $joined/$max';

  return TeamNearbyCard(
    teamId: _int(team['teamId']),
    activityId: _int(team['activityId']),
    topicId: _int(team['topicId']),
    name: name,
    heading: _text(team['activityName']).isEmpty
        ? name
        : _text(team['activityName']),
    sub: <String>[
      free ? '自由探索' : '城市定向',
      place,
      distance,
    ].where((String s) => s.isNotEmpty).join(' · '),
    membersLine: <String>[
      '队长 ${_text(team['leaderName']).isEmpty ? '玩家' : _text(team['leaderName'])}',
      '已组 $joined 人',
      left > 0 ? '还差 $left 人满员' : '已满员',
    ].join(' · '),
    faces: (team['memberAvatars'] is List ? team['memberAvatars'] as List<dynamic> : const <dynamic>[])
        .map((dynamic e) => _text(e))
        .where((String s) => s.isNotEmpty)
        .take(3)
        .toList(),
    plate: plate,
    joinedCount: joined,
    maxMembers: max,
    viewerStatus: status,
    viewerHasTicket: team['viewerHasTicket'] == true,
    latitude: _double(team['latitude']),
    longitude: _double(team['longitude']),
    card: teamCardState(team, now: now),
  );
}

class _TeamErrorRule {
  const _TeamErrorRule({
    this.title = '',
    this.why = '',
    this.dropTeam = false,
    this.dropApplicant = false,
    this.refresh = false,
    this.primary = '',
    this.secondary = '',
    this.primaryAction = '',
  });

  final String title;
  final String why;
  final bool dropTeam;
  final bool dropApplicant;
  final bool refresh;
  final String primary;
  final String secondary;
  final String primaryAction;
}

class _TeamErrorPatchRule extends _TeamErrorRule {
  const _TeamErrorPatchRule({
    required this.patch,
    super.title,
    super.primary,
    super.secondary,
    super.primaryAction,
  });

  final Map<String, Object?> patch;
}

/// 满员 / 进行中 / 审核中:队伍从地图上消失。快照 GONE。
const _TeamErrorRule _kTeamGone = _TeamErrorRule(
  dropTeam: true,
  title: '这支队伍现在申请不了',
  why: '队伍已满、活动已开始或正在审核,地图上已经刷新',
);

const Map<String, Map<String, _TeamErrorRule>> _kTeamErrors =
    <String, Map<String, _TeamErrorRule>>{
      'apply': <String, _TeamErrorRule>{
        'TICKET_REQUIRED': _TeamErrorPatchRule(
          title: '要先买这一场的票',
          patch: <String, Object?>{
            'viewerHasTicket': false,
            'viewerStatus': 'NONE',
          },
          primary: '去买票',
          secondary: '先不买',
          primaryAction: 'buy',
        ),
        'APPLY_REJECTED': _TeamErrorPatchRule(
          title: '不能再申请这支队伍',
          patch: <String, Object?>{'viewerStatus': 'REJECTED'},
        ),
        'APPLY_PENDING': _TeamErrorPatchRule(
          title: '你已经申请过了',
          patch: <String, Object?>{'viewerStatus': 'PENDING'},
        ),
        'ALREADY_JOINED': _TeamErrorPatchRule(
          title: '你已在这支队伍里',
          patch: <String, Object?>{'viewerStatus': 'JOINED'},
        ),
        'TEAM_FULL': _kTeamGone,
        'ACTIVITY_STARTED': _kTeamGone,
        'TEAM_UNDER_REVIEW': _kTeamGone,
        'TEAM_NOT_PUBLIC': _TeamErrorRule(
          dropTeam: true,
          title: '这支队伍只接受邀请',
          why: '队长已把它改成邀请制,地图上已经刷新',
        ),
        'APPLY_BLOCKED': _TeamErrorRule(title: '暂时不能申请这支队伍'),
      },
      'withdraw': <String, _TeamErrorRule>{
        'APPLY_NOT_PENDING': _TeamErrorRule(
          title: '这条申请已经处理或失效',
          refresh: true,
        ),
      },
      'handle': <String, _TeamErrorRule>{
        'APPLY_NOT_PENDING': _TeamErrorRule(
          title: '这条申请已经处理或失效',
          dropApplicant: true,
        ),
        'TICKET_REQUIRED': _TeamErrorRule(
          title: '对方已经退票',
          dropApplicant: true,
        ),
        'TEAM_FULL': _TeamErrorRule(title: '队伍已经满员', refresh: true),
        'APPLY_BLOCKED': _TeamErrorRule(
          title: '不能同意这条申请',
          dropApplicant: true,
        ),
      },
    };

const Map<String, String> _kTeamFallbackTitle = <String, String>{
  'apply': '申请没发出去',
  'withdraw': '撤回没成功',
  'handle': '处理没成功',
  'my': '我的队伍没读到',
  'applications': '申请列表没读到',
};

/// 失败 → 界面该怎么改 + 失败半屏画什么。快照 `resolveTeamError()`。 [].
class TeamErrorOutcome {
  const TeamErrorOutcome({
    required this.title,
    required this.why,
    this.patch,
    this.dropTeam = false,
    this.dropApplicant = false,
    this.refresh = false,
    this.primary = '',
    this.secondary = '',
    this.primaryAction = '',
  });

  final String title;
  final String why;

  /// 卡片要打的补丁(viewerStatus / viewerHasTicket)。null = 不动卡片。
  final Map<String, Object?>? patch;

  /// 把该队从列表里拿掉(满员 / 开场 / 审核中 / 邀请制)。
  final bool dropTeam;
  final bool dropApplicant;
  final bool refresh;
  final String primary;
  final String secondary;
  final String primaryAction;
}

TeamErrorOutcome resolveTeamError(String op, Map<String, dynamic>? res) {
  final String code = _text(res?['errorCode']);
  final _TeamErrorRule? hit = code.isEmpty ? null : _kTeamErrors[op]?[code];
  final String msg = _text(res?['msg']);
  final String fallbackTitle = _kTeamFallbackTitle[op] ?? '操作没成功';
  final String why = hit != null && hit.why.isNotEmpty
      ? hit.why
      : (msg.isNotEmpty ? msg : '请稍后再试');
  return TeamErrorOutcome(
    title: hit != null && hit.title.isNotEmpty ? hit.title : fallbackTitle,
    why: why,
    patch: hit is _TeamErrorPatchRule ? hit.patch : null,
    dropTeam: hit?.dropTeam ?? false,
    dropApplicant: hit?.dropApplicant ?? false,
    refresh: hit?.refresh ?? false,
    primary: hit?.primary ?? '',
    secondary: hit?.secondary ?? '',
    primaryAction: hit?.primaryAction ?? '',
  );
}

class MyTeamRow {
  const MyTeamRow({
    required this.key,
    required this.teamId,
    required this.name,
    required this.sub,
    required this.badge,
    required this.tone,
    required this.actionText,
    required this.actionKind,
    required this.action,
  });

  final String key;
  final int teamId;
  final String name;
  final String sub;
  final String badge;

  /// ok / wait / bad —— 三态各自有文字,不只靠颜色。
  final String tone;
  final String actionText;

  /// primary / secondary。
  final String actionKind;

  /// enter / withdraw / nearby。
  final String action;
}

/// P6:已加入(/api/team/my)+ 申请中/被拒(/api/team/my-applications)。
/// 快照 `myTeamRows()`:status 3/4(已结束/已解散)跳过;同一队以已加入为准。
List<MyTeamRow> myTeamRows(
  List<Map<String, dynamic>> joinedTeams,
  List<Map<String, dynamic>> applications, {
  DateTime? now,
}) {
  final List<MyTeamRow> rows = <MyTeamRow>[];
  final Set<int> seen = <int>{};
  for (final Map<String, dynamic> t in joinedTeams) {
    final int? id = _int(t['id']);
    final int? status = _int(t['status']);
    if (id == null || id <= 0 || status == 3 || status == 4 || seen.contains(id)) {
      continue;
    }
    seen.add(id);
    rows.add(
      MyTeamRow(
        key: 'j$id',
        teamId: id,
        name: teamDisplayName(t),
        sub: '${_int(t['joinedCount']) ?? 0}/${_int(t['maxMembers']) ?? 0} 人',
        badge: '已加入',
        tone: 'ok',
        actionText: '进入队伍',
        actionKind: 'primary',
        action: 'enter',
      ),
    );
  }
  for (final Map<String, dynamic> a in applications) {
    final int? id = _int(a['teamId']);
    if (id == null || id <= 0 || seen.contains(id)) continue;
    final String applyStatus = _text(a['applyStatus']);
    if (applyStatus == 'PENDING') {
      seen.add(id);
      final String left = teamExpireLeft(
        a['applyExpireTime'],
        now ?? DateTime.now(),
      );
      rows.add(
        MyTeamRow(
          key: 'p$id',
          teamId: id,
          name: teamDisplayName(a),
          sub:
              '队长 ${_text(a['leaderName']).isEmpty ? '玩家' : _text(a['leaderName'])}'
              '${left.isEmpty ? '' : ' · $left后失效'}',
          badge: '申请中',
          tone: 'wait',
          actionText: '撤回申请',
          actionKind: 'secondary',
          action: 'withdraw',
        ),
      );
    } else if (applyStatus == 'REJECTED') {
      seen.add(id);
      rows.add(
        MyTeamRow(
          key: 'r$id',
          teamId: id,
          name: teamDisplayName(a),
          sub: '不能再申请这支队伍',
          badge: '队长未同意',
          tone: 'bad',
          actionText: '看附近队伍',
          actionKind: 'secondary',
          action: 'nearby',
        ),
      );
    }
  }
  return rows;
}

/// 角控件计数:已加入 + 申请中,**不算被拒**(快照:showFail 弹失败时也用它)。
int teamMyTeamsCount(List<MyTeamRow> rows) =>
    rows.where((MyTeamRow r) => r.tone != 'bad').length;

class TeamApplicantRow {
  const TeamApplicantRow({
    required this.memberId,
    required this.name,
    required this.avatar,
    required this.sub,
    this.messageText = '',
  });

  final int memberId;
  final String name;
  final String avatar;
  final String sub;

  /// 申请留言(已带引号的展示形状);空串 = 不渲染。
  final String messageText;
}

/// 「N 分钟前申请」。快照 `ago()`;解析不出来返回空串(不编时间)。
String teamAppliedAgo(Object? appliedAt, DateTime now) {
  final String raw = _text(appliedAt);
  final RegExpMatch? m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(raw);
  if (m == null) return '';
  final DateTime at = DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  final int min = (now.difference(at).inMinutes) < 0
      ? 0
      : now.difference(at).inMinutes;
  if (min < 1) return '刚刚申请';
  if (min < 60) return '$min 分钟前申请';
  if (min < 1440) return '${min ~/ 60} 小时前申请';
  return '${min ~/ 1440} 天前申请';
}

/// P5 申请人行。快照 `applicantRows()`:服务端只回未过期待审,且申请时已验票。
/// 留言展示形状(引号)= 2026-09-17 拍板第19条:服务端已做 200 字上限与机审,
/// 这里只管形状;空串/null 不渲染。
List<TeamApplicantRow> teamApplicantRows(
  List<Map<String, dynamic>> list,
  DateTime now,
) {
  return list
      .where((Map<String, dynamic> a) => _int(a['memberId']) != null)
      .map((Map<String, dynamic> a) {
        final String left = teamExpireLeft(a['applyExpireTime'], now);
        final String message = _text(a['applyMessage']);
        return TeamApplicantRow(
          memberId: _int(a['memberId'])!,
          name: _text(a['memberName']).isEmpty
              ? '玩家'
              : _text(a['memberName']),
          avatar: _text(a['memberAvatar']),
          sub: <String>[
            '持本场票',
            teamAppliedAgo(a['appliedAt'], now),
            left.isEmpty ? '' : '$left后失效',
          ].where((String s) => s.isNotEmpty).join(' · '),
          messageText: message.isEmpty ? '' : '“$message”',
        );
      })
      .toList();
}

String teamLeaderSub(Map<String, dynamic>? team) {
  final int joined = _int(team?['joinedCount']) ?? 0;
  final int max = _int(team?['maxMembers']) ?? 0;
  return '你是队长 · 已组 $joined/$max · 还能再加 ${max - joined > 0 ? max - joined : 0} 人';
}

String teamLeaderFoot(Map<String, dynamic>? team) {
  final int joined = _int(team?['joinedCount']) ?? 0;
  final int max = _int(team?['maxMembers']) ?? 0;
  final int left = (max - joined) > 0 ? (max - joined) : 0;
  return '同意 $left 人后队伍满员:从地图上消失,其余申请自动失效';
}
