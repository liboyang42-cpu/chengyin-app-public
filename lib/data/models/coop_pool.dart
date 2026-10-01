/// 合作池一行(俱乐部视角看可承接的主题)。
/// 对齐后端 `ApiCoopPoolController.list`(/api/coop/pool/list)。
class CoopPoolItem {
  const CoopPoolItem({
    required this.topicId,
    required this.name,
    this.hasCustomName = true,
    this.cover,
    this.subtitle,
    this.startDate,
    this.endDate,
    this.recruitDeadline,
    this.merchantNick,
    this.state = 'open',
    this.applyId,
  });

  final int topicId;
  final String name;
  final bool hasCustomName;
  final String? cover;
  final String? subtitle;
  final String? startDate;
  final String? endDate;
  final String? recruitDeadline;
  final String? merchantNick;

  /// 八态之一,由**服务端**判定,前端不重算:
  /// open / applied / invited / taken / cooped / converted / declined / withdrawn。
  final String state;

  final int? applyId;

  /// 状态文案。逐条对齐小程序 pages/coop/list/index.js:83-91。
  String get stateText {
    switch (state) {
      case 'applied':
        return '已申请 · 等商家处理';
      case 'invited':
        return '商家已邀约';
      case 'taken':
        return '已被其他俱乐部承接';
      case 'cooped':
        return '合作中';
      case 'converted':
        return '已通过 · 已生成邀约';
      case 'declined':
        return '已婉拒 · 可再申请';
      case 'withdrawn':
        return '已撤回 · 可再申请';
      default:
        return '可申请';
    }
  }

  /// 能不能(再)申请。★ 只有这三态 —— 与小程序 canApply 一致。
  ///
  /// ⚠️ 后端注释点名了两个坑:
  ///   ① `invited` 必须**先于** `applied` 判定,否则「去接受邀约」这一跳
  ///      俱乐部在池里永远看不见;
  ///   ② 少了 `converted` 会掉进 else 显示成「可申请」——
  ///      明明已经被通过了却像没人理,而且**诱导他再申请一次**。
  ///   这两条都是"状态漏一档就把用户带进死路"的例子,所以八态全列、不留 default 兜底给可申请。
  bool get canApply =>
      state == 'open' || state == 'declined' || state == 'withdrawn';

  /// 能不能撤回(只有待商家处理时)。
  bool get canWithdraw => state == 'applied';

