// 资产流水模型(对齐后端 UmsMemberPointsDetail / UmsMemberBalanceDetail)。
// changeType:1=收入 2=支出。
//
// ⚠️ **本文件的 `PointsRecord` 与 `lib/data/models/points_record.dart` 里的同名类
//    是两套并存的模型**,建模的是同一份后端数据(/api/points/list):
//      · 这一套供 `/assets` 页(asset_api)
//      · 那一套供 `/points` 页(points_api)
//    两边字段可空性不同、符号判据也曾经不一致 —— 同一笔积分在两个页面可能显示
//    成不同的方向。合并它们要动两条 API 与两个页面,不在本轮范围;
//    在合并之前,**改任何一边的显示语义都必须同步改另一边**。

/// 积分流水(`/api/points/list`)。
class PointsRecord {
  PointsRecord({
    required this.id,
    required this.changePoints,
    required this.afterPoints,
    required this.changeReason,
    required this.changeType,
    required this.createTime,
  });

  final int id;

  /// 变动积分(正负)。
  final int changePoints;

  /// 变动后积分。
  final int afterPoints;

  /// 变动原因。
  final String changeReason;

  /// 1=收入 2=支出。**可空 —— 后端没下发就是 null,不兜 0**。
  /// 兜 0 的话「没下发」和「支出」在类型上就分不开了,只能靠每个消费方自己记得,
  /// 而这正是本轮反复出错的地方。空出来,让类型系统提醒调用方。
  final int? changeType;

  /// 创建时间(后端格式化字符串)。
  final String createTime;

  /// 是否收入。★ 不能写成 `changeType == 1` —— null 会落到 false,
  /// 把一笔**收入判成支出**,界面上显示为扣分。
  /// 缺席时退而看金额符号:符号本身就是方向信息,比猜一个默认值可靠。
  bool get isIncome {
    final int? t = changeType;
    if (t != null) return t == 1;
    return changePoints >= 0;
  }


  factory PointsRecord.fromJson(Map<String, dynamic> json) => PointsRecord(
    id: (json['id'] as num?)?.toInt() ?? 0,
    changePoints: (json['changePoints'] as num?)?.toInt() ?? 0,
    afterPoints: (json['afterPoints'] as num?)?.toInt() ?? 0,
    changeReason: (json['changeReason'] ?? '').toString(),
    changeType: (json['changeType'] as num?)?.toInt(),
    createTime: (json['createTime'] ?? '').toString(),
  );
}

/// 余额流水(`/api/balance/list`)。changeBalance/afterBalance 为 BigDecimal(JSON 里是数字)。
class BalanceRecord {
  BalanceRecord({
    required this.id,
    required this.changeBalance,
    required this.afterBalance,
    required this.changeReason,
    required this.changeType,
    required this.createTime,
  });

  final int id;

  /// 变动金额(正负,元)。
  final double changeBalance;

  /// 变动后余额(元)。
  final double afterBalance;

  /// 变动原因。
  final String changeReason;

  /// 1=收入 2=支出。**可空 —— 后端没下发就是 null,不兜 0**。
  /// 兜 0 的话「没下发」和「支出」在类型上就分不开了,只能靠每个消费方自己记得,
  /// 而这正是本轮反复出错的地方。空出来,让类型系统提醒调用方。
  final int? changeType;

  /// 创建时间(后端格式化字符串)。
  final String createTime;

  /// 见 [PointsRecord.isIncome] —— 同一条理由:缺席不等于支出。
  bool get isIncome {
    final int? t = changeType;
    if (t != null) return t == 1;
    return changeBalance >= 0;
  }

  factory BalanceRecord.fromJson(Map<String, dynamic> json) => BalanceRecord(
    id: (json['id'] as num?)?.toInt() ?? 0,
    changeBalance: (json['changeBalance'] as num?)?.toDouble() ?? 0,
    afterBalance: (json['afterBalance'] as num?)?.toDouble() ?? 0,
    changeReason: (json['changeReason'] ?? '').toString(),
    changeType: (json['changeType'] as num?)?.toInt(),
    createTime: (json['createTime'] ?? '').toString(),
  );
}
