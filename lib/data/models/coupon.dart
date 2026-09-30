/// 优惠券记录(对齐后端 ViewCouponHistory / `/api/coupon/myrecvlist`)。
///
/// ★ useStatus 语义与小程序 `scene-game-coupon-wallet` 一致:
///   0 待使用 / 1 已使用 / 2 已过期 / 3 已失效(平台手动失效)。后端在
///   myrecvlist 前会先跑 updateExpiredCouponsByMemberId,过期状态由**服务端**
///   落库,不在前端算;3 是平台侧撤销,不落任何筛选 tab,只在「全部」里可见。
class CouponRecord {
  CouponRecord({
    required this.id,
    required this.couponId,
    required this.couponCode,
    required this.useStatus,
    this.getTime,
    this.useTime,
    this.startTime,
    this.endTime,
    this.qrcodeUrl,
    this.couponName,
    this.couponDescription,
    this.note,
  });

  final int id;
  final int couponId;
  final String couponCode;

  /// 后端原始状态:0 待使用 / 1 已使用 / 2 已过期 / 3 已失效。
  final int useStatus;
  final String? getTime; // 领取时间
  final String? useTime; // 使用时间
  final String? startTime; // 有效期起
  final String? endTime; // 有效期止
  final String? qrcodeUrl;

  /// 券名(ViewCouponHistory 已带,couponName)。
  final String? couponName;

  /// 券描述(couponDescription;存量可能只有 note)。
  final String? couponDescription;
  final String? note;

  /// 卡片标题。对齐小程序 decorate:`couponName || '优惠券'`。
  String get displayName =>
      (couponName == null || couponName!.isEmpty) ? '优惠券' : couponName!;

  /// 卡片描述。对齐小程序 decorate:`couponDescription || note`。
  String get displayDescription {
    final d = couponDescription;
    if (d != null && d.isNotEmpty) return d;
    return note ?? '';
  }

  /// 状态文字。对齐小程序 decorate:0→待使用 / 1→已使用 / 2→已过期 /
  /// 3→已失效 / 其余→状态待确认(未知状态不许伪装成「待使用」继续亮入口)。
  String get statusText => switch (useStatus) {
    0 => '待使用',
    1 => '已使用',
    2 => '已过期',
    3 => '已失效',
    _ => '状态待确认',
  };

  /// 状态 tag 着色。对齐小程序 `_statusVariant`:待使用=info(蓝)、
  /// 已失效=danger(强调「已被平台手动失效」)、其余=中性。
  bool get isInfoStatus => useStatus == 0;
  bool get isDangerStatus => useStatus == 3;

  /// 状态是否中性终态(已使用/已过期 → 走中性 tag)。
  bool get isNeutralStatus => useStatus == 1 || useStatus == 2;