  factory CoopPoolItem.fromJson(Map<String, dynamic> json) {
    return CoopPoolItem(
      topicId: (json['topicId'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '未命名主题',
      hasCustomName: json['name'] != null,
      cover: json['cover'] as String?,
      subtitle: json['subtitle'] as String?,
      startDate: json['startDate']?.toString(),
      endDate: json['endDate']?.toString(),
      recruitDeadline: json['recruitDeadline']?.toString(),
      merchantNick: json['merchantNick'] as String?,
      state: (json['state'] as String?) ?? 'open',
      applyId: (json['applyId'] as num?)?.toInt(),
    );
  }
}

/// 合作池整体。
class CoopPool {
  const CoopPool({this.rows = const <CoopPoolItem>[], this.hasClub = false});

  final List<CoopPoolItem> rows;

  /// 当前用户是否有俱乐部。★ 没有俱乐部时**整页应说"先创建俱乐部"**,
  ///   而不是显示一个空列表 —— 空列表会让人以为"暂时没有可承接的主题"。
  final bool hasClub;

  factory CoopPool.fromJson(Map<String, dynamic> json) {
    return CoopPool(
      rows: ((json['rows'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CoopPoolItem.fromJson)
          .toList(),
      hasClub: json['hasClub'] == true,
    );
  }
}

/// 一条俱乐部带队申请(`/api/coop/pool/mine` / `/api/coop/pool/received` 的一行)。
///
/// ★ 同一行数据在两个箱子里含义不同(小程序 `utils/coop-invite-view.js:160`):
///   · received = **发布者/商家**看:谁申请了我的主题 → 可以「拒绝」或「回邀约」;
///   · sent = **俱乐部**看:我申请了谁的主题 → 只能「撤回」。
///   所以 [peer] 与可达动作都按箱子取,判错了摆出来的按钮就是必被服务端拒的。
class CoopPoolApply {
  const CoopPoolApply({
    required this.applyId,
    required this.topicId,
    required this.status,
    this.topicName,
    this.clubId,
    this.clubName,
    this.merchantNick,
    this.message,
    this.startDate,
    this.scope,
  });

  final int applyId;
  final int topicId;

  /// 0 待确认 / 1 商家婉拒 / 2 俱乐部撤回 / 3 商家已回带条款邀约。
  final int status;

  final String? topicName;

  /// 申请方俱乐部 id(「回邀约」要按它指名对方 —— 小程序
  /// `pages/coop/list/index.js:479` 的 `toId` 就是它)。
  final int? clubId;

  /// 申请方俱乐部名(received 箱里是对方)。
  final String? clubName;

  /// 主题发布商家名(sent 箱里是对方)。
  final String? merchantNick;

  final String? message;
  final String? startDate;

  /// 商家员工处理 owner 主题上的申请时带回的归属标记,`/decline` 要原样回传。
  final String? scope;

  /// 申请卡标题。★ 没有 topicName 时说「主题 #id」,不是留空
  ///   (coop-invite-view.js:169 同款)。
  String get titleText =>
      (topicName ?? '').trim().isNotEmpty ? topicName!.trim() : '主题 #$topicId';

  /// 对方是谁。received → 来自俱乐部;sent → 发给商家。
  String peerText({required bool received}) {
    final String? peer = received ? clubName : merchantNick;
    if ((peer ?? '').trim().isEmpty) return '';
    return '${received ? '来自' : '发给'} ${peer!.trim()}';
  }

  /// 副行。received 说清「俱乐部申请带队」;sent 点名是哪家俱乐部。
  String subText({required bool received}) => received
      ? '俱乐部申请带队'
      : '申请带队${(clubName ?? '').trim().isEmpty ? '' : ' · ${clubName!.trim()}'}';

  /// 留言行。★ 没留言时不是留白,而是说明「申请只表意向」——
  ///   这句话决定了商家知道该不该当合同看(coop-invite-view.js:181)。
  String get termsText => (message ?? '').trim().isEmpty
      ? '申请只表意向,条款随商家回的邀约走'
      : '留言:${message!.trim()}';

  /// 只取到日(小程序 `dateOf` 的 `slice(0, 10)`)。
  /// ★ 用 length 判断而不是直接 `substring(0, 10)`:后者遇到短于 10 个字符的
  ///   脏日期会抛 RangeError,而 JS 的 slice 只会返回原串 ——
  ///   一条格式不对的日期不该把整页打崩。
  String get dateText {
    final String v = (startDate ?? '').trim();
    if (v.isEmpty) return '';
    return v.length <= 10 ? v : v.substring(0, 10);
  }

  /// 状态文案,逐条对齐 APPLY_STATUS(coop-invite-view.js:140)。
  /// ★ 未知码不猜 —— 说「状态未知」,别让一条已拒绝的申请看起来还能处理。
  String get statusText {
    switch (status) {
      case 0:
        return '待确认';
      case 1:
        return '已拒绝';
      case 2:
        return '已撤回';
      case 3:
        return '已回邀约';
      default:
        return '状态未知';
    }
  }

  /// 只有待确认的申请才有动作,且动作按箱子分(canWithdraw / canHandle)。
  bool get isPending => status == 0;

  /// 我发出的、待商家处理 → 可撤回。
  bool get canWithdraw => isPending;

  /// 我收到的、待我处理 → 可拒绝 / 可回邀约。
  bool get canHandle => isPending;

  factory CoopPoolApply.fromJson(Map<String, dynamic> json) => CoopPoolApply(
    applyId: (json['applyId'] as num?)?.toInt() ?? 0,
    topicId: (json['topicId'] as num?)?.toInt() ?? 0,
    status: (json['status'] as num?)?.toInt() ?? -1,
    topicName: json['topicName'] as String?,
    clubId: (json['clubId'] as num?)?.toInt(),
    clubName: json['clubName'] as String?,
    merchantNick: json['merchantNick'] as String?,
    message: json['message'] as String?,
    startDate: json['startDate']?.toString(),
    scope: json['scope'] as String?,
  );
}
