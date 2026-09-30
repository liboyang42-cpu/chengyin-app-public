import 'package:chengyin_app/core/util/json_parse.dart';

/// 一条积分明细。对齐后端 `UmsMemberPointsDetail`(ums_member_points_detail)。
/// 来源:`/api/user/points/list`(真实分页,data.rows)。
class PointsRecord {
  PointsRecord({
    required this.id,
    this.changePoints = 0,
    this.afterPoints,
    this.changeReason,
    this.eventType,
    this.eventId,
    this.changeType,
    this.createTime,
  });

  final int id;

  /// 本次变化的积分(后端 changePoints,正数)。
  final int changePoints;

  /// 变化后余额(后端 afterPoints)。最新一条的 afterPoints 即当前余额。
  final int? afterPoints;

  /// 变化原因/标题(后端 changeReason)。
  final String? changeReason;

  /// 事件类型:1注册 2首次报名 3参与活动 4活动评价 5被邀注册首单 6被邀报名 7推荐商户 99其它。
  final int? eventType;

  /// 事件对象 id。eventType==5 时它是**被邀请人的 member_id** ——
  /// 邀请记录页靠它把奖励配到人头上。★ 后端两边一个给 int 一个给 String,
  /// 配对前要归一(见 feature/account/invite_history_logic.dart 的 normalizeId)。
  final String? eventId;

  /// 变化类型:1收入 2支出(后端 changeType)。
  final int? changeType;

  /// 变化时间(后端 createTime,格式 yyyy-MM-dd HH:mm:ss)。
  final String? createTime;

  /// 是否收入。
  ///
  /// ★ `changeType` 是首选判据(后端 1=收入 2=支出,各写入点都设了),
  ///   但它在模型里**可空**,而原来的 `changeType == 1` 在缺席时会落到 false ——
  ///   也就是**默认判成支出**,把一笔收入显示成扣分。
  ///   一个字段没下发就让用户以为自己被扣了分,这个失败形态太重,不能靠「后端总会给」。
  ///
  /// 缺席时退而看 `changePoints` 的符号:后端约定它是正数配 changeType 表达方向,
  /// 但真收到负数时,符号本身就是方向信息,比猜一个默认值可靠。
  bool get isIncome {
    final int? t = changeType;
    if (t != null) return t == 1;
    return changePoints >= 0;
  }

  /// 展示用的绝对值。★ 符号由 [isIncome] 决定并单独拼 ——
  ///   直接把 `changePoints` 拼在符号后面,遇到负数会渲成 `--200`(实拍到过)。
  int get displayPoints => changePoints.abs();

  /// 展示标题:优先 changeReason,缺省按事件类型兜底。
  String get title {
    if (changeReason != null && changeReason!.isNotEmpty) return changeReason!;
    switch (eventType) {
      case 1:
        return '注册账号';
      case 2:
        return '首次报名';
      case 3:
        return '参与活动';
      case 4:
        return '活动评价';
      case 5:
        return '邀请好友注册';
      case 6:
        return '邀请好友报名';
      case 7:
        return '推荐商户注册';
      default:
        return '积分变动';
    }
  }

  factory PointsRecord.fromJson(Map<String, dynamic> json) => PointsRecord(
    id: asInt(json['id']),
    changePoints: asInt(json['changePoints']),
    afterPoints: json['afterPoints'] == null ? null : asInt(json['afterPoints']),
    changeReason: json['changeReason'] as String?,
    eventType: json['eventType'] == null ? null : asInt(json['eventType']),
    eventId: json['eventId']?.toString(),
    changeType: json['changeType'] == null ? null : asInt(json['changeType']),
    createTime: json['createTime'] as String?,
  );
}
