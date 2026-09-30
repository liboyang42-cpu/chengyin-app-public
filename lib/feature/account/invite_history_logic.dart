// 邀请记录的分组与文案 —— 从小程序 components/cy/scene-member-invite-history 逐条移植。
//
// ★★ 这页的难点不是布局,是**四种状态说四句不同的话**,而且其中一句
//   是「我们没看全数据」而不是「你没赚到」:
//
//   | 邀请记录 | 积分流水拉到了吗 | 这条有奖励吗 | 该说什么      |
//   |---------|----------------|------------|--------------|
//   | 有      | 全拉到了        | 有          | 首购奖励已到账 |
//   | 有      | 全拉到了        | 没有        | 已加入·首购待完成 |
//   | 有      | **只拉到一部分** | 查不到      | 已加入·**奖励待同步** |
//   | 无      | —              | —          | 空态          |
//
//   第三行是关键:积分流水一次只拉 200 条,后端 total 比 200 大时,
//   「查不到这条的奖励」有可能只是**没翻到那一页**。
//   这时说「首购待完成」就是在编 —— 小程序为此专门有个 rewardReady 闸,
//   顶部还会横一条「邀请记录已到达,奖励流水暂未同步」。照搬。

/// 积分流水里「邀请首购奖励」的事件类型。
const int kInviteRewardEventType = 5;

class InviteReward {
  const InviteReward(this.points, this.createTime);
  final num points;
  final String? createTime;
}

/// 把积分流水折成 `被邀请人 id → 累计奖励`。
///
/// ★ 只认 eventType==5 且**正数**的行:负数是扣减(退款回收),
///   计进去会让「已到账」显示成负值。
Map<String, InviteReward> inviteRewardMap(
  Iterable<({int? eventType, String? eventId, num? changePoints, String? createTime})> rows,
) {
  final Map<String, InviteReward> out = <String, InviteReward>{};
  for (final r in rows) {
    if (r.eventType != kInviteRewardEventType) continue;
    final String key = normalizeId(r.eventId);
    final num? p = r.changePoints;
    if (key.isEmpty || p == null || p <= 0) continue;
    final InviteReward? prev = out[key];
    out[key] = InviteReward(
      (prev?.points ?? 0) + p,
      (prev?.createTime?.isNotEmpty ?? false) ? prev!.createTime : r.createTime,
    );
  }
  return out;
}

/// id 归一:非纯数字一律作废,前导零抹掉,'0' 视为无效。
///
/// ★ 抹前导零是必须的 —— 后端两边一个给 int 一个给 String,
///   '007' 和 '7' 不归一就永远配不上,表现为「奖励到账了但显示待解锁」。
String normalizeId(Object? v) {
  final String raw = (v ?? '').toString().trim();
  if (raw.isEmpty || !RegExp(r'^\d+$').hasMatch(raw)) return '';
  final String n = raw.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return n == '0' ? '' : n;
}

/// 积分流水是否**拉全了**。拉不全就不许说「待完成」。
///
/// [fetched] 本次拉到的行数;[total] 后端说一共有多少行(拿不到给 null)。
bool inviteRewardReady({required int? fetched, required num? total}) {
  if (fetched == null) return false;      // 流水根本没拉到 ⇒ 不能下结论
  return total == null || total <= fetched;
}

String pointText(num? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return (((v * 100).round()) / 100).toString();
}

class InviteRow {
  const InviteRow({
    required this.id,
    required this.name,
    this.avatar,
    required this.timeText,
    required this.statusText,
    required this.rewardText,
  });
  final int id;
  final String name;
  final String? avatar;
  final String timeText;
  final String statusText;
  final String rewardText;
}

class InviteGroup {
  const InviteGroup(this.label, this.rows, this.rewardText);
  final String label;
  final List<InviteRow> rows;
  final String rewardText;
}

DateTime? _parse(String? raw) =>
    (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw.replaceFirst(' ', 'T'));

String monthLabel(String? raw) {
  final DateTime? d = _parse(raw);
  return d == null ? '其他邀请' : '${d.year}年${d.month}月';
}

String shortTime(String? raw) {
  final DateTime? d = _parse(raw);
  if (d == null) return '';
  final String h = d.hour.toString().padLeft(2, '0');
  final String m = d.minute.toString().padLeft(2, '0');
  return '${d.month}月${d.day}日 $h:$m';
}

/// 按月分组。★ 保持后端给的顺序,不重排 —— 后端已按时间倒序,
/// 客户端再排一次会在跨页加载时把顺序搅乱。
List<InviteGroup> buildInviteGroups({
  required List<({int id, String name, String? avatar, String? createTime})> members,
  required Map<String, InviteReward> rewards,
  required bool rewardReady,
}) {
  final List<InviteGroup> groups = <InviteGroup>[];
  final Map<String, List<InviteRow>> byLabel = <String, List<InviteRow>>{};
  final Map<String, num> totals = <String, num>{};

  for (final m in members) {
    final String key = normalizeId(m.id);
    if (key.isEmpty) continue;
    final InviteReward? reward = rewards[key];
    final String label = monthLabel(m.createTime);
    final String joinedAt = shortTime(m.createTime);
    final bool earned = reward != null;
    final String rewardAt = earned ? shortTime(reward.createTime) : '';

    if (!byLabel.containsKey(label)) {
      byLabel[label] = <InviteRow>[];
      totals[label] = 0;
      groups.add(InviteGroup(label, byLabel[label]!, ''));
    }
    if (earned) totals[label] = totals[label]! + reward.points;

    byLabel[label]!.add(InviteRow(
      id: m.id,
      name: m.name,
      avatar: m.avatar,
      // ★ 邀请时间拿不到时说「暂未记录」,不留空白也不编一个时间。
      timeText: joinedAt.isEmpty ? '邀请时间暂未记录' : joinedAt,
      statusText: earned
          ? '首购奖励已到账${joinedAt.isEmpty && rewardAt.isNotEmpty ? ' · $rewardAt' : ''}'
          : (rewardReady ? '已加入 · 首购待完成' : '已加入 · 奖励待同步'),
      rewardText: earned
          ? '+${pointText(reward.points)} 积分'
          : (rewardReady ? '待解锁' : '待同步'),
    ));
  }

  return <InviteGroup>[
    for (final InviteGroup g in groups)
      InviteGroup(
        g.label,
        g.rows,
        // ★ 这组一分没有时显示「N 人」而不是「+0 积分」——
        //   「+0」看着像结算错了,「N 人」才是实话。
        (totals[g.label] ?? 0) > 0
            ? '+${pointText(totals[g.label])} 积分'
            : '${g.rows.length} 人',
      ),
  ];
}