  /// 有效期只显示到「日」(2026-09-17 全站拍板,共享 utils/datetime.formatDayDots)。
  /// 后端下发的是中国时间语义字符串,直接取日期段换点号,不依赖设备时区。
  static String _dayDots(String? value) {
    final s = (value ?? '').trim();
    if (s.length < 10) return '';
    final day = s.replaceFirst('T', ' ').substring(0, 10);
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      return day.replaceAll('-', '.');
    }
    return '';
  }

  /// 今天的中国日(yyyy-MM-dd)。真源 `_canView/_isUsable` 拆分的判据要按
  /// 中国自然日比较:设备时区不是 UTC+8 时,本地日期会把「中国已到 start、
  /// 本机还在前一天」的券错误锁住。
  static String _chinaTodayKey() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-'
        '${two(now.day)}';
  }

  /// 使用期承诺:start 前不算可使用。list 接口只精确到日;无 startTime 的
  /// 历史券按已开始兼容(真源 `startedAt` 同此)。
  bool get started {
    final s = (startTime ?? '').trim();
    if (s.isEmpty) return true;
    final day = _dayDots(s);
    if (day.isNotEmpty) {
      return day.replaceAll('.', '-').compareTo(_chinaTodayKey()) <= 0;
    }
    final parsed = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (parsed == null) return true;
    return !parsed.isAfter(DateTime.now());
  }

  /// 可查看(打开等待/详情)与可核销(亮码)是两件事(真源 `_canView/_isUsable`):
  /// 未到 start 的券保留查看入口但不亮码;已失效(3)两者都不给 ——
  /// 服务端 qr-token 只会回终态,点进去是死路。
  bool get canView => useStatus == 0;
  bool get isUsable => useStatus == 0 && started;

  /// 有效期行。对齐真源 `decorate.dateLine`:
  /// 3→「该券已被平台手动失效」;未开始→「YYYY.MM.DD 起可用 · 有效期至 …」;
  /// 其余→「有效期至 YYYY.MM.DD」(无 endTime 时「有效期待确认」)。
  String get dateText {
    if (useStatus == 3) return '该券已被平台手动失效';
    final end = endTime;
    final endDots = _dayDots(end);
    final endText = endDots.isEmpty ? '有效期待确认' : '有效期至 $endDots';
    if (started) return endText;
    final startDots = _dayDots(startTime);
    final startText = startDots.isEmpty ? '' : '$startDots 起可用';
    return startText.isEmpty ? endText : '$startText · $endText';
  }

  factory CouponRecord.fromJson(Map<String, dynamic> json) => CouponRecord(
    id: (json['id'] as num?)?.toInt() ?? 0,
    couponId: (json['couponId'] as num?)?.toInt() ?? 0,
    couponCode: (json['couponCode'] ?? '') as String,
    useStatus: (json['useStatus'] as num?)?.toInt() ?? 0,
    getTime: json['getTime'] as String?,
    useTime: json['useTime'] as String?,
    startTime: json['startTime'] as String?,
    endTime: json['endTime'] as String?,
    qrcodeUrl: json['qrcodeUrl'] as String?,
    couponName: json['couponName'] as String?,
    couponDescription: json['couponDescription'] as String?,
    note: json['note'] as String?,
  );
}

/// 券的展示状态(用于角标着色)。文案对齐小程序:待使用 / 已使用 / 已过期 / 已失效。
enum CouponDisplayStatus {
  unused('待使用'),
  used('已使用'),
  expired('已过期'),
  invalid('已失效');

  const CouponDisplayStatus(this.label);
  final String label;
}

/// 动态二维码签发结果:`POST /api/coupon/qr-token`。
/// 后端渲染好二维码图(60s 时效),前端按 expiresIn 倒计时刷新。
class CouponQr {
  const CouponQr({
    required this.qrcodeUrl,
    required this.expiresIn,
    required this.useStatus,
    this.token,
    this.endTime,
    this.startTime,
    this.couponName,
    this.description,
  });

  final String qrcodeUrl;
  final int expiresIn;

  /// 签发时刻的快照状态:0 待使用 / 1 已使用 / 2 已过期 / 3 已失效。
  final int useStatus;
  final String? token;
  final String? endTime;

  /// 可用开始时刻。★ 使用期承诺(真源 `coupon-qr` 的 notStarted):**到点才出码**。
  ///   后端 `/api/coupon/qr-token` 一直在下发,是模型没解析 —— 于是 App 会
  ///   把一张"还没到能用时间"的券亮给商家扫。
  final String? startTime;
  final String? couponName;
  final String? description;

  factory CouponQr.fromJson(Map<String, dynamic> json) => CouponQr(
    qrcodeUrl: (json['qrcodeUrl'] ?? '') as String,
    expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 60,
    useStatus: (json['useStatus'] as num?)?.toInt() ?? 0,
    token: json['token'] as String?,
    endTime: json['endTime'] as String?,
    startTime: json['startTime'] as String?,
    couponName: json['couponName'] as String?,
    description: json['description'] as String?,
  );
}

/// 核销状态轮询结果:`POST /api/coupon/status`。
class CouponStatus {
  const CouponStatus({required this.useStatus, this.useTime});

  final int useStatus;
  final String? useTime;

  factory CouponStatus.fromJson(Map<String, dynamic> json) => CouponStatus(
    useStatus: (json['useStatus'] as num?)?.toInt() ?? 0,
    useTime: json['useTime'] as String?,
  );
}
